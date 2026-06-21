#!/bin/bash
# 从 opencode-official checkout 构建 opencode binary 并 build Docker 镜像
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 配置
OPENCODE_CHECKOUT="${OPENCODE_CHECKOUT:-$(realpath ../opencode_ios_client/opencode-official)}"
GHCR_USER="${GHCR_USER:-your-github-username}"
IMAGE_NAME="${IMAGE_NAME:-opencode-private}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=== 1. 构建 opencode binary ==="
echo "checkout: $OPENCODE_CHECKOUT"

cd "$OPENCODE_CHECKOUT"
git branch --show-current | grep -q "private-dev-squashed" || {
    echo "当前分支不是 private-dev-squashed，请先切换"
    exit 1
}

echo "install dependencies..."
bun install

echo "build all target binaries (needed for linux-x64-baseline-musl)..."
cd packages/opencode
bun run build
cd "$OPENCODE_CHECKOUT"

BINARY="packages/opencode/dist/opencode-linux-x64-baseline-musl/bin/opencode"
if [ ! -f "$BINARY" ]; then
    echo "binary not found at $BINARY"
    exit 1
fi

echo "=== 2. 复制 binary 到 Docker context ==="
mkdir -p "$PROJECT_DIR/opencode/bin"
cp "$BINARY" "$PROJECT_DIR/opencode/bin/opencode"
chmod +x "$PROJECT_DIR/opencode/bin/opencode"

echo "=== 3. Build Docker 镜像 ==="
cd "$PROJECT_DIR"
docker build --platform linux/amd64 -t "ghcr.io/$GHCR_USER/$IMAGE_NAME:$IMAGE_TAG" ./opencode

echo "=== 4. Push 到 GHCR ==="
docker push "ghcr.io/$GHCR_USER/$IMAGE_NAME:$IMAGE_TAG"

echo "完成: ghcr.io/$GHCR_USER/$IMAGE_NAME:$IMAGE_TAG"
