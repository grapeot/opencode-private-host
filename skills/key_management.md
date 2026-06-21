# Skill: 用户 Key 管理（key_management）

## 元数据

- 类型: Workflow
- 适用场景: 运营者管理某个用户的 authorized_keys 条目（添加设备、删除设备、列出设备、轮换 key）
- 创建日期: 2026-06-21

## 目标与边界

管理 `keys/authorized_keys` 里某个用户对应的公钥行。一个用户可以有多把 key（对应多个设备：iOS、Mac、iPad 等），每把 key 独立管理——添加新设备、删除丢失的设备、轮换某台设备的 key。

**做什么**：按 `#user:<username>` 标记定位行，执行增删查。同一个用户可以有多行（多设备）。

**不做什么**：不创建/删除 Docker 容器（那是 add_user / remove_user 的职责）；不修改 port_map；不重启容器（authorized_keys 变更不需要重启，OpenSSH 每次连接重读文件）。

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
```

### 行为细节

`add` 是幂等的：如果该公钥已存在（完全匹配），不重复追加。如果用户不存在，报错退出。

`remove` 删除指定公钥对应的行。如果该公钥不在 authorized_keys 里，报错退出。如果用户不存在，报错退出。删除后该用户可能还有其他 key（其他设备），不影响。

`list` 输出该用户的所有 authorized_keys 行，每行一个。用户不存在时报错退出。

`verify` 退出码 0 表示 key 已存在，退出码 1 表示 key 不存在但用户存在，退出码 2 表示用户不存在。

### 多设备工作流

用户在电脑上生成 SSH key：`ssh-keygen -t ed25519`。把公钥发给运营者，运营者执行：

```bash
scripts/manage_key.sh add alice /path/to/alice_macbook_ed25519.pub
```

之后用户就可以从电脑上用这把 key 访问自己的 OpenCode 容器。iOS 客户端用另一把 key，两把 key 独立，互不影响。设备丢失时：

```bash
scripts/manage_key.sh remove alice /path/to/lost_device_ed25519.pub
```

## 测试设计

`tests/test_manage_key.py`：

1. 创建临时 authorized_keys 文件，预置几个用户（部分用户多 key）。
2. 测试 `add` 新用户的第一个 key：验证行被追加，格式正确，`#user:` 标记正确。
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

（部署后补充）