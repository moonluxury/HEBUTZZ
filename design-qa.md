# 工作台唯一首页核对

final result: passed

## 对照与状态

- 用户标注图：`outputs/workbench-final/user-markup.png`，1920 × 1032，含约 24px 系统标题栏与外部会议浮窗。浮窗不属于应用内容。
- 实现：`outputs/workbench-final/workbench-wide.png`，1920 × 1008，Godot 原生客户区截图。已与用户标注图放在同一检查输入中比较，按标题栏偏移对齐，不对外部浮窗作还原。
- 主界面补充：`workbench-light.png`（1543 × 949）、`workbench-with-records.png`、`workbench-dark.png`、`workbench-narrow.png`（1000 × 850）、`workbench-large-text.png`。
- 保留交互：`workbench-history.png`；收藏空页：`my-collection.png`（1600 × 984）。
- 用户截图为已有 2 题记录；宽屏实现图为隔离空记录，with-records / dark 图为真实测试答题后状态。数据状态差异不属于布局问题。
- 原生 Godot canvas_items 布局，CSS 与 deviceScaleFactor 不适用。全幅中的文字、图标及移除位置均可辨认，无需额外裁切。

## 本轮变更与视觉检查

用户指定删除右侧除学习趋势外的点击页面，将我的精灵替换为收藏空页，并移除原首页。

- 字体：沿用现有系统中文字体、字号层级及 4 倍采样与 mipmap 过滤；导航“我的收藏”、统计数字、历史日期、空页提示及返回按钮可读，无文字截断。
- 布局：侧栏、横幅、四张统计卡和两块图表位置及尺度保留；移除横幅的开始 / 继续学习按钮和左下原版首页入口。窄屏可滚动，侧栏五个入口保持可见。
- 颜色：原浅蓝背景、深蓝标题、蓝灰次级文字和统计图标色值保持；深色模式没有恢复被删除入口。
- 素材：继续引用原图标的独立素材、原品牌标志及原横幅插画，没有重新设计或替换图案。收藏空页复用原侧栏人物图标。
- 文案与内容：侧栏与新页面标题均为“我的收藏”，空状态显示“暂无收藏 / 收藏内容将在这里展示”，符合用户确认的先做空页。题库数量和学习记录继续显示真实数据。

## 功能检查

`tools/run_workbench_checks.py --visual` 通过：PASS，0 failures。隔离目录为 `.godot_appdata/workbench-check-vx9y4cfx`，不使用或修改用户存档。

- F5 主场景为工作台。
- 横幅、四张统计卡和题型分布是无焦点的展示面板，没有按钮子节点或点击处理；右侧内容区只有学习趋势仍是按钮。
- 学习趋势可打开记录，日期可进入每日记录，关闭及记录内学习入口可用。
- 总题库、错题库、六门课程、河工开物及返回工作台路径正常。
- 答题后的学习统计、题数去重、编程题复习及独立记录保存正常。
- 我的收藏打开空页，返回按钮和 Esc 均回到工作台。
- 旧首页场景、脚本及侧栏入口已删除；旧精灵展示页由收藏空页替换，原有答题经验数据未清除。
- 工作台与收藏页无 tooltip；深色、字号缩放与窄窗口仍可用。
- 已将题库回归脚本的首页入口引用改为 Workbench；本轮未重复运行完整题库判题套件，判题逻辑未变更。
- `git diff --check` 通过；旧首页和旧精灵展示页无运行时引用。
- 交互检查使用 Godot 真实 Button 信号和场景集成测试，不宣称完成桌面鼠标端到端测试。无脚本错误；测试退出仍有既有 ObjectDB cleanup warning。

## 结论

本轮实现后首次视觉对照未发现额外 P0/P1/P2，未因视觉对照继续修改外观。右侧按钮移除、收藏空页与唯一首页均符合本轮指示。历史版本核对记录保留在 outputs/workbench-v2/design-qa.md。

- [x] 仅学习趋势保留右侧点击页面。
- [x] 我的收藏入口及空页面完成。
- [x] 删除旧首页场景、脚本和入口。
- [x] 保持原图标及既有学习数据。
- [x] 实际渲染与交互检查通过。

## 2026-10-27 统一动效实施

本节记录本次增量，前文是已有静态设计验收。沿用 Godot 4.6.2、原生控件、原路由与 2,981 道真实题库；没有替换布局、素材、数据源、判题模式或框架。开始实施时仓库已有大量未提交修改，本轮在其上增量编辑，没有回退它们。

### 文件与页面

| 位置 | 本轮实现 |
| --- | --- |
| `scripts/ui_tokens.gd`（新增） | 工大蓝与派生色、统一秒制时长。深色主题保留可读浅色前景；原插画和多类别状态配色不重绘。 |
| `scripts/ui_motion.gd`（新增）、`project.godot` | UiMotion 自动加载；按目标属性替换旧 Tween，节点离树即清理；系统减少动态效果、手动关闭、触屏 hover 门控、应用失焦清理。 |
| `scripts/ui_feedback.gd`（新增） | 公共按钮/input/表面组合状态；固定尺寸、独立焦点环、disabled 阻止按压表现；一个 StyleBox 的颜色由一个来源控制。 |
| `scripts/minimal_page.gd` | 共享主色、主内容 180 ms 淡入、页签 120 ms、搜索焦点、导航和按钮 140/80/120 ms；主题重建保留滚动与可恢复焦点。 |
| `scripts/subject_select.gd` | 总题库卡片只变边框/淡底，局部筛选 140 ms；错题列表局部更新，科目切换保留图表实例，记录使用稳定课程/题目 ID；统计区不加按钮效果。 |
| `scripts/quiz.gd`、`scripts/minimal_quiz_view.gd` | 答题 120 ms 无位移淡入；跨题复用选项前清除旧语义颜色；多选即时保存、判题后禁用输入；题号标记用独立角标，不挤动数字；计时等宽数字、失焦停刷新；重复结束练习保留单个现有结果框；错题存档失败恢复原状态并显示错误。 |
| `scripts/workbench.gd`、`scripts/workbench_chart.gd` | 工作台数字直接更新，真实学习进度 280 ms，保留 chart/body 实例；趋势直接绘制真实数据、不归零重播；学习记录弹层 180 ms 入场、120 ms 离场，关闭立刻释放点击与焦点。 |
| `scripts/hegong_kaiwu.gd` | 资源搜索/分类/排序局部淡入，稳定条目标识，列表轻反馈与原示例展开 180 ms；尽量恢复局部操作焦点。 |
| `scripts/program_editor.gd` | 参考代码局部展开淡入、统一输入与按钮状态，保留真实运行状态、错误、停止与草稿。 |
| `scripts/my_collection.gd`、`scripts/hegong_kaiwu_detail.gd`（继承，无直接修改） | 收藏空页和资源正文页自动使用公共主内容入场与交互状态。 |
| `tools/check_motion.gd`（新增）、`tools/check_minimal_design.gd` | 风险行为检查；既有无动画断言更新为过渡结束后无持续动画，保留原业务/布局断言。 |
| `README.md`、本文件 | 参数位置、关闭入口、复现命令与能力边界。 |

### 实际检查与证据

- 工作台集成：`run_workbench_checks.py`，PASS / 0 failures；隔离日志 `.godot_appdata/workbench-check-wsvjaicj/check.log`。
- 六页真实 OpenGL 渲染：`--script check_minimal_design.gd --visual`，PASS / 0 failures；最终复测日志 `.godot_appdata/workbench-check-t0dbj4eu/check.log`。已查看六页、答题深色及窄屏截图，并在最后修复后重新查看深色答题图，确认题干/选项可见、角标不挤动数字。截图在 `outputs/minimal-design/`。
- 动效风险检查 headless：PASS / 0 failures；最终复测日志 `.godot_appdata/workbench-check-w_y4i4kw/check.log`。快速连续切 29 题、旧答案恢复、MATLAB 未交多选、重复提交、真实文件打开失败/重试、真实 Python 执行与异常、减少动态效果、关闭弹层焦点恢复、主题切换中复用控件可见性、离页后无 Tween 均验证。
- 动效风险检查真实渲染：PASS / 0 failures；`.godot_appdata/workbench-check-l4a7vjpx/check.log`。实际 Windows API 返回 `0`，headless 返回 `-1`。断言验证菜单打开中的透明度介于 0 与 1、应用不会因自己的弹出菜单而暂停；菜单实际渲染截图 `outputs/minimal-design/motion-filter-menu.png` 已查看。
- 完整 Python 题库/编辑器回归：`run_quiz_checks.py --course python`，PASS，覆盖 890 道源题、草稿、真实执行、原判题、错题、旧存档隔离与另五门课回归；`.godot_appdata/python-check-d_5_pp_y/check.log`。
- `git diff --check` 通过。所有运行使用独立存档，没有修改用户学习记录。检查脚本包含原生鼠标注入（既有六页套件）、键盘 Enter 输入与真实控件信号；没有声称完成真人桌面全流程或物理触屏验证。

检查过程中修复了延迟绑定已经销毁控件、SystemFont 不支持直接设置 OpenType 特性、微小进度被默认 step=1 取整等问题。最后人工截图复核还发现了切题淡入时切主题导致复用题目区域透明的问题：节点离树取消 Tween 前现在先到达最终值，并新增回归断言；修复后再次渲染确认。回归脚本也修正了题目 JSON 数值的比较方式，并使用实际包含多选题的 MATLAB 题库验证多选流程。

### 有意保留的功能/平台边界

- “我的精灵”已被仓库前一轮移除，现入口是“我的收藏”空页。没有恢复精灵/成就页面，没有新增经验或奖励；原存档、业务累计机制不变。首页开始按钮、课程收藏、持久化收藏系统、资源下载、时间筛选等目前不存在的功能没有虚构。
- 答题仍是原练习模式：单选即时判题，多选点击原提交按钮判题，“结束练习”是现有本地结果框，并无服务器交卷请求。代码运行期间使用既有真实状态文字，未增加假进度或最低等待时间。
- 图表是项目自绘图表，没有外部图表库；真实数据改变时直接刷新曲线，进度条从上次值过渡，不制造悬浮数据或逐点绘制。分布数据口径仍是原题库题型占比。
- PopupMenu 用其自身画布在 180 ms 内进入；关闭仍由 Godot 原生 popup 即时完成，以及时释放系统窗口的焦点/输入捕获。没有为了 120 ms 离场重建菜单或延迟用户操作。原生 AcceptDialog 保留引擎行为。内联长参考代码与资源预览关闭采用即时布局，进入仅淡入，避免公式/长文本高度动画引起滚动跳动。
- 仅颜色/透明度动效，无位移、缩放、旋转、循环 loading、宠物或庆祝动画；没有现成箭头独立层的按钮保持图标静止。时长仍统一引用 tokens，不强行拆原生图标布局。
- 系统偏好接口能力以 Godot 实际返回为准；未知平台可用环境变量或 `UiMotion.set_enabled(false)` 关闭。没有改变操作系统的偏好设置，没有执行真人物理触屏检查。应用恢复焦点时重新读取偏好，无常驻轮询。

品牌主色依据：[河北工业大学学校标识与视觉手册入口](https://www.hebut.edu.cn/gdgk/xxbz/index.htm)。系统偏好能力依据：[Godot 4.6 DisplayServer 文档](https://docs.godotengine.org/en/4.6/classes/class_displayserver.html#class-displayserver-method-accessibility-should-reduce-animation)。Godot 缓动采用 cubic ease-out/ease-in，无回弹，作为需求指定 Web 曲线在原生引擎中的等效实现。

## 2026-10-27 资源排序移除与错题课程卡片

按用户最新三张标注图做增量调整。`scripts/hegong_kaiwu.gd` 删除“默认 / 名称 / 分类”排序控件及状态逻辑，资源继续按原数据顺序显示，搜索与分类保留。`scripts/subject_select.gd` 删除“待复习错题”的逐题表格和“查看全部错题”，改用与总题库共享构建和布局的课程卡片；只展示有匹配错题的科目，保留原图标、课程标题、边框、进度条与右箭头。

卡片显示该科目的真实错题总数，进度沿用原有已练习记录口径（已练习错题数 / 该科目错题总数）。科目和已练习/未练习筛选共同决定可见课程，复习按钮进入对应科目的原错题流程，并定位到首道匹配题。没有匹配错题时显示空状态，不生成无错题课程卡片。原错题趋势和课程分布保留。

- 页面集成与真实 OpenGL 渲染：`--script check_minimal_design.gd --visual`，PASS / 0 failures，最终日志 `.godot_appdata/workbench-check-3ngg12qr/check.log`。覆盖有/无错题科目、真实数量及比例、组合筛选、空状态、课程复习跳转与首道匹配题、总题库共享卡片、窄窗口两列及大字号。
- 资源搜索/分类/预览回归：`--script check_hegong_search.gd`，PASS / 0 failures，日志 `.godot_appdata/workbench-check-lpvjedk6/check.log`；确认排序控件不存在，清除筛选后按源数据顺序显示。
- 动效与原业务风险回归：`--script check_motion.gd`，PASS / 0 failures，日志 `.godot_appdata/workbench-check-78_gv0jq/check.log`。
- 人工查看 `outputs/minimal-design/03-wrong-courses.png`、`03-wrong-dark.png`、`03-wrong-narrow.png`、`03-wrong-large-text.png`、`02-bank.png` 与 `04-resources.png`。卡片标题、数量、进度和入口可读，宽屏三列、窄屏两列，资源排序区域已移除。截图数据来自隔离测试夹具。
- `git diff --check` 通过。所有运行使用独立存档，未改动用户学习记录。

## 2026-10-27 页签下划线展开

用户要求所有现有带下划线的按钮在点击后从中间向两侧展开。已覆盖总题库的三项课程分类、河工开物的四项资源分类，均复用 `minimal_page.gd::_tab`。时长集中为 `ui_tokens.gd::TAB_UNDERLINE = 0.22` 秒，使用既有 cubic ease-out。仅下划线以中心为轴横向展开，文字、线高及点击区域不动；首次构建直接显示完整线，重复点击重新展开，切换立即移除旧线并取消旧 Tween。减少动态效果时立即到最终状态，主题重建使用对应主题强调色。

真实 OpenGL 动效回归 `--script check_motion.gd --visual`：PASS / 0 failures；最终日志 `.godot_appdata/workbench-check-7nejwc7n/check.log`。验证两组页签从近零宽度到全宽、展开中心固定、文字/点击区不动、选中文字颜色同步、快速切换、重复点击、关闭动态效果、主题重建及离页清理；同一套件的原答题/筛选/Python 运行检查均通过。已查看 `outputs/minimal-design/underline-bank-expanding.png` 和 `underline-resources-expanding.png` 的实际展开中间帧。所有运行使用隔离存档。

检查同时修复了原页签选中文字颜色被旧反馈状态覆盖的问题，并给答题计时偏好回调增加离树保护，避免旧页面退出后收到桌面焦点通知时报错；已增加对应回归。Godot 将 Control 的零缩放保留为约 0.00001，起点检查使用可忽略的宽度容差。调整时长的方法已写入 README，单位为秒，保存后重新运行生效。

## 2026-10-27 搜索框聚焦底色与错题下划线筛选

按用户最新要求，在 `ui_feedback.gd` 中仅对输入控件关闭焦点阴影叠色，保留透明的焦点样式和边框反馈，使搜索框聚焦前后内部底色一致。`subject_select.gd` 的“全部错题 / 未练习 / 已练习”改为复用公共下划线页签，选中状态不再使用填充底色；保留原有筛选与课程卡片逻辑。沿用用户已调整的 `TAB_UNDERLINE = 0.70` 秒，没有恢复此前 0.22 秒的值。

最终真实 OpenGL 动效与业务回归 `--script check_motion.gd --visual`：PASS / 0 failures；日志 `.godot_appdata/workbench-check-j2ivfqn1/check.log`。总题库和资源页搜索框分别覆盖深浅色模式、聚焦过程中底色、焦点边框、失焦恢复，并对真实画面的内部像素做前后相等检查。三个页面的下划线均验证居中展开、重复点击、快速切换和减少动态效果。原答题、存档、Python 运行与离页清理检查通过；全部使用隔离存档。

已查看 `outputs/minimal-design/search-focus-bank-light.png`、`search-focus-resources-light.png`、`search-focus-resources-dark.png` 与 `underline-wrong-expanding.png`。回归等待时间改为读取实际下划线时长；光标移出搜索区再检查聚焦/失焦边框，颜色使用浮点近似比较；判题颜色检查期间关闭 hover，避免桌面光标位置影响中性色断言。生产判题逻辑未改动。

## 2026-10-27 趋势图与进度条从左到右显示

按用户要求，学习趋势和错题趋势的折线按横向位置逐渐绘制，圆点随折线到达对应位置依次出现；坐标轴、网格、日期与真实数值不参与动画。所有现用进度条（工作台学习进度、题型分布、课程分布、总题库/错题库课程卡片）统一从左到右绘制实色填充，灰色底轨保留。两类动效共用 `ui_tokens.gd::DATA = 0.70` 秒，使用既有 cubic ease-out。

- `ui_data_reveal.gd`（新增）：在进入可视范围时播放一次，监听布局/滚动事件，开始播放后解除这些监听；没有逐帧可见性轮询。遵守减少动态效果、失焦完成和离树清理规则。
- `ui_progress_bar.gd`（新增）、`minimal_page.gd`：复用原 ProgressBar 背景和实色样式，仅动画绘制宽度，真实 value 和百分比文字立即保持最新值。零进度不创建无效填充动画。
- `workbench_chart.gd`、`workbench.gd`：保留原数据坐标，对折线末段做截取并按顺序显示圆点；真实数据更新时重播，快速更新只保留最后状态；窗口缩放不重播已完成的内容。
- `tools/check_data_reveal.gd`（新增）：实际中间帧/完成帧像素检查、滚动后开始、数据不变、连续更新、减少动态效果、主题及离页清理。`check_minimal_design.gd` 的等待时间改为读取实际公共动效时长。

实际检查全部 PASS / 0 failures：

- 专项真实 OpenGL 渲染：`--script check_data_reveal.gd --visual`；日志 `.godot_appdata/workbench-check-iomh9_s8/check.log`。
- 六页、深浅色、窄窗口与大字号真实渲染：`--script check_minimal_design.gd --visual`；日志 `.godot_appdata/workbench-check-gnhp70jl/check.log`。
- 原动效与答题业务风险回归：`--script check_motion.gd`；日志 `.godot_appdata/workbench-check-e9wdipw2/check.log`。
- 工作台集成：`run_workbench_checks.py`；日志 `.godot_appdata/workbench-check-iu4bi1lh/check.log`。

已查看 `outputs/minimal-design/data-home-expanding.png`、`data-home-complete.png`、`data-wrong-scrolled-expanding.png`、`data-wrong-dark-complete.png`，确认左侧已绘制而右侧尚未出现的中间态、最终圆点和实色宽度、滚动区卡片及深色效果。截图使用隔离夹具数据；所有检查均未改动用户存档。`git diff --check` 通过。

## 2026-10-27 统一选择框与分科目错题趋势

`minimal_page.gd::_style_choice` 统一总题库进度筛选和错题科目筛选的 50 高度、8 圆角、16 水平留白、边框及公共按钮反馈。`ui_motion.gd::bind_popup` 将按钮的高分辨率字体和字号显式传给独立的 PopupMenu 窗口，并设置完整的深浅色面板、文字、悬停及工大蓝选中标记；箭头和单选图标改用 DPITexture 矢量资源。原生弹窗已经跟随页面显示比例，不再叠加额外缩放。科目选择框宽度增至 320，保证最长现有标签及箭头不拥挤。

`study_stats.gd` 在原保存路径中新增每日分科目的作答/答对次数，保存格式版本升至 2。`recent_wrong_days` 按科目计算答错次数，重复答错逐次累加，参考代码复习不计入作答。旧的单科目日记录可准确迁移；混合科目日记录保留合计，不估算拆分。单科目图表遇到未归属旧数据时显示“近 7 天 · 已归属科目记录”。没有删除原学习进度、日期、错题或草稿。

`subject_select.gd` 切换科目时更新原图表实例，折线与圆点重播既有 0.70 秒展开；数值相同的不同科目也强制重播，快速切换保留最后一次选择，减少动态效果时直接显示结果。已练习/未练习页签仍仅筛选复习卡片，不改变答错历史的统计含义。

实际检查全部 PASS / 0 failures：

- 新增专项真实 OpenGL 检查 `--script check_choices_and_wrong_trends.gd --visual`；日志 `.godot_appdata/workbench-check-y13cvacb/check.log`。覆盖逐次统计、复习不计错、旧记录迁移、保存重载、曲线独立、快速切换、相同数值重播、减少动态效果、两类原生菜单打开和选择、深浅色、1.2 与 1.68 显示比例及离页清理。
- 整套页面真实渲染 `--script check_minimal_design.gd --visual`；日志 `.godot_appdata/workbench-check-ey09cgwr/check.log`。
- 动效与答题业务风险回归 `--script check_motion.gd`；日志 `.godot_appdata/workbench-check-1c2x6gxa/check.log`。
- 工作台集成；日志 `.godot_appdata/workbench-check-34z0j39u/check.log`。

已查看 `choice-subjects-light.png`、`choice-subjects-dark.png`、`choice-subjects-large-text.png`、`choice-progress-light.png` 与 `wrong-trends-marxism.png`（均在 `outputs/minimal-design/`），确认菜单文字清晰、主题一致、长标签完整、科目曲线与夹具数据对应。专项使用实际鼠标输入打开菜单、原生选择信号验证筛选，不声称完成真人键盘全流程。所有检查使用隔离存档；`git diff --check` 通过。

## 2026-10-27 右侧题号列表与 F8 专注布局

`scripts/minimal_quiz_view.gd` 将题号栏固定到答题区域右侧，分隔线移至栏左边；题干和底部操作区保持原宽度与留白。窄窗口延续按需展开的行为，改为从右侧覆盖显示，原题号点击、输入跳转、标记和隐藏按钮继续有效。

F8 仅在答题页切换 `distraction_free` 状态，隐藏/恢复侧栏和顶部栏，并重新排布原控件来利用腾出的宽高。未重新加载题目或重建输入区，保留当前题号、作答状态、草稿、计时基准及题号栏开关。按键在文本控件处理前响应，忽略自动重复；若焦点在被隐藏的导航/顶部按钮上，隐藏时释放，恢复且无其他控件占用焦点时还原。主题重建与窗口/字号调整保留专注状态，新练习以普通布局开始。

- 新增专项 `--script check_quiz_focus.gd --visual`，PASS / 0 failures；最终日志 `.godot_appdata/workbench-check-br4ib_um/check.log`。通过原生鼠标输入选择右侧题号、键盘事件触发 F8/F9，检查左右位置、区域扩展、再次恢复、长按、焦点、题号跳转、答案与统计不变、计时基准、填空/代码编辑草稿、窄窗口与大字号及页面作用范围。
- 专项 headless 检查，PASS / 0 failures；日志 `.godot_appdata/workbench-check-g46_5nd1/check.log`。
- 整套页面真实 OpenGL 回归 `--script check_minimal_design.gd --visual`，PASS / 0 failures；日志 `.godot_appdata/workbench-check-md4eoca4/check.log`。
- 已查看 `outputs/minimal-design/quiz-right-list.png`、`quiz-focus.png`、`quiz-focus-dark.png`、`quiz-right-list-narrow.png`、`quiz-focus-large-text.png`，确认普通布局和专注布局、底部按钮、右侧列表与深浅色渲染。所有检查使用隔离存档，未修改用户学习记录；`git diff --check` 通过。

## 2026-10-27 专注快捷键改为 F6

用户报告 F8 在 Godot 编辑器调试运行时会停止程序。前一轮独立运行检查未覆盖编辑器的停止快捷键监听，不能据此宣称 F8 在编辑器调试环境下无冲突。按用户最新指定，将 `minimal_quiz_view.gd` 的专注快捷键改为 F6，README 和专项检查同步更新；未修改 Godot 编辑器的快捷键或其他设置。使用时应让答题窗口获得焦点。

专项检查现在同时向 Window 的输入信号和页面输入链发送按键，覆盖 F6 隐藏/恢复、重复按键、文本编辑焦点与原答题状态。前一节的 F8 检查记录仅代表当时的独立运行结果，当前生效快捷键为 F6。

`--script check_quiz_focus.gd --visual` 复测 PASS / 0 failures，日志 `.godot_appdata/workbench-check-nt0wkf9f/check.log`；本次使用独立进程和隔离存档，未连接编辑器远程调试器。`git diff --check` 通过。

## 2026-10-27 移除答题页解析与标记

按用户要求，删除 `minimal_quiz_view.gd` 中的“解析”和“标记”按钮、回调、标记状态、题号角标及标记图例。题号栏隐藏后，“题号列表”入口靠右对齐，不再为标记按钮留位置；底部保留上一题、下一题和加入/移出错题库。提交后的答案反馈和编程题原有参考代码入口继续由原答题逻辑负责。

README 同步更新，既有页面、F6 和动效检查删除已移除功能的调用。已查看 `outputs/minimal-design/quiz-right-list.png`，确认右上角、底部及题号图例中的相应入口均已移除。

回归均 PASS / 0 failures：F6 与答题布局真实渲染 `--script check_quiz_focus.gd --visual`（`.godot_appdata/workbench-check-6il6xvd8/check.log`）；动效和答题业务 `--script check_motion.gd`（`.godot_appdata/workbench-check-3rdigzy1/check.log`）。使用隔离存档，`git diff --check` 通过。

## 2026-10-27 错题按钮前景反馈与普通答题字号

`ui_feedback.gd` 增加仅由错题库按钮启用的 `foreground_only_feedback`：悬停、键盘聚焦和按下时通过原有时长过渡文字/图标强调色，按钮底色保持主题页面底色，并移除该按钮的焦点阴影叠色。加入/移出错题库后文字和图标保持一致，已加入状态不再使用浅蓝底块。其他按钮沿用原反馈方式。

`minimal_quiz_view.gd` 将普通模式题干基础字号从 30 调为 26、选项从 26 调为 24，配合较紧凑的行距、间距和 72 高度的选项；F6 专注模式保留原 30/26 字号与 80 高度。共享排版函数在刷新、模式切换和窗口调整时应用，仅改变控件排版，保留输入、答题状态与字体缩放设置。字号常量及使用说明已补入 README。

专项检查增加深浅色下悬停、聚焦、按下、已加入状态的实际背景像素对比，以及加入/移出后的图标和文字颜色恢复检查。检查发现同帧移出错题库再失焦会使延迟绑定捕获旧强调色，已将该按钮最终状态绑定改为即时完成，避免颜色滞留。

最终专项真实 OpenGL 检查 `--script check_quiz_focus.gd --visual`：PASS / 0 failures，日志 `.godot_appdata/workbench-check-p6d1g8kc/check.log`；公共动效与答题业务回归 `--script check_motion.gd`：PASS / 0 failures，日志 `.godot_appdata/workbench-check-svjebycz/check.log`。已查看 `wrong-button-light.png`、`wrong-button-dark.png`、`quiz-normal-long-question.png` 和 `quiz-focus-long-question.png`（位于 `outputs/minimal-design/`）；普通模式下第 168 题的四个选项及提交按钮可完整显示。所有检查使用隔离存档；`git diff --check` 通过。

## 2026-10-27 页面切换卡顿诊断

新增 `tools/profile_page_switches.gd`，使用隔离存档及真实 OpenGL 窗口，在同一进程依次测量初次进入、再次进入、关闭动效三组页面。记录资源读取、场景实例化/ready、ready 后首帧间隔与后续帧间隔。没有修改业务页面或动效参数；当前文件中的 `DATA = 1.70` 保持原值。日志：`.godot_appdata/workbench-check-0q6d165t/check.log`。数值是本机本次诊断窗口结果，非正式导出包基准。

再次进入且动效开启时，工作台/总题库/错题库/资源页的场景进入约 83–123 ms，紧随的第一帧间隔约 301–356 ms；收藏空页约 50 + 118 ms。马克思主义答题页约 57 ms 资源读取 + 798 ms 进入 + 867 ms 首帧；Python 答题页约 58 + 1834 + 1280 ms。关闭动效后分别仍约 61 + 771 + 903 ms、56 + 1770 + 1202 ms。后续 45 帧的间隔中位数约 4.2 ms，主要卡顿集中在切页边界。

代码证据：每次导航 `change_scene_to_file` 销毁并重新构造页面；每页重新建立 4 倍过采样字体、主题和侧栏；答题页先构建旧 UI 的题号 ItemList，再构建新 UI 的全部题号 Button 及交互节点，隐藏的旧 UI 仍保留；题库已有 StudyStats 缓存，但答题页仍重复解析 JSON 并深拷贝。诊断中马克思主义答题页共约 804 节点、Python 页约 1952 节点（含自动加载）。这些是可定位的重复工作，但各项独立耗时未逐一拆分，不能将全部停顿归因于某一项。

建议优先复用字体/主题与共享页面框架、让题号列表只创建可见区域控件、避免旧 UI 和重复题库处理，再按同样诊断对比。减少动画时长可以改变观感，但本次关闭动效对比表明不能解决主要切页停顿。

## 2026-10-27 五项加载优化完成

1. `ui_resources.gd` 作为自动加载单例持有常规/粗体字体、默认主题和图标纹理，保留 4 倍过采样与 mipmap，页面复用同一字体资源及其字形缓存。
2. `minimal_quiz_view.gd` 用逻辑行和位置表表示全部题号，只为视口及上下缓冲行分配按钮/标题池。滚动复用控件；远距离跳题、分组标题、答题状态、错题删除、主题重建和 F6 布局仍有效。方向键、Home/End、PageUp/PageDown 可以移动到池外题号，再按 Enter/空格选择。专项检查将 890 题来回跳至首尾和中部，验证按钮映射与池规模小于 150。
3. `Quiz.tscn` 移除旧头部、卡片、ItemList 等隐藏结构；控制器只初始化实际使用的答题控件，取消旧题号循环、旧调色和重复刷新。判题、错题存档、经验、代码运行及草稿逻辑保留。真实截图检查发现返回按钮可能先被原尺寸图标撑大，已提前启用图标缩放并在布局时固定点击范围，新增顶部范围断言。
4. `StudyStats` 统一完成题库读取和校验；答题控制器直接引用缓存题目字典，仅浅复制可增删/重排的题目数组与选项数组。自动化检查确认作答、选项乱序和错题操作不会修改缓存题库。
5. `PageRouter` 复用侧栏、PackedScene 资源及最多 4 个非当前常用页面；总题库/错题库分开缓存，答题与文章详情不缓存。离页后控件脱离场景树并停止处理输入，返回恢复搜索、筛选和滚动位置，并更新学习/错题数据；主题重建推迟到重新显示，日期变化会刷新错题趋势。缓存采用最近使用顺序淘汰，退出时释放离树节点。

动效参数保持 `TAB_UNDERLINE = 0.70`、用户已调整的 `DATA = 1.70`。离页时结算动画；已 kill 的 Tween 转绑到常驻管理器，以便引擎清理其队列，避免绑定离树缓存节点后残留。完成回调只移除自己的动画记录，不覆盖同属性的新动画。[Godot Tween 绑定节点行为](https://docs.godotengine.org/en/4.6/classes/class_tween.html#class-tween-method-bind-node)与隔离回归共同用于核对这一边界。

最终计时日志：`.godot_appdata/workbench-check-3md5_w5_/check.log`；优化前为 `.godot_appdata/workbench-check-0q6d165t/check.log`。同一台电脑、Godot 4.6.2、OpenGL 兼容渲染、1600 × 984 窗口、相同页面访问序列、隔离存档，优化后走实际 `PageRouter` 路径。以下取第二轮、动效开启，合计为资源加载 + 页面进入 + ready 后首帧间隔，属于加载诊断近似值，不等同于完整动画结束时间。

| 页面 | 优化前合计 | 优化后合计 |
| --- | ---: | ---: |
| 总题库 | 453 ms | 54 ms |
| 错题库 | 439 ms | 24 ms |
| 河工开物 | 396 ms | 23 ms |
| 我的收藏 | 169 ms | 21 ms |
| 马克思主义原理答题 | 1,722 ms | 204 ms |
| Python 答题 | 3,172 ms | 211 ms |
| 从答题返回工作台 | 440–478 ms | 61–70 ms |

本轮序列内首次进入马克思主义答题页约 793 ms，之后首次进入 Python 约 350 ms；首次字体/图形资源初始化仍有成本，不能把重复访问结果当作冷启动承诺。答题页场景树节点监测值分别从 804 / 1952 降至 224 / 232；不包含离树缓存的节点。后续帧间隔中位数本轮约 8.3 ms，基线约 4.2 ms，因此结果用于比较大幅切页停顿改善，不作为严格的渲染吞吐基准或导出包性能声明。

验证使用隔离存档，未读取或改写用户的真实练习记录：

- 缓存、虚拟题号、键盘导航、资源详情返回、主题延迟更新、数据刷新、缓存上限与题库不变性：`check_loading_optimization.gd`，PASS，`.godot_appdata/workbench-check-hfvdvfo_/check.log`。
- 公共动效、判题、保存失败恢复和 Python 执行：`check_motion.gd`，最终 PASS，`.godot_appdata/workbench-check-_dhjvoxf/check.log`；确认无活动或遗留 Tween 队列。
- 全页面真实 OpenGL 渲染：`check_minimal_design.gd --visual`，PASS，`.godot_appdata/workbench-check-efk9e5fb/check.log`；最终答题布局、返回按钮点击范围、F6、长题、深浅色、错题按钮像素、草稿与窄窗口：`check_quiz_focus.gd --visual`，PASS，`.godot_appdata/workbench-check-_0l76q1c/check.log`。测试窗口移到桌面外并设置不获取系统焦点，仍渲染真实 OpenGL 帧，测试通过 Viewport 注入鼠标/键盘事件。
- 趋势/进度展开：`check_data_reveal.gd`，PASS，`.godot_appdata/workbench-check-c6jk0s15/check.log`；统一选择框与独立错题趋势：`check_choices_and_wrong_trends.gd`，PASS，`.godot_appdata/workbench-check-6ey0v3v4/check.log`。
- Python 890 题、实际代码运行、草稿、错题与其他五门课程回归：PASS，`.godot_appdata/python-check-83bxhzgl/check.log`；MATLAB 505 题与模式/判题/错题持久化：PASS，`.godot_appdata/matlab-check-3mhqgw8j/check.log`；C++ 402 题、71 道输出题与逐题判题/错题移除：PASS，`.godot_appdata/cpp-check-fv48g9fb/check.log`。旧检查访问隐藏标题/ItemList 的断言已更新为实际显示控件与虚拟列表总数。

已查看最终 `quiz-right-list.png`、`quiz-normal-long-question.png`、`quiz-focus-dark.png`，并检查全页面截图中的题号栏、窄窗口和错题卡片。`git diff --check` 通过。加载检查默认超时增至 240 秒，可用 `--timeout` 调整；这仅影响自动化检查，不影响应用加载或动画时长。

## 2026-10-31 赠送 / 换卡弹窗视觉核对

final result: passed

### 来源与证据

- source visual truth：用户 ZIP 内 `01_赠送好友弹窗_最终视觉基准.png`；本机解压为 `.godot_appdata/gift-dialog-reference-20261031/01-reference.png`。`02-before.png` 用于原收藏页背景和素材核对。
- implementation：`outputs/card-transfer-validation/gift-selected-page.png`、`gift-selected.png`、`exchange-select.png`、`exchange-review.png`、`exchange-dark.png`。
- 全景对照：`.godot_appdata/transfer-dialog-validation/comparison-full.png`；局部原尺寸对照：`comparison-dialog.png`。两者均将源图和实际渲染放入同一对比图，未重采样源像素。已打开并检查这些对比图及实机退出动画。
- viewport：主对照 1672×941；原图包含 Windows 标题栏，实机捕获为 Godot 客户区。以弹窗裁切区域比较尺寸，不把系统标题栏导致的垂直偏移视为布局错误。
- 源弹窗裁切约 526×772；实机约 522×781；实机逻辑尺寸约 500×748，页面缩放约 1.045。不存在 CSS 尺寸，此项目为原生 Godot。
- state：浅色、空间站、拥有七张、四位好友、选择第一位、赠送一张。账号/好友为隔离数据，原素材及实际库存规则保持真实来源；没有把参考图中的演示身份写进应用。

### 比较与修复记录

1. [P1 已修复] 原赠送和换卡窗口未跟随页面 UI 比例，内容整体偏小。改为相同排版和缩放路径，最终普通窗口及 2560×1500 截图中的标题、卡图与操作区均清楚可读。
2. [P2 已修复] 初版数量值改变后，原生 SpinBox 的延后文本刷新可能覆盖新值。分离手工输入提交与程序步进，核对页及返回修改均保留 2 张 / 3 张的测试条款。
3. [P2 已修复] 退出时复制控件引起重新排版，文字、头像被纵向压扁。改为原 Window 内容直接淡出；`motion-close-03.png` 及后续连续帧保持同一比例，关闭结束无遮罩或窗口残留。
4. [P2 已修复] 搜索无结果时可能保留不可见的旧选择。现在清除不在当前结果中的选择，确认禁用；搜索连续输入只发出一次最终查询。
5. [P2 已验证] 125% 父视口下核对实际像素缓冲而非仅看逻辑尺寸。实测渲染为 625×935，普通逻辑布局仍为 500×748；实际鼠标输入选中正确好友，交互后仍维持对应像素分辨率。

### 五项保真检查

- Fonts / typography：采用项目原 Microsoft YaHei UI 字体及四倍过采样；标题 24、分组 18、正文 16、ID 14 的层级清晰。长昵称和 ID 可截断，完整身份进入可访问文本；数字控件按实际文字宽度适配。
- Spacing / layout：摘要、搜索、紧凑头像行、数量、两颗底部按钮的次序及对齐与参考一致。换卡扩展为两组卡牌摘要和原有核对步骤；600×680 仍可滚动内容并访问固定底栏。
- Colors / tokens：工大蓝 `#092C87`、白底、浅蓝选择态、细灰分隔线；深色继承原主题。背景使用原项目单层遮罩，未改变其他页面布局。
- Image quality：七张原始卡图哈希一致，等比显示并保留 mipmap 过滤。头像复用原圆形裁切组件；没有从截图提取示例头像。原图比例与参考缩略图的细微差别属于素材保真要求。
- Copy / content：所有好友、公开 ID、季名称及库存来自现有状态层；赠送数量、剩余量和保留一张规则同步。换卡明确区分“我送出 / 我想换取 / 我获得”，发送和确认均保留既有权限与固定条款。

### 验证结果与边界

32 项实际渲染/交互检查通过；赠送/换卡浅深色及大视口、125% 的五组边缘像素检查均为 0 异常。收藏专项通过，社交专项 104 项通过。没有残留的 P0/P1/P2 问题。

可接受差异：取消按钮采用现有描边样式；单选采用项目自带圆点图标；中文字体抗锯齿和动态好友资料与参考 PNG 不逐像素相同。素材未裁切成参考中的示例比例。这里验证的是桌面客户端和隔离服务模型，未向真实好友发送赠送/换卡，也未改变移动端工程。

final result: passed
