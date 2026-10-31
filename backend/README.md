# 河工开物后端

2026-11-01 代码更新（服务器待部署）：`find_user` 的可访问用户响应增加 `school`、`college`、`major`、`grade`、`bio`，供会话操作的“查看资料”显示。只返回明确允许的五个字段，不展开整个用户表或资料 JSON；好友列表、会话同步和交易身份仍是简要结构。登录、双向屏蔽、停用账号限制保持不变，不涉及数据库迁移。本次仅同步代码，正式服务需后续部署此改动。

2026-10-29 部署第一版。后端为 FastAPI + PostgreSQL，由 Nginx 提供 HTTPS 入口，systemd 管理进程。服务与数据库同机；代码和依赖版本已保存在此目录。`backend/.gdignore` 防止服务端文件进入 Godot 客户端资源包。

## 当前入口与客户端

- 测试接口地址：`https://39.107.44.18`
- 健康检查：`GET /health`
- 功能状态：`GET /v1/meta`
- Godot 自动加载项：`BackendProvider`，脚本 `scripts/backend_provider.gd`。
- 正常运行项目后，通过个人中心的「登录 → 前往登录」打开账号密码窗口，可切换到「注册账号」。用户名为 4–32 位英文字母、数字或下划线，大小写不敏感；密码仅要求至少 6 位，不要求字母、数字或符号组合，不限制字符种类，也不裁剪首尾空格。显示名称可在个人资料中修改。
- 软件账号与服务器 root 账号完全分开；服务器密码和私钥不得放入客户端。
- Windows 桌面客户端在成功登录后记住上次账号，并用当前 Windows 用户的 DPAPI 加密保存会话凭证，不保存密码。普通关闭程序后可在登录窗口点击“一键登录”，通过现有 `profile` RPC 在线验证后恢复会话；服务器会话有效期仍默认 7 天，不在客户端延长。退出登录、修改密码或服务器拒绝会话后清除快捷凭证，保留用户名供密码登录；“移除记录”会清除本机账号记录。其他平台在未提供安全存储适配时仅记住用户名。修改密码继续撤销所有服务端会话。
- 设置环境变量 `HEGONG_API_URL` 可覆盖接口地址，必须是 HTTPS。`HEGONG_BACKEND_DISABLED=1` 禁用自动接入；headless 检查默认不接正式服务，只有明确开启 `HEGONG_BACKEND_LIVE_TEST=1` 才允许联调。

## 已实现范围

- 账号注册、密码登录、退出、修改密码；Argon2id 密码散列，数据库只保存访问令牌的 SHA-256 摘要。
- 个人资料读写、服务器生成的稳定公开 ID、从本人持有卡牌中选择头像。
- 按公开 ID 查找用户、好友申请/接受/忽略、好友列表、备注、免打扰、删除和拉黑。
- 私聊、历史分页、未读水位、系统通知；普通发消息接口不能伪造赠送/交换/官方消息。非好友每个方向最多一条招呼消息，删除和拉黑不清除历史额度。
- 权威收藏库存、赠送与操作结果查询；赠送后每种卡牌至少保留一张。
- 交换邀请、确认/取消/拒绝、历史记录；同卡交换按实际送出总量核验，条款不可变，邀请不冻结库存。
- 举报记录持久化，并验证附带消息属于举报双方的会话。记录目前存入 `reports` 表，尚无独立运营审核后台或消息通知渠道。
- 按设备保存的学习数据 API，带版本比较更新；不会自动覆盖或合并客户端已有本地学习记录。

所有账户初始库存为 0，没有自动发放示例卡牌或虚假余额。好友和交换数据始终来自数据库。客户端已有充值/钱包服务未接入本后端；支付、奖励、卡牌获取规则不在本次范围内。

## 明确未开通

1. 微信与 Steam 登录：只有数据结构和禁用状态的接口入口；缺少平台应用参数/凭据时返回不可用，不接受客户端自报 OpenID 或 Steam ID。接入前必须增加平台凭证校验和显式账号绑定流程。
2. 微信小程序前端及发布：此目录不生成小程序。正式小程序仍需要符合平台要求的域名、HTTPS、备案和审核。
3. 域名：用户正在申请。当前 IP HTTPS 入口用于部署联调；域名准备好后，修改 Nginx `server_name`、域名证书及客户端接口地址。IP 证书不能替代微信小程序的合法服务器域名。
4. 收藏「想要」仍以客户端既有本地存档为源；好友愿望清单返回明确 `unavailable`，未另造一份不同步的数据。
5. 学习记录的自动上传、跨设备合并策略、邮箱/短信找回密码和微信/Steam账号绑定界面尚未接入。

## API

所有业务请求通过 HTTPS 发送。认证请求返回 `access_token`、`account_id`；后续使用 `Authorization: Bearer <access_token>`。不要把令牌放进 URL。

| 路由 | 请求 |
| --- | --- |
| `POST /v1/auth/register` | `{username,password,display_name?}` |
| `POST /v1/auth/login` | `{username,password}` |
| `POST /v1/auth/logout` | `{}`，需要会话 |
| `POST /v1/auth/password` | `{current_password,new_password}`，需要会话 |
| `POST /v1/rpc` | `{version:1,action,payload}`，需要会话 |
| `POST /v1/auth/wechat`、`/v1/auth/steam` | 当前返回 `unavailable` |

RPC 的资料操作为 `profile`、`save_profile`、`account`；收藏操作为 `snapshot`、`send_gift`、`gift_status`；好友/聊天/交换操作见根目录 `SOCIAL_SERVICE_CONTRACT.md`。协议始终以认证会话确定当前用户，不接受 payload 中的 `account_id/actor_id/sender_id/type/status`。旧收藏函数中的 `id` 由适配器映射为 `operation_id`，不转发自报账户和本地状态。

资料保存：`{action:"save_profile",payload:{patch:{display_name:"新名字"},avatar_card_id:""}}`。

学习 API：`study_load` 的 payload 为 `{}`；`study_save` 为 `{device_id,expected_version,data}`。首次版本为 0，成功返回新版本。并发旧版本拒绝写入，按账号隔离。数据上限约 180 KB。

## 一致性与安全边界

- 所有涉及双方的写操作按稳定顺序锁定同一组 `users` 行。好友关系、拉黑、赠送、交换和头像拥有校验共享这一事务边界。
- 幂等操作键永久绑定操作者、动作及完整参数；重放返回原结果，变更条款返回冲突。赠送确定失败也保存可查询的失败结果。
- 库存扣增、流水、业务终态、outbox 及消息投影在同一个 PostgreSQL 事务内提交；当前投影没有外部消息系统，不能重复转移库存。
- 分页/增量游标使用 HMAC，绑定用户和查询范围。增量超限要求重建快照，不跳过未交付事件；旧消息仍可通过 history 读取。
- Nginx 限制请求体与入口请求速率，数据库计数实现跨 worker 的账号/IP 频率限制。校园 NAT 下的登录/注册阈值需要根据真实访问情况调整，不能把这些默认值当作容量承诺。
- 应用端口 `127.0.0.1:8000`、数据库端口 `127.0.0.1:5432` 均不向公网监听。UFW 当前仅允许 TCP 22、80、443；SSH 使用专用密钥。
- 正式服务器没有默认软件管理员账号或内置演示账号。客户端不包含服务器密钥、数据库凭据或平台 AppSecret。

## 服务器运维

| 项目 | 位置/名称 |
| --- | --- |
| 应用目录 | `/opt/hegong/backend` |
| Python 环境 | `/opt/hegong/venv` |
| 环境配置 | `/etc/hegong/backend.env`，root 与服务用户可读 |
| 数据库 | `hegong`；隔离测试数据库 `hegong_test` |
| 服务用户 | Linux/PostgreSQL `hegong`，数据库使用本机 peer 认证 |
| 应用服务 | `hegong-backend.service` |
| Nginx 配置 | `/etc/nginx/sites-available/hegong` |
| 证书 | `/etc/letsencrypt/live/hegong-ip/` |
| 证书续期 | `hegong-cert-renew.timer`，每天检查两次，成功后重载 Nginx |
| 本机备份 | `/var/backups/hegong/`，`hegong-backup.timer` 每天执行，保留约 7 天 |

IP 证书来自 Let's Encrypt，约六天有效，因此必须保留 HTTP 80 的 ACME 验证路径和续期 timer。服务器重启后服务、Nginx、PostgreSQL 和 timer 自动启动。备份检查包括 pg_dump 归档可读性；本机定时备份不能抵御整台服务器丢失，独立异地自动备份仍需后续配置。

常用操作（服务器终端）：

```bash
systemctl status hegong-backend --no-pager
journalctl -u hegong-backend --since '1 hour ago' --no-pager
systemctl list-timers hegong-cert-renew.timer hegong-backup.timer
systemctl start hegong-backup.service
```

新增安装：先运行 `ops/bootstrap.sh` 配置入口，然后将本目录程序上传 `/opt/hegong/backend`，运行 `ops/install.sh` 安装环境；`ops/test.sh` 通过后运行 `ops/activate.sh`。已有生产服务器更新代码时先备份，上传并测试，再重启 `hegong-backend`；不要再次运行 bootstrap 覆盖正式入口。`schema.sql` v1 为幂等初始迁移，后续字段变化必须添加有版本的迁移。

## 验证

- 2026-10-29 密码规则调整：统一为至少 6 位，无字符组合要求，移除客户端和 API 的 128 位密码字段上限。覆盖 6 位纯数字、字母、中文、符号、空格及长密码的注册/登录/改密，5 位拒绝；独立 PostgreSQL 测试共 23 项通过。Godot 实际注册窗口使用随机 6 位纯数字密码完成 HTTPS 注册和再次登录验证。
- 首轮部署结果：14 项独立 PostgreSQL 集成测试通过；真实 Godot 注册窗口及 HTTPS 接口联调通过。两个临时账号按确切 ID 清理，首次清理后正式库账号数为 0。
- 已执行 `ops/verify-backup.sh`，将正式备份恢复到临时独立数据库，核对版本及账号数后删除该临时库；恢复成功。
- Certbot `renew --dry-run --no-random-sleep-on-renew --cert-name hegong-ip` 模拟续期通过，正式证书与定时任务保持启用。
- `ops/test.sh` 只在独立 `*_test` 数据库运行。覆盖密码/令牌、会话撤销、资料权限、头像拥有、好友申请、会话访问、分页、消息幂等、赠送至少保留一张、失败恢复、多连接并发交割、取消/拉黑/赠送竞争、outbox 去重、举报授权、学习存档版本比较。
- `tools/check_backend_live.gd` 经用户授权显式开启时，使用真实 Godot HTTPRequest 和登录窗口，创建两个临时账号验证完整 HTTPS 流程。测试账号 ID 记录在 `.godot_appdata/backend-live-ids.json`，完成后从服务器按确切 ID 和 `livecheck_` 前缀清理。
- 测试通过代表这些功能和并发约束已验证；尚未完成 3000 用户容量压测，不据此承诺同时在线上限。
