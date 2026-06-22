#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/keys" "$TMP/workspaces"
cat > "$TMP/.env" <<'EOF'
SSH_PORT=18006
EOF
ssh-keygen -t ed25519 -f "$TMP/alice" -N "" -q

output="$(PROJECT_DIR="$TMP" SKIP_WORKSPACE_INIT=1 SKIP_DOCKER_UP=1 "$ROOT/scripts/add_user.sh" alice "$TMP/alice.pub" gateway.example.invalid "Alice OpenCode")"

contains() {
    local needle="$1"
    if ! grep -Fq "$needle" <<< "$output"; then
        echo "expected output to contain: $needle" >&2
        echo "$output" >&2
        exit 1
    fi
}

contains '已添加用户 alice'
contains 'SSH user: opencode'
contains 'Remote port: 19001'
contains 'iOS Host Config JSON:'
contains '"name": "Alice OpenCode"'
contains '"host": "gateway.example.invalid"'
contains '"port": 18006'
contains '"remotePort": 19001'

grep -Fq 'alice:19001' "$TMP/keys/port_map"
grep -Fq '#user:alice' "$TMP/keys/authorized_keys"
test -f "$TMP/docker-compose.yml"

echo "test_add_user_host_config.sh passed"
