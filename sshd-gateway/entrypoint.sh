#!/bin/sh
set -e

HOST_KEY=/etc/ssh/ssh_host_ed25519_key

if [ ! -f "$HOST_KEY" ]; then
    ssh-keygen -t ed25519 -f "$HOST_KEY" -N "" -q
fi

mkdir -p /run/sshd

# 动态生成 socat 规则：扫描 authorized_keys 里的 permitopen 端口，
# 为每个端口启动一个 socat forward 到对应的 opencode-<user> 容器。
# 端口与用户名的映射从 /keys/port_map 读取（格式：username:port）。
PORT_MAP="/keys/port_map"
AUTH_KEYS="/keys/authorized_keys"

if [ -f "$PORT_MAP" ] && [ -f "$AUTH_KEYS" ]; then
    while IFS=: read -r username port; do
        [ -z "$username" ] && continue
        [ -z "$port" ] && continue

        # 只为 authorized_keys 里实际存在的端口起 socat
        if grep -q "permitopen=\"127.0.0.1:${port}\"" "$AUTH_KEYS"; then
            echo "[entrypoint] socat 127.0.0.1:${port} -> opencode-${username}:4096"
            socat TCP-LISTEN:"${port}",fork,reuseaddr TCP:"opencode-${username}":4096 &
        fi
    done < "$PORT_MAP"
fi

/usr/sbin/sshd -D