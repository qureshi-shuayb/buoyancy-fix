#!/bin/bash
# Black-box end-to-end verifier for Homebidder. Builds the agent's project,
# starts the server, exercises it over HTTP, writes the reward file.
set -u
PORT=3000
export PORT
cd /app

apt-get update
apt-get install -y curl psmisc

npm install
npm run build --if-present

fuser -k "$PORT/tcp" 2>/dev/null || true
sleep 1

npm start &
SERVER_PID=$!

for i in $(seq 1 30); do
  if curl -sf "http://localhost:$PORT/listings" >/dev/null 2>&1; then
    echo "Server up after ${i}s"; break
  fi
  sleep 1
done

curl -LsSf https://astral.sh/uv/0.9.7/install.sh | sh
source "$HOME/.local/bin/env"

set +e
uvx \
  --with pytest==8.4.1 \
  --with pytest-json-ctrf==0.3.5 \
  --with requests==2.32.3 \
  pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
TEST_EXIT=$?

kill "$SERVER_PID" 2>/dev/null || true

mkdir -p /logs/verifier
if [ "$TEST_EXIT" -eq 0 ]; then echo 1 > /logs/verifier/reward.txt; else echo 0 > /logs/verifier/reward.txt; fi
cat /logs/verifier/reward.txt
