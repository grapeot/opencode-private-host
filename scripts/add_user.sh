#!/bin/bash
# 添加一个用户的 SSH 公钥到 authorized_keys
# 用法: scripts/add_user.sh <username> <public_key_file>
set -e

if [ $# -lt 2 ]; then
    echo "用法: $0 <username> <public_key_file>"
    echo "示例: $0 alice /path/to/alice_ed25519.pub"
    exit 1
fi

USERNAME="$1"
KEY_FILE="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AUTH_FILE="$PROJECT_DIR/keys/authorized_keys"

if [ ! -f "$KEY_FILE" ]; then
    echo "公钥文件不存在: $KEY_FILE"
    exit 1
fi

PUBKEY=$(cat "$KEY_FILE")

if [ -f "$AUTH_FILE" ] && grep -q "#user:$USERNAME$" "$AUTH_FILE"; then
    echo "用户 $USERNAME 已存在，更新中..."
    sed -i.bak "/#user:$USERNAME$/d" "$AUTH_FILE"
fi

echo "permitopen=\"127.0.0.1:18080\",no-pty,no-X11-forwarding,no-agent-forwarding $PUBKEY #user:$USERNAME" >> "$AUTH_FILE"

echo "已添加用户 $USERNAME"
echo "无需重启容器，OpenSSH 下次连接自动读取新文件"