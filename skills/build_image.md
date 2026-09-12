# Skill: 重建并发布 OpenCode 镜像（build_image）

## 元数据

- 类型: Workflow
- 适用场景: 维护者要更新 `OPENCODE_IMAGE`（新模型需要新 runtime、修定制 patch、或 GHCR `latest` 已过旧）
- 创建日期: 2026-09-12

## 目标与边界

在**有源码的机器**上从定制 OpenCode checkout 编译 musl binary、打 `linux/amd64` 镜像、push GHCR；再在 **VPS** 上 pull 并用 `op run` 重建用户容器。用户 volume 保留。

**做什么**：确认 checkout 分支、跑 `scripts/build_image.sh`、回报 digest / `opencode --version`、在 VPS pull + `docker compose up -d`（不带 `-v`）、按 `skills/web_ui.md` 刷新模型列表并验收。

**不做什么**：不在 VPS 上从源码编（VPS 普通部署只 pull）；不 `docker compose down -v` / `docker volume rm`；不把 `opencode/bin/*` 提交进 git；不把 GHCR token 或 1Password 路径写进公开文件；不把首次 onboard 和镜像维护混在一起。

## 开始前必问

1. 是 **编译推送**、**VPS 换镜像**，还是两步都做？编译通常在另一台有 Bun / checkout 的机器；VPS 只 pull。
2. checkout 路径和分支是什么？脚本默认要求 `private-dev-squashed`。若维护者故意用别的分支或未提交 patch，必须在回报里写明，否则无法复现 binary。
3. VPS 上要重建哪个逻辑用户的容器？从 `keys/port_map` 读出后请运营者确认。不要猜。

## 何时需要换镜像

`skills/web_ui.md` 的 `opencode models --refresh` 只更新 models.dev 缓存。若缓存 JSON 里已有新 model id（例如 `gpt-6-astra`），但 `docker exec opencode-<username> opencode models openai` **仍不列出**，说明 binary 不认识该型号。只重启容器没用，必须换 `OPENCODE_IMAGE`。

公开型号名以 models.dev / OpenAI 为准（例如 GPT-6 对应 `gpt-6-astra`，不是 `gpt-6`）。

## 编译机（维护者）

前置：`opencode-official` checkout、Bun、Docker、`docker login ghcr.io`（token 要有 `write:packages`）。Apple Silicon 也必须 `linux/amd64`。

在 `opencode-private-host` 根目录：

```bash
export OPENCODE_CHECKOUT=/absolute/path/to/opencode-official
export GHCR_USER=your-github-username
export IMAGE_NAME=opencode-private
export IMAGE_TAG=latest
./scripts/build_image.sh
```

必须显式设置 `GHCR_USER`，不要用脚本默认的 `your-github-username`。脚本会：`bun install` → `packages/opencode` 里 `bun run build` → 复制 `packages/opencode/dist/opencode-linux-x64-baseline-musl/bin/opencode` → `docker build --platform linux/amd64` → push `ghcr.io/$GHCR_USER/opencode-private:latest`。

编译机只回报这些（不要贴 token）：

1. 分支名、commit SHA、是否有未提交 worktree 改动（有则列出影响模型/SDK 的文件）
2. 推上去的 digest：`ghcr.io/<user>/opencode-private@sha256:...`
3. 新 binary / 容器内 `opencode --version`
4. 若能跑：`opencode models openai` 是否出现目标型号

`opencode/bin/opencode` 是构建产物，gitignored，不要 commit。

## VPS（换镜像，不丢数据）

会话、OAuth、`opencode.jsonc`、workspace 在 named volume / bind mount 上，不在镜像里。标准流程：

```bash
source ~/.config/op/service_account.env   # 或等价设置 OP_SERVICE_ACCOUNT_TOKEN
docker pull ghcr.io/your-github-username/opencode-private:latest
# 确认 digest 与编译机回报一致
docker image inspect ghcr.io/your-github-username/opencode-private:latest \
  --format '{{index .RepoDigests 0}}'

# 重建容器，不要带 -v / down --volumes
op run --env-file .env -- docker compose up -d
```

不要重启 `sshd-gateway`，除非 gateway 自己也要改。Compose 可能警告 volume 不是它创建的，只要没有 `external: true` 误删，可以忽略。

若 `op run` 报 not signed in：确认已 `source` service account；若 shell 里还有个人 `op signin` session，先保证 `OP_SERVICE_ACCOUNT_TOKEN` 已导出。`OP_SERVICE_ACCOUNT_TOKEN` 不会自动进新 shell。

验收：

```bash
docker exec opencode-<username> opencode --version   # 与编译机回报一致
docker exec opencode-<username> ls /data/opencode/auth.json /workspace/AGENTS.md
# 再按 skills/web_ui.md 刷新缓存
docker exec opencode-<username> opencode models --refresh
docker compose restart opencode-<username>
docker exec opencode-<username> opencode models openai
```

`opencode models <provider>` 应出现目标型号。让运营者刷新浏览器。

## 验收标准

1. GHCR 上新 `latest` 的 digest 与编译机 push 一致。
2. VPS 容器 `opencode --version` 与编译机回报一致。
3. `opencode-data-<username>`、`opencode-config-<username>`、`workspaces/<username>` 仍在；`auth.json` 还在。
4. `sshd-gateway` 仍 running（除非运营者要求一起更新）。
5. `opencode models openai`（或对应 provider）能列出本次要补的型号。
6. 没有 `docker volume rm`，没有把 `opencode/bin/*` 提交进 git。

## 可用资源

- `scripts/build_image.sh`
- `opencode/Dockerfile`（`XDG_CACHE_HOME=/tmp/opencode-cache`）
- `.env` 的 `OPENCODE_IMAGE`
- `skills/web_ui.md`：换镜像后的 tunnel / 刷新模型
- `skills/onboard.md`：首次部署不要走本 skill
- `docs/rfc.md` 镜像分发

## 已知陷阱

- VPS 上 `docker pull ...:latest` 若 digest 没变，说明 GHCR 还是旧镜像，refresh 解决不了。
- 缓存有 id、CLI 列表没有 = binary 过旧，不是 tunnel 问题。
- `docker compose restart` 不换镜像，也不清同一容器的 `/tmp` 缓存。
- 换镜像用 `up -d` 重建容器即可；`down -v` 会删 volume。
- 脚本默认 checkout 路径是 `../opencode_ios_client/opencode-official`，那台机器没有就显式设 `OPENCODE_CHECKOUT`。
- 偏离 `private-dev-squashed` 或带着未提交 patch 构建时，只报 commit SHA 无法复现；必须记下 worktree。
- Apple Silicon 漏掉 `--platform linux/amd64` 会得到 ARM base + x64 musl 的混镜像。
