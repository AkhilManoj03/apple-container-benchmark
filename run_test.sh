#! /bin/bash
#
# This script is used to run a test container and collect CPU and memory usage.
#
# Usage examples:
#   ./run_test.sh -e container -t small
#   ./run_test.sh -e docker -t large
#   ./run_test.sh -e podman -t multi
#
# Options:
#   -e, --engine: Container tool to use (container, docker, podman)
#   -t, --test-type: Test type to run (small, large, multi)

# --- Configuration ---
readonly TOP_ITERATIONS=5
readonly TOP_SLEEP_INTERVAL=2
readonly OUTPUT_STATS="pid,command,cpu,mem,time"
readonly OUTPUT_FILTER="com\.apple\.Virtu|docker"

readonly INTERVAL_DELIMITER="---END_OF_INTERVAL---"

readonly MACHINE_CPUS=5
readonly MACHINE_MEMORY_GB="8g"
readonly MACHINE_MEMORY_MB=8192

readonly TEST_IMAGE_SMALL="mysql:8.0"
readonly TEST_IMAGE_LARGE="gitlab/gitlab-ce:18.2.0-ce.0"
declare -A TEST_IMAGE_MULTI=(
	["nginx"]="nginx:1.28.0"
	["redis"]="redis:8.0.0"
	["postgres"]="postgres:17.5"
)

CONTAINER_TOOL=""
TOP_LOG_FILE=""
DEFAULT_TEST_TYPE="small"
TEST_TYPE=""

MIN_CPU_OVERALL=1000000.0
MAX_CPU_OVERALL=0.0
TOTAL_CPU_OVERALL=0.0

MIN_MEM_OVERALL=1000000000.0
MAX_MEM_OVERALL=0.0
TOTAL_MEM_OVERALL=0.0

# Helper function to convert memory to MB
function convert_mem_to_mb() {
	local mem_str="${1}"
	# Remove +/- signs for calculation
	local clean_mem_str=$(echo "${mem_str}" | sed 's/[+-]//g')
	local value=$(echo "${clean_mem_str}" | sed 's/[KMG]//g')
	local unit=$(echo "${clean_mem_str}" | sed 's/[0-9.]//g')

	case "${unit}" in
		"K")
			# Using printf for better float formatting for consistency
			printf "%.2f" "$(echo "scale=2; ${value} / 1024" | bc -l)"
			;;
		"M")
			printf "%.2f" "${value}"
			;;
		"G")
			printf "%.2f" "$(echo "scale=2; ${value} * 1024" | bc -l)"
			;;
		*) # Default to MB if no unit or unknown unit
			printf "%.2f" "${value}"
			;;
	esac
}

function initialize_container_tool() {
	if [ "${CONTAINER_TOOL}" == "container" ]; then
		container system stop || true
		container system start || { echo "error: Failed to start container system." >&2; exit 1; }
		container builder delete || true
		echo "info: Waiting for container builder to start..."
		container builder start \
			--cpus "${MACHINE_CPUS}" \
			--memory "${MACHINE_MEMORY_GB}" || { echo "error: Failed to start container builder." >&2; exit 1; }
	elif [ "${CONTAINER_TOOL}" == "docker" ]; then
		# Docker VMM machine is started automatically when Docker is opened and memory is set in
		# Docker Desktop settings(5 CPUs, 8GB memory).
		open -a Docker || { echo "error: Failed to open Docker Desktop." >&2; exit 1; }
		echo "info: Waiting for Docker to start..."
		sleep 10
	elif [ "${CONTAINER_TOOL}" == "podman" ]; then
		podman machine init \
			--cpus "${MACHINE_CPUS}" \
			--memory "${MACHINE_MEMORY_MB}" || { echo "error: Failed to initialize podman machine." >&2; exit 1; }
		echo "info: Waiting for podman machine to start..."
		podman machine start || { echo "error: Failed to start podman machine." >&2; exit 1; }
	else
		echo "error: Unknown container tool specified: ${CONTAINER_TOOL}" >&2
		exit 1
	fi
}

function run_tests() {
	if [ "${TEST_TYPE}" == "small" ]; then
		${CONTAINER_TOOL} run \
			--detach \
			--cpus "${MACHINE_CPUS}" \
			--memory "${MACHINE_MEMORY_GB}" \
			--name benchmark-${CONTAINER_TOOL}-${TEST_TYPE} \
			--env MYSQL_ROOT_PASSWORD=test \
			--env MYSQL_DATABASE=testdb \
			${TEST_IMAGE_SMALL} || { echo "error: Failed to run benchmark ${TEST_TYPE} container." >&2; exit 1; }
	elif [ "${TEST_TYPE}" == "large" ]; then
		${CONTAINER_TOOL} run \
			--detach \
			--cpus "${MACHINE_CPUS}" \
			--memory "${MACHINE_MEMORY_GB}" \
			--name benchmark-${CONTAINER_TOOL}-${TEST_TYPE} \
			--env GITLAB_OMNIBUS_CONFIG="external_url 'http://gitlab.example.com'" \
			${TEST_IMAGE_LARGE} || { echo "error: Failed to run benchmark ${TEST_TYPE} container." >&2; exit 1; }
		echo "info: Waiting 30 seconds for ${TEST_TYPE} container to start..."
		sleep 30
	elif [ "${TEST_TYPE}" == "multi" ]; then
		# Don't set cpus and memory for multi-container test, let the container tool decide.
		${CONTAINER_TOOL} run \
			--detach \
			--name benchmark-${CONTAINER_TOOL}-${TEST_TYPE}-postgres \
			--env POSTGRES_PASSWORD=test \
			--env POSTGRES_DB=testdb \
			${TEST_IMAGE_MULTI["postgres"]} || { echo "error: Failed to run benchmark ${TEST_TYPE} container." >&2; exit 1; }
		sleep 3
		${CONTAINER_TOOL} run \
			--detach \
			--name benchmark-${CONTAINER_TOOL}-${TEST_TYPE}-nginx \
			--env NGINX_PORT=8080:80 \
			${TEST_IMAGE_MULTI["nginx"]} || { echo "error: Failed to run benchmark ${TEST_TYPE} container." >&2; exit 1; }
		sleep 3
		${CONTAINER_TOOL} run \
			--detach \
			--name benchmark-${CONTAINER_TOOL}-${TEST_TYPE}-redis \
			--env REDIS_PORT=6379 \
			${TEST_IMAGE_MULTI["redis"]} || { echo "error: Failed to run benchmark ${TEST_TYPE} container." >&2; exit 1; }
	else
		echo "error: Invalid test type: '${TEST_TYPE}'" >&2
		exit 1
	fi
}

function stop_container_tool() {
	if [ "${CONTAINER_TOOL}" == "container" ]; then
		container stop --all || true
		container rm --all || true
		container system stop || true
	elif [ "${CONTAINER_TOOL}" == "docker" ]; then
		docker container stop "$(docker container ls --quiet)" 2>/dev/null || true
		docker container rm "$(docker ps --all --quiet)" 2>/dev/null || true
		pkill -SIGHUP -f /Applications/Docker.app 'docker serve' || true
	elif [ "${CONTAINER_TOOL}" == "podman" ]; then
		podman machine stop || true
		echo "y" | podman machine rm || true
	fi
}

function print_results() {
	echo "--- Overall Performance Summary (Aggregated per Top Interval) ---"
	echo "Based on ${TOP_ITERATIONS} intervals."
	echo "CPU Usage (%):"
	printf "  Average of interval sums: %.2f\n" "${AVG_CPU_OVERALL}"
	printf "  Highest interval sum: %.2f\n" "${MAX_CPU_OVERALL}"
	printf "  Lowest interval sum:  %.2f\n" "${MIN_CPU_OVERALL}"
	echo ""
	echo "Memory Usage (MB):"
	printf "  Average of interval sums: %.2f MB\n" "${AVG_MEM_OVERALL}"
	printf "  Highest interval sum: %.2f MB\n" "${MAX_MEM_OVERALL}"
	printf "  Lowest interval sum:  %.2f MB\n" "${MIN_MEM_OVERALL}"
}


function parse_args() {
	# Parse -t or --tool argument
	while [[ $# -gt 0 ]]; do
		case "${1}" in
			-e|--engine)
				CONTAINER_TOOL="${2}"
				shift 2
				;;
			-t|--test-type)
				TEST_TYPE="${2}"
				shift 2
				;;
			*)
				echo "error: Invalid argument: '${1}'. Use -t or --tool <container|docker|podman>" >&2
				exit 1
				;;
		esac
	done

	if [ -z "${CONTAINER_TOOL}" ]; then
		echo "error: Container tool is required. Use -t <container|docker|podman>" >&2
		exit 1
	fi

	case "${CONTAINER_TOOL}" in
    "container" | "docker" | "podman")
      TOP_LOG_FILE="log-${CONTAINER_TOOL}.log"
      ;;
    *)
      echo "error: Invalid container tool: '${CONTAINER_TOOL}'. Must be 'container', 'docker', or 'podman'." >&2
      exit 1
      ;;
  esac

	[ -z "${TEST_TYPE}" ] && TEST_TYPE="${DEFAULT_TEST_TYPE}"
}

function main() {
	trap 'echo "info: Cleaning up..."; stop_container_tool; rm -f "${TOP_LOG_FILE}"; exit 1' EXIT

  parse_args "$@"

	if ! command -v rg &>/dev/null; then
		echo "error: 'rg' (ripgrep) command not found. Please install it." >&2
		exit 1
	fi
	if ! command -v bc &>/dev/null; then
		echo "error: 'bc' (arbitrary precision calculator) command not found. Please install it." >&2
		exit 1
	fi

  initialize_container_tool

	run_tests

	for i in $(seq 1 "${TOP_ITERATIONS}"); do
    echo "--- Collecting interval ${i} of ${TOP_ITERATIONS} ---"

		top -l 2 -s 2 -stats ${OUTPUT_STATS} -o cpu | \
			rg -i "${OUTPUT_FILTER}" | \
			rg -v " 0\.0 " \
			>> "${TOP_LOG_FILE}" || { echo "error: Failed to collect data." >&2; exit 1; }
    echo "${INTERVAL_DELIMITER}" >> "${TOP_LOG_FILE}"
  done

	stop_container_tool

	[[ ! -f "${TOP_LOG_FILE}" ]] && { echo "error: ${TOP_LOG_FILE} not found" >&2; exit 1; }

	local -a interval_aggregated_cpus
	local -a interval_aggregated_mems
	local current_interval_cpu_sum=0.0
	local current_interval_mem_sum=0.0
	local current_interval_line_count=0
	local line cpu_val mem_str mem_mb

	while IFS= read -r line; do
		if [[ "${line}" =~ "${INTERVAL_DELIMITER}" ]]; then
			[[ "${current_interval_line_count}" -eq 0 ]] && continue

			# Add the current interval data to the aggregated arrays
			interval_aggregated_cpus+=("$(printf "%.2f" "$current_interval_cpu_sum")")
			interval_aggregated_mems+=("$(printf "%.2f" "$current_interval_mem_sum")")

			# Reset for the next interval
			current_interval_cpu_sum=0.0
			current_interval_mem_sum=0.0
			current_interval_line_count=0
			continue
		fi

		cpu_val=$(echo "${line}" | awk '{print $(NF-2)}')
		mem_str=$(echo "${line}" | awk '{print $(NF-1)}')

		# Skip if the line is empty or the CPU value is not a number
		if [[ -z "${cpu_val}" || ! "${cpu_val}" =~ ^[0-9.]+$ || -z "${mem_str}" ]]; then
			echo "warn: Skipping malformed line: '${line}' (CPU: '${cpu_val}', Mem: '${mem_str}')" >&2
			continue
		fi

		current_interval_cpu_sum=$(echo "${current_interval_cpu_sum} + ${cpu_val}" | bc -l)
		mem_mb=$(convert_mem_to_mb "${mem_str}")
		current_interval_mem_sum=$(echo "${current_interval_mem_sum} + ${mem_mb}" | bc -l)
		current_interval_line_count=$((current_interval_line_count + 1))
	done < "${TOP_LOG_FILE}"

	if [ "${#interval_aggregated_cpus[@]}" -eq 0 ] || [ "${#interval_aggregated_mems[@]}" -eq 0 ]; then
		echo "error: No interval data found"
		exit 1
	fi

	for i in "${!interval_aggregated_cpus[@]}"; do
		cpu_sum="${interval_aggregated_cpus[i]}"
		mem_sum="${interval_aggregated_mems[i]}"

		TOTAL_CPU_OVERALL=$(echo "${TOTAL_CPU_OVERALL} + ${cpu_sum}" | bc -l)
		TOTAL_MEM_OVERALL=$(echo "${TOTAL_MEM_OVERALL} + ${mem_sum}" | bc -l)

		(( $(echo "${cpu_sum} < ${MIN_CPU_OVERALL}" | bc -l) )) && MIN_CPU_OVERALL="${cpu_sum}"
		(( $(echo "${cpu_sum} > ${MAX_CPU_OVERALL}" | bc -l) )) && MAX_CPU_OVERALL="${cpu_sum}"

		(( $(echo "${mem_sum} < ${MIN_MEM_OVERALL}" | bc -l) )) && MIN_MEM_OVERALL="${mem_sum}"
		(( $(echo "${mem_sum} > ${MAX_MEM_OVERALL}" | bc -l) )) && MAX_MEM_OVERALL="${mem_sum}"
	done

	AVG_CPU_OVERALL=$(echo "scale=2; ${TOTAL_CPU_OVERALL} / ${#interval_aggregated_cpus[@]}" | bc -l)
	AVG_MEM_OVERALL=$(echo "scale=2; ${TOTAL_MEM_OVERALL} / ${#interval_aggregated_mems[@]}" | bc -l)

	rm -f "${TOP_LOG_FILE}"
	print_results
	trap - EXIT INT TERM ERR
}

main "$@"
