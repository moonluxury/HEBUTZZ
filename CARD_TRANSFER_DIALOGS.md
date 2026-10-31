# 赠送与换卡弹窗 · 2026-10-31

赠送弹窗依据用户资料包中的最终视觉稿实现，换卡的选择、核对、确认和结果页沿用同一套字体、卡牌摘要、间距、按钮与圆角。

## 界面与清晰度

- 赠送：标题、原始卡图摘要、好友搜索、圆形头像单选行、横向数量步进器、保留一张的说明、固定底部取消/确认按钮。
- 换卡：双方身份、送出和换取的原始卡图、数量选择、独立条款核对步骤；返回修改保留草稿，未知提交结果继续使用原操作标识。
- 共享项目字体和工大蓝；字体保留已有四倍过采样，卡图使用原始 1145×1374 资源及 mipmap 过滤。七张源图哈希与仓库原图一致。
- 按页面实际缩放设置弹窗排版。在父视口放大时，仅提高这两个嵌入弹窗的渲染分辨率，逻辑坐标及点击区域不变。125% 场景实测 500×748 逻辑窗口对应 625×935 像素缓冲，鼠标选中位置正确。
- 短窗口内部滚动，确认按钮固定。打开约 180ms、关闭约 120ms；原弹窗直接淡出，关闭期间文字和图片保持原比例，不再复制控件生成变形的退出画面。

字体及 DPITexture 的过采样语义参考 [Godot 多分辨率说明](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html#font-and-image-oversampling)；实际坐标、像素缓冲和最终合成均以 Godot 4.6.2 的运行检查为准。

## 交互与业务

复用 `CollectionStore`、`SocialStore` 及已有服务接口。赠送仍须至少保留一张；换卡使用服务返回的可交换数量，并保留发送前核对及接收方确认。没有发起真实账号之间的测试赠送或换卡。

搜索加入 250ms 防抖和过期结果隔离，昵称/公开 ID 来自好友服务。空结果清除旧选择并禁用确认。数量步进器区分用户输入和程序值更新，修复快速加减后核对数量被旧文本覆盖的问题。关闭或切换账号后的迟到回调不能再次提交；关闭后焦点回到赠送入口。

## 文件

- `scripts/card_transfer_ui.gd`：仅供赠送和换卡使用的布局、原图摘要、好友行、步进器及渲染密度。
- `scripts/collection_gift_dialog.gd`：赠送界面、搜索和数量交互。
- `scripts/trade_dialog.gd`：复用原社交对话框业务方法的换卡界面。
- `scripts/my_collection.gd`、`scripts/my_friends.gd`：弹窗入口、快速重开和焦点恢复。
- `tools/check_transfer_dialogs.gd`、`tools/check_collection.gd`：实机画面、像素合成、交互及回归检查。

## 验证

- `check_transfer_dialogs.gd --visual`：32 项通过，覆盖普通/窄窗口、深色、2560×1500、125% 缩放、实际鼠标命中、搜索防抖、数量、核对返回、退出动画与快速重开。
- 五组最终合成边缘检查均为 0 异常像素：赠送浅色、换卡浅色、换卡深色、赠送大视口、赠送 125%。
- `check_collection.gd`：通过，覆盖赠送成功、失败、重复提交、保留一张、库存变化、结果恢复及关闭清理。
- `check_social.gd`：104 项通过，覆盖换卡视角、固定条款、权限、丢失回包和重复交割防护。使用隔离服务模型，不代表本轮重测了生产数据库。

实机截图：[赠送](outputs/card-transfer-validation/gift-selected.png)、[搜索无结果](outputs/card-transfer-validation/gift-empty.png)、[换卡选择](outputs/card-transfer-validation/exchange-select.png)、[换卡核对](outputs/card-transfer-validation/exchange-review.png)、[深色](outputs/card-transfer-validation/exchange-dark.png)。完整视觉比较记录见 `design-qa.md`。

## 2026-11-01 · 换卡下拉菜单补齐

修复送出、换取选择框展开后仍使用 Godot 默认深灰菜单的问题。两个选择框接入已有 `UiMotion.bind_button` / `Styles.popup`，统一菜单背景、文字、边框、行距与悬停色，并使用共享字体和 DPI 矢量箭头、单选标记。保留原生键盘导航和选中行为。

隔离实机 `check_transfer_dialogs.gd --visual` 的 68 项检查通过；新增展开态检查覆盖两个选择框、深色、窄窗口及 125% 缩放，实际鼠标打开、方向键选择和回车收起均正常。125% 下拉菜单 372×282 逻辑尺寸对应 465×353 像素。六组原有弹窗边缘检查均为 0 异常像素。

展开态截图：[浅色](outputs/card-transfer-validation/exchange-dropdown-light.png)、[深色](outputs/card-transfer-validation/exchange-dropdown-dark.png)、[125% 缩放](outputs/card-transfer-validation/exchange-dropdown-dpi.png)。
