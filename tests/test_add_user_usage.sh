#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

output="$("$ROOT/scripts/add_user.sh" 2>&1 || true)"

contains() {
    local needle="$1"
    if ! grep -Fq "$needle" <<< "$output"; then
        echo "expected usage output to contain: $needle" >&2
        echo "$output" >&2
        exit 1
    fi
}

contains '逻辑用户名'
contains 'keys/port_map'
contains 'opencode'

echo "test_add_user_usage.sh passed"
