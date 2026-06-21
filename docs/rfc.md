# RFC - opencode-private-host 架构设计

## 整体架构

一个 SSH 网关容器 + N 个 OpenCode 容器（每用户一个），通过 Docker 内部网络连接。只有 sshd-gateway 对外暴露一个端口。

```
[iOS 客户端](https://github.com/grapeot/opencode_ios_client)
  │ SSH (ed25519 key auth, 非标准端口)
  ▼
sshd-gateway 容器 (Alpine + OpenSSH + socat)
  │ authorized_keys 每行 permitopen 到对应用户的 socat 端口
  │ socat 19001 → opencode-alice:4096
  │ socat 19002 → opencode-bob:4096
  │ ...
  ▼
opencode-<user> 容器 (Alpine + 定制 opencode binary)
  │ 独立 data volume (XDG_DATA_HOME / XDG_CONFIG_HOME)
  │ 独立 workspace volume (context-infrastructure + tavily skill)
  │ OPENCODE_AUTH_CONTENT (env, 1Password 注入, 所有用户共享同一组 key)
  ▼
OpenAI API (GPT-5.5)
```

### 数据流

[iOS 客户端](https://github.com/grapeot/opencode_ios_client)的 SSH tunnel 实现（`SSHTunnelManager.swift`）：

1. 客户端连到 `<VPS_IP>:<SSH_PORT>`，用 ed25519 key 认证
2. 认证通过后，客户端创建 direct-tcpip channel，target = `127.0.0.1:<remotePort>`
3. sshd-gateway 容器内对应的 socat 实例监听该端口，forward 到 `opencode-<user>:4096`
4. 客户端本地监听 `localhost:4096`，iOS app 的 HTTP 请求走本地 4096 → SSH channel → socat → opencode

客户端的 `targetHost` 硬编码为 `127.0.0.1`（`SSHTunnelManager.swift:353`），`remotePort` 用户可配。每个用户的 remotePort 不同（19001、19002...），用户在 iOS app 的 SSH Tunnel 设置里填自己的编号。

### 为什么每用户一个容器

OpenCode 的 session 模型是 flat 的：所有 session 在同一个 SQLite 数据库里，通过 session ID 区分，没有 owner/用户的概念。文件操作也都落在同一个 `/workspace` 下，没有 per-user 的访问控制。共享 OpenCode 容器意味着用户之间能互相看到 session 和文件，这不是隔离。

per-user 容器提供真正的 OS 级隔离：独立的进程空间、独立的文件系统、独立的 SQLite 数据库。用户 A 无法访问用户 B 的任何东西。

## 存储三层设计

### 第一层：OpenCode 自身状态（持久化，per-user named volume）

opencode 的所有数据路径由 XDG 环境变量控制（`packages/core/src/global.ts:11-14`）：

- `XDG_DATA_HOME` → `~/.local/share/opencode/`（session 数据库、log、repos）
- `XDG_CONFIG_HOME` → `~/.config/opencode/`（配置文件）
- `XDG_STATE_HOME` → state 目录
- `XDG_CACHE_HOME` → cache 目录（不持久化，设为 /tmp）

每个用户一个 Docker named volume（`opencode-data-alice`、`opencode-data-bob`），挂载到容器的 `/data`（`XDG_DATA_HOME=/data`）。容器销毁后 volume 保留，重建容器后数据恢复。opencode 首次启动会自动创建数据库和目录，不需要 bootstrap。

### 第二层：API key（BYOK + 可选 1Password 注入）

OpenAI 的 key 由用户自己提供：用户通过 OpenCode web 界面的 "connect new provider" 功能走 ChatGPT OAuth 登录，用自己 的 ChatGPT subscription。OAuth token 存在各自容器的 volume 里（`XDG_DATA_HOME` 下的 `auth.json`），持久化不丢失，opencode 自动 refresh。不通过 `OPENCODE_AUTH_CONTENT` 统一注入 OpenAI 的 OAuth token，因为多实例共用同一 OAuth refresh token 容易触发 OpenAI 封号。

`OPENCODE_AUTH_CONTENT` 注入机制保留在架构中，用于未来注入非 OAuth 类的 provider key（如 ollama-cloud for GLM-5.2 的 API key）。此时 key 通过 1Password `op run` 注入，所有用户共享运营者的 key，不落盘。

`OPENCODE_AUTH_CONTENT` 的内容格式（`packages/opencode/src/auth/index.ts:59`）：

```json
{"ollama-cloud":{"type":"api","key":"..."}}
```

### 第三层：用户 OAuth token（持久化，per-user volume）

第三方 skill（Outlook、Google Docs 等）的 OAuth token 存在用户自己的 volume 里。路径取决于 skill 配置，通常落在 `XDG_CONFIG_HOME` 或 `XDG_DATA_HOME` 下的 skill 子目录。

OAuth 登录方式：Outlook skill 已支持 device code flow（`outlook_skill/src/outlook_skill/auth.py:29`，`initiate_device_flow`）。device code flow 不弹窗——返回一个 URL + code，用户在自己的手机浏览器上打开 `https://microsoft.com/devicelogin` 输入 code 完成登录。token 回来后 `SerializableTokenCache` 序列化存到 `token_cache_path`，下次自动 refresh。不需要 VPS 上有浏览器，不需要用户远程操作 VPS。

其他需要 OAuth 的 skill 如果也走 device code flow 或类似的 non-interactive flow，同样适用。如果某个 skill 只支持 interactive browser flow（`acquire_token_interactive`），在远程部署下走不通，需要改 skill 或不用。

### 第四层：用户 workspace（持久化，per-user bind mount 或 named volume）

每个用户的 workspace 是一个独立目录，包含 context-infrastructure（公版 clone）+ tavily skill。挂载到容器的 `/workspace`。

workspace 结构：

```
/workspace/
├── AGENTS.md              # context-infrastructure 的根路由
├── rules/                 # SOUL.md, USER.md, COMMUNICATION.md, skills/ 等
├── contexts/              # memory, survey_sessions, daily_records
├── adhoc_jobs/tavily_skill/  # tavily skill 安装位置
├── tools/
└── docs/
```

tavily skill 从 `TAVILY_API_KEY` 环境变量读 key（`skill_tavily.md:28`），也支持 `ONEPASSWORD_TAVILY_REFERENCE`。在容器化部署中，`TAVILY_API_KEY` 作为环境变量注入（通过 1Password 或直接在 .env 里配），skill 不需要 `.env` 文件就能工作。

## 容器设计

### sshd-gateway

职责：SSH 公钥认证 + direct-tcpip 转发到对应用户的 opencode 容器。

基镜像：`alpine:latest`。安装 `openssh` 和 `socat`。

SSH 用户：创建一个 `opencode` 用户（`/usr/sbin/nologin` 作为 login shell），所有连接都以这个用户身份进来。不同用户靠 authorized_keys 里的不同 key 行区分，每行用不同的 `permitopen` 端口路由到各自的 opencode 容器。

sshd_config 关键配置：

```
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers opencode
AllowTcpForwarding local
PermitTunnel no
X11Forwarding no
AllowAgentForwarding no
PermitTTY no
ForceCommand /usr/sbin/nologin
AuthorizedKeysFile /keys/authorized_keys
```

authorized_keys 格式（每行一个用户，端口不同）：

```
permitopen="127.0.0.1:19001",no-pty,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... #user:alice
permitopen="127.0.0.1:19002",no-pty,no-X11-forwarding,no-agent-forwarding ssh-ed25519 BBBB... #user:bob
```

entrypoint.sh 动态生成 socat 规则：扫描 authorized_keys 里的 `permitopen` 端口，为每个端口启动一个 socat 实例 forward 到对应的 `opencode-<user>:4096`。这样加用户时只需要追加 authorized_keys 一行 + compose 加一个 service，entrypoint 重启后自动起 socat。

### opencode-\<user\>

职责：运行定制版 OpenCode server，为单个用户提供服务。

基镜像：`alpine:latest`。安装 `libgcc libstdc++ ripgrep`（和官方 Dockerfile 一致）。

binary 来源：从 `opencode-official` 的 `private-dev-squashed` 分支本地编译，COPY 进镜像。

认证注入：`OPENCODE_AUTH_CONTENT` 环境变量（可选，用于注入非 OAuth 类 provider key 如 GLM-5.2）。OpenAI 认证由用户通过 OpenCode web 界面自行完成（ChatGPT OAuth），token 存在容器 volume 里。OpenCode 内置 basic auth 关闭（不设 `OPENCODE_SERVER_PASSWORD`），SSH key 是唯一入口认证。

Tavily key 注入：`TAVILY_API_KEY` 环境变量，所有用户共享运营者的 key。

存储：

- `opencode-data-<user>` named volume → `/data`（XDG_DATA_HOME）
- `opencode-config-<user>` named volume → `/data/config`（XDG_CONFIG_HOME）
- workspace bind mount 或 named volume → `/workspace`

## 加用户流程

运营者执行 CLI 命令（`scripts/add_user.sh <username> <public_key_file>`），CLI 完成：

1. 在 docker-compose.yml 里追加一个 `opencode-<username>` service（基于模板）
2. 在 sshd-gateway 的 entrypoint 配置里追加一条 socat 规则（`127.0.0.1:<port> → opencode-<username>:4096`）
3. 创建 workspace 目录，clone context-infrastructure，安装 tavily skill
4. 在 authorized_keys 里追加该用户的公钥行（`permitopen` 到对应端口）
5. `docker compose up -d` 启动新容器 + 重启 sshd-gateway（让新 socat 生效）

端口分配规则：从 19001 开始递增，按用户名 hash 或顺序分配。CLI 维护一个端口分配表（`keys/port_map` 文件，`username:port` 格式）。

## 删用户流程

运营者执行 CLI 命令（`scripts/remove_user.sh <username>`），CLI 完成：

1. 从 docker-compose.yml 里移除对应 service
2. 从 sshd-gateway entrypoint 配置里移除对应 socat 规则
3. 从 authorized_keys 里移除对应行
4. `docker compose stop opencode-<username>` + `docker compose rm -f opencode-<username>`
5. 删除 named volume（`docker volume rm opencode-data-<username> opencode-config-<username>`）
6. 删除 workspace 目录
7. 从端口分配表里移除记录
8. `docker compose up -d` 更新 sshd-gateway

## Key 管理（1Password 集成，Route A）

### 原理

1Password 存储真实 secret，`.env` 文件只存 1Password 引用（`op://vault/item/field`）。部署时 `op run --env-file .env -- docker compose up -d` 解析引用为真实值，注入 Docker 环境变量。secret 不落盘。

### 具体配置

1Password 里存一个 Secure Note：

1. `opencode/auth_content`：可选的 opencode auth JSON（非 OAuth 类 provider key，如 ollama-cloud for GLM-5.2）
2. `tavily/api_key`：Tavily API key（纯字符串，所有用户共享）

`.env` 里引用：

```
OPENCODE_AUTH_CONTENT=op://your-vault/opencode/auth_content
TAVILY_API_KEY=op://your-vault/tavily/api_key
```

`OPENCODE_AUTH_CONTENT` 是可选的——如果不需要注入任何 provider key，`.env` 里留空或不设这个变量。OpenAI 的认证由用户在 OpenCode web 界面自行完成。

### 安全边界

- VPS 磁盘上：只有 `.env`（1Password 引用）和 docker-compose.yml
- Docker compose 进程：短暂持有明文
- opencode 容器内：环境变量中有明文，不写磁盘
- 1Password：唯一持久化存储点

Route A 的已知边界：VPS 被入侵后攻击者能从 `/proc/<pid>/environ` 读到环境变量。暂不做更安全的 Route B（容器内 op run）。

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

效果：即使用户密钥泄露，攻击者只能 forward 到该用户对应的 OpenCode 端口，不能在容器内执行任何命令，不能访问其他用户的容器。

### OpenCode 攻击面

每个 opencode 容器不对外暴露任何端口。只有通过 sshd-gateway 的 direct-tcpip channel（且 `permitopen` 匹配）才能到达。用户 A 的 key 只能 forward 到用户 A 的 opencode 端口，物理上无法访问用户 B 的容器。

### 容器逃逸

sshd-gateway 和各 opencode 容器都以非 root 运行。host 端口只映射 sshd-gateway 的 22→8008。所有 opencode 容器的 4096 不映射到 host。容器间通过 Docker internal network 通信，没有 host 端口映射。