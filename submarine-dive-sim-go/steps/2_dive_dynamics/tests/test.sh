#!/bin/bash
set -u
mkdir -p /logs/verifier
# R05: clear prior verifier-generated Go files so inherited session does not leak /tests content
rm -f /app/*_test.go /app/ast_check*.go 2>/dev/null || true
rm -f /logs/verifier/ctrf.json 2>/dev/null || true

set +e
python3 -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
TEST_EXIT=$?
set -e

if [ "$TEST_EXIT" -eq 0 ]; then
 echo 1 > /logs/verifier/reward.txt
else
 echo 0 > /logs/verifier/reward.txt
fi
# R05 FIX: clean up verifier-generated Go files BEFORE next agent step (if any) and before returning
rm -f /app/*_test.go /app/ast_check*.go 2>/dev/null || true
cat /logs/verifier/reward.txt
