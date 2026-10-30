# 答题页题库讨论交付记录（2026-10-30）

已在根目录 Godot 4.6.2 工程实现。正式启动不注入演示评论；以下带“本机测试”昵称的截图来自本机 FastAPI + PostgreSQL 隔离数据库，由独立测试账号实际发布。

**后续更新：2026-10-30 评论后端已上线。** 现有客户端可通过 `https://39.107.44.18` 读取六门课程讨论，登录后可发布、回复、点赞/取消、删除本人评论及举报。Godot 真实 HTTPS 验收 26 项通过，临时账号与私有测试题库已清理。

## 已完成

- 按最新要求，顶栏仅保留标记、讨论两个居中的纯图标按钮，不显示文字；已删除新增的解析入口与右侧解析面板。课程标题、计时器、结束练习、侧栏、判题和原底部加入错题库继续使用原控件。
- 默认题号列表，与讨论在同一个裁切右栏中切换。双向短距离滑动与交叉淡入淡出，快速操作终止旧 Tween 并从当前位置转向最终目标。仅目标视图接收鼠标和键盘输入。
- 题库 ID 使用 `AppState.SUBJECTS` 原有稳定 ID：`marxism / mao / xi / matlab / python / cpp`。讨论请求没有题目序号或 question_id；切题不关闭讨论、不请求评论。
- 最新/热门、首批 20 条及加载更多、两层回复、点赞/取消、作者删除、举报；匿名用户可以读取公开题库，发布沿用原登录窗口。
- 固定输入区、提交中禁用及防重复、失败保留输入、同内容重试沿用操作编号、加载/空列表/失败/权限/待审核/隐藏/删除状态。草稿、滚动位置、排序、回复展开保存在当前会话服务，退出登录/切换账号清空。未发布草稿没有跨程序重启持久化。
- 旧的列表请求不能覆盖成功的新操作；旧账号响应被 epoch 丢弃。按需读取，无轮询和 WebSocket。
- 标记按账号、bank_id 和原 question_id 保存于 `user://quiz_marks_v1.json`，复用 LocalJsonStore 原子写盘。与错题、答案、奖励和收藏相互独立；题号右上角显示小旗。
- 原有作答后的答案反馈、编程题参考代码操作和学习记录规则保持原样。
- F6、深浅色、字号缩放和系统减少动态效果继续可用。窄窗口右栏也预留空间，两种模式切换不盖住题目；主区小于 550 逻辑像素时底部错题按钮另占一行，以免按钮互相覆盖。普通参考分辨率的主区与底部位置保持不变。

## 文件与复用模块

| 文件 | 本次作用 |
| --- | --- |
| `scripts/minimal_quiz_view.gd` | 两个顶栏图标按钮、题号标记、右栏组装与响应式布局 |
| `scripts/quiz_right_panes.gd` | 固定裁切、可中断双向 Tween、减少动态效果、焦点恢复 |
| `scripts/bank_discussion_view.gd` | 原生评论控件、列表、回复、状态和固定输入区 |
| `scripts/bank_discussion_store.gd` | 按题库缓存、分页、草稿、请求幂等与会话隔离 |
| `scripts/quiz_marks.gd` | 独立题目标记及存档 |
| `scripts/quiz.gd` | Esc 优先关闭讨论右栏 |
| `scripts/app_services.gd` | 按需持有标记及讨论服务 |
| `scripts/backend_provider.gd` | 复用现有 HTTPS / Bearer 请求适配器，新增评论调用 |
| `scripts/submission_store.gd` | 仅为现有 `restored` 变量补 `bool` 声明，修复阻碍工程加载的类型推断错误；无业务变化 |
| `backend/comment_service.py` | 题库访问检查、查询、写操作、审核与幂等事务 |
| `backend/migrations/003_bank_comments.sql` | 题库、访问授权、评论、点赞关系、举报及审核员表和索引 |
| `backend/app.py / backend/domain.py` | 公共读取路由、评论 RPC 分派和服务端限流 |
| `assets/discussion/` | 气泡、点赞 SVG 及 Lucide 授权；标记、关闭仍复用原图标 |
| `backend/tests/test_comments.py` | PostgreSQL 权限、分页、并发、幂等和审核检查 |
| `tools/check_bank_discussion.gd` | 原生 Godot 界面与真实 HTTP 联调、连续帧采集 |
| `tools/run_discussion_checks.py / tools/fixtures/discussion_http_provider.gd` | 仅回环地址、隔离数据库和独立客户端存档的运行器 |
| `tools/package_discussion_evidence.py` | 将真实连续帧按采集间隔打包为 GIF，无插帧或重画 |
| `tools/check_quiz_focus.gd / check_back_navigation.gd / check_minimal_design.gd` | 跟随右栏容器层级与窄屏预留布局调整原断言 |

复用 `QuizSession`、`QuizContentView`、`ProfileStore`、`ProfileAvatar`、`AppServices`、`UiStyles`、`UiMotion`、`LocalJsonStore`，以及服务端现有认证、事务、签名游标、operations 幂等表。未改判题器、奖励、文章评论配置或投稿页面业务。仓库原本有其他未提交修改，本次仅追加必要接入点，未回滚那些修改。

## API 与部署

读取入口 `POST /v1/comments/query`，请求沿用 `{version:1,action,payload}`。支持匿名公开题库读取，登录时可携带原 Bearer 会话。写入仍走需认证的 `POST /v1/rpc`。

| action | payload（所有操作另有 `target_type:"bank",target_id:<bank_id>`） |
| --- | --- |
| `comment_list` | `sort:"latest"或"hot", limit:20, cursor:""` |
| `comment_replies` | `parent_id, limit:20, cursor:""` |
| `comment_create` | `body, parent_id:""或一级评论ID, operation_id` |
| `comment_like` | `comment_id, value:true/false, operation_id` |
| `comment_delete` | `comment_id, operation_id`（仅作者） |
| `comment_report` | `comment_id, reason, operation_id` |
| `comment_moderate` | `comment_id, decision:"published"或"hidden", operation_id`（仅服务端审核员） |

所有身份取自服务端会话，禁止自报作者/状态/点赞数；点赞唯一关系及事务锁避免并发重复计数，签名游标绑定用户/题库/排序/回复范围。正文限 1–2000 字，拒绝无效控制字符；客户端使用普通 Label/TextEdit 文本，不执行 HTML、BBCode 或脚本。写接口每用户每分钟 60 次，发评论/回复每分钟 8 次；匿名读取也有 IP 限流。

**已部署正式服务器。** 用户随后要求补齐后端，已从线上原始版本构建评论专用发布包，仅上线 `app.py` 的评论路由/限流、`domain.py` 的评论分派、`database.py` 的迁移加载，以及 `comment_service.py` 和 `003_bank_comments.sql`。没有把工作区其他未发布功能一起上线。迁移已由服务启动执行，六门题库均已开放；正式源文件哈希与测试通过的发布包一致。

部署前已备份数据库与旧代码，服务器备份目录为 `/var/backups/hegong/comments-20261029T174115Z`。发布暂存目录为 `/opt/hegong/releases/comments-20261030-01`。迁移是增量建表；代码回退不覆盖部署后的用户数据。北京时间上线时间为 2026-10-30 01:41。

现有六门课程作为公开题库登记；未来受限题库可通过 `discussion_banks.public` 和 `discussion_access` 授权。设置 `BANK_COMMENTS_REVIEW_REQUIRED=1` 可启用先审后发；审核员需服务端写入 `bank_comment_moderators`，客户端无法自授权限。举报已进入真实待处理表，管理员审核 RPC 已提供；本次未新增运营审核后台界面或自动内容分类服务。现有文章模块没有评论功能，本次未强制开放文章评论。

## 实际检查结果

后端上线补充验收：

- 新增异常参数/动作字段校验；列表改为一次数据库快照查询，减少逐条查询并避免账号删除时作者读取竞争。
- 独立评论发布包：本机 **39 项**、服务器隔离 PostgreSQL **39 项**通过（原有 23 项 + 评论 16 项）。
- 通过正式客户端 `BackendProvider`、真实 TLS 证书和正式 HTTP 路由完成 **26 项线上检查**。真实发布/回复/点赞/取消/删除/举报在临时私有题库内进行，不向公开课程插入测试数据；两个临时账号及题库均已删除，测试会话已撤销。
- 线上验收日志：`.godot_appdata/comments-live-hibtoshk/process.log`。可复用 `tools/run_comments_live_checks.py`、`tools/check_comments_live.gd` 和服务端 `ops/comment_smoke_fixture.py` 执行相同流程；工具只清理本次精确标识的临时数据，不清空生产表。
- 现有账号、资料、好友等线上模块保持原版本，服务和数据库健康检查通过；没有修改 HTTPS 配置、服务凭据或发布投稿模块。

前一轮客户端与本地服务验收：

最新纯图标调整已重跑真实渲染与回环 HTTP 检查，89 条断言通过；截图及连续帧已更新。顶栏不再显示解析入口，也不显示标记/讨论文字。下面旧版解析权限检查属于调整前的历史结果。

- 后端完整回归：**33 项通过**，包括 5 项新增评论集成测试；使用独立 `hegong_comments_test` PostgreSQL，未触碰线上用户。
- Godot 真实图形渲染 + 回环 HTTP：**89 条断言通过**。覆盖默认零请求、真实评论、跨题共享、草稿/滚动/焦点保留、双向中间帧、连续快切、解析权限、标记存档、发布防重及重试、回复/点赞/删除、迟到列表与回复、账号切换、深浅色、F6、减少动态效果和窄屏布局。
- 原答题重做/紧凑布局检查、F6/字体/错题按钮检查、31 项返回导航检查、统一动效风险检查均通过。
- `check_motion.gd` 的 headless 系统偏好返回 `-1`（能力未知）；程序减少动态效果开关及立即结束过渡已验证，不声称在此环境获得了真实系统偏好。
- 连续帧采集窗口位于屏幕外且不可聚焦；采集开始时在该隔离进程中明确开启动画，避免用户切换其他应用使测试窗口的失焦策略提前结束动画。未更改正式客户端的系统偏好处理。
- 首次并行打开工程导入时遇到现有 CEF 编辑器 DLL 被占用；未改动该扩展。后续正常 Godot 实际运行及上述检查均无脚本/运行错误。本次未重新导出发布 EXE。

复现（需要本机测试 PostgreSQL 已启动，数据库名必须以 `_test` 结尾；所有账户和客户端存档均隔离）：

```powershell
# 在 backend 目录，使用项目现有 backend-venv Python
$env:DATABASE_URL='host=127.0.0.1 port=55439 dbname=hegong_comments_test user=hegong_test_owner'
$env:CURSOR_SECRET='isolated-comments-check-key'
..\.godot_appdata\backend-venv\Scripts\python.exe -m pytest -q tests

# 在工程根目录
.\.godot_appdata\backend-venv\Scripts\python.exe tools/run_discussion_checks.py --godot '<Godot控制台程序路径>' --visual
.\.godot_appdata\backend-venv\Scripts\python.exe tools/package_discussion_evidence.py
```

## 真实界面证据

客户端区域为 2048×1195，与参考图去除原生窗口标题栏后的区域一致；窄屏额外使用 1200×900。截图中的评论均是隔离测试记录，不作为正式客户端初始数据。

- [默认题号栏与两个纯图标](outputs/discussion-validation/01-default.png)
- [讨论展开、真实记录及输入区](outputs/discussion-validation/02-discussion.png)
- [标记开启及题号角标](outputs/discussion-validation/04-marked.png)
- [真实回复与点赞](outputs/discussion-validation/05-replies.png)
- [深色模式](outputs/discussion-validation/06-dark.png)、[未登录](outputs/discussion-validation/07-signed-out.png)、[另一题库空列表](outputs/discussion-validation/08-empty.png)、[窄屏](outputs/discussion-validation/09-compact.png)
- [打开连续帧 GIF](outputs/discussion-validation/motion-open.gif)、[关闭连续帧 GIF](outputs/discussion-validation/motion-close.gif)
- [原始采样数据](outputs/discussion-validation/motion-trace.json)，同目录保留 `motion-open-00…23.png` 和 `motion-close-00…23.png`。每帧都检查题目区及计时器坐标不变；GIF 来自这些实际帧，未用两张静态截图模拟过渡。

## 可直接调整的参数

- `quiz_right_panes.gd`：`DURATION=0.22` 秒、`DISTANCE=24.0` 逻辑像素；Cubic Ease Out，不回弹。
- `minimal_quiz_view.gd::_layout`：右栏 365、两个纯图标按钮 50×50、间距 8，图标水平和垂直居中；仅在宽度受限时课程名称省略显示。
- `bank_discussion_view.gd`：正文 16、辅助文字 12–14、头像 42/回复头像 32；排序下划线 0.15 秒、列表和点赞反馈 0.14 秒。
- `ui_tokens.gd`：继续使用既有 `PRIMARY=#092C87`、`SOFT=#EBEEF5` 及共享按钮 hover/pressed 时长。本次没有修改全局主题变量。
