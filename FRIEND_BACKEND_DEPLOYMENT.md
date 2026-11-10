# 好友申请后端部署记录 · 2026-10-30

已部署到现有 HTTPS 入口 `https://39.107.44.18`，正式服务验证通过。新客户端可直接使用原地址，无需修改配置。

## 本次生效内容

- 申请附言最多 100 个 Unicode 可见字符，组合音标和多码点 Emoji 按一个字符计数。
- 保留附言原有的首尾空白和换行；超长、NUL、非法代理字符被服务端拒绝。
- 已成为好友时，申请接口明确返回 `state:friend`，供客户端处理关系状态的竞争变化。
- 继续使用原认证、用户 ID、好友关系、屏蔽规则、限流、唯一约束和幂等事务。

从线上代码快照生成增量包，仅激活以下 6 个文件：

```text
domain.py
friend_note.py
requirements.txt
requirements.lock
tests/test_backend.py
tests/test_friend_note.py
```

生产 Python 环境新增 `regex==2026.9.29`，没有升级其他依赖。没有数据库迁移；最终迁移版本仍为 1、2、3。评论、投稿、账号资料等文件及 Nginx 配置经哈希核对保持原样；没有将本地其他未发布改动打包上线。

## 验证结果

- 服务器独立 PostgreSQL 测试环境：**46 项通过**，包含账号、好友、消息、转卡、评论、投稿与新增附言校验。
- 正式 HTTPS：**23 项通过**。包括真实账号注册、ID 查询、自己的账号/无结果/已有好友/收到/发出状态、身份伪造拒绝、101 字拒绝、含复杂 Emoji 的 100 字附言接受、原样附言、幂等重试、5 个并发请求去重、接受、忽略、双向好友关系以及原评论/文章接口。
- 两轮发布校验分别创建的两个临时账号均已按确切 ID 和专用前缀清理，最终 `friendcheck_*` 账号数为 0，正式用户总数仍为 1。
- 最终 `hegong-backend`、Nginx、PostgreSQL 均为 `active`；服务器和本机访问 HTTPS `/health` 均返回 `ok`。
- 已验证 6 个部署文件与 10 个保留文件的哈希；Nginx 配置未变化。

证据：[测试日志](outputs/friends-deployment/server-tests.log)、[HTTPS 检查](outputs/friends-deployment/https-checks.json)、[最终状态](outputs/friends-deployment/server-status.json)、[发布清单](outputs/friends-deployment/friends-release.json)、[激活结果](outputs/friends-deployment/activation.json)。证据不包含密码、访问令牌或数据库备份内容。

## 备份与回退

成功发布前的数据库归档和原代码保存在服务器：

```text
/var/backups/hegong/friends-20261030T093058Z
```

归档已通过 `pg_restore --list` 检查。发布候选和隔离测试记录保留于：

```text
/opt/hegong/releases/friends-20261030T092040Z-r2
```

首次发布的正式检查发现新增依赖由 root 以过严权限安装，服务账号读取不完整。该轮于 `/var/backups/hegong/friends-20261030T092813Z` 留存备份并自动回退代码，临时账号清理成功。随后用正常运行包权限重新安装该单一依赖，增加服务账号的真实导入/组合字符检查，重新完成隔离测试和正式 HTTPS 验证后发布成功。

激活流程使用部署锁、基线哈希和候选哈希检查。失败时仅恢复本次改动代码，不以旧数据库覆盖发布后的用户写入。本轮无需恢复数据库。

复用工具为 `backend/ops/prepare_friends_release.py`、`activate_friends_release.py`、`smoke_friends_release.py` 和 `friends_smoke_cleanup.py`。后续发布仍应重新下载线上基线、在独立 `*_test` 库测试；不要直接用整个本地工作区覆盖生产目录。
