#!/bin/bash
# 输出 iOS 客户端可导入的 Host Config JSON。不包含密码、token 或 SSH 私钥。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}" # project root
PORT_MAP="${PORT_MAP:-$PROJECT_DIR/keys/port_map}"

usage() {
    cat <<'EOF'
用法:
  scripts/export_host_config.sh <username> <gateway_host> [display_name]

示例:
  scripts/export_host_config.sh yage gateway.example.invalid "Yage OpenCode"

输出可直接粘贴到 iOS: Settings -> Current Host -> Add Host -> Import Host Config。
EOF
}

require_safe_value() {
    local label="$1"
    local value="$2"
    local pattern="$3"
    if ! [[ "$value" =~ $pattern ]]; then
        echo "$label 包含不支持的字符: $value" >&2
        exit 1
    fi
}

port_for_user() {
    local user="$1"
    if [ ! -f "$PORT_MAP" ]; then
        echo "port_map 不存在: $PORT_MAP" >&2
        exit 2
    fi
    awk -F: -v user="$user" '$1 == user { print $2; found=1; exit } END { if (!found) exit 1 }' "$PORT_MAP"
}

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    usage
    exit 1
fi

username="$1"
gateway_host="$2"
display_name="${3:-$username OpenCode}"

require_safe_value "username" "$username" '^[a-z][a-z0-9_-]*$'
require_safe_value "gateway_host" "$gateway_host" '^[A-Za-z0-9._:-]+$'
require_safe_value "display_name" "$display_name" '^[A-Za-z0-9 ._-]+$'

remote_port="$(port_for_user "$username")" || {
    echo "用户不存在: $username" >&2
    exit 2
}

ssh_port="${SSH_PORT:-8006}"
if [ -f "$PROJECT_DIR/.env" ]; then
    env_ssh_port="$(awk -F= '$1 == "SSH_PORT" { print $2; found=1; exit } END { if (!found) exit 0 }' "$PROJECT_DIR/.env" | tr -d '"' | tr -d "'")"
    if [ -n "$env_ssh_port" ]; then
        ssh_port="$env_ssh_port"
    fi
fi

require_safe_value "ssh_port" "$ssh_port" '^[0-9]+$'
require_safe_value "remote_port" "$remote_port" '^[0-9]+$'

cat <<EOF
{
  "version": 1,
  "name": "$display_name",
  "transport": "sshTunnel",
  "ssh": {
    "host": "$gateway_host",
    "port": $ssh_port,
    "username": "opencode",
    "remotePort": $remote_port
  }
}
EOF
