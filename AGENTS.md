# AGENTS.md - opencode-private-host

## 项目说明

SSH 网关 + 每用户独立 OpenCode 容器的部署方案。sshd-gateway 容器做 SSH 公键认证和端口转发，每个用户一个独立的 opencode 容器（OS 级隔离，互不可见）。对外只暴露一个 SSH 端口。

## 结构

- `sshd-gateway/` — SSH 网关容器（Alpine + OpenSSH + socat）
- `opencode/` — OpenCode 容器镜像构建上下文（Alpine + 预编译 binary）
- `keys/` — authorized_keys 文件 + port_map（gitignored，不进 repo）
- `workspaces/` — 每个用户的 workspace 目录（context-infrastructure clone + tavily skill，gitignored）
- `skills/` — 运维 skill 文档（add_user、key_management）
- `scripts/` — 构建、部署、用户管理、key 管理 CLI
- `docs/` — PRD、RFC、working notes、测试策略

## 环境约束

- 部署需要 `op` (1Password CLI) 已登录
- 普通部署和 shell 测试使用 GHCR 镜像，不需要 `opencode-official` checkout
- 只有维护者需要重建并 push `OPENCODE_IMAGE` 时，才需要本地 `opencode-official` checkout（`private-dev-squashed` 分支）+ Bun
- VPS 需要安装 Docker + Docker Compose v2
- VPS 需要安装 Python + uv（用于 tavily skill 的 .venv）
- VPS 需要安装 git（用于 clone context-infrastructure 和 tavily skill）

## 工作要求

- 改了东西就更新 `docs/working.md` 的 Changelog
- 频繁 commit，不要攒一堆改动
- 所有公开文件用 fake 占位符（`op://your-vault/...`、`your-github-username`），不要出现真实 key、邮箱、域名
- `.env` 不进 git，`keys/authorized_keys` 不进 git，`keys/port_map` 不进 git，`opencode/bin/*` 不进 git，`workspaces/*` 不进 git

## 兼容约束

- [iOS 客户端](https://github.com/grapeot/opencode_ios_client)的 `SSHTunnelManager.swift:353` 硬编码 targetHost 为 `127.0.0.1`，所以 socat 必须监听 `127.0.0.1`，不能改成其他 host。remotePort 用户可配，每个用户的 remotePort 不同（19001、19002...）。
- OpenCode 的 `OPENCODE_AUTH_CONTENT` 和 `OPENCODE_CONFIG_CONTENT` 环境变量是 opencode 为容器场景设计的注入通道，见 `packages/opencode/src/auth/index.ts:59` 和 `packages/opencode/src/config/config.ts:467`。
- OpenCode 的存储路径由 XDG 环境变量控制（`packages/core/src/global.ts:11-14`）：`XDG_DATA_HOME` → data 目录，`XDG_CONFIG_HOME` → config 目录。Dockerfile 里设 `XDG_DATA_HOME=/data`、`XDG_CONFIG_HOME=/data/config`，对应 volume 挂载。
- Tavily skill 从 `TAVILY_API_KEY` 环境变量读 key（`skill_tavily.md:28`），不需要 `.env` 文件就能在容器里工作。
- context-infrastructure 公开 repo：`https://github.com/grapeot/context-infrastructure`
- tavily skill 公开 repo：`https://github.com/grapeot/tavily-skill`
