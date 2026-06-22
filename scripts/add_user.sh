#!/bin/bash
# 创建一个隔离的 OpenCode 用户：port_map + workspace + authorized_keys + compose service。
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "用法: $0 <username> <public_key_file> [gateway_host] [display_name]"
    echo "示例: $0 alice /path/to/alice_ed25519.pub gateway.example.invalid \"Alice OpenCode\""
    echo ""
    echo "<username> 是逻辑用户名（写入 keys/port_map、容器 opencode-<username>），"
    echo "由运营者指定，格式 ^[a-z][a-z0-9_-]*$。不是 SSH 登录名 opencode。"
    echo "创建前请向运营者确认用户名，不要从 hostname 或示例名猜测。"
    echo "现有用户: cat keys/port_map"
    exit 1
fi

USERNAME="$1"
KEY_FILE="$2"
GATEWAY_HOST="${3:-}"
DISPLAY_NAME="${4:-$USERNAME OpenCode}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}" # project root
PORT_MAP="$PROJECT_DIR/keys/port_map"
WORKSPACE_DIR="$PROJECT_DIR/workspaces/$USERNAME"

if ! printf '%s' "$USERNAME" | grep -Eq '^[a-z][a-z0-9_-]*$'; then
    echo "username 必须匹配 ^[a-z][a-z0-9_-]*$: $USERNAME" >&2
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "公钥文件不存在: $KEY_FILE" >&2
    exit 1
fi

mkdir -p "$PROJECT_DIR/keys" "$PROJECT_DIR/workspaces"
touch "$PORT_MAP"

if grep -q "^$USERNAME:" "$PORT_MAP"; then
    echo "用户已存在: $USERNAME" >&2
    exit 1
fi

LAST_PORT=$(awk -F: 'BEGIN { max=19000 } $2+0 > max { max=$2+0 } END { print max }' "$PORT_MAP")
PORT=$((LAST_PORT + 1))

echo "$USERNAME:$PORT" >> "$PORT_MAP"

if [ "${SKIP_WORKSPACE_INIT:-0}" != "1" ]; then
    if [ -e "$WORKSPACE_DIR" ] && [ "$(ls -A "$WORKSPACE_DIR" 2>/dev/null || true)" ]; then
        echo "workspace 已存在且非空: $WORKSPACE_DIR" >&2
        exit 1
    fi
    rm -rf "$WORKSPACE_DIR"
    git clone --depth 1 https://github.com/grapeot/context-infrastructure "$WORKSPACE_DIR"
    git clone --depth 1 https://github.com/grapeot/tavily-skill "$WORKSPACE_DIR/adhoc_jobs/tavily_skill"
    (cd "$WORKSPACE_DIR/adhoc_jobs/tavily_skill" && uv venv .venv && uv pip install --python .venv/bin/python -e '.[dev]')
else
    mkdir -p "$WORKSPACE_DIR"
fi

PROJECT_DIR="$PROJECT_DIR" "$SCRIPT_DIR/manage_key.sh" add "$USERNAME" "$KEY_FILE"
PROJECT_DIR="$PROJECT_DIR" "$SCRIPT_DIR/render_compose.sh"

if [ "${SKIP_DOCKER_UP:-0}" != "1" ]; then
    (cd "$PROJECT_DIR" && op run --env-file .env -- docker compose up -d --build --remove-orphans)
fi

echo "已添加用户 $USERNAME"
echo "SSH user: opencode"
echo "Remote port: $PORT"
if [ -n "$GATEWAY_HOST" ]; then
    echo ""
    echo "iOS Host Config JSON:"
    PROJECT_DIR="$PROJECT_DIR" "$SCRIPT_DIR/export_host_config.sh" "$USERNAME" "$GATEWAY_HOST" "$DISPLAY_NAME"
else
    echo ""
    echo "生成 iOS Host Config JSON:"
    echo "  scripts/export_host_config.sh $USERNAME <gateway_host> \"$DISPLAY_NAME\""
fi
