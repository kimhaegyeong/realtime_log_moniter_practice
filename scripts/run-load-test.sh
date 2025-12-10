#!/bin/bash

echo "=== Running Load Test with k6 ==="

# k6 설치 확인
if ! command -v k6 &> /dev/null; then
    echo "k6 not found. Installing..."
    
    # OS 감지 및 설치
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo gpg -k
        sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
        echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
        sudo apt-get update
        sudo apt-get install k6
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install k6
    else
        echo "Please install k6 manually: https://k6.io/docs/getting-started/installation/"
        exit 1
    fi
fi

echo "Starting load test..."
k6 run scripts/load-test-k6.js

echo ""
echo "✅ Load test completed!"
echo "Results saved to: load-test-results.json"
