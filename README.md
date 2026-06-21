# opencode-private-host

通过 SSH 公钥认证在自有 VPS 上安全部署定制版 OpenCode，支持多用户。对外只暴露一个 SSH 端口，OpenCode HTTP 端口不对外。

## 架构

两个 Docker 容器，通过内部网络连接：

```
[iOS 客户端](https://github.com/grapeot/opencode_ios_client)
  │ SSH (ed25519 key auth, 非标准端口)
  ▼
sshd-gateway 容器 (Alpine + OpenSSH + socat)
  │ direct-tcpip → socat forward
  ▼
opencode 容器 (Alpine + 定制 opencode binary)
  │ OPENCODE_AUTH_CONTENT (1Password 注入)
  ▼
OpenAI API
```

### 安全模型

- SSH 公钥认证替代 HTTP basic auth
- `authorized_keys` 每行用 `permitopen` 限制只能 forward 到 OpenCode 端口
- `ForceCommand /usr/sbin/nologin` 阻止 shell/exec
- `PermitTTY no`、`AllowAgentForwarding no`、`PermitTunnel no`
- OpenCode 端口不映射到 host，只通过 SSH channel 可达
- API key 通过 1Password `op run` 注入，不落盘

## 快速开始

### 1. 构建 opencode 镜像

需要本地有 `opencode-official` checkout（`private-dev-squashed` 分支）。

```bash
export OPENCODE_CHECKOUT=/path/to/opencode-official
export GHCR_USER=your-github-username
./scripts/build_image.sh
```

### 2. 配置 1Password

在 1Password 里创建一个 Secure Note，内容是 opencode auth JSON：

```json
{"openai":{"type":"api","key":"sk-..."}}
```

记录 1Password 引用路径，例如 `op://your-vault/opencode/auth_content`。

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
- Port: 8008（或 .env 里配的 SSH_PORT）
- Username: opencode
- Remote Port: 18080
- 生成或导入 SSH key

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
│   ├── add_user.md
│   └── key_management.md
├── scripts/
│   ├── build_image.sh   # 构建 + push 镜像
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
├── docker-compose.yml
├── .env.example
└── .gitignore
```

## Privacy

This repository is designed to be publishable with only fake examples. All real keys, 1Password references, and server addresses are in `.env` (gitignored).

## License

MIT