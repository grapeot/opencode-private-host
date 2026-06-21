# 测试策略

## 验证层次

### 1. 容器构建验证

sshd-gateway 镜像能 build 成功，opencode 镜像能 build 成功（需要先有 binary）。

```bash
docker compose build
```

### 2. SSH 认证验证

加一个测试 key 后，能用这个 key SSH 连上 sshd-gateway 容器，但不能 exec 命令。

```bash
# 生成测试 key
ssh-keygen -t ed25519 -f /tmp/test_key -N ""

# 添加到 authorized_keys
echo 'permitopen="127.0.0.1:18080",no-pty,no-X11-forwarding,no-agent-forwarding '"$(cat /tmp/test_key.pub)"' #user:test' >> keys/authorized_keys

# 启动
docker compose up -d

# 验证：能连上但被 ForceCommand 拒绝
ssh -p 8008 -i /tmp/test_key opencode@localhost
# 预期：连接成功但立即被 nologin 关闭

# 验证：exec 被拒绝
ssh -p 8008 -i /tmp/test_key opencode@localhost ls
# 预期：This account is currently not available.

# 验证：forward 能到达 opencode
ssh -p 8008 -i /tmp/test_key -L 14096:127.0.0.1:18080 -N opencode@localhost &
curl -s http://localhost:14096/
# 预期：opencode HTTP 响应
```

### 3. 权限锁定验证

用测试 key 尝试越权操作，确认都被拒绝。

```bash
# 尝试 forward 到其他端口（应被 permitopen 拒绝）
ssh -p 8008 -i /tmp/test_key -L 12345:127.0.0.1:22 -N opencode@localhost
# 预期：channel open refused

# 尝试 forward 到其他 host（应被 permitopen 拒绝）
ssh -p 8008 -i /tmp/test_key -L 12345:8.8.8.8:53 -N opencode@localhost
# 预期：channel open refused
```

### 4. 1Password 注入验证

`op run --env-file .env -- docker compose up -d` 能正确解析引用，opencode 容器内能看到真实 API key。

```bash
# 验证环境变量已注入
docker compose exec opencode env | grep OPENCODE_AUTH_CONTENT
# 预期：有值（不检查具体内容，避免泄露）
```

### 5. 中国可达性验证（手工）

从中国境内网络连接 VPS 的 SSH 端口，测试连通性和稳定性。

```bash
# 在中国境内机器上执行
ssh -p 8008 -i <key> -o ConnectTimeout=10 opencode@<VPS_IP>
# 测试多次、不同时段、不同运营商
```

### 6. iOS 客户端端到端验证（手工）

在 iOS app 的 SSH Tunnel 设置里配好 VPS 地址、端口、用户名、remotePort，连接后能正常对话。

## 自动化测试

当前没有自动化测试。原因：架构验证依赖外部资源（VPS、1Password、SSH 客户端），适合手工验证。后续如果加 enrollment service，需要补 API 测试。