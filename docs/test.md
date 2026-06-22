# 测试策略

## 验证层次

### 1. 容器构建验证

sshd-gateway 镜像能 build 成功，opencode 镜像能 build 成功（需要先有 binary）。OpenCode 镜像固定按 `linux/amd64` 构建，因为当前打包的是 `opencode-linux-x64-baseline-musl`。

```bash
docker compose build
```

### 2. SSH 认证验证

加一个测试用户后，能用这个 key 通过 sshd-gateway forward 到自己的 OpenCode 容器，但不能 exec 命令。

```bash
# 生成测试 key
ssh-keygen -t ed25519 -f /tmp/test_key -N ""

# 添加用户但跳过 workspace clone 和自动启动，便于本地快速 E2E；最后一个参数会输出 iOS Host Config JSON
SKIP_WORKSPACE_INIT=1 SKIP_DOCKER_UP=1 scripts/add_user.sh testuser /tmp/test_key.pub localhost "Test OpenCode"

# 启动
op run --env-file .env -- docker compose up -d --build --remove-orphans

# 验证：能连上但被 ForceCommand 拒绝
ssh -p 8006 -i /tmp/test_key opencode@localhost
# 预期：连接成功但立即被 nologin 关闭

# 验证：exec 被拒绝
ssh -p 8006 -i /tmp/test_key opencode@localhost true
# 预期：This account is not available

# 验证：forward 能到达 opencode
ssh -p 8006 -i /tmp/test_key -L 14096:127.0.0.1:19001 -N opencode@localhost &
curl -s http://localhost:14096/
# 预期：opencode HTTP 响应
```

若 SSH 始终 `Permission denied (publickey)` 但公钥已在 `keys/authorized_keys` 里，先排查 bind mount 的 uid/权限（OpenSSH 会静默忽略不符合要求的 authorized_keys）：

```bash
ls -ln keys/authorized_keys keys/
docker exec sshd-gateway id opencode
docker exec sshd-gateway ls -ln /keys/authorized_keys /keys/
# host 与容器内 authorized_keys uid 必须一致；文件 600、目录 755
# 详见 skills/add_user.md
```

### 3. 权限锁定验证

用测试 key 尝试越权操作，确认都被拒绝。

```bash
# 尝试 forward 到其他端口（应被 permitopen 拒绝）
ssh -p 8006 -i /tmp/test_key -L 12345:127.0.0.1:19002 -N opencode@localhost
# 预期：channel open refused

# 尝试 forward 到其他 host（应被 permitopen 拒绝）
ssh -p 8006 -i /tmp/test_key -L 12345:8.8.8.8:53 -N opencode@localhost
# 预期：channel open refused
```

### 4. 1Password 注入验证

`op run --env-file .env -- docker compose up -d` 能正确解析引用，opencode 容器内能看到 Tavily API key。不要打印真实值。

```bash
# 验证环境变量已注入
docker compose exec opencode-testuser sh -c 'test -n "$TAVILY_API_KEY"'
# 预期：退出码 0（不打印具体内容，避免泄露）
```

### 5. 中国可达性验证（手工）

从中国境内网络连接 VPS 的 SSH 端口，测试连通性和稳定性。

```bash
# 在中国境内机器上执行
ssh -p 8006 -i <key> -o ConnectTimeout=10 opencode@<VPS_IP>
# 测试多次、不同时段、不同运营商
```

### 6. iOS 客户端端到端验证（手工）

管理员用 `scripts/add_user.sh <username> <pubkey> <gateway_host> "<Display Name>"` 或 `scripts/export_host_config.sh <username> <gateway_host> "<Display Name>"` 输出 Host Config JSON。用户在 iOS app 里进入 Settings -> Current Host -> Add Host，把 JSON 粘贴到 Import Host Config，保存后连接。导入配置不包含 SSH 私钥、Basic Auth 密码或 provider token。

## 自动化测试

当前有 shell 自动化覆盖 key 管理、Host Config 导出和 add_user 输出：

```bash
tests/test_manage_key.sh
tests/test_export_host_config.sh
tests/test_add_user_host_config.sh
```

容器 E2E 仍偏手工，因为需要 Docker、1Password CLI、SSH 客户端和本地可用端口。后续如果加 enrollment service，需要补 API 测试。
