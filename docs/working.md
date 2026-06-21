# Working Notes

## Changelog

### 2026-06-21

- 项目脚手架初始化：创建 docs/、sshd-gateway/、opencode/、keys/、scripts/、tests/ 目录
- 写完 PRD、RFC、test.md
- sshd-gateway：Dockerfile + sshd_config + entrypoint.sh
- opencode：Dockerfile（基于 alpine + COPY 预编译 binary）
- docker-compose.yml：双容器架构，internal network，sshd-gateway 对外暴露 SSH_PORT，opencode 不暴露端口
- .env.example：1Password 引用格式（Route A），SSH 端口可配置
- scripts：build_image.sh、deploy.sh、add_user.sh
- 架构改为 per-user 容器：每个用户独立的 opencode 容器 + data volume + workspace，OS 级隔离
- RFC 重写：storage 三层设计（opencode 状态 volume + API key 1Password 注入 + OAuth token per-user volume + workspace clone context-infrastructure + tavily skill）
- PRD 重写：per-user 容器隔离，加用户/删用户 CLI 流程，key 管理 CLI + 测试
- 新增 skills/add_user.md：加用户全流程 skill 文档
- 新增 skills/key_management.md：key 管理 skill 文档 + CLI + 测试设计
- README/PRD/RFC 加 iOS 客户端 repo 链接

## Lessons Learned

（部署后补充）