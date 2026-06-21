#!/bin/sh
set -e

HOST_KEY=/etc/ssh/ssh_host_ed25519_key

if [ ! -f "$HOST_KEY" ]; then
    ssh-keygen -t ed25519 -f "$HOST_KEY" -N "" -q
fi

mkdir -p /run/sshd

FORWARD_PORT="${FORWARD_PORT:-18080}"
TARGET_HOST="${TARGET_HOST:-opencode}"
TARGET_PORT="${TARGET_PORT:-4096}"

socat TCP-LISTEN:"$FORWARD_PORT",fork,reuseaddr TCP:"$TARGET_HOST":"$TARGET_PORT" &

/usr/sbin/sshd -D