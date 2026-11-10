# 添加好友弹窗交付记录 · 2026-10-30

已在原「我的好友」入口实现参考图中的单层圆角弹窗。标题固定为「添加好友」，顶部包含「添加好友 / 好友申请」，搜索、结果行、发送申请、100 字附言及提示语均在同一窗口完成。首次打开没有示例用户。

## 修改范围

| 文件 | 本次修改 |
| --- | --- |
| `scripts/friend_dialog.gd` | 新的局部弹窗、白色圆角表面、分段页签、真实查询/申请状态、附言计数、申请分组、焦点、动效、登录返回和缩放。 |
| `scripts/my_friends.gd` | 现有 add/requests 入口使用新窗口；关闭中重新打开复用同一实例；登录来源表单只恢复输入草稿。 |
| `scripts/social_policy.gd`、`scripts/social_dialog.gd` | 申请附言统一为 100 个可见字符；兼容原聊天区的申请入口。 |
| `backend/friend_note.py`、`backend/domain.py` | 服务端验证 Unicode 可见字符长度并原样保留附言；已有好友的竞争情况返回明确 `state:friend`。 |
| `backend/requirements.txt`、`backend/requirements.lock` | 增加 `regex`，锁定本轮已测试的 `2026.9.29`。 |
| `tools/check_friend_dialog.gd`、`tools/fixtures/social_provider.gd` | 隔离数据的界面、流程、动效、实际合成四角和登录返回检查。 |
| `backend/tests/test_friend_note.py`、`backend/tests/test_backend.py` | Unicode 长度、原样附言、关系状态、身份权限和并发重复申请测试。 |
| `SOCIAL_SERVICE_CONTRACT.md` | 更新附言限制及已有好友的返回约定。 |

工作区已有的投稿、评论和其他后端改动保留。本次没有修改侧栏、聊天区、通知、赠送或换卡的布局，也没有改变全局主题或应用主窗口透明设置。

## 接口与数据

继续使用已认证的 `BackendProvider → /v1/rpc → SocialStore`：`find_user`、`request_friend`、`respond_request`、`sync`、`mark_requests_read`，已有好友通过 `open_conversation` 打开原对话。没有新增 URL、数据库表或第二套好友关系。

查询按现有完整公开 ID 精确匹配，没有新增 HG 前缀规则。发送使用查询返回的稳定内部 ID，身份来自服务端会话。保留已有的用户锁、单对用户 pending 唯一索引、操作幂等标识、屏蔽规则、速率限制与接受好友事务。前端等待服务确认后再显示已发送；失败保留目标与附言。收到交叉申请时转到申请页签，不自动接受。

附言以原生 Label/TextEdit 展示，不解析富文本。客户端用 Godot 的 Unicode 组合字符边界，服务端用 `regex` 的 `\X`，避免将组合音标或家庭 Emoji 拆成多个字。参考：[Godot TextServer](https://docs.godotengine.org/en/4.6/classes/class_textserver.html#class-textserver-method-string-get-character-breaks)、[regex 文档](https://pypi.org/project/regex/)。

## 圆角、布局与动效

标准 1672×918 客户区（含系统标题栏约 1672×941）中，弹窗实际约 527×648 像素，居中。仅一个白色圆角 Panel 和一层遮罩，复用项目 `DialogSurface` 的透明合成。标题、页签、关闭按钮固定，内容可滚动；小窗口保留至少约 0.85 倍的可读字号，超出的表单内部滚动。

实际渲染发现：只验证弹窗纹理的 alpha 不足以排除黑角。Godot 的嵌入窗口在缩放后的纹理范围与窗口范围不一致时，会补画不透明矩形。局部修复让 Window 视口保持 1:1，只缩放内部 Control；没有用同色块遮角，也没有改动主窗口。[Godot 4.6 实现依据](https://github.com/godotengine/godot/blob/4.6/scene/main/viewport.cpp#L364-L370)。检查同时比较透明纹理与最终页面合成后的四角。

打开为 170/180 ms 淡入和 4 个逻辑像素的轻位移，关闭为 120 ms；页签底色/下划线 160 ms、内容 130 ms、结果 150 ms。输入和按钮沿用 UiMotion 的 140 ms hover、120 ms focus/state、80 ms pressed。快速切换和开关可中断，减少动态效果复用系统偏好、`UiMotion.set_enabled(false)` 和 `HEGONG_REDUCED_MOTION=1`。

## 已完成验证

- 实际 Windows OpenGL 渲染：`check_friend_dialog.gd --visual`，**142 项通过，0 失败**。覆盖默认空态、真实适配器结果、无结果/自己/已有好友/已发/收到/屏蔽/网络失败、附言长度和空白保留、五次连续点击、接受/忽略、登录返回、切换账号、10 次开关、关闭中的响应、减少动态效果、Esc 焦点恢复、标准/800×580/620×420 窗口、140% 字号和动画期间四角。
- 原社交回归：`check_social.gd`，**104 项通过**，含聊天、官方通知、赠送、换卡与旧查询时序检查。
- 回环真实 HTTPRequest：`run_social_http_checks.py`，**8 项通过**。
- 独立本机 PostgreSQL 17 数据库 `friend_dialog_test`：`pytest tests/test_friend_note.py tests/test_backend.py -q`，**25 项通过**。包含五个并发申请仍只有一条 pending、接收人权限、幂等和原有后端回归。依赖有一条现有 Starlette/httpx 弃用提示，不影响结果。
- `git diff --check` 通过。

界面测试数据只在隔离存档/测试适配器中存在；截图标记「隔离测试」，不代表线上账号或申请。未在生产服务器创建好友申请，未对实体显示器执行系统 DPI 切换；已检查项目真实逻辑分辨率、非整数窗口缩放及应用字号缩放。系统减少动画 API 在 headless 可能返回未知值，测试使用项目提供的可控接口。

截图位于 `outputs/friend-dialog-validation/`：

- `01-empty.png`：默认空态。
- `02-found.png`：查到用户，使用已有卡牌头像。
- `03-sent.png`：申请已发送。
- `04-requests.png`：接收申请、附言、接受/忽略。
- `05-small.png`、`06-scaled.png`、`07-short-scrolled.png`：小窗口、放大字号、短窗口滚动。
- `08-opening.png`、`09-closing.png`：开关过渡帧。
- 同名 `-dialog.png` 为直接读取的窗口纹理，保留透明圆角。

运行界面检查：

```powershell
python tools/run_workbench_checks.py --godot <Godot控制台程序路径> --script check_friend_dialog.gd --visual
```

## 部署状态

客户端修改已在当前工程中，重新运行根目录 `project.godot` 后生效。本轮没有导出安装包。

用户后续授权部署后，2026-10-30 好友申请后端已上线：100 个可见字符校验、原样附言和已有好友状态返回均已通过正式 HTTPS 验证。服务器隔离回归 46 项、正式 HTTPS 23 项全部通过。没有数据库迁移，历史申请保留；其他未发布本地改动没有带入本次上线。备份、部署范围和校验记录见 [好友申请后端部署记录](FRIEND_BACKEND_DEPLOYMENT.md)。
