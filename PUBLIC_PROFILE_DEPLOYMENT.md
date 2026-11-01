# 好友公开资料部署记录 · 2026-11-01

已部署到现有 HTTPS 服务 `https://39.107.44.18`。会话操作的“查看资料”现在可以取得对方已保存的学校、学院、专业、年级和个人简介。使用当前客户端重新打开资料页面即可重新查询；客户端仍运行旧界面时需重新运行项目。

## 上线内容

从服务器当前代码快照制作增量包，仅替换生产目录 `/opt/hegong/backend/domain.py`。与 Git 提交 `b4f54479228bc505dbafdffb0672c1fb5afbe00c` 对应，新增字段为 `school / college / major / grade / bio`。

五项资料只在明确的 `find_user` 查询中返回，好友列表、会话轮询及交易身份继续返回简要对象。保留登录、双向屏蔽和停用账号限制，不返回其他未声明的资料或账号字段。空资料返回空字符串，客户端显示“未填写”。没有安装依赖或执行新增数据库迁移。

发布按基线和候选文件哈希核验，保留了线上已部署的评论、投稿与电池功能。其余 27 个运行文件以及 Nginx、服务单元、环境配置均通过哈希核对。

## 验证

- 服务器独立 PostgreSQL 测试库：30 项通过，包含新增 3 项资料测试。测试库已删除。
- 正式 HTTPS：23 项通过。覆盖五项真实保存和读取、300 字简介、修改与清空、响应字段白名单、未登录拒绝、双向屏蔽、解除屏蔽、备注、好友关系，以及原文章/评论读取。
- 两个临时 `profilecheck_*` 账号按确切 ID 和专用命名前缀清理；最终残留 0 个。正式用户总数部署前后均为 2，没有修改真实用户资料。
- 数据库版本部署前后均为 `[1, 2, 3, 4, 5]`。
- 最终 `hegong-backend`、Nginx、PostgreSQL 均为 active；本机通过正式 HTTPS 验证健康状态为 ok。

证据：[服务器测试](outputs/public-profile-deployment/server-tests.log)、[正式接口检查](outputs/public-profile-deployment/https-checks.json)、[最终服务状态](outputs/public-profile-deployment/server-status.json)、[激活结果](outputs/public-profile-deployment/activation.json)、[发布摘要](outputs/public-profile-deployment/release-summary.json)。证据不包含密码、访问令牌、环境配置内容或数据库备份内容。

## 备份与回退

备份位于服务器 `/var/backups/hegong/public-profile-20261031T171549Z`（目录时间为 UTC，对应北京时间 2026-11-01）。包含原 `domain.py`、完整数据库归档、发布清单和通过测试的记录；归档已通过 `pg_restore --list` 检查。

候选目录为 `/opt/hegong/releases/public-profile-20261101-fc60484f`。激活使用部署锁，验证失败会恢复本次替换的代码并重启服务，不用旧数据库覆盖发布期间的用户写入。本轮激活成功，没有执行回退。

复用工具位于 `backend/ops/`：`prepare_public_profile_release.py`、`validate_public_profile_release.py`、`activate_public_profile_release.py`、`smoke_public_profile_release.py`、`public_profile_smoke_cleanup.py`。后续发布必须重新取得线上基线，不能用整个本地工作区覆盖生产目录。
