# 投稿后端部署记录

2026-10-30 09:33（北京时间）部署至现有 HTTPS 服务 `https://39.107.44.18`。投稿接口、图片上传、私有草稿、版本保存、提交待审、公开文章接口以及受保护的审核接口已启用。

## 发布范围

从服务器当前账号/评论版本下载基线并逐文件固定 SHA-256，只插入投稿路由与分发，新增投稿服务、文档校验、奖励投递适配和迁移 `002_submissions.sql`。未携带工作区中尚未发布的头像重置与资料保存行为改动。既有数据库基础结构、收藏目录和题库评论代码哈希保持不变。

- 应用：`/opt/hegong/backend`；候选包：`/opt/hegong/releases/submissions-20261030/candidate`。
- 数据库迁移版本现为 **1、2、3**；原有用户数据保留。
- 新增依赖：Pillow 13.0.0，服务器已安装，`requirements.lock` 已记录。
- Nginx 只为 `/v1/submission-assets` 设置 9 MiB 请求体上限（容纳 6 MiB 图片的 base64），为 `/v1/rpc` 设置 1 MiB；其余入口继续使用原 256 KiB 限制。原 HTTPS、认证限流和转发设置保留。
- 已重启 `hegong-backend` 并重新加载 Nginx；最终均为 `active`，部署文件和保留文件的哈希复核通过。

## 备份和回退

数据库完整备份、修改前的代码、Nginx 配置和发布清单位于：

`/var/backups/hegong/submissions-20261030T013320Z`

数据库归档已用 `pg_restore --list` 验证可读取。激活脚本在健康检查失败时自动恢复本次替换的代码和 Nginx 配置；新增数据库表保留，避免把恢复数据库覆盖到发布后的真实用户写入上。正式激活前后均验证基线哈希，发现并行修改会拒绝覆盖。

工具：`backend/ops/prepare_submissions_release.py` 和 `activate_submissions_release.py`。临时测试账号清理使用服务器发布目录内的 `submission_smoke_cleanup.py`，按准确 ID 和专用账号前缀核验，不对正式库执行 TRUNCATE。

## 验证结果

- 服务器隔离 PostgreSQL `hegong_test`：**44 项通过**，覆盖既有账号、社交、评论及投稿权限、版本冲突、审核/发布状态和奖励幂等。
- 正式 HTTPS：**27 项通过**，覆盖证书、注册、投稿配置、原资料 RPC/题库讨论、真实大于 256 KiB 的 PNG 上传、私有图片权限、草稿创建/保存/重放、旧版本冲突、本人列表、提交待审、禁止越权审核、公开文章入口和撤回。
- 未向生产环境发表测试文章、未创建奖励事件、未给正式账号发电池。
- 临时账号和稿件已清理；最后核对正式用户仍为 1，测试账号、测试稿件、附件、公开文章和奖励事件均为 0。

证据：[服务器测试](outputs/submissions-deployment/server-tests.log)、[HTTPS 检查](outputs/submissions-deployment/https-checks.json)、[最终状态](outputs/submissions-deployment/server-status.json)、[发布清单](outputs/submissions-deployment/release-manifest.json)。

## 使用与保留条件

启动当前客户端，使用原账号登录，进入侧栏“投稿”即可保存草稿和提交审核；客户端默认服务地址不需更改。公开文章列表当前为空是因为还没有正式发表文章。

服务器审核员表当前为空。审核/发表接口已部署，但需要运营方指定真实账号后再授权，普通作者不能自行审核。奖励数额、规则版本和正式钱包接收端尚未配置；本次部署没有启用或模拟奖励到账。文章评论尚无对应接口，原题库评论保持可用。废弃附件清理和奖励投递的运维命令已部署，尚未添加自动执行定时器。
