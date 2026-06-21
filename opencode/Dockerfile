FROM alpine:latest

RUN apk add --no-cache libgcc libstdc++ ripgrep

RUN addgroup -S opencode && adduser -S -G opencode opencode \
    && mkdir -p /data/home /data/config \
    && chown -R opencode:opencode /data

COPY bin/opencode /usr/local/bin/opencode
RUN chmod +x /usr/local/bin/opencode

WORKDIR /workspace

ENV HOME=/data/home
ENV XDG_DATA_HOME=/data
ENV XDG_CONFIG_HOME=/data/config
ENV XDG_CACHE_HOME=/tmp/opencode-cache

EXPOSE 4096

USER opencode

CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]
