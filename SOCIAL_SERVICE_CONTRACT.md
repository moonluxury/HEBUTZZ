# 社交服务适配契约 v1

本文件定义当前客户端已经调用的接口；不是已经部署的服务。沿用既有 ProfileStore/CollectionStore 账户与卡牌 ID。服务可映射到已有路由，不强制采用本文件命名的数据库表或新技术栈。

## 身份、封装和错误

资料宿主适配器实现 `social_request(action: String, payload: Dictionary) -> Dictionary`。服务端操作者取自可信会话；JSON 中不得接受 `account_id/sender_id/actor_id/type/status` 等伪造身份或业务类型字段。响应包含 `{ok: bool, account_id: string, code?: string, message?: string, definitive?: bool, ...}`，其中 account_id 为服务验证的当前主体关联键，仅用于客户端防串号，不是向他人公开的 ID。

成功必须来自真实持久化；操作超时/断线/5xx/格式异常使用 `unknown` 或 `network`，不标记已拒绝/已取消；只有确定未执行且无需原键核实时可返回 `definitive:true`。`unauthenticated` 触发原 ProfileStore 登录恢复并清空敏感视图。`forbidden/private/not_found/inaccessible/insufficient_stock/terms_changed/idempotency_conflict/rate_limited/unavailable` 保持可区分的具体 `message`。禁止将网络错误映射成“用户不存在”。

可选 HTTP 形式：POST 宿主指定的既有 HTTPS 端点，`{version:1, action, payload}`；会话通过宿主提供的请求头，12 秒超时。无 CORS/网页假设，无新登录系统。HTTP 401 为登录失效；其他非 2xx 即使正文写 ok:true 也不按成功处理。禁止跟随重定向转发凭据。每个真实适配器均须具有有界超时。

## 读取结构

```text
PublicUser = {id, public_id, name, avatar?, remark?}
Friend = PublicUser + {conversation_id?, eligible?}
Conversation = {
  id, kind: direct|system, peer?: PublicUser, name?, is_friend?,
  blocked_by_me?, can_send, send_reason?, muted?, pinned?,
  read_seq, unread, activity_seq, summary?, time_label?
}
Message = {
  id, conversation_id, sender_id, seq, client_id?,
  type: text|trade|gift|notification, time_label?, date_label?,
  text?, record_id?, title?, body?, summary?, event?
}
Request = {id, seq, direction: received|sent, peer:PublicUser, note, time_label,
           status:pending|accepted|ignored|invalidated}
Line = {card_id, season_id, quantity}
Trade = {
  id, initiator_id, recipient_id, initiator:PublicUser, recipient:PublicUser,
  give:[Line], receive:[Line], terms_version, revision, conversation_id,
  status:pending|completed|rejected|cancelled|invalidated|expired,
  time_label?, result_label?, expiresAt?
}
```

`id` 是稳定业务标识，`public_id` 是对外展示/核对标识，不能拿昵称作提交身份。sender_id/initiator_id/recipient_id 必须与当前账号身份键采用同一命名空间，才能正确显示自己的气泡与条款视角。不下发邮箱、手机、口令、后台角色或库存明细。avatar 由已有资源适配层下载缓存为本地可访问图片；卡图、季和卡名由同一 `collection_catalog.json` 的稳定 card_id 解析。

`kind=system` 必须服务端可信投影，只给本人访问且唯一；不能由昵称/头像/客户端字段推导。没有管理员登录账号。text 接口只产生 text 消息；其余三种由服务事件产生，必须验证业务记录双方与会话成员相同。notification 的可导航 event 白名单为 `friend_request/trade/gift`，其他公告显示正文且不执行动作。

## 接口表

以下均附带上文响应封装。所有列表、游标、详情与关联 ID 都要重新验证当前主体访问权，游标须绑定主体及查询条件。

| action | payload | 成功额外响应 / 语义 |
| --- | --- | --- |
| sync | `{cursor}` | `{revision,cursor,friends:[Friend],conversations:[Conversation],requests:[Request],pending_requests,request_unread,capabilities,messages:[Message],trades:[Trade]}`。summary/关系/未读为当前权威快照，messages/trades 可为增量；revision 对主体单调递增。初次只返回必要的最新消息，旧消息走 history。增量游标须覆盖断线期间的持久事件，过期返回 cursor_expired；空游标重建快照时不可再次返回 cursor_expired。响应不能跨多次未完成读取跳过事件。 |
| friends | `{query,eligible_for_gift?}` | `{friends:[Friend]}`。供收藏和社交共用；资格变化立即反映，不因无最后消息漏人。 |
| find_user | `{public_id}` | `{state:available|not_found|self|inaccessible|friend|outgoing|incoming,user?:PublicUser}`；支持现有公开 ID，不暴露私密字段。 |
| open_conversation | `{peer_id}` | `{conversation:Conversation,sync?}`；按双方唯一建会话，不发送招呼，不创建关系。 |
| history | `{conversation_id,before,limit:40}` | `{messages:[Message],next_before}`；按权威 seq 排序，空游标取最新页，空 next_before 表示结束。 |
| send_text | `{conversation_id,client_id,text}` | `{message_record:Message}`；唯一键 `(actor,client_id)` 永久绑定原会话及原文。重放原请求返回同一消息；更改文本/会话拒绝。 |
| request_friend | `{peer_id,note,operation_id}` | `{request?,sync?,message?}`；同对用户一个有效 pending，交叉返回原申请，禁止静默互加。 |
| respond_request | `{request_id,decision:accept|ignore,operation_id}` | `{sync,message?}`；仅接收者，接受时一次建立双向关系，对已处理请求重复调用返回一致结果。 |
| preferences | `{peer_id,remark? ,muted?,operation_id}` | `{sync,message?}`；备注与免打扰为当前主体私有设置，不改变对方昵称/阅读状态。 |
| relationship | `{peer_id,operation:remove|block|unblock,operation_id}` | `{sync,message?}`；关系/拉黑与待处理交换失效必须和交割采用同一并发边界；解除不恢复好友。 |
| blacklist | `{}` | `{users:[PublicUser]}`；仅自己的屏蔽列表。 |
| mark_read | `{conversation_id,through_seq}` | `{sync}`；水位单调推进，不能超过该主体可访问的真实会话消息序列。 |
| mark_all_read | `{operation_id}` | `{sync,message?}`；服务捕获此次操作水位，推进本人所有会话/通知及申请提醒的已见状态，水位之后的内容仍未读；不接受申请、不确认交易。原键重试沿用原水位。 |
| mark_requests_read | `{through_seq}` | `{sync}`；前台申请窗口实际到达的服务端申请序列，服务限制在本人可访问范围内单调推进，pending 业务计数不变。 |
| wishlist | `{peer_id}` | `{visibility:accessible|private|inaccessible,card_ids:[string]}`。接入收藏原想要数据；不包含持有数。获卡不能删除想要。默认好友可见。 |
| create_trade | `{peer_id,give:[Line],receive:[Line],terms_version:1,operation_id}` | `{trade,sync?}`；校验双方关系、自己真实可转出总量、目录/季/正整数；条款固定，无默认冻结；幂等键绑定双方和全部原条款。 |
| trade_action | `{trade_id,terms_version,decision:confirm|cancel|reject,operation_id}` | `{trade,sync?,message?}`；confirm/reject 仅接收者，cancel 仅发起者；终态返回权威原结果，无第二次转移。 |
| trade_detail | `{record_id}` | `{trade}`；本人是交易一方才可读。 |
| trade_records | `{peer_id?,before,limit:40}` | `{trades:[Trade],next_before}`；最新在前，可按对方筛选，双方/卡/季/数量/时间/状态使用同一流水。 |
| gift_detail | `{record_id}` | `{gift:{summary,time_label,...}}`；仅双方，源为既有赠送记录。 |
| report | `{peer_id,reason:harassment|fraud|content|other,note,message_ids,operation_id}` | `{message,report_id?}`；真实接收持久化才成功；逐条核验所选消息确属双方可访问的会话，绝不自动附加全聊天。 |

`capabilities` 至少提供 `{exchange:bool,exchange_reason?:string,reports:bool}`。服务可返回更严格的业务限制及失败说明；没有 exchange 能力不开放提交，没有 reports 不显示伪提交。统一的 transfer 限制在服务执行；赠送独有额度不能冒充交换额度。

## 收藏、赠送和想要接入

保留既有 `request_snapshot(account_id)`、`request_friends(account_id,query)`、`send_gift(operation)`、`gift_status(account_id,operation_id)`。服务仍从会话确认 actor，不能相信函数参数自报身份。完整快照需要 `inventory_complete:true,revision,inventory:{card_id:{count,giftable_count?,exchangeable_count?,gift_reason?,gift_consequence?}}`。缺 `exchangeable_count` 时客户端不猜可转出数量。

赠送参数沿用 `id/account_id/card_id/friend_id/quantity/state`；业务幂等绑定 actor/card/recipient/quantity，不把客户端可变查询状态 state 作为条款。成功含匹配的 operation_id、account_id、state=succeeded 及完整新库存，失败含真实原因，响应丢失后 gift_status 查询原记录。必须在赠送的同一事务内产生唯一业务事件投影到双方会话，不能在聊天端再调用一次赠送；通知失败不得回滚已经完成的库存转移。

自己的想要当前在 `CollectionStore` 的账号分区本机存档。若真实服务尚未接通收藏想要同步，wishlist 返回明确 unavailable，不能另建一份社交愿望清单或把测试 wanted 当成正式数据。后端需沿用收藏未来同步接口完成同一源的公开投影及隐私权限。

## 后端必须补充和验证的持久化约束

在实际数据库选型已知后提供可审查迁移；本仓库没有该数据库，下面不冒充已执行的 DDL。

1. 规范化的用户对唯一好友关系、有效 pending 申请唯一约束；双向读取来自同一关系。删除/拉黑记录与永久会话/问候历史分别存储，删除本地会话不能重置招呼额度。
2. direct 会话用户对唯一；system 官方投影与用户唯一；成员表具有 actor、remark、muted、read_seq。所有 history/search/details/unread 通过成员授权，公开通知正文可共享，个人通知与阅读水位独立。
3. message 的 `(actor,client_id)` 唯一，存请求原文/目标摘要用于冲突检测；服务器分配 id/seq/time。消息与业务事件分型，普通发送不能引用他人 record_id。服务应限流，记录日志不含私聊原文或凭据。
4. 交换邀请条款不可变；保存 parties、lines/card_id/season_id/quantity、terms_version、status、revision、创建幂等键及内容绑定。可选 expiresAt 只在已有过期策略启用，不造倒计时。
5. **确认交割必须是一个真实事务**：锁定邀请、关系/拉黑与双方相关库存/统一额度，按稳定顺序取锁；核验接收角色、pending、版本、到期、双方好友资格、目录/转出资格；重复 card 行先汇总，按双方各自实际送出总量检查（交换同卡不能仅看净额）。同一事务完成双方扣增、必要额度、库存流水、邀请终态、唯一业务事件 outbox。禁止两次赠送拼接。
6. 上述锁/版本必须与已有赠送、领取、消耗、关系删除和拉黑共用；仅给 exchange 一个独立进程锁不合格。完成与取消竞争只能有一个终态。库存不足可保持 pending 并返回明确错误，关系丧失将 pending 永久 invalidated，恢复关系不复活旧邀请。
7. 唯一操作键绑定 actor/action/完整参数；成功响应丢失后重试返回原结果。outbox 重投按 event/record 去重，读取通知/收到推送不能交割。消息里的交易卡与历史读同一条权威记录，库存绝不靠解析文字修正。
8. 举报必须接真实接收队列/表/既有渠道并逐条授权，不创建可登录的“管理员好友”接收私聊。

验收需要实际数据库上的隔离多账号/多连接测试：同时确认、确认与取消、相同卡、赠送与交换/消耗竞争、关系变更与交割竞争、事务提交后断响应、进程崩溃重试、outbox 重投和越权枚举。本次内存契约模型无法证明这些数据库性质，必须在真实后端完成后再验证并开放正式服务。
