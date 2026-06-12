#!/bin/bash
# Offline verifier: all deps (pytest, playwright, chromium, pillow, numpy)
# are baked into /opt/venv at build time. No network needed here.
export PATH="/opt/venv/bin:/usr/local/fbpkg/vscodefb/vscode-server/418/bin/remote-cli:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/usr/facebook/ops/scripts:/usr/facebook/scripts:/usr/facebook/scripts/db:/sbin:/var/www/scripts/bin:/home/shuaybqureshi/.yarn/bin:/home/shuaybqureshi/bin"

mkdir -p /logs/verifier
cd /app
set +e
python -m pytest /tests/test_outputs.py -v -rA
PYTEST_EXIT=$?
set -e

if [ $PYTEST_EXIT -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
cat /logs/verifier/reward.txt
