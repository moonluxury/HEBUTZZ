# 电池与充值服务接入契约 v1

2026-10-31：答题批量奖励、50 电池上架奖励、稿件购买和 20% 三天提成已接入现有 PostgreSQL/HTTPS 服务，当前接口和规则见 [电池奖励实现](BATTERY_REWARDS_IMPLEMENTATION.md)。下文逐题 attempt 契约保留供旧测试兼容，新客户端使用 `practice_begin` / `practice_finish`；商户充值部分仍未开放。`tools/fixtures/wallet_service.py` 只允许创建在 `workbench-check-*` 目录中的隔离 SQLite 库，其 HMAC 仅用于虚构测试渠道。

## 接入现有认证

继续使用 `ProfileStore.use_provider(adapter, session, collection_adapter)`。认证宿主提供已验证会话；不从充值页构造身份。该 adapter 保留原有资料、收藏及社交方法，另外实现：

```gdscript
# 在已有认证 adapter 内组合一个 WalletHttpTransport 节点。
func wallet_request(action: String, payload: Dictionary) -> Dictionary:
    return await wallet_transport.wallet_request(action, payload)

func wallet_cancel_requests() -> void:
    wallet_transport.wallet_cancel_requests()

func wallet_payment_hosts() -> Array:
    return configured_payment_hosts # 可信部署配置，不从订单响应扩展白名单
```

宿主初始化 transport 的 `endpoint`、`authorization`、`response_account`。`authorization` 是返回当前会话请求头的 Callable；`response_account` 返回当前已认证账号，用于本地传输错误的归属。服务端必须从凭据独立取得身份，不能相信这个客户端字段。HTTP 请求是 HTTPS POST，不跟随重定向，12 秒超时，响应上限 1 MiB。`allow_loopback_test` 只有编辑器构建且存档路径为隔离检查目录时才能使用 HTTP 回环。

`config/wallet.example.json` 是接入方的空配置模板，不会由客户端自动加载或开放收款。其中 `endpoint` / `payment_hosts` 属于宿主可信配置，其余是服务端 catalog 的配置来源。令牌从既有认证系统获取；商户私钥、平台证书解密密钥、数据库凭据仅放服务端密钥管理中。模板不包含示例价格、密钥或账号。

## 请求与响应

统一请求为 `{version: 1, action: String, payload: Dictionary}`。金额使用整数分，电池使用整数；范围为 0～9,007,199,254,740,991，价格和到账数量必须大于零。余额可以为零。拒绝小数、字符串数值、布尔数值、溢出及超出余额的消费。服务端应另外施加正式业务上限。

成功响应包含 `{ok: true, account_id: authenticated_account, ...}`。失败包含 `{ok: false, account_id, code, definitive?: bool}`。`ok` 必须是布尔值。401 使客户端退出失效会话，并通过原个人中心重新认证。客户端不展示原始错误体。

| action | payload | 成功响应附加字段 |
| --- | --- | --- |
| `balance` | `{}` | `balance`, 单调递增 `revision` |
| `catalog` | `{}` | `packages`, `channels`, `rules`, `recharge_enabled`, 可选 `default_package_id`, `preview: false` |
| `create_order` | `request_id`, `package_id`, `package_version`, `channel` | `order` |
| `order` | `order_id` | `order`；必要时服务端查支付渠道并处理可信结果 |
| `orders` | `cursor`, `limit: 20`, 可选 `scope: "unfinished"` | `items: Order[]`, `next_cursor: String` |
| `ledger` | `cursor`, `limit: 20`, `filter: "all"/"income"/"expense"` | `items: Ledger[]`, `next_cursor: String` |
| `quiz_attempt` | `request_id`, `subject_id`, `question_id`, `bank_version` | `attempt_id`；服务端核对题库版本、题型和资格 |
| `quiz_submit` | `attempt_id`, `answer: {selected_keys, entered_answers}` | `reward: {status: "credited"/"pending"/"ineligible", amount?, ledger_id?}` |

`orders` / `ledger` 必须服务端分页，cursor 必须绑定身份与筛选条件；客户端不把当前页当总计。`unfinished` 至少覆盖所有仍可能需恢复的待支付、未知、处理中、已付待入账及入账异常订单。主页面自动恢复第一页，全部订单可在充值记录分页访问；本机最后订单号也独立查单，因此已到账后退出重启仍能找回。

支持的错误码：`unavailable`、`unauthenticated`、`forbidden`、`not_found`、`price_changed`、`conflict`、`disabled`、`unknown`。仅当 `price_changed` 或 `disabled` 且服务端确认**没有创建订单**时返回 `definitive: true`，客户端才解除原请求并要求重新核对。超时、断连、响应不完整一律保留原请求，绝不能返回可重新下单的确定失败。

## 套餐与订单快照

Package：`{id: String, version: String, price_cents: int, batteries: int, currency: "CNY", enabled: bool}`。版本绑定金额和数量；修改内容必须换版本。正式 catalog 没有默认规则时省略 `default_package_id`，由用户明确选择。不能将测试的 3/6/12/30 元或 1:100 比例作为正式默认配置。

Channel：`{id: String, label: String, enabled: bool, brand?: "wechat-pay"/"alipay"}`。只返回真实已开通可用渠道；`brand` 仅影响图标。测试的品牌位置明确带“测试”，不代表真实商户已开通。

Order 必填字段：

```text
id, account_id, request_id, package_id, package_version,
price_cents, batteries, currency="CNY", channel,
payment_status, credit_status, revision, created_at
```

可选 `account_label`（昵称及公开 ID 的快照）、`channel_label`。`credited` 必须具有 `ledger_id` 且 `payment_status=paid`。`revision` 单调递增；身份、套餐、金额、币种、数量和渠道不可变。客户端丢弃旧 revision 及将已支付/已到账降级的结果。

创建请求的唯一键为 `(authenticated_user, request_id)`，并持久化请求内容指纹。先查询原请求，再检查新套餐是否下架；原请求重试必须返回原订单，即使当前价格、渠道或套餐已变化。同键不同载荷报 conflict。服务端从套餐取实际金额和数量，不接受客户端指定账户、价格、数量。下单保存完整快照，支付调用同样使用稳定业务幂等键。

客户端首次提交前以临时文件与重命名保存请求 ID 和核对快照；成功后保存原订单号。文件位于 `user://wallet_requests_v1/<account SHA-256>.json`，不含会话令牌和支付 URL。退出清除内存中的个人状态；保留账号分区内的恢复标识以便本人再次登录。付款永远入创建订单时的原账户。

## 支付步骤与归并

支付状态：`pending`（待支付）、`processing`、`unknown`、`paid`、`closed`、`failed`。入账状态：`none`、`pending`、`credited`、`failed`。已支付且入账失败仍保留“已支付，到账异常”及查询入口。

当前客户端支持可信服务返回的 HTTPS 跳转支付：

```text
payment: {
  kind: "redirect",
  verified: true,
  url: <该订单的 HTTPS 支付链接>,
  expires_at: <UTC Unix 秒>
}
```

必须来自真实订单；host 必须在宿主白名单内。`verified` 是服务端声明且不能代替后端验签。支付过期只禁止再次打开旧链接，仍可查询原订单。若最终商户产品仅提供原生扫码，需在选定产品后补受验证二维码交付，当前没有假二维码或个人收款码兜底。没有正式渠道，跳转和扫码都没有真实联调结果。

主页面没有提前二维码；创建订单后展示账户、数量、金额和订单号。“我已支付”只查询。关闭弹窗不取消订单；仓库没有既有远程关单接口，当前不擅自实现关单，未完成订单期间锁定本次操作。可查看其他记录，不修改支付目标。

页面激活、重新认证、支付返回时查询原订单；详情跟踪正在查看的订单。等待约 3 秒开始，之后退避至最多 60 秒，单次可见周期最多 12 次自动查询；手动查询仍可用。窗口失焦和离页停止自动查询，原生支付弹窗聚焦不被当成离开应用。晚到付款可以覆盖服务端已关闭提示，已到账不能被旧待支付覆盖。

真实渠道接入前，必须根据已选择的商户类型和支付产品核对对应的最新官方文档。当前没有选定产品，因此没有照搬合作伙伴模式代码、验证真实微信/支付宝回调或宣称通过官方验签。接入后需要验证签名、必要解密、商户/应用、订单号、交易号、币种、渠道定义的订单总额及成功状态，正确区分订单总额与优惠后的付款人实付额。回调和主动查单必须进入同一个履约函数。

服务端持久化支付事实后再应答；如异步入账，应可重启恢复。采用 `(channel, provider_transaction_id)`、订单支付关联、账本业务事件的唯一约束。在同一事务/锁边界内核对余额范围、写账本、更新余额及 revision、标记订单到账，奖励与消费复用同一边界。重复回调和查单并发只入账一次；回滚不留下半份余额。退款、冲正、撤稿追扣等沿用已批准规则，当前没有这些规则，不作自动处理或业务承诺。

## 奖励与账本

`rules.quiz` 包含 `enabled`、`trusted_attempts`、`types`、`bank_versions`。缺规则或可信题库验证时，答题照常，客户端不发奖励请求。服务器持有权威题目答案；attempt 绑定用户、题目版本、资格、规则快照。`correct=true`、本地成绩及要求“增加 N 电池”的参数不是奖励凭据。attempt 创建与提交需幂等，重复提交改变答案报冲突。

每题数量、每日上限、重复答题资格、适用题型、规则时区及策略版本必须由正式配置确定。首次/每次/每日策略分别确定稳定业务事件，不能用随机请求 ID 绕过限制，也不能误伤允许的后续奖励。客户端只发送用户选择/输入；确认为已到账且含有效流水 ID 后才显示“获得 N 电池”并重新读余额。临时网络失败最多重试同一个 attempt；无法核实则显示待核实，可查看账本，不能按本地正确结果补发。

`rules.publication.entry_enabled=true` 且 adapter 提供 `open_publication()` 才进入既有投稿入口。当前仓库只有征稿公告，没有投稿/审核/发表后台，入口回到已有征稿说明，并说明尚未开放。奖励服务必须从可信稿件状态同时验证**审核通过且已发表**、作者、奖励策略和稳定发表事件，重复发表通知和普通编辑不能重复奖励。应由该后台展示审核中、待发表、待发放、已发放或失败；当前没有编造投稿后台。

Ledger：`{id, account_id, source, delta, created_at, reference, order_id?}`。`delta` 是非零有符号整数。source 为 `recharge`、`quiz`、`publication`、`spend`、`opening`、`adjustment` 等真实来源。只有真正入账事件进入账本，未付订单不能成为收入。期初/迁移必须来自真实存量余额，纠正沿用关联调整记录，不删除原流水。

## 接入尚需提供

1. 现有正式认证 provider、钱包服务地址与服务端代码/数据库环境；当前适配器已可调用，尚无真实服务可连接。
2. 正式套餐 ID、版本、人民币分值、电池数和默认选择规则；空配置保持禁用。
3. 已签约商户类型、支付产品、可用渠道、可信支付 host、服务端凭据及回调地址。先在渠道允许的测试环境验证，不直接收真实款。
4. 答题权威题库映射、奖励数量、上限、重复资格、题型、策略时区及去重规则。
5. 现有投稿路由、审核/发表可信事件、奖励数量和业务去重规则；撤稿/冲正处理需使用已确定业务规则。
6. 支持入口及充值用途、兑换说明、退款等已确认条款。缺失时页面不制造客服或承诺。

当前没有可迁移的正式数据库，因此没有执行生产迁移。SQLite 建表、唯一约束和事务仅用于隔离契约验证；部署前需结合现有数据库生成并审查真实迁移、余额期初迁移与索引，不能把测试库当成生产后端。
