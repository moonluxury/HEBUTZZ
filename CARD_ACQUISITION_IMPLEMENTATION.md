# 获取卡牌

## 当前 PC 实现 · 2026-11-11

入口仍为「我的收藏 → 获取卡牌」。打开场景不扣费；点击任意可见卡背均调用原 `CardDrawStore.acquire()`，键盘仍可 Tab 聚焦入口、Enter 选择中央卡背。重叠处按实际绘制层级选择最上层的可见卡片，PNG 透明外角不拦截点击。Space 在待点击/请求未确认时不会产生请求。价格仍为 200 电池，中奖结果由服务器决定。

### 场景与素材

数据来自 `CollectionStore.season/results/card/count` 和 `data/collection_catalog.json`。当前系列为 `season-001`（空天探索 / 第一季），包括 `0001` 火箭、`0002` 人造卫星、`0003` 空间站、`0004` 宇航员、`0005` 空天飞机、`0006` 射电望远镜、`0007` 环状行星。卡背为目录中的 `res://assets/collection/cards/HEBUT_团队Logo卡背.png`；逐卡 `back_image` 存在时优先使用，否则继承系列卡背。七张卡面的 PNG、名称、编号、描述及比例均未修改。

舞台沿用原字体、标题渐变、按钮、按压反馈、蓝灰配色与原生 CanvasLayer。浅色地球弧面位于底部，原生绘制的低对比卫星线稿、少量星点及轨道线只作用于背景；原页面通过独立遮罩过渡进入。背景底图来自本轮对话中已生成的地球弧面素材，保持整图比例转存为 `assets/collection/stage/earth_horizon.webp`，不是卡牌素材。深色模式仅改变背景与文字配色。

### 文件与职责

| 文件 | 职责 |
| --- | --- |
| `scripts/card_acquisition_dialog.gd` | 总控：任意卡背选择、真实回执、卡池停中、图片就绪、揭晓、键盘与关闭；保留原返回信号和焦点恢复 |
| `scripts/card_carousel_stage.gd`（新增） | 只负责卡池资源、弧线位置/大小/透明度/排序、流转、停中、放大与取消；不访问交易服务 |
| `shaders/card_carousel.gdshader`（新增） | 卡背轻透视与远侧 mip 模糊，保留 PNG 透明外角 |
| `scripts/card_aerospace_backdrop.gd`（新增） | 地球弧面底景、原生星点/卫星/轨道线与独立入场 |
| `assets/collection/stage/earth_horizon.webp`（新增） | 独立背景底图，导入配置随项目保存 |
| `scripts/ui_tokens.gd` | PC 卡池时长、展示数量和悬停速度参数，见下表 |
| `tools/check_card_carousel.gd`（新增） | 原生渲染、七卡停中、真实回执交接、跳过/关闭/减少动态效果、窗口适配的隔离检查 |
| `tools/check_card_acquisition.gd` | 原有交易/恢复回归，等待新卡池和原揭晓的完成事件 |
| `tools/check_card_draw_live.gd` | 保留原受限临时账号联调入口，等待新舞台就绪和退出完成；本轮未执行线上联调 |

`CardDrawStore`、后端、收藏页入口/筛选/导航、CardReveal 本体及其着色器没有修改。当前 CardReveal 是 700ms 翻面、48 个外围光点、160ms 信息淡入；沿用标题自身的轻扫光，不恢复旧版本的长蓄势或强扫光。

### 时序与安全边界

1. 遮罩和内容组复用 `CardModalMotion`；背景在 400ms 内显现。场景入场完成后卡池用 300ms 排开。
2. 原七款卡牌的本地展示副本组成 11 张卡带，约每 0.30 秒流过一个卡位。位置与倾角统一取自半径 3000px 的圆弧，按 112px 弧长间距排列；倾角始终沿轨迹切线，两端约 12°，大小仅平滑缩小至 0.965 倍，避免中心和边缘断层。悬停任意卡片时，全带速度平滑降至 30%（约每 1 秒流过一个卡位），移开恢复；悬停响应常数 140ms，不触发购买。两端各以 0.60 个卡位宽度淡入淡出，正常流速约 180ms，悬停速度稳定后约 600ms；宽度位于 `card_carousel_stage.gd` 的边缘 `smoothstep`。
3. 任意卡背点击先锁定所有选择入口，再调用原获卡服务；同时立即开始整组流转到中。11 张卡共用一个连续相位，选中卡片仍随队列沿原方向移动，左侧卡片可自然绕回；不会原地悬停或单独横飞。根据剩余卡位距离，以 250ms 基础时长加每卡位 140ms（上限 2100ms）完成整组转动，起始速度衔接当前流速，终点停稳。没有把卡位、索引或卡牌 ID 加入请求载荷。
4. 回执验证成功后，将真实结果绑定到用户选中的展示卡位，保持已经进行中的流转轨迹；若先到中央，保留卡背等待真实结果。若先收到回执，继续流转到中央后再揭示。恢复旧回执默认选中央附近卡位。七款真实目录、概率及库存不受展示数量或本地重排影响。
5. 选中卡片到达中央、真实结果和 CardReveal 正反面图片均就绪后，再用 450ms 放大并移至结果位置，其他卡背轻轻淡出；交接后由原组件执行 700ms 翻面。结果页按原生标题字形边界，将标题到卡面顶部的留白减半；卡面、卡名、说明及按钮整体上移，保持内部间距，卡池选择布局不受影响。
6. 结果说明展示实际卡名/系列/编号/描述、回执中的本次 `+quantity` 和服务快照中的当前数量。恢复回执不重新发奖。
7. Space 可跳过已确认结果的停中/放大/揭晓；图片未就绪时只记住跳过意图。请求未确认时 Space 不生效，长按/重复按键不再次购买。
8. Esc、关闭和返回按钮沿用统一退出：取消新增卡池 Tween 与帧循环、冻结当前可见姿态，原 200ms 退出完成后卸载并恢复入口焦点。关闭不取消业务服务，迟到回执只持久化，不重开弹层。
9. 减少动态效果时卡池静止；停中与交接直接完成，结果仍通过原短交叉淡化显示。运行中切换偏好也保留同一回执。

### 新增 UiTokens 参数

时长以秒为单位；仅作用于 PC 开卡舞台。展示张数、悬停倍率另行标注；原翻面时长在 `scripts/card_reveal.gd` 的 `REVEAL := 0.70`。

| 常量 | 默认值 | 含义 |
| --- | --- | --- |
| `CARD_STAGE_ENTER` | `0.40` | 空天背景进入 |
| `CARD_POOL_ENTER` | `0.30` | 卡池排开 |
| `CARD_POOL_STEP` | `0.30` | 流过一个卡位的秒数；调小更快；调大更慢 |
| `CARD_POOL_SETTLE` | `0.25` | 选中后整组流转到中的基础时长 |
| `CARD_POOL_TRAVEL_PER_SLOT` | `0.14` | 每个剩余卡位增加的流转时长 |
| `CARD_POOL_TRAVEL_MAX` | `2.10` | 整组流转到中的时长上限 |
| `CARD_POOL_EXTRACT` | `0.45` | 到中后放大并交接给 CardReveal |
| `CARD_POOL_DISPLAY_COUNT` | `11` | 展示卡背数量，不改变卡种和概率 |
| `CARD_POOL_HOVER_SPEED` | `0.30` | 悬停流速倍率；调大更快，如 `0.50` 是正常速度的 50% |
| `CARD_POOL_HOVER_RESPONSE` | `0.14` | 悬停变速响应常数；越大越柔缓 |
| `CARD_POOL_ARC_RADIUS` | `3000.0` | 圆弧半径（逻辑 px），越大越平缓 |
| `CARD_POOL_SPACING` | `112.0` | 沿圆弧的卡位间距（逻辑 px） |

### 运行与验证

用 Godot 4.6.2 打开根目录 `project.godot`，F5 启动并登录，从侧栏进入「我的收藏 → 获取卡牌」。点击任意可见卡牌均会触发真实的 200 电池业务操作。需要无真实扣费验证时使用以下隔离入口，不使用正式账号：

```powershell
python tools/run_workbench_checks.py --godot '<Godot 4.6.2 控制台程序>' --script check_card_carousel.gd --visual --timeout 110
python tools/run_workbench_checks.py --godot '<Godot 4.6.2 控制台程序>' --script check_card_acquisition.gd --visual
python tools/run_workbench_checks.py --godot '<Godot 4.6.2 控制台程序>' --script check_card_reveal.gd --visual
```

启动前设置 `$env:HEGONG_REDUCED_MOTION = '1'` 可检查减少动态效果；移除此环境变量后重新运行恢复正常动效。代码级入口仍是 `/root/UiMotion.set_enabled(false)`，系统设置也继续自动读取。

本轮实际检查：新卡池专项在 **OpenGL Compatibility 与默认 Vulkan Forward+ 渲染器下各 207 项通过**；原获卡回归 **34 项通过**；原 CardReveal、收藏页及架构边界回归通过。验证包括逐张原生鼠标选择全部 11 个卡位（含左右两端），逐卡验证整组沿原方向连续移动、选中卡片真正到中转正后才交接，先到中/先收回执两种时序，重叠处选中最上层卡片，透明外角不拦截，悬停减速和移开恢复，跨卡快速连点一次扣费，请求不携带卡牌 ID，服务器返回与点击卡位不同的结果，全部七款卡交接矩形一致，错误卡图，迟到结果关闭/重开，重复获得，Space/Tab/Esc，运行中减少动态效果以及 900×620 / 1600×540 / 1920×1080 适配。截图在 `outputs/card-carousel-validation/`，最新卡带为 `02-dense-arc-flow.png`，悬停状态为 `02-hover-slowdown.png`。

所有获卡数据使用隔离 provider 和独立 `workbench-check-*` 存档。未对正式账号扣费、未修改或重新部署后端、未导出安装包。原 CardReveal 检查退出时出现过 Godot ObjectDB 清理警告，断言通过；本轮卡池专项与原获卡回归无该警告。

---

## 初版实现与上线记录 · 2026-11-02

以下保留历史交付记录；当前前端呈现和参数以上一节为准。

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
