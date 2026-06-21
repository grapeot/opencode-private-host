# RFC - opencode-private-host 架构设计

## 整体架构

两个 Docker 容器，通过 Docker 内部网络连接，只有 sshd-gateway 对外暴露一个端口。

```
iOS 客户端
  │ SSH (ed25519 key auth, 非标准端口)
  ▼
sshd-gateway 容器 (Alpine + OpenSSH + socat)
  │ direct-tcpip channel → 127.0.0.1:18080
  │ socat forward → opencode:4096 (Docker internal network)
  ▼
opencode 容器 (Alpine + 定制 opencode binary)
  │ OPENCODE_AUTH_CONTENT (env, 1Password 注入)
  │ OPENCODE_CONFIG_CONTENT (env, 可选)
  ▼
OpenAI API (GPT-5.5)
```

### 数据流详解

iOS 客户端的 SSH tunnel 实现（`SSHTunnelManager.swift`）：

1. 客户端连到 `<VPS_IP>:<SSH_PORT>`，用 ed25519 key 认证
2. 认证通过后，客户端创建 direct-tcpip channel，target = `127.0.0.1:<remotePort>`
3. sshd-gateway 容器内的 socat 监听 `127.0.0.1:18080`，forward 到 `opencode:4096`
4. 客户端本地监听 `localhost:4096`，iOS app 的 HTTP 请求走本地 4096 → SSH channel → socat → opencode

客户端的 `targetHost` 硬编码为 `127.0.0.1`（`SSHTunnelManager.swift:353`），`remotePort` 用户可配。所以 socat 监听的端口必须匹配用户在 app 里填的 remotePort。

### 为什么是 forward tunnel 而不是 reverse tunnel

客户端代码用的是 `createDirectTCPIPChannel`（SSH direct-tcpip），不是 `-R` reverse tunnel。`reverseTunnelCommand` 属性只是给用户看的调试提示，实际不走 reverse。这意味着 SSH 连接方向 = 数据流方向，不需要 VPS 主动连客户端。

## 容器设计

### sshd-gateway

职责：SSH 公钥认证 + direct-tcpip 转发到 opencode 容器。

基镜像：`alpine:latest`。安装 `openssh` 和 `socat`。

SSH 用户：创建一个 `opencode` 用户（`/usr/sbin/nologin` 作为 login shell），所有连接都以这个用户身份进来。不同用户靠 authorized_keys 里的不同 key 行区分。

sshd_config 关键配置：

```
PasswordAuthentication no       # 只允许密钥认证
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers opencode             # 只允许这一个用户
AllowTcpForwarding local        # 只允许 direct-tcpip，禁止 reverse tunnel
PermitTunnel no                 # 禁止 tun 设备
X11Forwarding no
AllowAgentForwarding no
PermitTTY no                    # 禁止 PTY
ForceCommand /usr/sbin/nologin  # 阻止 exec/shell，不影响 direct-tcpip
AuthorizedKeysFile /keys/authorized_keys
```

authorized_keys 格式（每行一个用户）：

```
permitopen="127.0.0.1:18080",no-pty,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... #user:alice
permitopen="127.0.0.1:18080",no-pty,no-X11-forwarding,no-agent-forwarding ssh-ed25519 BBBB... #user:bob
```

`permitopen` 限制这个 key 只能 forward 到指定 host:port。`no-pty` 等选项在 authorized_keys 行级生效，和 sshd_config 的全局配置形成双重保险。

### opencode

职责：运行定制版 OpenCode server。

基镜像：`alpine:latest`。安装 `libgcc libstdc++ ripgrep`（和官方 Dockerfile 一致）。

binary 来源：从 `opencode-official` 的 `private-dev-squashed` 分支本地编译，COPY 进镜像。不使用官方镜像 `ghcr.io/anomalyco/opencode:latest`（缺少 patch）。

认证注入：通过 `OPENCODE_AUTH_CONTENT` 环境变量注入 API key（JSON 格式），opencode 启动时读取，跳过磁盘 auth.json。这是 opencode 为容器/嵌入式场景设计的注入通道（`auth/index.ts:59`）。

配置注入：通过 `OPENCODE_CONFIG_CONTENT` 环境变量注入 opencode.json 配置（可选），用于限制可用模型等。

OpenCode 内置 basic auth：默认关闭（不设 `OPENCODE_SERVER_PASSWORD`）。SSH key 是唯一认证层。如果需要双因素，可以在 .env 里设置 basic auth 凭据，iOS 客户端已支持。

## Key 管理（1Password 集成，Route A）

### 原理

1Password 存储真实 secret，`.env` 文件只存 1Password 引用（`op://vault/item/field`）。部署时 `op run --env-file .env -- docker compose up -d` 解析引用为真实值，注入 Docker 环境变量。secret 不落盘。

### 具体配置

1Password 里存一个 Secure Note，内容是 opencode 的 auth JSON：

```json
{"openai":{"type":"api","key":"sk-..."}}
```

`.env` 里引用：

```
OPENCODE_AUTH_CONTENT=op://your-vault/opencode/auth_content
```

`op run` 在传给 docker compose 之前把 `op://...` 解析成真实 JSON 字符串。docker compose 把它作为环境变量传给 opencode 容器。容器内 `OPENCODE_AUTH_CONTENT` 是明文 JSON，但只在运行时内存中，不持久化。

### 安全边界

- VPS 磁盘上：只有 `.env`（1Password 引用，不是真实 key）和 docker-compose.yml
- Docker compose 进程：短暂持有明文（`op run` 解析后传给 compose）
- opencode 容器内：环境变量中有明文，不写磁盘
- 1Password：唯一持久化存储点

如果 VPS 被入侵，攻击者能从 `/proc/<pid>/environ` 读到环境变量。这是 Route A 的已知边界。更安全的 Route B（容器内 `op run`）需要额外维护，暂不做。

## 二阶段演进

### Phase 1：共享 OpenCode（当前）

一个 opencode 容器，所有用户共享。隔离靠 OpenCode session 机制（逻辑隔离）。

- sshd-gateway 内一个 socat：`127.0.0.1:18080 → opencode:4096`
- 所有 authorized_keys 行用同一个 `permitopen="127.0.0.1:18080"`
- 加用户：append 一行到 `keys/authorized_keys`，无需重启容器（OpenSSH 每次连接重读文件）

### Phase 2：每用户独立 OpenCode 容器（未来）

每个用户一个 opencode 容器（opencode-alice、opencode-bob），OS 级隔离。

- sshd-gateway 内多个 socat：`127.0.0.1:19001 → opencode-alice:4096`，`127.0.0.1:19002 → opencode-bob:4096`
- authorized_keys 每行用不同 `permitopen` 端口
- 加用户：compose 加一个 opencode service + entrypoint 加一条 socat + authorized_keys 加一行
- iOS 客户端不需要改代码，用户把 remotePort 改成自己的编号

### 迁移路径

Phase 1 → Phase 2 是纯增量操作：

1. compose 加 `opencode-alice` service
2. entrypoint 加 `socat TCP-LISTEN:19001,fork,reuseaddr TCP:opencode-alice:4096 &`
3. alice 的 authorized_keys 行改成 `permitopen="127.0.0.1:19001"`
4. alice 在 iOS app 把 remotePort 改成 19001
5. `docker compose up -d`

不需要改 Dockerfile、不需要改客户端代码、不需要改网络结构。sshhd-gateway 的 Dockerfile 原封不动。

## 镜像分发

本地 build → push 到 GHCR（GitHub Container Registry）→ VPS pull。

1. 在 `opencode-official` checkout 的 `private-dev-squashed` 分支执行 `bun run build -- --single --skip-install --target linux-x64-baseline-musl`
2. 复制 binary 到 `opencode/bin/opencode`
3. `docker build -t ghcr.io/<user>/opencode-private:latest ./opencode`
4. `docker push ghcr.io/<user>/opencode-private:latest`
5. VPS 上 `docker pull ghcr.io/<user>/opencode-private:latest`

GHCR 公开镜像免费，pull 不需要认证。push 需要 PAT（`write:packages` scope）。

## 端口可达性

SSH 端口默认 8008（可配置）。非标准端口被针对的概率低于 22。需要在目标用户网络环境下实测连通性。

备用策略：如果 8008 不通，依次试 2222、8443、443。443 上的 SSH 流量特征不明显，通常能过。

测试方法：从目标用户网络 `ssh -p 8008 opencode@<VPS_IP> -i <key>`，看连接是否稳定、是否被 RST。测试多个时段和多个运营商。

## 安全审计

### SSH 攻击面

sshd-gateway 对外暴露的唯一端口。防护措施：

- 密钥认证 only（`PasswordAuthentication no`）
- 只允许 `opencode` 用户（`AllowUsers opencode`）
- 只允许 direct-tcpip 转发（`AllowTcpForwarding local`）
- 每个 key 只能 forward 到指定端口（`permitopen`）
- 禁止 shell/exec（`ForceCommand /usr/sbin/nologin`）
- 禁止 PTY、X11、agent forwarding、tun

效果：即使用户密钥泄露，攻击者只能 forward 到 OpenCode 端口，不能在容器内执行任何命令。

### OpenCode 攻击面

opencode 容器不对外暴露任何端口。只有通过 sshd-gateway 的 direct-tcpip channel 才能到达。如果 SSH 认证被绕过，攻击者能访问 OpenCode HTTP API（包括 basic auth 如果配置了的话）。

### 容器逃逸

sshd-gateway 和 opencode 都以非 root 运行（opencode 用户 / 容器内默认用户）。host 端口只映射 sshd-gateway 的 22→8008。opencode 的 4096 不映射到 host。