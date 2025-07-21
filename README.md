# apple-container-benchmark
Benchmark testing the Apple Container tool vs. Docker and Podman

## Container Build Performance Benchmark Results

### ARM64 Architecture Builds

| Application | Docker (seconds) | Podman (seconds) | Apple Container (seconds) |
|-------------|------------------|------------------|---------------------------|
| Python-FastAPI | 20.509 | 18.509 | 18.711 |
| Node-Express.js | 28.232 | 34.433 | 37.784 |
| Go-Gin | 27.521 | 27.992 | 33.401 |
| Rust-Axum | 277.733 | 213.781 | 312.856 |

### AMD64 Architecture Builds

| Application | Docker (seconds) | Podman (seconds) | Apple Container (seconds) |
|-------------|------------------|------------------|---------------------------|
| Python-FastAPI | 77.691 | 23.393 | 30.252 |
| Node-Express.js | 68.492 | 43.028 | 42.515 |
| Go-Gin | 180.556 | 70.939 | 96.475 |
| Rust-Axum | 2804.950 | 650.814 | 1112.928 |
