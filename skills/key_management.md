# Skill: 用户 Key 管理（key_management）

## 元数据

- 类型: Workflow
- 适用场景: 运营者管理某个用户的 authorized_keys 条目（添加设备、删除设备、列出设备、轮换 key）
- 创建日期: 2026-06-21

## 目标与边界

管理 `keys/authorized_keys` 里某个用户对应的公钥行。一个用户可以有多把 key（对应多个设备：iOS、Mac、iPad 等），每把 key 独立管理——添加新设备、删除丢失的设备、轮换某台设备的 key。

**做什么**：按 `#user:<username>` 标记定位行，执行增删查。同一个用户可以有多行（多设备）。

**不做什么**：不创建/删除 Docker 容器（那是 add_user / remove_user 的职责）；不修改 port_map；不重启容器（authorized_keys 变更不需要重启，OpenSSH 每次连接重读文件）；**不猜测逻辑用户名**。

## 开始前必问

`manage_key.sh` 的每个子命令都需要 `<username>`（逻辑用户名，不是 SSH 登录名 `opencode`）。

- 若系统里**只有一个**用户，仍应向运营者确认「是给 `<port_map 里那一行>` 这个用户加 key 吗？」，不要 silent 假设。
- 若**多个**用户，必须先列出 `keys/port_map` 或运行 `scripts/manage_key.sh list <candidate>`，请运营者指明给哪个用户加/删 key。

创建全新用户（新容器、新 workspace）不走本 skill，应使用 `scripts/add_user.sh`，并先按 `skills/add_user.md` 问清逻辑用户名。

## 可用资源

- keys/authorized_keys（项目根目录）
- keys/port_map（端口分配表，只读，用于验证用户存在）

## 验收标准

1. 添加 key 后，`keys/authorized_keys` 里有该用户的新公钥行，`#user:<username>` 标记正确。
2. 删除 key 后，该 key 对应的行从 authorized_keys 移除，该用户的其他 key 行保留。
3. 同一用户可以有多把 key（多设备），每把 key 一行。
4. 同一公钥不会重复添加。
5. 删除某个用户的所有 key 不会影响其他用户的行。
6. 修改 authorized_keys 后不需要重启任何容器，新 key 立即生效（下次 SSH 连接时 OpenSSH 重读文件）。
7. CLI 有单元测试：测试添加、删除、列出、轮换、重复添加、删除不存在的 key、删除不存在的用户等 edge case。

## CLI 设计

```bash
# 列出某个用户的所有 key
scripts/manage_key.sh list <username>

# 为用户添加一把新 key（新设备）
scripts/manage_key.sh add <username> <public_key_file>

# 删除用户的某一把 key（指定公钥文件或 fingerprint）
scripts/manage_key.sh remove <username> <public_key_file>

# 验证某个公钥是否已在 authorized_keys 里
scripts/manage_key.sh verify <username> <public_key_file>

# 导出 iOS 可导入的 Host Config JSON（不含 secret）
scripts/export_host_config.sh <username> <gateway_host> [display_name]
```

### 行为细节

`add` 是幂等的：如果该公钥已存在（完全匹配），不重复追加。如果用户不存在，报错退出。

`remove` 删除指定公钥对应的行。如果该公钥不在 authorized_keys 里，报错退出。如果用户不存在，报错退出。删除后该用户可能还有其他 key（其他设备），不影响。

`list` 输出该用户的所有 authorized_keys 行，每行一个。用户不存在时报错退出。

`verify` 退出码 0 表示 key 已存在，退出码 1 表示 key 不存在但用户存在，退出码 2 表示用户不存在。

`export_host_config` 只读 `keys/port_map` 和 `.env` 里的 `SSH_PORT`，输出 iOS `Import Host Config` 可粘贴 JSON。JSON 只包含 name、transport、gateway host、SSH port、SSH username 和 remotePort；不包含 SSH 私钥、Basic Auth 密码、provider token 或任何 1Password 引用。

### 多设备工作流

用户在电脑上生成 SSH key：`ssh-keygen -t ed25519`。把公钥发给运营者，运营者执行：

```bash
scripts/manage_key.sh add alice /path/to/alice_macbook_ed25519.pub
```

然后运营者给用户一段 Host Config JSON：

```bash
scripts/export_host_config.sh alice gateway.example.invalid "Alice OpenCode"
```

用户在 iOS 里进入 Settings -> Current Host -> Add Host，把 JSON 粘到 Import Host Config，点 Import Host Config，再保存。每台设备仍然使用自己生成的 SSH 私钥；导入配置不会带入任何 secret。

之后用户就可以从电脑上用这把 key 访问自己的 OpenCode 容器。iOS 客户端用另一把 key，两把 key 独立，互不影响。设备丢失时：

```bash
scripts/manage_key.sh remove alice /path/to/lost_device_ed25519.pub
```

## 测试设计

`tests/test_manage_key.sh`：

1. 创建临时 authorized_keys 文件，预置几个用户（部分用户多 key）。
2. 测试 `add` 已有用户的第一个 key：验证行被追加，格式正确，`#user:` 标记正确。
3. 测试 `add` 已有用户的新 key（第二个设备）：验证新行追加，旧行保留。
4. 测试 `add` 已存在的 key（完全匹配）：不产生重复行。
5. 测试 `add` 不存在的用户：报错退出码非 0。
6. 测试 `remove` 指定 key：该 key 行删除，同用户其他 key 行保留。
7. 测试 `remove` 不存在的 key：报错退出码非 0。
8. 测试 `remove` 不存在的用户：报错退出码非 0。
9. 测试 `list` 有 key 的用户（多 key）：验证输出匹配所有行。
10. 测试 `list` 不存在的用户：报错退出码非 0。
11. 测试 `verify` key 存在：退出码 0。
12. 测试 `verify` key 不存在但用户存在：退出码 1。
13. 测试 `verify` 用户不存在：退出码 2。

## 已知陷阱

- `manage_key.sh add` 要求用户已经存在于 `keys/port_map`，用户创建由 `scripts/add_user.sh` 负责。
- `authorized_keys` 行用 `#user:<username>` 做归属标记，删除用户时 `scripts/remove_user.sh` 会删除该用户所有 key 行。
- 只支持 `ssh-ed25519` 公钥，方便限制格式和减少老旧 key 类型。
- **`add` 会自动 `chmod 600 keys/authorized_keys` 和 `chmod 755 keys/`。** OpenSSH 会拒绝 group-writable 的 authorized_keys 或其父目录；手工编辑 keys 后若 SSH 突然失败，先检查权限，再对照 `skills/add_user.md` 里的 uid 排查。
- 修改 authorized_keys **不需要**重启容器，但前提是 sshd 愿意读取该文件——uid/权限不对时，改 key 内容也无效，需要先修属主或重建 gateway。
