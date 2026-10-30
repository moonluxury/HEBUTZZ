# 投稿系统接续交付记录（2026-10-30）

**后续部署状态：** 2026-10-30 09:33 已按用户要求部署服务器，通过服务器 44 项回归和 HTTPS 27 项检查。见 [部署记录](SUBMISSIONS_DEPLOYMENT.md)。下文“接续时”描述的是部署前基线。

## 检查到的原进度

接续时，根工程已经存在 Godot 4.6.2 + CEF 2.1.1 内嵌 Tiptap 编辑器、五个界面状态、FastAPI/PostgreSQL 投稿迁移、DOCX 转换和初版集成检查；原记录仍写着“正在实现”。代码未部署到正式服务器，不能把本机测试通过等同于线上可用。

本轮沿用这些实现，在当前工程中修复、验收和补齐；没有建立独立演示站，没有替换个人头像或重做题库、收藏、好友、充值页面。所有测试均使用本机 `127.0.0.1` 的 `*_test` 数据库及隔离 Godot 存档。

## 当前能力

| 参考状态 | 当前实现 |
| --- | --- |
| 01 基础信息 | 标题、服务端分类、课程、标签、封面和快速富文本编辑；保存、预览及提交；双栏轻量表单 |
| 02 沉浸写作 | 同一 `client_key/submission_id/revision_id`、同一个编辑器实例及结构化正文；标题、列表、任务、图片、公式、表格、代码、引用、链接、撤销重做；真实大纲；Word 工具 |
| 03 我的投稿 | 服务端作者范围查询、分页、真实统计；草稿、待审核、退回、已发表，以及待发表、拒绝、下架的状态映射；撤回、修订、重提、删除未发表稿件 |
| 04 阅读顶部 | 服务端已发表版本、真实作者和图片、统一受控正文渲染、目录、点赞/收藏/举报 |
| 05 阅读下半段 | 同一 `SubmissionArticle` 场景、同一文章和滚动容器；当前章节、资料来源、底部操作及上一篇/下一篇 |

投稿导航只有一个入口；“我的投稿”是模块内子页。公开资源页中的已发表文章链接进入同一个阅读场景。截图中的作者、标题、文章和图片均为隔离测试资料，不是正式账号数据，也不会向生产环境插入样例。

## 本轮补齐与修复

- Windows 150% DPI 下纠正 CEF 与 Godot 的重复缩放，使用实际 DPR 和宿主 canvas 比例同步；宽屏保留大纲，1366×768 不横向溢出。
- 修复原生中文拼音候选框偏移：根据真实正文/输入框光标范围向宿主报告归一化位置，在 CEF 更新后定位候选框。实际 Windows 键盘中文、拼音 `ni → 你` 已验证；修正后候选框贴近正文光标。
- 保存状态由原生 Store 的写入结果决定，切换页面不会虚报“等待自动保存”；冲突/待审文档正确限制编辑。
- 恢复干净服务器草稿时保留本机光标和滚动元数据；点赞、收藏、公开列表更新不会把读者从文章下方送回顶部；不同文章使用独立滚动位置。
- 账号切换清除旧公开列表，并丢弃过期请求；服务器稿件已进入审核时，不能把“保留本机版本”当成绕过审核的覆盖入口。
- 本机断网副本可由全新 Store 实例恢复，重连沿用稳定操作键同步；服务端版本冲突、权限和奖励幂等保持原有规则。
- 增加图片拖放桥接、缩放后的光标定位、减少动态效果、键盘可见焦点；Esc 先关闭编辑器弹层，活动输入法组合拥有首次 Esc。
- Word 导入保留表格内图片，超大表格明确拒绝，嵌套/合并表格明确提示；导出保持 JPEG 比例，修复列表编号结构和标题大纲语义。
- 补充可重复执行的隔离客户端、手工输入探针、模型测试和发布包启动检查。

## 数据与权限

服务端动作沿用 `/v1/rpc`，包括 `submission_config/create/get/save/mine/submit/withdraw/revise/delete`、`article_get/react/report` 和 `publication_review`。图片通过 `/v1/submission-assets` 上传和按资源 ID 读取；公开列表/详情为 `/v1/articles`。

服务端以会话确定作者，保存使用 revision 乐观锁，审核固定 revision。普通用户无法调用审核；审核员权限来自 `publication_reviewers`。未发表正文和图片均限制访问；发表更新继续公开旧版本直到新版本完成审核与发布。允许节点、链接、数学源、真实图片文件头、尺寸、数量和附件归属在服务端验证。

标题上限 100 字、正文 50000 字、标签 5 个、每篇引用图片 9 张、单图 6 MiB，配置由 `submission_config` 返回。分类由数据库启用配置返回。正文不长期保存 base64 图片，桥接临时图片以受控 asset_id 引用。

作者提交只进入待审；审核通过但未发表不发奖。成功发表事务写入唯一奖励事件，钱包接收端必须用同一个事件键幂等记账。当前正式奖励规则/钱包服务尚未配置，没有实际给任何正式用户发测试电池。

## Word 边界

只支持 `.docx`。使用内置 Python 标准库读写有边界的 OOXML ZIP，离线运行，无付费 Word 转换服务、宏执行或外部图片下载。导入前可选择覆盖或插入，失败保持旧正文。

常用标题、段落、字体强调、多级列表、链接、表格和 PNG/JPEG/WEBP 图片可转换。常见 Word 数学结构转换为数学源，并显示转换报告；复杂公式、嵌套/合并表格、页眉页脚和特殊对象不能承诺等价保留。导出数学节点保留为可编辑 LaTeX 文本和原始结构化数据，重新导入可恢复；不声称生成原生 OMML 公式。已用本机 Microsoft Word 打开真实导出文件，未要求修复文件；另用独立 python-docx 检查对象。

## 代码位置

- 页面/桥接：`scenes/Submissions.tscn`、`scenes/SubmissionArticle.tscn`、`scripts/submission_page.gd`、`ui/submissions/src/{app,model,caret}.js`、`style.css`。
- 草稿/转换：`scripts/submission_store.gd`、`submission_word.gd`、`submission_docx.py`。
- 公共接入：`scripts/app_services.gd`、`backend_provider.gd`、`minimal_page.gd`、`page_router.gd`、`hegong_kaiwu.gd`；本轮 `app_state.gd` 仅增加内嵌编辑器的 IME Escape 归属判断。
- 服务端：`backend/submission_service.py`、`submission_document.py`、`publication_rewards.py`、`migrations/002_submissions.sql`；`app.py/domain.py/database.py` 接入服务与迁移。
- 运维接口：`backend/ops/grant_reviewer.py`、`cleanup_submission_assets.py`、`deliver_publication_rewards.py`。
- 构建：`addons/godot_cef`、`tools/setup_submission_editor.py`、`ui/submissions/build.mjs`、`export_presets.cfg`。`ui/submissions/dist` 是运行所需产物。
- 检查：`tools/check_submissions.gd`、`serve_submission_checks.py`、`run_submission_checks.py`、`submission_input_probe.gd`、`test_submission_docx.py`、`run_submission_export_check.py`、`ui/submissions/tests/model.test.mjs`。

## 实际验证与截图

- PostgreSQL 后端回归：44 项通过（包含账户/讨论既有行为及投稿权限、并发、审核版本、图片权限、重复发布、奖励投递幂等）。
- DOCX 回归：7 项通过，覆盖中文、列表/表格/公式/图片、表格图片、JPEG 比例、Word 修改后重新导入、安全拒绝、超大表格拒绝。
- JavaScript 模型回归：4 项通过。
- 原应用返回导航：31 个断言通过。
- Godot + CEF + 本机 FastAPI/PostgreSQL 完整投稿链路：0 失败。包含 12000 字中文长文保存与撤销、自动保存、单稿双视图、公式/表格/图片、DOCX、提交待审、私有预览、公开阅读、目录联动、点赞后位置不变、磁盘恢复及重连。
- 已在 1710×920 和 1366×768 捕获真实 Godot 合成画面；较窄窗口继续使用应用原有缩放规则。
- 发布导出和独立 EXE 运行结果见后附验收记录。不会仅凭导出成功声称发布包可启动。

五屏截图：

1. [基础信息](outputs/submissions-validation/01-settings.png)
2. [沉浸写作](outputs/submissions-validation/02-writer.png)
3. [我的投稿](outputs/submissions-validation/03-mine.png)
4. [文章顶部](outputs/submissions-validation/04-article-top.png)
5. [同一文章下半段](outputs/submissions-validation/05-article-bottom.png)

实际界面复用本项目侧栏与测试素材，因此不把参考图作者/日期/固定计数当作视觉验收内容。正文是一列连续文档，未实现参考图中的自由浮动公式/图片排版；正文节点支持全宽流式排版和图片宽度设置。

## 复现命令

先确保本机 PostgreSQL 测试库存在，安装 `backend/requirements.txt` 以及转换测试需要的 `python-docx`。下面使用本次已有的 Python 环境与 Godot；请按实际安装位置替换。

```powershell
$env:DATABASE_URL='host=127.0.0.1 port=5432 dbname=hegong_submission_test user=hegong_test_owner'
$env:PYTHONPATH='E:\zhengzhi\backend'
& '.godot_appdata\backend-venv\Scripts\python.exe' -m pytest backend/tests -q
& '.godot_appdata\backend-venv\Scripts\python.exe' -m unittest tools.test_submission_docx -v
& '.godot_appdata\backend-venv\Scripts\python.exe' tools/run_submission_checks.py --godot 'C:\Users\Legion\Desktop\工具\游戏创作\Godot_v4.6.2-stable_win64_console.exe'
# 加 --manual 打开隔离的原生输入验证窗口；这是人工检查入口，不自动宣称 PASS。
```

编辑器在 `ui/submissions` 中执行 `pnpm install --frozen-lockfile`、`pnpm build`、`pnpm test`。本轮使用现有锁定依赖和 Node 直接运行 `build.mjs` 与 `node --test tests/model.test.mjs`。

运行项目：根 `project.godot`，F5，侧栏“投稿”。未登录沿用现有账号登录。正式服务器未开通投稿时明确显示服务不可用，本机恢复副本不会冒充服务器成功保存。

## 依赖、许可证和发布条件

Tiptap/ProseMirror（MIT）、KaTeX（MIT）、DOMPurify（Apache-2.0 或 MPL-2.0）、esbuild（MIT，构建用途）、Noto Sans SC（OFL-1.1）、Godot CEF 插件（MIT，CEF/Chromium 独立许可）。通知随 `ui/submissions/dist/THIRD_PARTY_LICENSES.txt`、`NotoSansSC-OFL.txt`、`addons/godot_cef/{LICENSE,CEF-LICENSE.txt}` 保存。内置 Python 使用项目已有 PSF 许可运行时。

CEF Windows x64 运行时约 386 MB，不进入 Git；发布时必须随 EXE 携带导出的 `addons/godot_cef` 运行目录，不能只发送单独 EXE。安装脚本从固定官方版本获取并保存文件哈希。不支持把当前实现称作 Android/macOS/Linux 已验收。

仍需的正式条件：

1. **已完成：** 投稿后端和迁移 002 已独立部署服务器，保留现有评论，完成备份和回归。
2. 运营侧授权真实审核员；本轮只提供受权限保护的接口，不新增管理后台 UI。
3. 确认正式奖励数额/规则版本并接入钱包接收端及投递任务，才能实际到账。
4. 文章评论接口尚未提供；已有题库评论服务没有冒充文章评论。
5. 原生拖放桥接已实现，但完整文件管理器拖放和多显示器热切换尚未做人工组合验收。复杂 Word 排版仍按转换报告处理。

## 发布启动修复

独立发布版曾在 CEF 初始化时失败。定位到 Chromium 继承或共用日志文件路径后，给每个进程设置独立 `cef-<pid>.log`，与 Godot 日志分开。保留证书/跨域/权限限制；发布版远程调试关闭。启动失败在 15 秒后显示明确提示，不无限停留在“正在加载”。未采用放宽浏览器安全选项的办法。

正式 release 模板禁用外部 `--script/--path` 覆盖，因此发布检查改为启动真实的 `--open-submissions` 入口，读取实际 JS/原生桥接就绪结果，再人工查看窗口。不会把外部脚本没有执行当作验收通过。当前候选目录为 `.godot_appdata/submission-final/`，旧的 `submission-release/` 仅为诊断遗留，不用于交付。

最终 release 导出退出码 0；`tools/run_submission_export_check.py --exe .godot_appdata/submission-final/Hegong.exe` 通过，实际发布日志包含 `SUBMISSION EDITOR READY` 和 `remote_debugging=false`，无 ERROR。之后已打开实际发布窗口，看到完整侧栏、投稿登录引导和按钮；截图为 [08-packaged-login.png](outputs/submissions-validation/08-packaged-login.png)，日志为 [packaged.log](outputs/submissions-validation/packaged.log)。候选 EXE 与同目录 addons 必须一起使用。

## 正常启动不弹控制台（2026-10-30）

用户反馈进入投稿时出现黑色调试窗口，已复现。原因是 CEF 插件在父/子进程中强制传递 `enable-logging`，Chromium 会为无控制台启动的 GUI 程序创建控制台；只把 stderr 改成文件日志仍会出现。

现使用单独的 `x86_64-pc-windows-msvc-quiet` 运行目录，按固定上游哈希准备取消强制控制台日志的插件；补丁过程、原始/结果哈希和许可记录在 `addons/godot_cef/LOCAL_PATCHES.md` 及运行时清单中。正常应用错误继续记入 Godot 日志。Windows 导出关闭额外 `.console.exe` 启动器。

现有开发目录可以运行 `python tools/prepare_submission_runtime.py` 生成修复后的运行时；首次安装继续运行 `python tools/setup_submission_editor.py`，会自动完成。所有运行时 DLL 仍由安装脚本准备，不提交 Git。旧进程不被强制关闭，停止当前运行后重新打开即可使用修复。

验证使用 GUI 版 Godot，以 DETACHED_PROCESS 启动，不重定向 stdout/stderr，也不以 CREATE_NO_WINDOW 隐藏应用。旧版本在同样条件下出现 conhost；新版本 `tools/check_submission_console.py` 检查编辑器就绪及其进程树，0 个控制台进程。完整投稿链路（含 Word 导入/导出）再次通过，0 失败。

源码 GUI 与独立 release EXE 的无控制台检查均通过，记录见 outputs/submissions-validation/console-audit-debug.json 和 console-audit-release.json。新打包候选目录为 .godot_appdata/submission-no-console/，该目录无 .console.exe 启动器。

## 列表删除按钮（2026-10-30）

我的投稿在未发表的草稿、退回稿和不予采用稿件右侧直接显示删除按钮。确认弹窗显示实际标题，取消保留稿件；请求执行期间禁用重复操作。删除使用已有服务端接口，成功后留在列表并刷新数量；目标稿件读取失败不会误删此前打开的其他稿件。待审需先撤回，已发表版本不显示删除入口。隔离客户端集成检查及 5 项文档模型检查通过，截图见 outputs/submissions-validation/11-delete-confirmation.png。

## 投稿入口顺序（2026-10-30）

点击侧栏投稿默认先显示我的投稿列表；仅点击写新投稿才创建新稿件，继续编辑打开选中的已有稿件。取消了进入模块时自动恢复编辑页或自动建立空白稿件的行为，已有稿件与本机未同步内容保留。文章详情的编辑文章使用明确的编辑入口，仍直接进入对应修订稿。页面退出时解除草稿状态订阅，避免切换页面后的旧编辑器收到状态更新。

实际客户端验证首次进入/再次点击投稿均为列表，服务器稿件数量不增加；显式新建、继续编辑、公开文章修订和离线稿件恢复均通过。完整投稿集成 0 失败；公共返回导航 31 个断言通过。入口截图见 outputs/submissions-validation/00-submission-entry.png。
