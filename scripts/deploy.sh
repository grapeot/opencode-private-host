#!/bin/bash
# 用 1Password op run 注入 secret 后部署
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=== 检查 .env ==="
if [ ! -f .env ]; then
    echo ".env 不存在，请复制 .env.example 并填入 1Password 引用"
    exit 1
fi

echo "=== 用 op run 注入 secret 并启动 ==="
op run --env-file .env -- docker compose up -d --build

echo "=== 状态 ==="
docker compose ps