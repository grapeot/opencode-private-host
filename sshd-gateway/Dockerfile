FROM alpine:latest

RUN apk add --no-cache openssh socat

# keys/authorized_keys bind mount 保留 host 文件 uid。OpenSSH 只接受属主为 root
# 或登录用户 (opencode) 的 AuthorizedKeysFile；uid 不匹配会静默忽略公钥。
# 默认 1001 与常见 VPS 部署用户一致；若 `id -u` 不同，改此处 uid/gid 后 rebuild。
RUN addgroup -S -g 1001 opencode && adduser -S -G opencode -u 1001 opencode \
    && passwd -d opencode \
    && mkdir -p /home/opencode/.ssh \
    && chown opencode:opencode /home/opencode/.ssh \
    && chmod 700 /home/opencode/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/keys"]

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
