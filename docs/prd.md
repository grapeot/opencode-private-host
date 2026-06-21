# PRD - opencode-private-host

## 目标

在自有 VPS 上部署定制版 OpenCode，通过 SSH 公钥认证替代 HTTP basic auth，提供安全的多用户 AI 写作与调研环境。每个用户拥有独立的 OpenCode 容器和隔离的存储，互不可见。

## 用户

使用 [iOS 客户端](https://github.com/grapeot/opencode_ios_client)（OpenCodeClient）连接服务器的用户。运营者负责部署、维护、加用户、管理 API key。

## 需求

### 必须满足

1. **安全认证**：用 SSH ed25519 公钥认证替代 OpenCode 内置 basic auth。每个用户有独立密钥，密钥泄露只影响容器内权限，不危及 VPS 主环境。
2. **单端口暴露**：对外只暴露一个非标准 SSH 端口（默认 8008，可配置），不暴露任何 OpenCode HTTP 端口。
3. **API key 由运营者统一提供**：用户不需要自备 OpenAI key。key 通过 1Password 注入，不落盘。
4. **隔离**：每个用户一个独立的 OpenCode Docker 容器，独立的 data volume，独立的 workspace。用户之间互不可见——不能看到对方的 session、文件、OAuth token。
5. **权限锁定**：SSH 用户只能做一件事——forward 到自己的 OpenCode 端口。不能 exec 命令、不能开 shell、不能转发到其他目标、不能转发到其他用户的端口。
6. **加用户流程**：运营者执行一条命令完成加用户——创建容器、创建 volume、初始化 workspace（clone context-infrastructure + 安装 tavily skill）、添加 SSH key。配套 CLI 和 skill 文档。
7. **删用户流程**：运营者执行一条命令完成删用户——停止并删除容器、删除 volume、删除 workspace、删除 SSH key。配套 CLI 和 skill 文档。
8. **key 管理流程**：运营者执行一条命令添加或删除某个用户的 authorized_keys 条目。配套 CLI 和 skill 文档，CLI 有测试。

### 暂不要求

- 自助注册（enrollment service）：当前由运营者手工执行 CLI 加用户。
- Web 端 OIDC 登录（Logto）：当前 iOS 客户端通过 SSH 直连，不需要 web auth。
- 自动化备份和监控：后续迭代。
- OAuth 弹窗登录的远程化：Outlook 等 skill 的 OAuth 登录走 device code flow（不弹窗），已由 skill 自身支持，不需要额外架构。

## 成功标准

1. 用 iOS 客户端能连上服务器并正常对话。
2. 用户的 SSH key 只能 forward 到自己的 OpenCode 端口，执行 `ssh user@host ls` 等命令被拒绝。
3. 用户 A 无法访问用户 B 的 session、文件、容器。
4. API key 不出现在 VPS 磁盘的任何文件中（只在 1Password 和运行时环境变量里）。
5. 加一个用户的全流程：运营者执行一条 CLI 命令 + 用户提供公钥，完成。
6. OpenCode 容器重启不影响 SSH 网关（sshd-gateway 和各 opencode 容器独立）。

## 限制

- OpenCode 镜像基于定制版（private-dev-squashed 分支），需要本地 build 后推到 GHCR。不能用官方镜像（缺少 symlink、run-state、codesign 等 patch）。
- SSH 端口的可达性需要实测，建议备用端口。
- 每用户一个容器意味着 VPS 资源消耗随用户数线性增长。每个 opencode 容器约 200-300 MB RAM。VPS 需要足够内存。