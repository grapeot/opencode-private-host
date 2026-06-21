#!/bin/bash
# 根据 keys/port_map 渲染 docker-compose.yml。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}" # project root
PORT_MAP="$PROJECT_DIR/keys/port_map"
COMPOSE="$PROJECT_DIR/docker-compose.yml"

mkdir -p "$PROJECT_DIR/keys"
touch "$PORT_MAP"

cat > "$COMPOSE" <<'EOF'
services:
  sshd-gateway:
    build: ./sshd-gateway
    container_name: sshd-gateway
    restart: unless-stopped
    ports:
      - "${SSH_PORT:-8006}:22"
    volumes:
      - ./keys:/keys:ro
    networks:
      - internal
EOF

while IFS=: read -r username port; do
    [ -z "$username" ] && continue
    [ -z "$port" ] && continue
    cat >> "$COMPOSE" <<EOF

  opencode-$username:
    platform: linux/amd64
    image: \${OPENCODE_IMAGE:-ghcr.io/grapeot/opencode-private:latest}
    container_name: opencode-$username
    restart: unless-stopped
    environment:
      OPENCODE_AUTH_CONTENT: "\${OPENCODE_AUTH_CONTENT:-}"
      TAVILY_API_KEY: "\${TAVILY_API_KEY:-}"
      OPENCODE_CONFIG_CONTENT: "\${OPENCODE_CONFIG_CONTENT:-}"
    volumes:
      - opencode-data-$username:/data
      - opencode-config-$username:/data/config
      - ./workspaces/$username:/workspace
    networks:
      - internal
EOF
done < "$PORT_MAP"

cat >> "$COMPOSE" <<'EOF'

networks:
  internal:
    driver: bridge

volumes:
EOF

if [ -s "$PORT_MAP" ]; then
    while IFS=: read -r username port; do
        [ -z "$username" ] && continue
        cat >> "$COMPOSE" <<EOF
  opencode-data-$username:
    name: opencode-data-$username
  opencode-config-$username:
    name: opencode-config-$username
EOF
    done < "$PORT_MAP"
else
    cat >> "$COMPOSE" <<'EOF'
  sshd-gateway-empty:
    name: sshd-gateway-empty
EOF
fi

echo "已生成 $COMPOSE"
