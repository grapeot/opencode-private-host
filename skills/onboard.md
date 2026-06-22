# Skill: 首次部署与第一个用户（onboard）

## 元数据

- 类型: Workflow
- 适用场景: 运营者第一次拿到 opencode-private-host repo，想让 AI agent 帮他把本机或 VPS 上的第一个用户跑起来
- 创建日期: 2026-06-21

## 目标与边界

把一个空的 opencode-private-host 部署带到可用状态：`.env` 可用、Docker Compose 可启动、第一个用户存在、SSH tunnel 能访问对应 OpenCode Web UI。

这个 skill 负责首次上线的引导和决策收集。真正创建用户时调用 `scripts/add_user.sh`；后续增加设备或用户分别看 `skills/key_management.md` 和 `skills/add_user.md`。

不做这些事：不替用户生成 iOS 私钥，不把运营者自己的 OpenAI / Codex OAuth token 注入给别人，不把真实 1Password 路径或 key 写进公开文件，不暴露 OpenCode HTTP 端口到 host。

## 需要先问清楚的决定

首次 onboarding 需要把少数用户决策浮出来，避免 agent 擅自替用户选择安全边界。

**部署目标**：本地测试还是 VPS。默认本地测试可以用任意空闲 SSH 端口；VPS 上默认用 `8006`。

**第一个用户名**：必须匹配 `^[a-z][a-z0-9_-]*$`，例如 `alice`、`yage`、`testuser`。

**第一个 SSH 公钥来源**：有两种合法路径。

- 运营者提供公钥文件路径或直接提供一行 `ssh-ed25519 ...` 公钥，agent 写成临时 `.pub` 后调用 `scripts/add_user.sh`。
- 最终用户自己在 iOS / Mac / iPad 生成 key。agent 暂停创建用户，输出需要用户提供的 public key 格式和之后要执行的命令。

**Tavily 是否启用**：如果启用，`.env` 里需要 `TAVILY_API_KEY`，建议使用 1Password 引用，例如 `op://your-vault/tavily/api_key`。如果不用 Tavily，允许留空，但要明确告知用户：workspace 仍会 clone tavily skill，调用时会因为没有 key 而不可用。

**OpenCode provider auth**：默认 BYOK，不注入 OpenAI / Codex。首次用户创建后，agent 必须提醒管理员：需要用这个用户的 SSH tunnel 打开 OpenCode Web UI，并完成第一次 ChatGPT / provider 连接；iOS native client 只负责连接已经可用的 OpenCode server。只有当用户明确要注入非 OAuth provider key 时，才配置 `OPENCODE_AUTH_CONTENT`。

**镜像来源**：默认用 `OPENCODE_IMAGE=ghcr.io/grapeot/opencode-private:latest`。如果 fork 后自建镜像，则改成对应 GHCR path。不要让首次用户临时从源码 build OpenCode，除非当前任务就是维护镜像。

## 验收标准

onboarding 完成时必须满足这些条件：

1. `.env` 存在且未进入 git；公开 `.env.example` 仍只含 fake placeholder。
2. `docker-compose.yml` 由 `scripts/render_compose.sh` 或 `scripts/add_user.sh` 生成，未进入 git；公开 `docker-compose.yml.example` 仍只含无用户的 baseline。
3. `docker compose config --quiet` 通过。
4. `keys/port_map` 有第一个用户，端口默认从 `19001` 开始。
5. `keys/authorized_keys` 有第一个用户的 `ssh-ed25519` 公钥行，并包含 `permitopen="127.0.0.1:<remotePort>"` 和 `#user:<username>`。
6. `docker compose ps` 显示 `sshd-gateway` 和 `opencode-<username>` 均为 running。
7. 用该 key 建立 SSH local forward 后，`curl http://127.0.0.1:<localForwardPort>/` 返回 OpenCode HTML。
8. `ssh opencode@host true` 被 `nologin` 阻止。
9. forward 到非授权 remotePort 被拒绝或连接 reset。
10. 最终输出给管理员的连接信息包含 Host、SSH Port、Username、Remote Port，以及“先通过 Web UI 完成 provider auth，再让 iOS native client 使用”的提醒。

## 可用资源

- `.env.example`：公开模板，只能放 fake placeholder。
- `.env`：真实本地部署配置，gitignored。
- `docker-compose.yml.example`：公开 baseline，仅用于说明初始 compose 形态。
- `docker-compose.yml`：真实部署状态，由脚本生成，gitignored。
- `scripts/add_user.sh <username> <public_key_file>`：创建第一个和后续用户。
- `scripts/render_compose.sh`：从 `keys/port_map` 生成 compose。
- `scripts/manage_key.sh`：后续设备 key 管理。
- `scripts/build_image.sh`：只有需要重建 GHCR 镜像时才用。
- `docs/test.md`：手工 E2E 验证命令参考。

## 推荐执行策略

如果用户已经给出所有信息，直接执行，不要再问确认。缺信息时，只问当前无法推进的一项或几项，不要把整个部署流程变成问卷。

本地测试时，先检查 `8006` 是否空闲。如果被占用，可以只改 gitignored `.env` 的 `SSH_PORT` 为临时端口，例如 `18006`；不要改 `.env.example` 的默认端口。

如果用户直接粘贴 public key，一定只保存公钥，不保存私钥。临时 `.pub` 文件可以放在 repo 外的临时目录；如果要长期保留，放进用户明确指定的位置。不要把测试 key 放进 git。

如果 `scripts/add_user.sh` 默认 workspace 初始化耗时太长，本地 smoke test 可以用 `SKIP_WORKSPACE_INIT=1`。正式 VPS onboarding 应该跑完整 workspace 初始化，确保 `context-infrastructure` 和 `tavily-skill` 都存在。

第一个用户启动后，管理员需要先完成 provider auth 验证：用该用户 key 建立 tunnel，访问 `http://127.0.0.1:<localForwardPort>`，在 OpenCode Web UI 中连接 ChatGPT / provider。这个动作完成前，iOS native client 可以连上 server，但发起需要 provider 的对话可能失败。

## 已知陷阱

- 本地 Docker Desktop 的其他容器可能占用 `8006`；只改 `.env` 做本地测试，不改公开默认值。
- OpenCode 容器的 `4096` 只在 Docker internal network 中使用；用户不应该直接连 host 的 `4096`。
- 第一个用户和后续用户没有特殊差异，都通过 `scripts/add_user.sh` 创建。
- OpenAI / Codex OAuth token 属于用户个人账号状态，默认让用户在 OpenCode Web UI 中自己连接。
