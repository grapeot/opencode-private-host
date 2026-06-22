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

ssh-keygen -t ed25519 -f "$TMP/alice_phone" -N "" -q
ssh-keygen -t ed25519 -f "$TMP/alice_mac" -N "" -q
ssh-keygen -t ed25519 -f "$TMP/bob_phone" -N "" -q

run() {
    PROJECT_DIR="$TMP" "$ROOT/scripts/manage_key.sh" "$@"
}

assert_contains() {
    local needle="$1"
    local file="$2"
    grep -q "$needle" "$file" || {
        echo "expected $file to contain: $needle" >&2
        exit 1
    }
}

assert_not_contains() {
    local needle="$1"
    local file="$2"
    if grep -q "$needle" "$file"; then
        echo "expected $file not to contain: $needle" >&2
        exit 1
    fi
}

run add alice "$TMP/alice_phone.pub"
assert_contains '#user:alice$' "$TMP/keys/authorized_keys"
assert_contains 'restrict,port-forwarding' "$TMP/keys/authorized_keys"
assert_contains 'permitopen="127.0.0.1:19001"' "$TMP/keys/authorized_keys"
assert_not_contains 'no-pty' "$TMP/keys/authorized_keys"

run add alice "$TMP/alice_mac.pub"
[ "$(grep -c '#user:alice$' "$TMP/keys/authorized_keys")" -eq 2 ]

run add alice "$TMP/alice_mac.pub"
[ "$(grep -c '#user:alice$' "$TMP/keys/authorized_keys")" -eq 2 ]

run add bob "$TMP/bob_phone.pub"
assert_contains '#user:bob$' "$TMP/keys/authorized_keys"
assert_contains 'permitopen="127.0.0.1:19002"' "$TMP/keys/authorized_keys"

run list alice | grep -q '#user:alice$'
run verify alice "$TMP/alice_phone.pub"

if run verify alice "$TMP/bob_phone.pub"; then
    echo "verify should fail for wrong key" >&2
    exit 1
fi

run remove alice "$TMP/alice_phone.pub"
[ "$(grep -c '#user:alice$' "$TMP/keys/authorized_keys")" -eq 1 ]
assert_not_contains "$(awk '{print $2}' "$TMP/alice_phone.pub")" "$TMP/keys/authorized_keys"
assert_contains "$(awk '{print $2}' "$TMP/alice_mac.pub")" "$TMP/keys/authorized_keys"

if run remove alice "$TMP/alice_phone.pub"; then
    echo "remove should fail for missing key" >&2
    exit 1
fi

if run add charlie "$TMP/alice_phone.pub"; then
    echo "add should fail for missing user" >&2
    exit 1
fi

echo "test_manage_key.sh passed"
