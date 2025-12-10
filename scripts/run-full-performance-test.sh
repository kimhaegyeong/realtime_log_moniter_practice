#!/bin/bash

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Full Performance Test Suite                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Baseline measurement
echo "Step 1/5: Measuring baseline performance..."
./scripts/benchmark-baseline.sh > baseline-results.txt
cat baseline-results.txt
echo ""
read -p "Press Enter to continue to optimization..."

# 2. Apply optimizations
echo ""
echo "Step 2/5: Applying optimizations..."
./scripts/apply-optimizations.sh

# 3. After optimization benchmark
echo ""
echo "Step 3/5: Measuring optimized performance..."
./scripts/benchmark-after-optimization.sh > optimized-results.txt
cat optimized-results.txt

# 4. Resource monitoring (background)
echo ""
echo "Step 4/5: Starting resource monitoring (60 seconds)..."
timeout 60 ./scripts/monitor-resources.sh &
MONITOR_PID=$!
sleep 60

# 5. Custom stress test
echo ""
echo "Step 5/5: Running custom stress test..."
read -p "Install Python dependencies? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    pip install -r scripts/requirements-test.txt
    python3 scripts/stress-test-custom.py
fi

# Generate report
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Final Report                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Baseline results: baseline-results.txt"
echo "Optimized results: optimized-results.txt"
echo "Resource logs: resource-monitoring.log"
echo ""
echo "✅ Full performance test completed!"
