# 我要充值 · 两格横向电池版

2026-10-28，在已有部分实现上继续完成。使用 Godot 4.6.2 原生场景和控件，品牌、全局主题和其他页面结构保持现状。工作区中原有的好友、收藏、题库等未提交修改均保留；本轮没有整理或提交这些无关修改。

同日按最新截图调整：充值导航未选中为灰色；删除充值页顶部标题、副标题和余额标签，将主余额左移、主体上移。答题/投稿入口以线性图标、说明和链接组成两列，中间细线分隔。所有主页面和答题/资源详情页的右上角增加共用余额标识，使用现有顶部留白，不挤占原操作区域；F6 专注模式随原顶栏隐藏。未知余额显示“—”，缓存页面重入与切换账号同步共享状态。

## 进入与交付状态

打开 `E:/zhengzhi/project.godot`，F5，点击「我的好友」下方的「我要充值」。正常运行呈现真实未接入状态：余额/预计余额为“—”，套餐和收款保持禁用，可进入原答题入口及现有征稿说明。不会自动填入禹浩、1,280 电池、示例价格或支付成功。

| 范围 | 当前状态 |
| --- | --- |
| 页面、六处统一图标、窄窗口/长名字/大余额 | 完成，实际 Godot 渲染核对 |
| 余额、套餐、明细、订单及错误状态 | 客户端状态层和 provider/HTTP 接口完成，隔离环境可运行 |
| 重复下单、原请求恢复、订单快照、账号隔离 | 客户端专项及真实回环 HTTP 验证通过 |
| 事务、可信支付事实、奖励去重 | 真实 SQLite 隔离契约模型验证通过；不是正式后端或官方验签 |
| 现有答题入口和判题流程 | 已复用；可选可信 attempt 奖励桥已接到原答题结果区 |
| 投稿入口 | 现有征稿说明已关联；没有投稿/审核/发表后台可接，真实发奖未启用 |
| 正式接口与收款 | **尚未接通**：缺正式认证、钱包后端、价格、商户产品及规则 |

## 文件与主要改动

| 文件 | 用途 |
| --- | --- |
| `scenes/Recharge.tscn`、`scripts/recharge.gd` | 主页面、两列套餐/核对分区、状态联动和窄窗口堆叠 |
| `assets/recharge/battery-two.svg` | 唯一电池遮罩：透明内部、描边、右端子、偏左两条；组件着工大蓝，未选中导航着灰色，格数固定 |
| `scripts/battery_amount.gd` | 复用图标/数字/单位、千分位、整数分金额及数值检查 |
| `scripts/wallet_badge.gd` | 各页面右上角图标/数量，共用 WalletStore，兼容缓存、账号切换和未知状态 |
| `assets/recharge/reward-quiz.svg`、`reward-publication.svg` | 答题与投稿入口的线性图标 |
| `assets/recharge/selected-check.svg`、`wechat-pay.svg`、`alipay.svg` | 小勾及支付品牌位置素材，是否显示取决于服务渠道配置 |
| `scripts/minimal_page.gd`、`scripts/page_router.gd` | 原有新增充值导航及懒加载 WalletStore；本轮沿用 |
| `scripts/recharge_dialog.gd` | 原生独占窗口：明细筛选/分页、记录、订单、规则、帮助及焦点恢复 |
| `scripts/wallet_store.gd` | 会话隔离、订单核对快照、幂等请求持久化、支付状态归并、有限退避查询 |
| `scripts/wallet_http_transport.gd` | HTTPS、超时、响应上限、拒绝跳转、取消请求及失效凭据处理 |
| `scripts/quiz_wallet_bridge.gd`、`scripts/quiz.gd` | 最小奖励接入；发送用户答案到服务端 attempt，到账反馈保持并随切换账号清除 |
| `config/wallet.example.json`、`WALLET_SERVICE_CONTRACT.md` | 空配置模板和请求/响应、商户、奖励、数据库边界 |
| `tools/check_recharge.gd`、`check_wallet_recovery.gd` | 页面、风险与恢复专项 |
| `tools/run_wallet_http_checks.py`、`check_wallet_http.gd` | 实际 HTTPRequest 到回环服务及 SQLite 的验证 |
| `tools/check_wallet_service.py`、`tools/fixtures/wallet_service.py` | 隔离持久化、并发、回滚及支付/奖励契约验证 |

这次续做修复了以下边界：恢复未完成请求后保持原选择及核对快照；套餐调价不会把进行中的确认区改成新价格或空白；错误金额响应不会直接打开支付；重新认证自动恢复本人未完成订单；历史详情跟踪该订单，原生弹窗聚焦时继续查询；从渠道返回后即使订单曾显示已关闭也再次核实；账号切换取消旧请求并拒绝旧响应；答题结果重绘后保留一次到账反馈。首次进入答题页时，用户提前提交的答案会等待奖励规则与服务端 attempt 就绪，再按同一作答验证，避免异步初始化漏掉首题。大套餐数量自动转单列，超范围预计余额禁止提交。HTTP 测试不再依赖前端服务替身。

## 本地验证

以下命令全部使用隔离存档/测试库，不修改真实余额、真实学习记录或发送消息，也没有部署和实际付款。`tools/.gdignore` 将测试工具排除在 Godot 正常资源扫描之外，生产脚本不引用 fixtures。

```powershell
Set-Location 'E:\zhengzhi'
$godot = 'C:\Users\Legion\Desktop\工具\游戏创作\Godot_v4.6.2-stable_win64_console.exe'
$python = 'C:\Users\Legion\AppData\Local\Python\bin\python.exe'
& $python tools/run_workbench_checks.py --godot $godot --script check_recharge.gd --visual
& $python tools/run_workbench_checks.py --godot $godot --script check_wallet_recovery.gd
& $python tools/run_wallet_http_checks.py --godot $godot
& $python tools/check_wallet_service.py
```

本机 `python` 命令有 WindowsApps 别名，不可用时使用上面的真实 Python 路径。检查会将 APPDATA/LOCALAPPDATA 指向 `.godot_appdata/workbench-check-*`，截图在 `outputs/recharge-validation/`。SQLite 和 HTTP 服务测试结束后关闭连接并清理临时数据库；Godot 检查日志留在隔离目录供追踪。

实际通过：充值页面及共享余额 **62 项**（Windows OpenGL 实际渲染）；订单恢复 **20 项**；真实回环 HTTP **18 项**；SQLite **8 组**。本次界面调整另通过页面缓存、F6 专注模式和返回导航回归；服务端逻辑未改变，服务验证沿用前轮结果。专项包括：

- 六处相同两格电池、0 与大余额、正常/未登录/无渠道状态、档位与预计余额一致；长名字、窄窗及极大套餐。
- 重复点击、同键不同载荷、响应丢失后重试、持久化恢复、调价快照、非本人订单和旧账号响应隔离。
- 原窗口关闭不取消订单、已付款待到账、晚到已付款覆盖关闭提示、已到账不回退、详情目标切换、失焦/离页停止及 12 次轮询上限。
- SQLite 并发创建唯一订单、重复付款事实与查单共用入账、交易号唯一、错签名/商户/应用/订单/金额/币种/状态不入账、付款人优惠不误作订单总额。
- 已支付事实持久化、事务中断完整回滚、重启恢复与再次恢复不重复入账；充值、奖励和消费并发后余额等于账本合计。
- 客户端伪造正确不发奖；同 attempt 重试不重复；每次策略允许后续作答、每日策略允许下一有效日；投稿需审核通过且发表，重复通知和后续编辑不重复奖励。
- HTTP 401、拒绝、非法 JSON、重定向、断连与取消请求不会制造成功。

同时通过：返回导航 **31 项**、个人中心 **69 项**、社交 **101 项**，以及收藏、答题重试布局和动效回归。收藏检查在退出时仍报告一个 ObjectDB 实例泄漏警告，断言为 0 失败；该警告不属于本轮充值专项，未借此修改收藏模块。系统减少动态效果在 headless 返回 `-1`（未知），应用内减少动画接口已验证，不宣称实体系统偏好已验证。

## 实际运行截图

截图来自此次运行的 Godot，测试账号/示例套餐带隔离标识，不是设计稿，也不是正式支付证明。

- `outputs/recharge-validation/00-unconfigured.png`：当前正常启动的未接入状态。
- `01-main-preview.png`：两格图标、四档示例、余额条及右侧确认区。
- `02-order-pending-panel.png`：原订单查询；`03-paid-pending-panel.png`：已付款待到账；`04-credited-panel.png`：隔离测试到账结果。
- `05-ledger-panel.png`、`06-orders-panel.png`：账本与订单关联。
- `07-large-balance-name.png`、`08-narrow.png`、`08b-narrow-confirmation.png`、`09-dark.png`、`10-large-package.png`：长名字、大数字、窄窗口滚动、既有深色主题和大套餐。
- `11-header-Workbench.png`、`11-header-PersonalCenter.png`、`11-header-MyFriends.png`、`11-header-Quiz.png`：各页右上角共用余额及未选中充值导航的灰色图标。

## 未验证与必要依赖

正式价格、可收款渠道、答题奖励规则和投稿奖励规则四项均**尚未具备**。普通答题和现有页面可正常使用；正式奖励和支付不自动切到模拟成功。真实登录、官方支付验签/解密与主动查单、正式数据库事务/权限、渠道允许的支付测试、实体高 DPI/触屏及真实投稿发布链均未联调。

当前仅实现可信 HTTPS 跳转支付适配，没有编造扫码二维码；若所选商户产品要求原生扫码，需在产品确定后补相应适配。无正式后端数据库，因此没有执行或伪造生产迁移。服务端接入需要提供商户类型/产品、正式套餐、现有认证及钱包环境、可信题库和奖励策略、稿件发布事件、支持入口和已确认条款；完整字段与接入步骤见 `WALLET_SERVICE_CONTRACT.md`。
