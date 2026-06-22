# opencode-private-host

通过 SSH 公钥认证在自有 VPS 上安全部署定制版 OpenCode，支持多用户。对外只暴露一个 SSH 端口，OpenCode HTTP 端口不对外。

## 架构

一个 SSH 网关容器 + 每用户一个 OpenCode 容器，通过内部网络连接：

```
[iOS 客户端](https://github.com/grapeot/opencode_ios_client)
  │ SSH (ed25519 key auth, 非标准端口)
  ▼
sshd-gateway 容器 (Alpine + OpenSSH + socat)
  │ direct-tcpip → 127.0.0.1:<remotePort> → socat
  ▼
opencode-<username> 容器 (Alpine + 定制 opencode binary)
  │ 用户在 Web UI 里连接自己的 ChatGPT / provider 账号
```

### 安全模型

- SSH 公钥认证替代 HTTP basic auth
- `authorized_keys` 每行用 `restrict,port-forwarding,permitopen=...` 限制只能 forward 到 OpenCode 端口
- `ForceCommand /usr/sbin/nologin` 阻止 shell/exec
- `PermitTTY no`、`AllowAgentForwarding no`、`PermitTunnel no`
- OpenCode 端口不映射到 host，只通过 SSH channel 可达
- 每个用户独立 OpenCode 容器、独立 `/data` volume、独立 `workspaces/<username>`
- Tavily key 通过 1Password `op run` 注入，不落盘
- OpenAI / Codex 默认 BYOK：用户在 OpenCode web UI 自己连接账号

## 快速开始

### 1. 选择 opencode 镜像

普通部署直接使用 `.env` 里的 `OPENCODE_IMAGE`，不需要本地 `opencode-official` checkout，也不需要从源码构建 OpenCode。

只有维护者要重建并 push GHCR 镜像时，才需要本地 `opencode-official` checkout（`private-dev-squashed` 分支）：

```bash
export OPENCODE_CHECKOUT=/path/to/opencode-official
export GHCR_USER=your-github-username
./scripts/build_image.sh
```

### 2. 配置 1Password

在 1Password 里保存 Tavily API key，并在 `.env` 中用 `op://...` 引用。OpenAI / Codex 默认不由运营者注入，用户进入 OpenCode web UI 后自己连接账号。

可选：如果以后需要注入非 OAuth provider auth（例如 GLM / ollama-cloud），可以把 OpenCode auth JSON 放进 1Password，然后填到 `OPENCODE_AUTH_CONTENT`。

```json
{"provider":{"type":"api","key":"provider-key"}}
```

示例引用路径：`op://your-vault/tavily/api_key`、`op://your-vault/opencode/auth_content`。

### 3. 配置 .env

```bash
cp .env.example .env
# 编辑 .env，填入 1Password 引用
```

### 4. 添加用户

```bash
# 用户的公钥（iOS 客户端在 Settings > SSH Tunnel 里生成并导出）
./scripts/add_user.sh alice /path/to/alice_ed25519.pub
```

### 5. 部署

```bash
./scripts/deploy.sh
```

### 6. iOS 客户端配置

在 OpenCodeClient 的 Settings > SSH Tunnel 里：

- Host: VPS IP 地址
- Port: 8006（或 .env 里配的 SSH_PORT）
- Username: opencode
- Remote Port: `scripts/add_user.sh` 输出的端口（默认从 19001 开始）
- 每台设备生成自己的 SSH key，把公钥交给运营者添加；不要共享或导出 iOS 私钥

也可以由管理员导出 iOS Host Config JSON：

```bash
./scripts/export_host_config.sh alice gateway.example.invalid "Alice OpenCode"
```

iOS 里进入 Settings -> Current Host -> Add Host，把 JSON 粘到 Import Host Config，点 Import Host Config，再保存。这个 JSON 不包含 SSH 私钥、Basic Auth 密码或 provider token。

## 文件结构

```
├── sshd-gateway/        # SSH 网关容器
│   ├── Dockerfile
│   ├── sshd_config
│   └── entrypoint.sh
├── opencode/            # OpenCode 容器镜像构建上下文
│   ├── Dockerfile
│   └── bin/             # 预编译 binary（gitignored）
├── keys/                # authorized_keys + port_map（gitignored）
├── workspaces/          # 每用户 workspace（gitignored）
├── skills/              # 运维 skill 文档
│   ├── onboard.md
│   ├── add_user.md
│   └── key_management.md
├── scripts/
│   ├── build_image.sh   # 维护者重建 + push OpenCode 镜像
│   ├── deploy.sh        # 1Password 注入 + docker compose up
│   ├── add_user.sh      # 添加用户（容器+volume+workspace+key）
│   ├── remove_user.sh   # 删除用户
│   └── manage_key.sh    # 用户 key 管理（增删查轮换）
├── tests/               # key 管理 CLI 测试
├── docs/
│   ├── prd.md
│   ├── rfc.md
│   ├── working.md
│   └── test.md
├── docker-compose.yml.example
├── .env.example
└── .gitignore
```

## Privacy

This repository is designed to be publishable with only fake examples. All real keys, 1Password references, and server addresses are in `.env` (gitignored).

## License

MIT
