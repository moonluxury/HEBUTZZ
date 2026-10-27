# 工作台美术素材（停用版本）

**当前使用 `original/` 子目录中由原版 SVG 直接导出的 11 个图标，形状和配色均保留。** 详见 [当前素材说明](original/README.md)。

下面的立体图标已停用，仅留存追溯。工作台不再引用本目录根部的 PNG。

以下 11 个图标均通过 ImageGen **逐个单独生成**，每个文件为独立的 1254 × 1254 RGBA 透明 PNG。源文件保持原始分辨率；Godot 使用 512px 导入尺寸及 mipmaps，适配约 38–77 个设计像素的显示区域。

| 文件 | 用途 |
| --- | --- |
| nav_home.png | 工作台：蓝色立体房屋 |
| nav_bank.png | 总题库：蓝色书本与金色书签 |
| nav_wrong.png | 错题库：带白色叉号的蓝色夹板 |
| nav_kaiwu.png | 河工开物：蓝色资料箱 |
| nav_spirit.png | 我的精灵：蓝色人物图案 |
| nav_legacy.png | 原版首页：蓝色窗口图案 |
| stat_today.png | 今日学习：金色清单 |
| stat_progress.png | 学习进度：青绿色递增柱形 |
| stat_days.png | 累计学习：蓝色勾选日历 |
| stat_total.png | 题库总数：蓝色加号圆牌 |
| action_arrow.png | 开始 / 继续学习：白色立体箭头 |

`manifest.json` 记录实际图片尺寸、色彩模式及透明通道范围。

学习横幅仍单独存放在 `../study_hero.png`，品牌图标使用既有的 `../../branding/hegong_zhigu_icon.png`，两者均未修改。界面文字和实时图表不烘焙进图片，继续由 Godot 渲染。第一版 SVG 图标留存于 `../icons/`，当前工作台使用由这些源文件直接导出的 `original/` 图标。
