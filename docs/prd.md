# PRD - opencode-private-host

## 目标

在自有 VPS 上部署定制版 OpenCode，通过 SSH 公钥认证替代 HTTP basic auth，提供安全的多用户 AI 写作与调研环境。

## 用户

使用 iOS 客户端（OpenCodeClient）连接服务器的用户。运营者负责部署、维护、加用户、管理 API key。

## 需求

### 必须满足

1. **安全认证**：用 SSH ed25519 公钥认证替代 OpenCode 内置 basic auth。每个用户有独立密钥，密钥泄露只影响容器内权限，不危及 VPS 主环境。
2. **单端口暴露**：对外只暴露一个非标准 SSH 端口（默认 8008，可配置），不暴露 OpenCode HTTP 端口。
3. **API key 由运营者统一提供**：用户不需要自备 OpenAI key。key 通过 1Password 注入，不落盘。
4. **隔离**：OpenCode 跑在 Docker 容器中，与 VPS 主环境隔离。
5. **多用户支持**：支持添加多个用户，每人一把 SSH key。当前为共享 OpenCode 实例（session 级隔离），架构上预留每用户独立容器的升级路径。
6. **权限锁定**：SSH 用户只能做一件事——forward 到 OpenCode 端口。不能 exec 命令、不能开 shell、不能转发到其他目标。

### 暂不要求

- 自助注册（enrollment service）：当前手工加 key，用户量到几十个再做。
- Web 端 OIDC 登录（Logto）：当前 iOS 客户端通过 SSH 直连，不需要 web auth。
- 每用户独立 OpenCode 容器：当前共享一个实例，session 级隔离足够。
- 自动化备份和监控：后续迭代。

## 成功标准

1. 用 iOS 客户端能连上服务器并正常对话。
2. 用户的 SSH key 只能 forward 到 OpenCode 端口，执行 `ssh user@host ls` 等命令被拒绝。
3. API key 不出现在 VPS 磁盘的任何文件中（只在 1Password 和运行时环境变量里）。
4. 加一个用户的全流程不超过 2 分钟（拿到公钥 → append 到 authorized_keys → restart）。
5. OpenCode 容器重启不影响 SSH 网关（sshd-gateway 和 opencode 是独立容器）。

## 限制

- OpenCode 镜像基于定制版（private-dev-squashed 分支），需要本地 build 后推到 GHCR。不能用官方镜像（缺少 symlink、run-state、codesign 等 patch）。
- SSH 端口的可达性需要实测，建议备用端口。
- 共享 OpenCode 实例下，用户之间的文件隔离依赖 OpenCode session 机制，不是 OS 级隔离。