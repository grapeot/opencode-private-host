# AGENTS.md - opencode-private-host

## 项目说明

SSH 网关 + OpenCode 双容器部署方案。sshd-gateway 容器做 SSH 公钥认证和端口转发，opencode 容器跑定制版 OpenCode server。对外只暴露一个 SSH 端口。

## 结构

- `sshd-gateway/` — SSH 网关容器（Alpine + OpenSSH + socat）
- `opencode/` — OpenCode 容器（Alpine + 预编译 binary）
- `keys/` — authorized_keys 文件（gitignored，不进 repo）
- `scripts/` — 构建、部署、用户管理脚本
- `docs/` — PRD、RFC、working notes、测试策略

## 环境约束

- 部署需要 `op` (1Password CLI) 已登录
- 镜像构建需要本地有 `opencode-official` checkout（`private-dev-squashed` 分支）+ Bun
- VPS 需要安装 Docker + Docker Compose v2

## 工作要求

- 改了东西就更新 `docs/working.md` 的 Changelog
- 频繁 commit，不要攒一堆改动
- 所有公开文件用 fake 占位符（`op://your-vault/...`、`your-github-username`），不要出现真实 key、邮箱、域名
- `.env` 不进 git，`keys/authorized_keys` 不进 git，`opencode/bin/*` 不进 git

## 兼容约束

- iOS 客户端的 `SSHTunnelManager.swift:353` 硬编码 targetHost 为 `127.0.0.1`，所以 socat 必须监听 `127.0.0.1`，不能改成其他 host。remotePort 用户可配，默认 18080。
- OpenCode 的 `OPENCODE_AUTH_CONTENT` 和 `OPENCODE_CONFIG_CONTENT` 环境变量是 opencode 为容器场景设计的注入通道，见 `packages/opencode/src/auth/index.ts:59` 和 `packages/opencode/src/config/config.ts:467`。