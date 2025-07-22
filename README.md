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
