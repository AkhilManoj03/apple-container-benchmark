#!/bin/bash

# Start timer
start_time=$(date +%s.%N)

# Replace this line with your build command
container build --arch arm64 -t product:benchmark-arm64 --no-cache .

# End timer
end_time=$(date +%s.%N)

# Calculate elapsed time
elapsed=$(echo "$end_time - $start_time" | bc -l)

# Print result
echo "Build completed in: ${elapsed} seconds"
