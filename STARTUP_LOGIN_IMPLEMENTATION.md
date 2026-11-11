# PC 启动登录

PC 端正常启动后直接弹出既有账号登录窗口。登录完成前，背景页面不处理输入，侧栏和启动跳转请求等待认证成功。上次登录账号及一键登录继续保留，但每次启动均显示登录窗口，快捷登录仍需在线验证。

点击登录窗口的 X 或按 Esc 直接退出软件，没有退出确认框，也不增加“必须登录”等解释文字。登录失败保留原窗口。退出登录或会话失效后重新要求登录，不能以退出账号绕过限制；已登录时主动打开的其他账号设置窗口仍保持原关闭行为。

## 实现

- `scripts/backend_provider.gd`：正常 PC 启动启用登录要求，复用已有认证和会话接入；未登录时禁用当前页面，认证后恢复，取消时结束进程。
- `scripts/backend_login_dialog.gd`：取消结果增加内部 `cancelled` 状态，现有界面文字不变。关闭后立即清空密码，迟到响应不能重新登录。
- `scripts/page_router.gd`：等待登录时阻止导航和返回；认证后恢复此前请求的入口。

首页仍为 Workbench，未改动移动端或后端。`HEGONG_BACKEND_DISABLED`、隔离检查及 `--script` 工具入口继续用于开发验证；正常桌面启动不会跳过登录。

2026-11-11 修复点击“一键登录”后自动改高造成的灰角：问题来自分数缩放后的窗口合成矩形存在极小舍入差异，子窗口本身的透明四角检查无法发现。公共 `DialogSurface` 现会在尺寸变化后稳定该矩形；登录请求、上次账号记录、密码处理与失败重试逻辑不变。同类圆角弹窗统一覆盖。合成检查增加宽短窗口、验证中、验证失败、再次调整尺寸、注册切换和返回登录，不通过隐藏/重新显示窗口掩盖动态问题。

## 验证

- `check_dialog_compositing.gd --visual`：本次 OpenGL Compatibility 与 Vulkan Forward+ 各 102 个窗口状态通过，宽短窗口、分数缩放、125% 缩放和深浅色下，最终合成边缘异常均为 0；包括登录等待/失败/重试、改高、注册切换，以及资料、头像、赠送、换卡、想要清单、好友和充值弹窗。
- `check_startup_login.gd --visual`：18 项通过，覆盖自动弹窗、背景与跳转限制、失败重试、注册入口、快捷登录、重复提交、会话失效、关闭时清空密码及迟到结果隔离。
- `check_account_dialogs.gd`：53 项通过。
- `check_remembered_login.gd`：36 项通过。
- `check_startup_launch.py`：使用临时工程启动真实主场景和正式自动加载顺序，没有 `--script`；自动登录弹窗和 X 退出验证通过，测试地址不连接正式服务。
- `check_startup_login_exit.gd`：普通关闭、认证进行中关闭、Esc 三个独立进程均以 0 退出，未停留在主界面。延迟认证的隔离替身在进程退出时有 Godot ObjectDB 清理警告，不影响进程退出；迟到响应不能接入会话另有独立检查。

检查通过 `tools/run_workbench_checks.py --godot <Godot控制台程序> --script <检查脚本>` 运行；实际渲染增加 `--visual`。真实启动检查使用 `py -3 tools/check_startup_launch.py --godot <Godot控制台程序>`。退出场景由环境变量 `STARTUP_LOGIN_EXIT_CASE=close / busy / escape` 选择，全部使用独立 `workbench-check-*` 存档。

实际截图：`outputs/startup-login-validation/01-required-login.png`、`02-authenticated-entry.png`，均使用隔离测试资料。

灰角修复的等待/失败重试截图位于 `outputs/dialog-compositing-validation/`，同样使用隔离账号和模拟响应。
