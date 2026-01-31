#!/bin/bash
# Wait for a service to be ready
# Usage: ./wait_for.sh <host> <port> <timeout>

set -e

HOST=$1
PORT=$2
TIMEOUT=${3:-30}

echo "Waiting for $HOST:$PORT to be ready..."

for i in $(seq 1 $TIMEOUT); do
    if nc -z "$HOST" "$PORT" 2>/dev/null; then
        echo "$HOST:$PORT is ready!"
        exit 0
    fi
    echo "Attempt $i/$TIMEOUT: $HOST:$PORT not ready yet..."
    sleep 1
done

echo "Timeout waiting for $HOST:$PORT"
exit 1
