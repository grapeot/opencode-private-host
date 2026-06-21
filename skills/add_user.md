# Skill: 添加用户（add_user）

## 元数据

- 类型: Workflow
- 适用场景: 运营者在 VPS 上为 opencode-private-host 添加一个新用户
- 创建日期: 2026-06-21

## 目标与边界

为指定用户名创建一个完整的、隔离的 OpenCode 实例：Docker 容器 + 数据 volume + workspace（含 context-infrastructure + tavily skill）+ SSH key 条目。完成后该用户可以立即用 iOS 客户端连接。

**做什么**：创建 compose service、socat 规则、数据 volume、workspace（clone context-infrastructure + 装 tavily skill）、authorized_keys 条目、端口分配、启动容器。

**不做什么**：不处理用户自助注册；不帮用户生成 SSH key（用户在 iOS 客户端自己生成后提供公钥）；不配置 1Password（1Password 由运营者预先配好，所有用户共享）；不配置 OAuth token（用户自己在 OpenCode 里跑 `auth login --device-code` 完成第三方 skill 登录）。

## 可用资源

- docker-compose.yml（项目根目录，可读写）
- keys/authorized_keys（项目根目录，可读写）
- keys/port_map（端口分配表，可读写，格式 `username:port` 每行）
- sshd-gateway/entrypoint.sh（可读写，socat 规则来源）
- workspace 目录（项目根目录下 `workspaces/<username>/`）
- context-infrastructure 公开 repo：`https://github.com/grapeot/context-infrastructure`
- tavily skill 公开 repo：`https://github.com/grapeot/tavily-skill`
- Docker + Docker Compose v2
- op run（1Password CLI，用于注入 API key 启动容器）

## 验收标准

1. `docker compose ps` 显示 `opencode-<username>` 和 `sshd-gateway` 都在运行。
2. `keys/port_map` 里有该用户的端口分配记录。
3. `keys/authorized_keys` 里有该用户的公钥行，`permitopen` 指向正确端口。
4. `workspaces/<username>/AGENTS.md` 存在（context-infrastructure clone 成功）。
5. `workspaces/<username>/adhoc_jobs/tavily_skill/` 存在且 `.venv` 已创建（tavily skill 安装成功）。
6. 用该用户的 key SSH 连上后，forward 到对应端口能到达 OpenCode HTTP（`curl` 返回 opencode 响应）。
7. 用该用户的 key 尝试 forward 到其他端口被拒绝（`permitopen` 生效）。
8. 该用户无法 `ssh opencode@host ls`（ForceCommand nologin 生效）。

## CLI 设计

```bash
scripts/add_user.sh <username> <public_key_file>
```

### CLI 执行步骤

1. 校验参数：username 非空、public_key_file 存在且是合法 ed25519 公钥。
2. 检查 `keys/port_map` 是否已有该用户（避免重复创建）。
3. 分配端口：读取 port_map 最大端口 +1，最小 19001。
4. 在 docker-compose.yml 的 services 下追加 `opencode-<username>` service（基于模板，volume 名用 username，workspace 路径用 `./workspaces/<username>`）。
5. 创建 `workspaces/<username>/` 目录。
6. `git clone https://github.com/grapeot/context-infrastructure workspaces/<username>`（浅克隆，`--depth 1`）。
7. `git clone https://github.com/grapeot/tavily-skill workspaces/<username>/adhoc_jobs/tavily_skill`（浅克隆）。
8. 在 tavily_skill 目录创建 `.venv` 并安装：`uv pip install -e '.[dev]'`（需要 VPS 有 Python + uv）。
9. 在 `keys/authorized_keys` 追加该用户行（`permitopen="127.0.0.1:<port>",no-pty,no-X11-forwarding,no-agent-forwarding <pubkey> #user:<username>`）。
10. 在 `keys/port_map` 追加 `<username>:<port>`。
11. `op run --env-file .env -- docker compose up -d`（启动新容器 + 重启 sshd-gateway 让 socat 生效）。
12. 输出用户的连接信息：VPS 地址、SSH 端口、用户名（opencode）、remotePort（分配的端口）。

### opencode service 模板

```yaml
  opencode-<username>:
    image: ghcr.io/<GHCR_USER>/opencode-private:latest
    container_name: opencode-<username>
    restart: unless-stopped
    environment:
      OPENCODE_AUTH_CONTENT: "${OPENCODE_AUTH_CONTENT}"
      TAVILY_API_KEY: "${TAVILY_API_KEY}"
      OPENCODE_CONFIG_CONTENT: "${OPENCODE_CONFIG_CONTENT:-}"
    volumes:
      - opencode-data-<username>:/data
      - opencode-config-<username>:/data/config
      - ./workspaces/<username>:/workspace
    networks:
      - internal
```

## 已知陷阱

（部署后补充）