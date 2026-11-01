# 想要清单 · 2026-11-02

收藏页的「想要」已接入现有 HTTPS 服务和 PostgreSQL，好友「想要清单」读取同一来源。好友弹窗使用与赠送、换卡一致的尺寸、字体、卡牌原图和固定底部按钮，支持加载、重试、空清单、深色、窄窗口和滚动。赠送、换卡先进入已有确认流程，不在清单中直接交割。

## 同步方式

- 已登录账户在登录、进入收藏、重新进入缓存页或点击「同步想要」时读取云端。好友打开弹窗或点击「刷新清单」时重新读取；没有额外的清单轮询。
- 添加、取消先原子保存到当前账户的本机存档；350ms 合并连续操作，按卡牌发送最终意图。没有修改的卡牌不随旧缓存覆盖另一台设备的操作。
- 断网保留待提交修改，重试间隔从 3 秒逐步退避至 60 秒；切换账号立即隔离旧请求。原操作编号在请求前持久化，丢失回包或重启后重试不会重新覆盖其他设备后续取消的卡牌。
- 初次创建云端清单时，迁移该登录账户原有的本机想要标记。云端已有清单时，以云端加本机明确待提交操作为准，不再次导入其他设备的陈旧缓存。未登录的 `local-profile` 不自动合入任何登录账户。
- 获得、赠送和换卡不会自动取消想要。好友清单只向仍有好友关系且双方均未屏蔽的账户开放；不返回持有数量。

## 服务接口

沿用 `POST /v1/rpc` 和现有鉴权：

| action | payload | 结果 |
| --- | --- | --- |
| `wishlist_load` | `{}` | 当前账户的 `card_ids / wishlist_revision / initialized` |
| `wishlist_update` | `{operation_id, expected_revision, changes:{card_id:boolean}}` | 原子应用逐卡修改；旧版本返回 `wishlist_conflict`，客户端重读合并；重复操作返回原回执 |
| `wishlist` | `{peer_id}` | 同一云端清单的好友只读投影，含 `visibility:accessible` |

新表 `collection_wishlists` 独立版本号；`006_collection_wishlist.sql` 为兼容性新增迁移。服务端校验公开目录、布尔标记、登录身份、好友权限和幂等指纹；更新沿用用户锁，避免多设备并发丢失更新。

## 验证和交付

- 本机 PostgreSQL：35 项通过（基础服务与新增 8 项清单检查）。
- 从生产快照制作的服务器候选包：35 项通过，独立测试库已清理。
- 正式 HTTPS：28 项通过；两个临时账号已按确切 ID 清理。
- 真实 Godot HTTPS：10 项通过；独立缓存的第二设备读取、修改、第一设备刷新、JSON 存档恢复原操作均通过，临时账号已清理。
- 界面与本机状态：18 项通过；收藏专项通过；社交回归 104 项通过。测试不向真实用户发送消息或转卡。

预览：[浅色](outputs/wishlist-validation/wishlist-light.png)、[深色](outputs/wishlist-validation/wishlist-dark.png)、[窄窗口](outputs/wishlist-validation/wishlist-small.png)、[空清单](outputs/wishlist-validation/wishlist-empty.png)、[读取失败](outputs/wishlist-validation/wishlist-error.png)。

已部署至现有服务，仅激活 `domain.py`、`wishlist_service.py`、`migrations/006_collection_wishlist.sql`，未修改生产配置、评论、投稿或电池结算逻辑。数据库版本由 `[1,2,3,4,5]` 升至 `[1,2,3,4,5,6]`。候选目录 `/opt/hegong/releases/wishlist-20261102-8a833fd0`；备份 `/var/backups/hegong/wishlist-20261101T160441Z`（UTC，对应北京时间 11 月 2 日）。数据库归档已通过 `pg_restore --list` 检查。失败回退恢复代码，保留兼容性新表与发布期间的用户写入。

证据见 [部署结果](outputs/wishlist-validation/activation.json)、[服务端测试](outputs/wishlist-validation/server-tests.log)、[真实客户端检查](outputs/wishlist-validation/godot-https.log)。
