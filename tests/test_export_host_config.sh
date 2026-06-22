#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/keys"
cat > "$TMP/keys/port_map" <<'EOF'
alice:19001
bob:19002
EOF
cat > "$TMP/.env" <<'EOF'
SSH_PORT=18006
EOF

output="$(PROJECT_DIR="$TMP" "$ROOT/scripts/export_host_config.sh" alice gateway.example.invalid "Alice OpenCode")"

contains() {
    local needle="$1"
    if ! grep -Fq "$needle" <<< "$output"; then
        echo "expected output to contain: $needle" >&2
        echo "$output" >&2
        exit 1
    fi
}

contains '"version": 1'
contains '"name": "Alice OpenCode"'
contains '"transport": "sshTunnel"'
contains '"host": "gateway.example.invalid"'
contains '"port": 18006'
contains '"username": "opencode"'
contains '"remotePort": 19001'

if PROJECT_DIR="$TMP" "$ROOT/scripts/export_host_config.sh" charlie gateway.example.invalid >/dev/null 2>&1; then
    echo "export should fail for missing user" >&2
    exit 1
fi

echo "test_export_host_config.sh passed"
