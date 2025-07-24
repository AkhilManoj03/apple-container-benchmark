# apple-container-benchmark
Benchmark testing the Apple Container tool vs. Docker and Podman

## Docker Configuration
- CPU limit: 5
- Memory Limit: 8GB
- Swap: 1GB
- Resource Saver: Disabled
- VMM(Virtual Machine Manager): Apple Virtualization Framework
- Rosetta: Enabled(for x86_64/amd64 emulation)

## Podman Configuration
- CPU limit: 5
- Memory Limit: 8GB
- Swap: N/A(Not available for podman machine yet, will be available [next release](https://github.com/containers/podman/pull/25945))
- VMM(Virtual Machine Manager): quay.io/podman/machine-os:5.6 for arm64
- Rosetta: Enabled(for x86_64/amd64 emulation)

## Apple Container Configuration
- CPU limit: 5
- Memory Limit: 8GB
- Swap: N/A(Not available for Apple Container machine yet)
- Builder virtual machine: ghcr.io/apple/container-builder-shim/builder:0.2.1
- Rosetta: Enabled(for x86_64/amd64 emulation)

## Container Build Performance Benchmark Results

### ARM64 Architecture Builds(Native)

| Application | Docker (seconds) | Podman (seconds) | Apple Container (seconds) |
|-------------|------------------|------------------|---------------------------|
| Python-FastAPI | 17.403 | 18.509 | 18.711 |
| Node-Express.js | 22.636 | 34.433 | 35.539 |
| Go-Gin | 22.517 | 27.992 | 33.401 |
| Rust-Axum | 194.510 | 213.781 | 216.090 |

### AMD64 Architecture Builds(Rosetta)

| Application | Docker (seconds) | Podman (seconds) | Apple Container (seconds) |
|-------------|------------------|------------------|---------------------------|
| Python-FastAPI | 20.872 | 23.393 | 23.821 |
| Node-Express.js | 29.061 | 43.028 | 43.390 |
| Go-Gin | 64.117 | 70.939 | 67.035 |
| Rust-Axum | 600.306 | 650.814 | 619.163 |

## Container Runtime Performance Benchmark

Comprehensive performance comparison of container runtimes across different workload sizes using the
[`run_test.sh`](./run_test.sh) script.

### Methodology

Each test monitors container performance over 15-30 intervals (2-second sampling) to capture startup,
steady-state, and resource allocation patterns across different container runtimes.

### Test Case 1: Small Workload
#### MySQL 8.0 Container

**Workload Profile:** Database service with moderate resource requirements

#### Test Configuration

| Parameter | Value |
|-----------|-------|
| **Test Image** | `mysql:8.0` |
| **Monitoring Intervals** | 15 iterations |
| **Interval Duration** | 2 seconds |
| **Resource Allocation** | 5 CPUs, 8GB RAM |

#### Performance Summary

| Runtime | Avg CPU (%) | Peak CPU (%) | Avg Memory (MB) | Peak Memory (MB)
|---------|-------------|--------------|-----------------|------------------|
| **Apple Container** | 6.77 | 54.30 | 1,252 | 1,466 |
| **Docker** | 11.42 | 55.90 | 1,688 | 1,816 |
| **Podman** | 9.76 | 57.60 | 2,355 | 2,358 |

### Test Case 2: Heavy Workload  
#### GitLab CE 18.2.0 Container

**Workload Profile:** Full-featured DevOps platform with high resource demands

#### Test Configuration

| Parameter | Value |
|-----------|-------|
| **Test Image** | `gitlab/gitlab-ce:18.2.0-ce.0` |
| **Monitoring Intervals** | 30 iterations |
| **Interval Duration** | 2 seconds |
| **Resource Allocation** | 5 CPUs, 8GB RAM |

#### Performance Summary

| Runtime | Avg CPU (%) | Peak CPU (%) | Avg Memory (MB) | Peak Memory (MB) |
|---------|-------------|--------------|-----------------|------------------|
| **Apple Container** | 95.54 | 185.90 | 2,700 | 4,396 |
| **Docker** | 83.29 | 178.00 | 3,388 | 4,967 |
| **Podman** | 91.22 | 179.80 | 7,194 | 8,196 |

### Test Case 3: Multi-Container Workload
#### Nginx, Redis, and Postgres Containers

**Workload Profile:** Web server, cache, and database services

#### Test Configuration

| Parameter | Value |
|-----------|-------|
| **Test Image** | `nginx:1.28.0`, `redis:8.0.0`, `postgres:17.5` |
| **Monitoring Intervals** | 15 iterations |
| **Interval Duration** | 2 seconds |
| **Resource Allocation** | N/A(Let the container tool decide for multi-container workload) |

| Runtime | Avg CPU (%) | Peak CPU (%) | Avg Memory (MB) | Peak Memory (MB) |
|---------|-------------|--------------|-----------------|------------------|
| **Apple Container** | 1.72 | 4.80 | 925.60 | 1,160 |
| **Docker** | 8.24 | 17.50 | 1468.33 | 1,601 |
| **Podman** | 2.69 | 4.80 | 1893.00 | 1,893 |
