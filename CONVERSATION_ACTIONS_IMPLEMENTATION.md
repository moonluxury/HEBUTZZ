# 会话操作（P3 布局，2026-11-01 更新）

入口：运行 `project.godot`，进入「我的好友」，选择普通联系人，点击会话顶栏 `⋯`。已运行的客户端需要重新运行以加载新脚本。

按用户最新圈图要求，第三项“标记卡牌”改为“赠送”，第四项“与此好友的记录”改为“换卡”，同时移除这两个旧入口的专用子页面。当前顺序为：查看资料、修改备注、赠送、换卡、屏蔽此好友、删除好友。最新要求覆盖原资料包对第三、四项文案的限制；其余菜单尺寸、颜色、圆角、间距、键盘和动效保持 P3。

赠送、换卡已从会话顶栏移入菜单，顶栏保留想要清单和 `⋯`，联系人名称可使用释放出的宽度。原有交易数据、聊天中的赠送/换卡卡片及其详情继续保留。

## 功能映射

| 入口 | 实际实现 |
| --- | --- |
| 查看资料 | 复用 `find_user(public_id)`，核对稳定联系人 ID，展示公开昵称、头像、公开 ID、自己的备注，以及学校、学院、专业、年级和个人简介。学校等四项两列排列，简介全宽；长内容可滚动，返回按钮固定。已返回但为空的字段显示“未填写”，旧服务未返回字段时显示“暂未提供”，不把缺少接口数据误当作未填写。 |
| 修改备注 | 复用 `preferences(peer_id, remark, operation_id)`；服务成功后同步名称，失败保留输入，重复提交锁定，不改对方昵称。 |
| 赠送 | 打开既有 `CollectionGiftDialog`，提供实际卡牌选择，预选当前好友；保留库存、至少保留一张、数量、确认提交和幂等规则。打开或取消不转移卡牌。辅助文案为“向该好友赠送卡牌”。 |
| 换卡 | 打开既有 `TradeDialog` 的 exchange 模式，关联当前好友；保留选择卡牌和数量、核对条款、发送邀请与对方确认流程。辅助文案为“与该好友交换卡牌”。 |
| 屏蔽此好友 / 解除屏蔽 | 复用 `relationship(operation=block/unblock)`。确认框继续说明原服务规则：阻止消息、申请及转卡，同时解除好友关系，待确认交换失效；解除不会恢复好友关系。 |
| 删除好友 | 确认后调用 `relationship(operation=remove)`，服务成功后同步好友列表，保留聊天、卡牌与已完成交易。 |

正式权限、库存和业务操作继续由现有服务校验。资料补充仅修改本地后端的 `find_user` 成功响应，明确允许返回 `school / college / major / grade / bio` 五个字段；好友列表、同步、交易对象仍使用简要身份，不传播整份资料。继续要求登录，双向屏蔽或账号停用时不返回对方资料，不返回邮箱、电话、口令或其他未声明的内部字段。无需数据库迁移。

本次提交包含菜单调整和资料字段的客户端、后端代码；正式服务部署是独立步骤。本轮未部署服务器，正式服务尚未更新时，这五项会显示“暂未提供”；同步后端后才能读取正式账号已经保存的对应内容。官方系统会话没有普通好友操作，非好友不能从新入口进入赠送或换卡。

## 弹窗衔接与文件

会话菜单仍使用页面内 `CanvasLayer + ColorRect + Panel`。赠送、换卡沿用项目已有的嵌入式窗口；先完成菜单的 120 ms 退出，再释放旧遮罩、延迟打开目标窗口，不叠加两个活动蒙层。打开目标窗口前再次核对账号 epoch、选中的会话及联系人 ID、好友关系和页面生存期。切换账号或联系人、离页、退出过程中取消，均不能打开旧对象的赠送窗口。关闭目标窗口后焦点回到 `⋯`。

- `scripts/conversation_actions_dialog.gd`：六行配置、原有资料/备注/关系操作、转卡窗口衔接；移除卡牌标记说明页和汇总记录视图。
- `backend/domain.py`、`backend/tests/test_backend.py`：为明确的资料查询补充五项已保存字段，并验证白名单、空值、更新、登录、屏蔽和停用限制。
- `scripts/conversation_action_row.gd`：第三、四项改为礼物与交换箭头图标，沿用局部线性图标和反馈。
- `scripts/my_friends.gd`：移除顶栏赠送/换卡控件并收起空位；增加带身份和联系人校验的入口；退出页面后不再启动滚动恢复协程。
- `tools/check_conversation_actions.gd`：更新菜单、赠送/换卡衔接、权限、取消、焦点和竞态检查。
- `tools/check_social.gd`、`tools/check_transfer_dialogs.gd`：将原顶栏入口检查改为菜单入口。
- `outputs/conversation-transfer-validation/`：本轮实际运行截图，全部使用隔离测试账号。
- `outputs/friend-profile-validation/`：资料完整、未填写、旧服务及长简介/小窗口的实际运行截图，使用隔离测试账号。

菜单基准 455×532，正常桌面尺寸完整显示六行。打开 180 ms、关闭 120 ms、悬停 140 ms、按下 80 ms，减少动态效果时立即完成。Tab / Shift+Tab 限定在菜单内，Enter / Space 激活，X / Esc / 外部遮罩关闭。保留项目现有字体和主题，未宣称与原生成图逐像素一致。

## 验证

2026-11-01，Windows Godot 4.6.2：

- `check_conversation_actions.gd --visual`：105 项通过，0 失败。包括五项资料和空值/旧服务、长内容换行与滚动，以及六行顺序、旧入口移除、整行点击、Space 打开换卡、当前好友预选、单层遮罩、四角合成、关闭焦点、取消不转卡、非好友限制、切换联系人时取消待打开窗口、账号隔离、缩放和动效。
- `backend/tests/test_backend.py`：完整本地工作区 27 项通过，包含新增的资料字段白名单、已保存内容与空值、更新和清空、登录/双向屏蔽/停用账号测试。使用新建的本机 PostgreSQL 隔离库，测试结束后已关闭该实例；未连接正式数据库。测试依赖有一条现有 TestClient 弃用提示，不影响测试结果。
- `check_social.gd`：104 项通过，0 失败。
- `check_transfer_dialogs.gd --visual`：68 项通过，0 失败；赠送与换卡的浅色、深色、缩放合成检查均为 0 个边缘异常。

```powershell
py -3 tools/run_workbench_checks.py --godot <Godot控制台程序路径> --script check_conversation_actions.gd --visual --timeout 180
py -3 tools/run_workbench_checks.py --godot <Godot控制台程序路径> --script check_social.gd --timeout 180
py -3 tools/run_workbench_checks.py --godot <Godot控制台程序路径> --script check_transfer_dialogs.gd --visual --timeout 240
```

运行器关闭正式后端，使用独立 `workbench-check-*` 存档和服务契约替身。上述结果不表示对正式账号执行过赠送或换卡。转卡窗口专项包含渲染纹理检查，需要 `--visual`。

上传前从暂存内容导出独立副本，实际渲染检查再次通过 105 项，真实本机 PostgreSQL 后端测试通过 26 项。该提交不包含工作区另一项好友申请附言改动及其测试，因此比完整本地工作区少 1 项后端测试；本次资料字段的 3 项新增后端测试全部包含并通过。

资料后端检查在 `backend` 目录使用 `python -m pytest tests/test_backend.py -q`；必须配置指向专用本地 `_test` 数据库的 `DATABASE_URL`，该测试文件会清空测试库中的用户数据。此轮独立数据库日志保留在 `.godot_appdata/public-profile-db-d4fb526c00e4/pytest.log`。资料页面预览位于 `outputs/friend-profile-validation/01-profile-details.png` 及对应 `-dialog.png`，另有空资料、旧服务、长简介的小窗口截图。

主要截图：`01-current-menu.png` / `01-current-menu-dialog.png`、`02-current-hover.png`、`03-gift-from-menu.png`、`04-exchange-from-menu.png`、`06-closed-chat.png`，另含小窗口、大字号与深色背景。原始 P3 资料及旧验证截图作为历史参考保留，最新实现以本记录和本轮截图为准。
