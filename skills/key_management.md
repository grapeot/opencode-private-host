# Skill: 用户 Key 管理（key_management）

## 元数据

- 类型: Workflow
- 适用场景: 运营者管理某个用户的 authorized_keys 条目（添加、删除、轮换）
- 创建日期: 2026-06-21

## 目标与边界

管理 `keys/authorized_keys` 里某个用户对应的公钥行。支持添加新 key（用户轮换了 iOS 客户端的 key）、删除旧 key、列出当前 key。

**做什么**：按 `#user:<username>` 标记定位行，执行增删查。

**不做什么**：不创建/删除 Docker 容器（那是 add_user / remove_user 的职责）；不修改 port_map；不重启容器（authorized_keys 变更不需要重启，OpenSSH 每次连接重读文件）。

## 可用资源

- keys/authorized_keys（项目根目录）
- keys/port_map（端口分配表，只读，用于验证用户存在）

## 验收标准

1. 添加 key 后，`keys/authorized_keys` 里有该用户的新公钥行，`#user:<username>` 标记正确。
2. 删除 key 后，该用户的所有行从 authorized_keys 移除。
3. 同一用户不会出现重复行。
4. 修改 authorized_keys 后不需要重启任何容器，新 key 立即生效（下次 SSH 连接时 OpenSSH 重读文件）。
5. CLI 有单元测试：测试添加、删除、轮换、重复添加、删除不存在的用户等 edge case。

## CLI 设计

```bash
# 列出某个用户的 key
scripts/manage_key.sh list <username>

# 添加 key（替换该用户现有的所有 key）
scripts/manage_key.sh set <username> <public_key_file>

# 删除某个用户的所有 key
scripts/manage_key.sh remove <username>

# 验证某个公钥是否在 authorized_keys 里
scripts/manage_key.sh verify <username> <public_key_file>
```

### 行为细节

`set` 是幂等的：如果该用户已有 key，先删除旧 key 再写入新 key。这样轮换 key 时一条命令搞定。

`remove` 删除该用户的所有行。如果用户不存在，报错退出（不静默成功）。

`list` 输出该用户的所有 authorized_keys 行，每行一个。用户不存在时输出空。

`verify` 退出码 0 表示 key 已存在，退出码 1 表示 key 不存在，退出码 2 表示用户不存在。

## 测试设计

`tests/test_manage_key.sh` 或 `tests/test_manage_key.py`：

1. 创建临时 authorized_keys 文件，预置几个用户。
2. 测试 `set` 新用户：验证行被追加，格式正确。
3. 测试 `set` 已有用户：验证旧行被删除、新行被写入，行数不变。
4. 测试 `remove` 存在的用户：验证行被删除。
5. 测试 `remove` 不存在的用户：验证报错退出码非 0。
6. 测试 `list` 有 key 的用户：验证输出匹配。
7. 测试 `list` 无 key 的用户：验证输出为空。
8. 测试 `verify` key 存在：退出码 0。
9. 测试 `verify` key 不存在但用户存在：退出码 1。
10. 测试 `verify` 用户不存在：退出码 2。
11. 测试重复 `set` 同一 key：不产生重复行。

## 已知陷阱

（部署后补充）