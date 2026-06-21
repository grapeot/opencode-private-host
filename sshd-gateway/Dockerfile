FROM alpine:latest

RUN apk add --no-cache openssh socat

RUN addgroup -S opencode && adduser -S -G opencode opencode \
    && mkdir -p /home/opencode/.ssh \
    && chown opencode:opencode /home/opencode/.ssh \
    && chmod 700 /home/opencode/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/keys"]

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]