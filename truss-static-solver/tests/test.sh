#!/bin/bash
set -euo pipefail
cd /app
mkdir -p /logs/verifier /tmp
export GO111MODULE=off
set +e
# Copy test file robustly from multiple possible locations so go test discovers it in package main alongside truss_solver.go
cp /tests/test_outputs_test.go /app/ 2>/dev/null || cp /app/tests/test_outputs_test.go /app/ 2>/dev/null || cp "$(dirname "$0")/test_outputs_test.go" /app/ 2>/dev/null || true
# Ensure test file exists before running
if [ ! -f /app/test_outputs_test.go ] && [ ! -f /app/*_test.go ]; then
  echo "No test file found" > /tmp/test.log
  TEST_EXIT=1
else
  go test -v > /tmp/test.log 2>&1
  TEST_EXIT=$?
fi
set -e
mkdir -p /logs/verifier
if [ "$TEST_EXIT" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
cat /tmp/test.log
cat /logs/verifier/reward.txt
