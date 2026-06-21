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

## Lessons Learned

（部署后补充）