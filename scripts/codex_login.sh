#!/usr/bin/env bash
set -euo pipefail
export PATH="$PATH:/usr/local/share/npm-global/bin"
if [ -d "/workspace" ]; then
  cd /workspace
fi
container_ip=$(hostname -I | awk '{print $1}')
socat TCP-LISTEN:1455,fork,reuseaddr,bind="$container_ip" TCP:127.0.0.1:1455 >/tmp/codex-login-bridge.log 2>&1 &
bridge_pid=$!
cleanup() {
  if [ -n "$bridge_pid" ]; then
    kill "$bridge_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
codex login
