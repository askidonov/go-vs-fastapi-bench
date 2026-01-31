#!/bin/bash
set -e

# Run k6 test with BASE_URL and save results
# Usage: ./run_k6.sh <base_url> <scenario> <output_prefix>

BASE_URL=$1
SCENARIO=$2
OUTPUT_PREFIX=$3

if [ -z "$BASE_URL" ] || [ -z "$SCENARIO" ] || [ -z "$OUTPUT_PREFIX" ]; then
    echo "Usage: $0 <base_url> <scenario> <output_prefix>"
    echo "Example: $0 http://localhost:8080 read_user go"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="loadtest/results/${OUTPUT_PREFIX}-${SCENARIO}-${TIMESTAMP}.json"
LOG_FILE="loadtest/results/${OUTPUT_PREFIX}-${SCENARIO}-${TIMESTAMP}.log"

echo "Running k6 test: ${SCENARIO}"
echo "Target: ${BASE_URL}"
echo "Output: ${OUTPUT_FILE}"
echo "Log: ${LOG_FILE}"
echo "---"

# Use Docker if k6 is not installed locally
if ! command -v k6 &> /dev/null; then
    echo "Using Docker k6..."
    docker run --rm -i --network=host \
        -v "$(pwd)/loadtest:/loadtest" \
        -u "$(id -u):$(id -g)" \
        grafana/k6 run \
        --env BASE_URL="${BASE_URL}" \
        --summary-export="/loadtest/results/${OUTPUT_PREFIX}-${SCENARIO}-${TIMESTAMP}.json" \
        "/loadtest/k6/${SCENARIO}.js" 2>&1 | tee "${LOG_FILE}"
else
    k6 run \
        --env BASE_URL="${BASE_URL}" \
        --summary-export="${OUTPUT_FILE}" \
        "loadtest/k6/${SCENARIO}.js" 2>&1 | tee "${LOG_FILE}"
fi

echo ""
echo "Results saved to: ${OUTPUT_FILE}"
echo "Log saved to: ${LOG_FILE}"
