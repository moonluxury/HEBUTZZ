# 获取卡牌 · 2026-11-02

PC「我的收藏」右上角新增“获取卡牌”，旁边以原有灰色文字标注“200 电池/次”。点击入口打开全屏遮罩与当前 HEBUT 卡背；只有再点击卡背才发起获取。成功后复用原 `CardReveal` 的入场、翻面、扫光、15 颗光点和文字/按钮淡入时序；空格跳过动画，按住或松开不会再次获取。展示完成后点击卡牌或“返回我的收藏”回到原收藏总览，保留筛选及展开状态。

开卡前关闭不扣电池。进行中的请求由持久服务管理，关闭页面不重新发起；断网、切换账号或重启后核实原操作。未确认结果不显示获卡成功，余额不足不扣电池、不发卡。损坏的本机请求记录保留原文件并阻止再次扣费。

展示间距按最新要求缩小 70 个布局像素：标题保持原位，卡背、开卡动画、周围光效、说明和返回按钮一起上移；点击区域跟随卡背，窗口缩放沿用原有比例。

## 价格与概率

固定 200 电池获得 1 张，允许重复，重复卡增加数量。卡池为当前“空天探索”7 张；保留原卡图、卡背、名称和编号。

| 卡牌 | 原 ID | 概率 |
| --- | --- | --- |
| 宇航员 | 0004 | 10% |
| 环形行星（现有目录名：环状行星） | 0007 | 10% |
| 空天飞机 | 0005 | 12% |
| 空间站 | 0003 | 14% |
| 火箭 | 0001 | 16% |
| 射电望远镜 | 0006 | 18% |
| 人造卫星 | 0002 | 20% |

服务端使用 `secrets.randbelow(100)` 按上述区间抽取，客户端不能传入中奖卡牌、概率、操作者或其他扣费数额。价格、卡池、概率调整需更新 `RULE_VERSION`，旧请求仍按原回执恢复。

## 实现与事务

- `scripts/card_draw_store.gd`：由 AppServices 持有，按账号持久化请求标识后才提交；核对账号、卡牌、价格、数量和规则版本，合并服务返回的完整库存与钱包版本。UI 销毁不拥有交易生命周期。
- `scripts/card_acquisition_dialog.gd`：页面内遮罩与卡背等待态；直接复用未修改的 `card_reveal.gd` 及其着色器，详情跟随 `detail_alpha / detail_offset` 出现，空格仅跳动画。
- `scripts/my_collection.gd`：入口、浅色价格、关闭焦点及 Esc 返回；`scripts/recharge_dialog.gd` 把对应电池支出显示为“获取卡牌”。
- `backend/card_draw_service.py`：价格、概率、原操作回执、扣费及发卡；`backend/wallet_service.py` 在既有鉴权及账号锁之后接入三个动作。

RPC 位于既有 `/v1/wallet`：

| action | payload / 结果 |
| --- | --- |
| `card_draw_options` | `{}` → `price, pool_id, rule_version, duplicates, odds` |
| `card_draw` | `{operation_id, pool_id, expected_price:200, rule_version}` → 成功回执、当前余额及完整库存；业务拒绝为 `ok:false, state:failed` |
| `card_draw_status` | `{operation_id}` → 本人的原回执及当前余额/库存；不存在为 `state:not_found`，客户端继续保留原标识 |

服务沿用账号行锁，与赠送、交换和钱包支出串行协调。余额扣减、账本、库存增加、版本更新和 `operations` 回执处于同一事务；余额不足等终态拒绝也记录回执，迟到重试不能在以后赚到电池时突然扣费。数据库忙、断网和结果不明不当作终态拒绝。恢复旧回执返回当前库存/余额，不能使已经转走的卡牌重新出现。无需新表、迁移或依赖。

仓库同时补齐此前线上已有的钱包依赖：`wallet_service.py`、`quiz_rewards.py`、`/v1/wallet` 路由，以及钱包迁移 `005_battery_economy.sql` 和它引用的 `002_submissions.sql` 表结构。新数据库可直接初始化；这不是给正式服务器新增迁移。此次上传不包含其他正在进行的评论、投稿或好友弹窗修改，也不能用整个仓库目录直接覆盖现有服务器；线上增量发布仍使用下方按基线校验的工具。

## 验证

- 本机真实 PostgreSQL：59 项通过，覆盖原账号、钱包/投稿经济及新增 16 项开卡测试。概率按 100 个完整区间逐一核对；另验证原请求并发只扣一次、不同请求不能透支、发卡失败回滚、失败回执、跨账号恢复拒绝和伪造参数拒绝。
- `check_card_acquisition.gd --visual`：27 项通过，包括实际界面、当前卡背、既有动效、文字按钮、空格长按、返回、重复点击、丢包/重启恢复、账号切换、存储失败、损坏存档和小窗口。
- 原 `check_card_reveal.gd`、`check_collection.gd` 均通过。
- 服务器候选在独立数据库：43 项通过。
- 正式 HTTPS：20 项通过；真实 Godot 客户端到正式 HTTPS：11 项通过。只使用专门的临时账号和测试电池，三次临时身份均已清理，真实用户余额和卡牌未用于测试。

本地运行：`py -3 tools/run_workbench_checks.py --godot <Godot控制台程序> --script check_card_acquisition.gd --visual`。真实接口联调工具是 `tools/run_card_draw_live_checks.py`，只创建和操作受限前缀的临时账号。正式联调退出时有 Godot ObjectDB 清理警告，测试断言和实际交易均通过；没有把这些检查作为真实账号购买。

实际界面截图在 `outputs/card-acquisition-validation/`：入口、待点击卡背、翻面中、结果、返回收藏、余额不足和小窗口。截图中的账号、卡牌结果和余额均为隔离测试数据。

## 已部署

已在现有 `https://39.107.44.18` 服务上线，正式运行文件仅新增 `card_draw_service.py`、更新 `wallet_service.py`。基于线上最新基线生成，不覆盖已上线的公开资料、想要清单、评论、投稿及电池逻辑。其余 29 个文件和三个配置哈希保持一致。数据库版本部署前后均为 `[1,2,3,4,5,6]`，用户数均为 2；最终临时开卡账号数为 0，后端、Nginx、PostgreSQL 均 active，外部 HTTPS 健康检查正常。

候选：`/opt/hegong/releases/card-draw-20261102-1351b24f`。备份：`/var/backups/hegong/card-draw-20261101T170730Z`（UTC，对应北京时间 2026-11-02），原代码与数据库归档已保留并验证。发布锁及基线哈希防止覆盖并发更新；失败自动回退本次代码，不恢复旧数据库覆盖用户新写入。本次发布成功，无需回退。

部署工具：`backend/ops/prepare_card_draw_release.py`、`validate_card_draw_release.py`、`activate_card_draw_release.py`、`smoke_card_draw_release.py`、`card_draw_smoke_accounts.py`。

证据：[服务器回归](outputs/card-draw-deployment/server-tests.log)、[正式接口验证](outputs/card-draw-deployment/https-checks.json)、[Godot 实际联调](outputs/card-draw-deployment/godot-live.log)、[最终状态](outputs/card-draw-deployment/server-status.json)、[发布摘要](outputs/card-draw-deployment/release-summary.json)。公开证据不包含密码、访问令牌、环境配置内容或数据库备份。
