#!/bin/bash
# 管理用户 authorized_keys。一个用户可有多把 key（多设备）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}" # project root
AUTH_FILE="${AUTH_FILE:-$PROJECT_DIR/keys/authorized_keys}"
PORT_MAP="${PORT_MAP:-$PROJECT_DIR/keys/port_map}"

usage() {
    cat <<'EOF'
用法:
  scripts/manage_key.sh list <username>
  scripts/manage_key.sh add <username> <public_key_file>
  scripts/manage_key.sh remove <username> <public_key_file>
  scripts/manage_key.sh verify <username> <public_key_file>
EOF
}

require_user() {
    local user="$1"
    if [ ! -f "$PORT_MAP" ] || ! grep -q "^$user:" "$PORT_MAP"; then
        echo "用户不存在: $user" >&2
        exit 2
    fi
}

port_for_user() {
    local user="$1"
    awk -F: -v user="$user" '$1 == user { print $2; found=1; exit } END { if (!found) exit 1 }' "$PORT_MAP"
}

key_id() {
    awk '{ print $1 " " $2 }' "$1"
}

validate_key() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "公钥文件不存在: $file" >&2
        exit 1
    fi
    if ! awk '{ exit !($1 == "ssh-ed25519" && length($2) > 10) }' "$file"; then
        echo "只支持 ssh-ed25519 公钥: $file" >&2
        exit 1
    fi
}

list_keys() {
    local user="$1"
    require_user "$user"
    [ -f "$AUTH_FILE" ] || return 0
    grep "#user:$user$" "$AUTH_FILE" || true
}

add_key() {
    local user="$1"
    local file="$2"
    require_user "$user"
    validate_key "$file"
    mkdir -p "$(dirname "$AUTH_FILE")"
    touch "$AUTH_FILE"

    local id port pubkey
    id="$(key_id "$file")"
    port="$(port_for_user "$user")"
    pubkey="$(cat "$file")"

    if awk -v id="$id" -v user="$user" 'index($0, id) && index($0, "#user:" user) { found=1 } END { exit !found }' "$AUTH_FILE"; then
        echo "key 已存在: $user"
        return 0
    fi

    printf 'permitopen="127.0.0.1:%s",no-pty,no-X11-forwarding,no-agent-forwarding %s #user:%s\n' "$port" "$pubkey" "$user" >> "$AUTH_FILE"
    echo "已添加 key: $user"
}

remove_key() {
    local user="$1"
    local file="$2"
    require_user "$user"
    validate_key "$file"
    [ -f "$AUTH_FILE" ] || { echo "authorized_keys 不存在" >&2; exit 1; }

    local id
    id="$(key_id "$file")"
    if ! awk -v id="$id" -v user="$user" 'index($0, id) && index($0, "#user:" user) { found=1 } END { exit !found }' "$AUTH_FILE"; then
        echo "key 不存在: $user" >&2
        exit 1
    fi

    awk -v id="$id" -v user="$user" '!(index($0, id) && index($0, "#user:" user)) { print }' "$AUTH_FILE" > "$AUTH_FILE.tmp"
    mv "$AUTH_FILE.tmp" "$AUTH_FILE"
    echo "已删除 key: $user"
}

verify_key() {
    local user="$1"
    local file="$2"
    require_user "$user"
    validate_key "$file"
    [ -f "$AUTH_FILE" ] || exit 1
    local id
    id="$(key_id "$file")"
    awk -v id="$id" -v user="$user" 'index($0, id) && index($0, "#user:" user) { found=1 } END { exit !found }' "$AUTH_FILE"
}

cmd="${1:-}"
case "$cmd" in
    list)
        [ $# -eq 2 ] || { usage; exit 1; }
        list_keys "$2"
        ;;
    add)
        [ $# -eq 3 ] || { usage; exit 1; }
        add_key "$2" "$3"
        ;;
    remove)
        [ $# -eq 3 ] || { usage; exit 1; }
        remove_key "$2" "$3"
        ;;
    verify)
        [ $# -eq 3 ] || { usage; exit 1; }
        verify_key "$2" "$3"
        ;;
    *)
        usage
        exit 1
        ;;
esac
