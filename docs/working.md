# Working Notes

## Changelog

### 2026-06-21

- 项目脚手架初始化：创建 docs/、sshd-gateway/、opencode/、keys/、scripts/、tests/ 目录
- 写完 PRD、RFC、test.md
- sshd-gateway：Dockerfile + sshd_config + entrypoint.sh
- opencode：Dockerfile（基于 alpine + COPY 预编译 binary）
- docker-compose.yml：生成态 compose 文件，internal network，sshd-gateway 对外暴露 SSH_PORT，opencode 不暴露端口；当前已改为 gitignored，公开 baseline 放在 docker-compose.yml.example
- .env.example：1Password 引用格式（Route A），SSH 端口可配置
- scripts：build_image.sh、deploy.sh、add_user.sh
- 架构改为 per-user 容器：每个用户独立的 opencode 容器 + data volume + workspace，OS 级隔离
- RFC 重写：storage 三层设计（opencode 状态 volume + API key 1Password 注入 + OAuth token per-user volume + workspace clone context-infrastructure + tavily skill）
- PRD 重写：per-user 容器隔离，加用户/删用户 CLI 流程，key 管理 CLI + 测试
- 新增 skills/add_user.md：加用户全流程 skill 文档
- 新增 skills/key_management.md：key 管理 skill 文档 + CLI + 测试设计
- README/PRD/RFC 加 iOS 客户端 repo 链接
- 实现 `scripts/manage_key.sh`：按 `#user:<username>` 管理多设备 ed25519 key，支持 list/add/remove/verify
- 实现 `scripts/render_compose.sh`：从 `keys/port_map` 重新生成每用户 OpenCode service 和 volume
- 重写 `scripts/add_user.sh` / `scripts/remove_user.sh`：用户端口从 19001 开始分配，workspace 独立，compose 自动渲染
- `scripts/build_image.sh` 改为从 `packages/opencode` 构建全量 target，复制 `opencode-linux-x64-baseline-musl`，并固定 `docker build --platform linux/amd64`
- `opencode/Dockerfile` 修复 `/data`、`/data/config` 权限，保证 named volume 首次挂载后 OpenCode 可写
- `sshd-gateway/Dockerfile` 解锁 `opencode` 账号的 shadow password，同时保持 `PasswordAuthentication no`，允许 key-only 登录
- 本地 Docker E2E 通过：allowed tunnel 可访问 OpenCode HTML；exec 被 `nologin` 阻止；错误 remotePort 被 `permitopen` 拒绝
- 新增 `skills/onboard.md`：首次部署与第一个用户引导，覆盖 `.env`、Tavily、BYOK、首个 SSH key 来源和 E2E 验收
- 将 `docker-compose.yml` 改为 gitignored 生成文件，新增公开 `docker-compose.yml.example` baseline，避免用户把本地用户/端口状态 push 上去
- 更新 `skills/onboard.md`：明确 provider auth 是管理员在 OpenCode Web UI 中完成的首次验证步骤，iOS native client 只连接已经可用的 OpenCode server

## Lessons Learned

- Apple Silicon 本地 build 如果不指定 `linux/amd64`，会得到 ARM Alpine base + x86_64 OpenCode binary 的混合镜像，运行时报 `rosetta error: failed to open elf at /lib/ld-musl-x86_64.so.1`。
- Alpine `adduser -S` 创建的账号默认 shadow locked；即使 `PasswordAuthentication no`，OpenSSH 也会拒绝 public-key login。需要 `passwd -d opencode` 删除密码哈希，让账号可登录但仍只接受 key。
- Docker named volume 首次挂载会覆盖镜像内路径内容；镜像里需要提前创建并 chown `/data`，否则非 root 用户启动 OpenCode 会 EACCES。
- `opencode web` 在无桌面环境里会尝试 `xdg-open` 并打印错误；当前服务仍保持运行，E2E 以 HTTP 响应为准。
