#! /bin/bash

# --- Configuration ---
TOP_ITERATIONS=5 # Roughly 2 minutes at 2-second intervals
TOP_SLEEP_INTERVAL=2
OUTPUT_STATS="pid,command,cpu,mem,time"
OUTPUT_FILTER="com\.apple\.Virtu|docker"

INTERVAL_DELIMITER="---END_OF_INTERVAL---"
TOP_LOG_FILE="log.log"

MACHINE_CPUS=5
MACHINE_MEMORY_GB=8g
MACHINE_MEMORY_MB=8192

OVERALL_MIN_CPU=1000000.0
OVERALL_MAX_CPU=0.0
OVERALL_TOTAL_CPU=0.0

OVERALL_MIN_MEM=1000000000.0
OVERALL_MAX_MEM=0.0
OVERALL_TOTAL_MEM=0.0

TEST_IMAGE="mysql:8.0"

CONTAINER_TOOL="container"

function initialize_container_tool() {
	if [ "${CONTAINER_TOOL}" == "container" ]; then
		container system stop
		container system start
		container builder delete || true
		echo "info: Waiting for container builder to start..."
		container builder start --cpus "${MACHINE_CPUS}" --memory "${MACHINE_MEMORY_GB}"
	elif [ "${CONTAINER_TOOL}" == "docker" ]; then
		# Docker VMM machine is started automatically when Docker is opened and memory is set in
		# Docker Desktop settings(5 CPUs, 8GB memory).
		open -a Docker
		echo "info: Waiting for Docker to start..."
		sleep 10
	elif [ "${CONTAINER_TOOL}" == "podman" ]; then
		podman machine init --cpus "${MACHINE_CPUS}" --memory "${MACHINE_MEMORY_MB}"
		echo "info: Waiting for podman machine to start..."
		podman machine start
	fi
}

function stop_container_tool() {
	if [ "${CONTAINER_TOOL}" == "container" ]; then
		container stop --all
		container rm --all
		container system stop
	elif [ "${CONTAINER_TOOL}" == "docker" ]; then
		docker container stop $(docker container ls --quiet)
		docker container rm $(docker ps --all --quiet)
		pkill -SIGHUP -f /Applications/Docker.app 'docker serve' || true
	elif [ "${CONTAINER_TOOL}" == "podman" ]; then
		podman machine stop
		echo "y" | podman machine rm
	fi
}

# --- Function to convert memory to MB ---
# Handles K, M, G suffixes and +/- signs
function convert_mem_to_mb() {
	local mem_str=$1
	# Remove +/- signs for calculation, keep for display later if needed
	local clean_mem_str=$(echo "$mem_str" | sed 's/[+-]//g')
	local value=$(echo "$clean_mem_str" | sed 's/[KMG]//g')
	local unit=$(echo "$clean_mem_str" | sed 's/[0-9.]//g')

	case "$unit" in
		"K")
			# Using printf for better float formatting for consistency
			printf "%.2f" "$(echo "scale=2; $value / 1024" | bc -l)"
			;;
		"M")
			printf "%.2f" "$value"
			;;
		"G")
			printf "%.2f" "$(echo "scale=2; $value * 1024" | bc -l)"
			;;
		*) # Default to MB if no unit or unknown unit
			printf "%.2f" "$value"
			;;
	esac
}

function print_results() {
	echo "--- Overall Performance Summary (Aggregated per Top Interval) ---"
	echo "Based on ${TOP_ITERATIONS} intervals."
	echo "CPU Usage (%):"
	printf "  Average of interval sums: %.2f\n" "${OVERALL_AVG_CPU}"
	printf "  Highest interval sum: %.2f\n" "${OVERALL_MAX_CPU}"
	printf "  Lowest interval sum:  %.2f\n" "${OVERALL_MIN_CPU}"
	echo ""
	echo "Memory Usage (MB):"
	printf "  Average of interval sums: %.2f MB\n" "${OVERALL_AVG_MEM}"
	printf "  Highest interval sum: %.2f MB\n" "${OVERALL_MAX_MEM}"
	printf "  Lowest interval sum:  %.2f MB\n" "${OVERALL_MIN_MEM}"
}


function parse_args() {
	while getopts "t:" opt; do
		case ${opt} in
			t) CONTAINER_TOOL=${OPTARG} ;;
		esac
	done

	if [ -z "${CONTAINER_TOOL}" ]; then
		echo "error: Container tool is required"
		exit 1
	fi

	if [ "${CONTAINER_TOOL}" != "container" ] && [ "${CONTAINER_TOOL}" != "docker" ] && [ "${CONTAINER_TOOL}" != "podman" ]; then
		echo "error: Invalid container tool: ${CONTAINER_TOOL}"
		exit 1
	fi
}

function main() {
  parse_args "$@"

  initialize_container_tool

	# Run the test container
	${CONTAINER_TOOL} run \
		--detach \
		--cpus "${MACHINE_CPUS}" \
		--memory "${MACHINE_MEMORY_GB}" \
		--name benchmark-${CONTAINER_TOOL} \
		--env MYSQL_ROOT_PASSWORD=test \
		--env MYSQL_DATABASE=testdb \
		${TEST_IMAGE}

	for i in $(seq 1 ${TOP_ITERATIONS}); do
    echo "--- Collecting interval ${i} of ${TOP_ITERATIONS} ---"
    # top -l 2 means two snapshots, -s 2 is the interval between *total* snapshots.
  	top -l 2 -s 2 -stats ${OUTPUT_STATS} -o cpu | \
			rg -i "${OUTPUT_FILTER}" | \
			rg -v " 0\.0 " \
			>> "${TOP_LOG_FILE}"
    echo "${INTERVAL_DELIMITER}" >> "${TOP_LOG_FILE}"
  done

	stop_container_tool

	local -a interval_aggregated_cpus
	local -a interval_aggregated_mems
	local current_interval_cpu_sum=0.0
	local current_interval_mem_sum=0.0
	local current_interval_line_count=0

	while IFS= read -r line; do
		if [[ "${line}" =~ "${INTERVAL_DELIMITER}" ]]; then
			[[ "${current_interval_line_count}" -eq 0 ]] && continue

			# Add the current interval data to the aggregated arrays
			interval_aggregated_cpus+=("${current_interval_cpu_sum}")
			interval_aggregated_mems+=("${current_interval_mem_sum}")

			# Reset for the next interval
			current_interval_cpu_sum=0.0
			current_interval_mem_sum=0.0
			current_interval_line_count=0
			continue
		fi

		local cpu_val=$(echo "${line}" | awk '{print $(NF-2)}')
		local mem_str=$(echo "${line}" | awk '{print $(NF-1)}')

		# Skip if the line is empty or the CPU value is not a number
		if [[ -z "${cpu_val}" || ! "${cpu_val}" =~ ^[0-9.]+$ || -z "${mem_str}" ]]; then
			echo "error: invalid line format: ${line}"
			exit 1
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

		OVERALL_TOTAL_CPU=$(echo "${OVERALL_TOTAL_CPU} + ${cpu_sum}" | bc -l)
		(( $(echo "${cpu_sum} < ${OVERALL_MIN_CPU}" | bc -l) )) && OVERALL_MIN_CPU=${cpu_sum}
		(( $(echo "${cpu_sum} > ${OVERALL_MAX_CPU}" | bc -l) )) && OVERALL_MAX_CPU=${cpu_sum}

		OVERALL_TOTAL_MEM=$(echo "${OVERALL_TOTAL_MEM} + ${mem_sum}" | bc -l)
		(( $(echo "${mem_sum} < ${OVERALL_MIN_MEM}" | bc -l) )) && OVERALL_MIN_MEM=${mem_sum}
		(( $(echo "${mem_sum} > ${OVERALL_MAX_MEM}" | bc -l) )) && OVERALL_MAX_MEM=${mem_sum}
	done

	OVERALL_AVG_CPU=$(echo "scale=2; ${OVERALL_TOTAL_CPU} / ${#interval_aggregated_cpus[@]}" | bc -l)
	OVERALL_AVG_MEM=$(echo "scale=2; ${OVERALL_TOTAL_MEM} / ${#interval_aggregated_mems[@]}" | bc -l)

	print_results
}

main "$@"