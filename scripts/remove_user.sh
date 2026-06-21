#!/bin/bash
# 删除一个隔离的 OpenCode 用户：keys + port_map + compose service + workspace + volumes。
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "用法: $0 <username>"
    exit 1
fi

USERNAME="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}" # project root
PORT_MAP="$PROJECT_DIR/keys/port_map"
AUTH_FILE="$PROJECT_DIR/keys/authorized_keys"

if [ ! -f "$PORT_MAP" ] || ! grep -q "^$USERNAME:" "$PORT_MAP"; then
    echo "用户不存在: $USERNAME" >&2
    exit 1
fi

if [ -f "$AUTH_FILE" ]; then
    awk -v marker="#user:$USERNAME" 'index($0, marker) == 0 { print }' "$AUTH_FILE" > "$AUTH_FILE.tmp"
    mv "$AUTH_FILE.tmp" "$AUTH_FILE"
fi

awk -F: -v user="$USERNAME" '$1 != user { print }' "$PORT_MAP" > "$PORT_MAP.tmp"
mv "$PORT_MAP.tmp" "$PORT_MAP"

PROJECT_DIR="$PROJECT_DIR" "$SCRIPT_DIR/render_compose.sh"

if [ "${SKIP_DOCKER_UP:-0}" != "1" ]; then
    (cd "$PROJECT_DIR" && docker compose rm -sf "opencode-$USERNAME" 2>/dev/null || true)
    docker volume rm "opencode-data-$USERNAME" "opencode-config-$USERNAME" 2>/dev/null || true
    (cd "$PROJECT_DIR" && op run --env-file .env -- docker compose up -d --build --remove-orphans)
fi

if [ "${KEEP_WORKSPACE:-0}" != "1" ]; then
    rm -rf "$PROJECT_DIR/workspaces/$USERNAME"
fi

echo "已删除用户 $USERNAME"
