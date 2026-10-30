# 头像设置：原素材、预览与确认保存

2026-10-29。沿用 Godot 原生 Window/Control、项目主题、ProfileStore 和现有 BackendProvider。点击个人中心的大头像打开，右侧不增加独立入口。

## 最终布局

按用户提供的参考排版，基准尺寸为 840×900 个逻辑单位，预览直径 144，候选直径 136，默认头像与原七张卡牌按两行四列排列。弹窗跟随主页面的实际 UI 缩放，同时根据父窗口可用空间居中适配；主体可滚动，取消与保存始终在固定底部。标题、说明、预览、细分隔线、网格和底部操作分别使用原生容器布局。

后续真实窗口截图暴露了旧检查未覆盖的问题：项目根视口是 2560×1680，主页面还对自身 canvas 进行缩放，旧弹窗保持 1 倍，导致实际显示明显偏小。现在使用 Window 的 Canvas Items 内容缩放，按页面比例设置 `content_scale_factor`，并在父视口坐标中计算尺寸和边距。使用项目原视口配置、2560×1500 客户区实测，弹窗逻辑尺寸约 1488×1594，屏幕可见约 1329×1423 像素，八个候选完整可见。相关 API 语义见 [Godot Window 文档](https://docs.godotengine.org/en/stable/classes/class_window.html#class-window-property-content-scale-factor)。

头像使用动态方形单元，横纵间隔共用 24 个逻辑单位；窗口变窄时按视口可用宽度减少列数，避免旧四列最小宽度把弹窗撑出边界。右上角关闭按钮保留 44×44 点击区，内部为居中的矢量叉号，去掉叉号下方多余的焦点横线。默认蓝色头像继续引用原 SVG，仅把导入倍率提高到 4 倍并生成 mipmaps，源 SVG 没有改写。

候选没有名称文字、方形底板、上传入口或“重新读取”按钮。选中圆环和蓝色勾选由独立绘制层显示，不改写或染色源图片。键盘焦点不再绘制额外圆环或按钮下划线，方向键和空格操作保留；弹窗圆角外为透明，不显示矩形底色。未登录允许预览全部原图；已登录仍执行原有拥有资格，真实不可用卡牌保留灰显/禁用语义。错误或缺失状态单独提示，不把占位图写回账户。

## 原资源与稳定 ID

目录来源为 `data/collection_catalog.json`。预览和候选共用 `profile_avatar.gd` 与现有圆形裁切着色器；原图尺寸均为 1145×1374。默认头像使用原 `assets/profile/default-avatar.svg`，持久化值仍为空字符串，没有新增虚构头像 ID。

| 顺序 / ID | 原资源 |
| --- | --- |
| 默认 / 空字符串 | `assets/profile/default-avatar.svg` |
| `0001` | `assets/collection/artworks/01_rocket.png` |
| `0002` | `assets/collection/artworks/02_satellite.png` |
| `0003` | `assets/collection/artworks/03_space_station.png` |
| `0004` | `assets/collection/artworks/04_astronaut.png` |
| `0005` | `assets/collection/artworks/05_spaceplane.png` |
| `0006` | `assets/collection/artworks/06_radio_telescope.png` |
| `0007` | `assets/collection/artworks/07_ringed_planet.png` |

八份源文件与改动前的 SHA-256 一致。没有从参考截图提取图片，没有重绘、复制另一套素材、重编号或修改目录。

## 文件与接入

- `scripts/avatar_settings_dialog.gd`：独立弹窗、草稿、原值、预览、固定底栏、单选与键盘操作、取消、登录返回、结果提示。
- `scripts/avatar_choice.gd`：原图及独立外圈/勾选绘制。悬浮不改变原图颜色或裁切。
- `scripts/personal_center.gd`：原头像入口分派到新弹窗；主页面和其他业务布局保持现状。
- `scripts/profile_dialog.gd`：移除旧的“点选立即保存”头像分支；其他资料与账号面板继续沿用。
- `scripts/profile_store.gd`：保留既有资料接口，增加头像专用提交、有限等待、未知结果核实与本次登录完成信号。
- `scripts/profile_avatar.gd`：只按明确匹配的本人稳定 ID 更新缓存中的本人头像；不覆盖其他用户。
- `scripts/backend_provider.gd`：复用现有账号密码登录窗口与 HTTPS RPC，新增头像操作封装及带本次流程标识的登录返回。请求身份由原会话确定。
- `backend/domain.py`：本地服务端补充默认头像重置与头像请求的幂等处理，复用已有账户锁和 operations 表，不新增数据库或消息系统。

点击候选只修改弹窗内的 `selected_avatar`，已保存值单独保存在 `saved_avatar`。取消、关闭及 Esc 不提交。成功后以规范响应更新 ProfileStore，关闭窗口并反馈一次“头像已更新”。只有此次明确发起的登录流程、返回的账号和会话代次均匹配，才保留候选；登录本身不会保存。

头像专用调用为 `save_avatar(account_id, avatar_card_id, request_id)`，适配到既有 `save_profile` RPC：`{patch: {}, avatar_card_id, avatar_change: true, operation_id}`。空 ID 配合 `avatar_change: true` 才表示重置默认头像；旧 `save_profile(..., "")` 仍表示不修改头像。服务返回 `editable_fields.avatar_card_id.reset_supported=true` 后客户端才允许提交默认重置；旧服务缺此能力时保持禁用并说明原因。

每次实际提交固定原账号、卡牌 ID 和操作 ID。重复提交被拦截；未知结果先读取本人真实头像，匹配才确认成功，否则保留同一个未决操作供核实，禁止同时切到另一候选再次写入。HTTP 超时沿用 15 秒，状态层默认最多等待单次调用 20 秒；核实读取也有界。关闭已经提交的窗口不等于撤销持久化，迟到响应按账号代次丢弃。

## 验证与边界

```powershell
& 'C:\Users\Legion\AppData\Local\Python\bin\python.exe' tools/run_workbench_checks.py --godot 'C:\Users\Legion\Desktop\工具\游戏创作\Godot_v4.6.2-stable_win64_console.exe' --script check_avatar_settings.gd --visual
```

原 `check_card_avatars.gd` 入口转到同一新版专项。所有测试使用隔离存档、服务替身或真实客户端适配器的本地响应，显式禁用正式后端自动接入；没有修改真实账户或发送好友消息。

实际 OpenGL 专项 64 项通过：原资源/顺序、默认值、预览不提交、取消/重开、登录取消/失败/返回、现有登录窗口嵌套、显式重置、旧服务能力限制、失败重试、重复提交、未知结果、超时后的迟到提交、库存变化、账号隔离、本人缓存刷新、素材缺失、键盘、深色、小窗口固定底栏及真实控件 200% 画布渲染。个人中心 69 项、返回导航 31 项、社交 104 项回归通过；检查过程中发现的离页头像订阅错误已修正。源文件哈希校验为 8 项、0 修改。Python 服务端改动通过语法检查。

后续缩放修复后的最新 OpenGL 专项为 **69 项通过**，新增实际项目视口下的文字缩放、窗口占比、头像横纵等距、关闭图标居中且无横线、八个候选完整可见检查；返回导航 31 项再次通过。源文件哈希复核仍为 8 项、0 修改，只有默认头像导入参数变化。

运行截图在 `outputs/avatar-settings-validation/`：`01-signed-out-preview.png`、`02-authenticated-preview.png`、`03-dark-preview.png`、`04-narrow-footer.png`、`05-preview-200-percent.png`，以及反映用户实际视口比例的 `06-project-resolution-2560-page.png`。这些是 Godot 实际渲染，账户与库存为隔离测试状态；200% 图为实际控件在两倍画布中的渲染，不是把低分辨率截图放大。`scale-*` 文件仅为排查中间状态，不能当作最终效果。

**服务端边界：** 本轮仅修改本地工程，没有部署服务器补丁，也没有修改真实用户资料。已有登录与选取已拥有卡牌的资料接口继续复用。默认头像重置能力声明与操作 ID 幂等扩展需随 `backend/domain.py` 更新部署后启用。相关 PostgreSQL 回归断言已补入 `backend/tests/test_backend.py`，但本机没有 PostgreSQL/该隔离数据库，未执行新增数据库用例；不能把客户端隔离验证当作真实服务端事务验证。发布前应在既有 `*_test` 数据库运行这些用例。没有验证实体显示器 DPI 切换或真实输入法候选窗口的端到端行为。
