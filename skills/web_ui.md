# Skill: 连接 Web UI 与刷新模型（web_ui）

## 元数据

- 类型: Workflow
- 适用场景: 运营者要打开某个已有用户的 OpenCode Web UI，或刷新该实例的 provider 模型列表
- 创建日期: 2026-09-12

## 目标与边界

给已部署用户建立 SSH tunnel、打开 OpenCode Web UI，以及在 Web 里看不到新模型时刷新 models.dev 缓存。

**做什么**：确认逻辑用户名和 remotePort、必要时加设备公钥、打 local forward、告诉运营者打开哪个本机 URL；在容器内执行 `opencode models --refresh` 后重启对应 OpenCode 容器。

**不做什么**：不创建新用户（那是 `skills/add_user.md`）；不替用户生成私钥；不把真实 gateway 域名、公钥或 token 写进公开文件；不把 OpenCode HTTP `4096` 映射到 host；不重建 GHCR 镜像（那是 `scripts/build_image.sh`）。

## 开始前必问

1. **逻辑用户名是哪个？** 从 `keys/port_map` 读出现有用户，请运营者确认。不要从 hostname 或示例名猜测。
2. 若要连 Web：运营者是用 **电脑 SSH tunnel** 还是 **iOS 客户端**？电脑端还缺不缺一把已授权的 `ssh-ed25519` 公钥？
3. 若要刷新模型：是刷新 **models.dev 公开目录**，还是重新连接 **ChatGPT / provider 账号**？

逻辑用户名 ≠ SSH 登录名。SSH 登录名对所有用户始终是 `opencode`。

## 连接 Web UI

OpenCode 的 `4096` 只在 Docker internal network 里。必须经 sshd-gateway 的 SSH local forward，不能直接访问 host 上的 `4096`。

### 连接参数

从本机 gitignored 文件读取，不要写进公开文档：

- **Host**：运营者提供的 gateway（VPS hostname 或 IP）
- **SSH Port**：`.env` 的 `SSH_PORT`，默认 `8006`
- **SSH Username**：`opencode`
- **Remote Port**：`keys/port_map` 里该用户的端口（从 `19001` 起）

iOS Host Config JSON（不含 secret）：

```bash
scripts/export_host_config.sh <username> <gateway_host> "<Display Name>"
```

### 电脑：先确保有授权公钥

本机已有 key 但未登记时，只支持 `ssh-ed25519`。运营者给出公钥文件或一行公钥后：

```bash
# 公钥若是粘贴的一行，写到 repo 外的临时文件再 add
scripts/manage_key.sh add <username> /path/to/device_ed25519.pub
```

加 key 立刻生效，不需要重启容器。细节见 `skills/key_management.md`。

### 电脑：打 tunnel 并打开浏览器

```bash
ssh -p <SSH_PORT> -i ~/.ssh/id_ed25519 \
  -L 14096:127.0.0.1:<remotePort> \
  -N opencode@<gateway_host>
```

浏览器打开 `http://127.0.0.1:14096/`。

预期：`ssh opencode@<gateway_host> true` 会被 `nologin` 关掉；这是正常的，只做端口转发。`opencode web` 在容器里会因没有桌面而报 `xdg-open`，不影响 HTTP 服务。

本地 forward 的 `14096` 可换成任意空闲本机端口；remote 一侧必须是 `127.0.0.1:<该用户 remotePort>`，不能改成其他 host（iOS 客户端同样硬编码 `127.0.0.1`）。

### iOS 客户端

1. 用户在设备上生成 SSH key，把公钥交给运营者，`scripts/manage_key.sh add <username> <pub>`。
2. 运营者把 `export_host_config.sh` 输出的 JSON 发给用户。
3. 用户在 iOS 里：Settings → Current Host → Add Host → Import Host Config，粘贴 JSON，保存后连接。
4. JSON 不含 SSH 私钥、Basic Auth 密码或 provider token。

### 首次打开 Web 后

管理员应在 OpenCode Web UI 里完成 ChatGPT / provider 连接。iOS native client 只连接已经可用的 OpenCode server；这一步没做完时，需要 provider 的对话可能失败。

## 刷新模型列表

只重启容器通常不够。Web 进程启动时读取 `/tmp/opencode-cache/opencode/models.json`（`XDG_CACHE_HOME=/tmp/opencode-cache`）。`docker compose restart` 不会清掉同一容器里的 `/tmp`，所以会继续用旧缓存。

### models.dev 目录（常见）

```bash
docker exec opencode-<username> opencode models --refresh
docker compose restart opencode-<username>
```

然后让运营者刷新浏览器。`--refresh` 拉的是 [models.dev](https://models.dev) 公开目录，不是实时打 OpenAI `/v1/models`。新模型若还没进 models.dev，刷新也出不来。

不要重启 `sshd-gateway`，除非 socat / 端口映射也改了。

### ChatGPT 订阅侧模型

OAuth token 在用户 volume 的 `/data/opencode/auth.json`，重启容器不会重拉账号侧模型。需要在 Web UI 再走一遍 `/connect` → OpenAI → ChatGPT Plus/Pro。

### 镜像过旧

`docker exec opencode-<username> opencode --version` 若是很久以前的 `private-dev-squashed` 构建，刷新缓存也补不进需要新 runtime 才认识的型号。那种情况走镜像维护（`scripts/build_image.sh` + pull `OPENCODE_IMAGE`），不要和本 skill 的 cache refresh 混在一起。

## 验收标准

连接 Web：

1. `docker compose ps` 显示 `sshd-gateway` 和 `opencode-<username>` 均为 running。
2. 该用户 key 能建立 `-L <local>:127.0.0.1:<remotePort>`。
3. `curl http://127.0.0.1:<local>/` 返回 OpenCode HTML。
4. `ssh opencode@<gateway_host> true` 被 nologin 阻止。

刷新模型：

1. `docker exec opencode-<username> opencode models --refresh` 成功退出。
2. `opencode-<username>` 已重启且仍在 running。
3. `docker exec opencode-<username> opencode models openai` 能列出模型；运营者刷新 Web 后能看到更新后的列表。

## 可用资源

- `keys/port_map`：逻辑用户名 → remotePort
- `.env` 的 `SSH_PORT`（gitignored）
- `scripts/manage_key.sh`
- `scripts/export_host_config.sh`
- `skills/key_management.md`：加/删设备 key
- `docs/test.md`：SSH tunnel E2E 命令参考

## 已知陷阱

- OpenCode HTTP 不暴露到 host；直接访问 `http://<gateway>:4096` 会失败。
- 只支持 `ssh-ed25519`。RSA 等类型 `manage_key.sh` 会拒绝。
- 加 key 后不需要重启 gateway；uid/权限不对时 OpenSSH 会静默忽略整个 `authorized_keys`，见 `skills/add_user.md`。
- `xdg-open` 报错可忽略。
- 刷新 models.dev 缓存后必须重启对应 `opencode-<username>`，否则正在跑的 Web 进程仍持有旧列表。
- 公开文件里的 gateway 只用 `gateway.example.invalid` 这类 placeholder，不要写入真实域名。
