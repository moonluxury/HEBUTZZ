# 会话操作 P3（2026-11-01）

入口：运行 `project.godot`，进入「我的好友」，选择普通联系人，点击会话顶栏 `⋯`。已运行的客户端需要重新运行以加载新脚本。

弹窗按用户资料包的 P3 制作，固定为查看资料、修改备注、标记卡牌、与此好友的记录、屏蔽此好友、删除好友六行。标题及六条辅助文案均来自资料包；姓名、公开 ID、备注和业务记录从当前账号的服务数据取得。聊天页、侧栏和顶栏的想要清单、赠送、换卡入口保持现有布局。

## 文件

| 文件 | 用途 |
| --- | --- |
| `scripts/conversation_actions_dialog.gd` | 页面内单层遮罩、P3 布局、二级内容、稳定联系人上下文、权限状态、服务请求和焦点管理 |
| `scripts/conversation_action_row.gd` | 六行共用样式、局部矢量线性图标及其缓存、悬停/按下反馈、键盘焦点环 |
| `scripts/time_display.gd` | 记录日期显示所需的共用北京时间格式器；此次一并提交依赖模块 |
| `scripts/my_friends.gd` | 将原 `⋯` 接到新弹窗，清理离页弹窗，关闭后恢复当前触发按钮的焦点 |
| `scripts/social_dialog.gd` | 移除已被替换的旧会话菜单生成函数，其他原有面板保留 |
| `tools/check_conversation_actions.gd` | 隔离账号下的运行、截图、交互、异常及资源清理检查 |
| `materials/conversation-actions-p3/` | 原始参考图与需求，`.gdignore` 避免导入游戏资源 |
| `outputs/conversation-actions-validation/` | 实际运行截图，全部使用隔离测试账号与交易 |

## 六项功能与接口

| 入口 | 实际实现 |
| --- | --- |
| 查看资料 | 使用 `find_user(public_id)`，再次核对返回的稳定联系人 ID，只显示公开昵称、头像、公开 ID 和自己的备注。当前公开用户接口没有学校、联系方式等字段，不推测或读取私密账号资料。 |
| 修改备注 | 使用 `preferences(peer_id, remark, operation_id)`；成功后由 SocialStore 同步列表和会话名称，不改对方昵称。失败保留输入，重复提交锁定，未知结果重试复用原操作标识。 |
| 标记卡牌 | 保留指定入口和独立说明界面。当前没有好友与卡牌标记的读写接口，保存按钮禁用；不将其替换为赠送或想要清单，不写本地假标记。后续需要返回此联系人的标记集合以及经过鉴权的保存接口。 |
| 与此好友的记录 | 二级内容分赠送、换卡。赠送通过当前会话的 `history` 分页读取服务生成的 gift 业务事件，按记录 ID 去重；换卡使用 `trade_records(peer_id)`。详情复用 `gift_detail` / `trade_detail`，仅展示真实状态和条款，不执行交易操作。赠送还有旧页时提示继续查找，不将未加载的数据宣称为空。 |
| 屏蔽此好友 / 解除屏蔽 | 映射既有 `relationship(operation=block/unblock)`，不是免打扰。确认框说明原服务的完整行为：屏蔽消息、申请及转卡，同时解除好友关系并使待确认交换失效；解除不会恢复好友关系。只有成功响应后才显示成功。 |
| 删除好友 | 昵称及公开 ID 确认后调用 `relationship(operation=remove)`；失败保留状态，成功由服务同步好友列表。保留聊天、卡牌及已完成交易；沿用原服务对待确认交换的失效处理。 |

所有读写经既有 SocialStore / BackendProvider，操作主体由服务端认证。界面绑定稳定的联系人和会话 ID，切换账号或会话立即清理旧弹窗，迟到响应不更新新对象。官方系统会话不能打开此菜单；非好友尝试备注、标记或删除会显示真实限制。此次未更改后端、数据库、部署环境或正式账号数据。

## 布局与动效

使用 `CanvasLayer + ColorRect + Panel`，不创建新的 Window。只有 ColorRect 绘制全局遮罩；白色圆角 StyleBox 之外直接露出真实背景，没有矩形窗口底板，也没有改主窗口透明设置。

基准面板为 455×532，左右留白 28，前五行 399×60、间隔 10，第六行位于分隔线下方；跟随现有页面缩放并限制在可见区域。正常尺寸六行均可见。面板遵循 P3 保持白色，深色主题仅影响原页面。

沿用 UiMotion：打开 180 ms 淡入，关闭 120 ms 淡出；行悬停 140 ms、按下 80 ms 改变颜色，不位移或缩放行。二级内容先淡出再替换，复用同一遮罩。减少动态效果时立即到达最终状态。Tab / Shift+Tab 在弹窗内循环，Enter / Space 使用原生 Button 行为，X、Esc 和外部遮罩均可关闭；关闭后恢复 `⋯` 焦点。离页直接清理，无退出动画访问已脱离场景树的控件。

## 验证

2026-11-01，Windows Godot 4.6.2 OpenGL：

- `check_conversation_actions.gd --visual`：84 项通过，0 失败。覆盖精确文案、真实整行点击、单层遮罩、合成后四角、无默认高亮、焦点循环、备注失败和重试、记录分页、只读详情、屏蔽/删除确认、库存不变、官方会话限制、账号切换、动画中间值、快速开关、减少动态效果、主题与缩放、切页清理。
- `check_social.gd`：104 项通过，0 失败。
- `check_back_navigation.gd`：31 项通过，0 失败。
- `git diff --check`：通过；仓库已有文件的换行转换提示不影响本次检查。

```powershell
py -3 tools/run_workbench_checks.py --godot 'C:\Users\Legion\Desktop\工具\游戏创作\Godot_v4.6.2-stable_win64_console.exe' --script check_conversation_actions.gd --visual --timeout 180
py -3 tools/run_workbench_checks.py --godot 'C:\Users\Legion\Desktop\工具\游戏创作\Godot_v4.6.2-stable_win64_console.exe' --script check_social.gd --timeout 180
py -3 tools/run_workbench_checks.py --godot 'C:\Users\Legion\Desktop\工具\游戏创作\Godot_v4.6.2-stable_win64_console.exe' --script check_back_navigation.gd --timeout 180
```

运行器关闭正式后端，并将用户存档隔离到 `.godot_appdata/workbench-check-*`。业务验证使用现有服务契约替身，不等于本轮对正式服务器进行了写入验收。离屏窗口可能有帧率限制，动画中间值通过实际 UiMotion Tween 的 `custom_step` 校验；常规截图由实际主视口渲染取得，没有合成假页面。

上传前另从暂存内容导出独立代码副本，再次运行 P3 实际渲染检查，84 项全部通过。该副本包含本次会话操作及时间格式器依赖，不依赖工作区其他尚未提交的好友表单、讨论、投稿或后端改动。上方 104 项好友回归和 31 项返回导航结果对应完整本地工作区。

截图包括 `01-p3-default.png`、`01-p3-default-dialog.png`、`02-p3-hover.png`、`03-card-mark-unavailable.png`、`04-gift-records.png`、`05-remove-confirmation.png`、`06-closed-chat.png`、`07-small-window.png`、`08-large-font.png`、`09-dark-background.png`。正常截图为 1624×946 客户区，对应参考图约 1624×969 减去原生标题栏；小窗口为 900×620。每个弹窗截图还提供原始分辨率局部裁切。

## 与参考图的差异

保留项目现有微软雅黑字体，字重与参考生成图并非逐像素一致；线性图标为本地矢量重绘。面板在真实客户区严格居中，参考图中的中心略有偏移。背景使用当前项目及隔离测试数据，不复制参考图中的姓名、头像、余额、聊天或导航顺序。采用纯淡入淡出，没有增加可选的 4 px 归位位移。好友卡牌标记仍需接口，未宣称可保存。
