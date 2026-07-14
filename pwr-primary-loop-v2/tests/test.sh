#!/bin/bash
set -u
mkdir -p /logs/verifier
python -m pip install --quiet --no-cache-dir --disable-pip-version-check pytest==8.4.1 pytest-json-ctrf==0.3.5
set +e
# Ensure tests owned by root and unreadable to agent user for anti-cheat; run pytest as agent user to enforce permission barrier
chown -R root:root /tests 2>/dev/null || true
chmod -R 700 /tests 2>/dev/null || true
chown -R agent:agent /app 2>/dev/null || true
chmod -R 755 /app 2>/dev/null || true
# run pytest as non-root agent to block oracle read; GT runner runs as root but test drops privileges if possible, else fallback to root for GT compatibility
if id agent >/dev/null 2>&1; then
  if command -v runuser >/dev/null 2>&1; then
    runuser -u agent -- python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
    TEST_EXIT=$?
  elif command -v su >/dev/null 2>&1; then
    su agent -s /bin/bash -c "python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA"
    TEST_EXIT=$?
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u agent python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
    TEST_EXIT=$?
  else
    python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
    TEST_EXIT=$?
  fi
else
  python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
  TEST_EXIT=$?
fi
chown -R root:root /tests 2>/dev/null || true
chmod -R 755 /tests 2>/dev/null || true
set -e
if [ "$TEST_EXIT" -eq 0 ]; then echo 1 > /logs/verifier/reward.txt; else echo 0 > /logs/verifier/reward.txt; fi
cat /logs/verifier/reward.txt
