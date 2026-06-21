#!/bin/bash
# 删除一个用户的 SSH 公钥
# 用法: scripts/remove_user.sh <username>
set -e

if [ $# -lt 1 ]; then
    echo "用法: $0 <username>"
    exit 1
fi

USERNAME="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AUTH_FILE="$PROJECT_DIR/keys/authorized_keys"

if [ ! -f "$AUTH_FILE" ]; then
    echo "authorized_keys 不存在"
    exit 1
fi

if ! grep -q "#user:$USERNAME$" "$AUTH_FILE"; then
    echo "用户 $USERNAME 不存在"
    exit 1
fi

sed -i.bak "/#user:$USERNAME$/d" "$AUTH_FILE"
echo "已删除用户 $USERNAME"