# 原图标的独立素材

这 11 张 512 × 512 透明 PNG 直接由项目原有的 Bootstrap SVG 导出，路径几何未改动。它们是原版图标的独立栅格素材，不使用立体改绘、替换图案或新配色。

PNG 为白色透明蒙版；Godot 按原版颜色着色，浅色和深色模式均保留原逻辑。白色画布预览时图形可能不显眼，可在透明棋盘背景下查看。

| 文件 | 原图标 | 浅色界面配色 |
| --- | --- | --- |
| nav_home.png | house-door-fill，房屋 | #087FFF |
| nav_bank.png | journal-text，带行文的笔记本 | #586B9C |
| nav_wrong.png | clipboard-x-fill，叉号夹板 | #586B9C |
| nav_kaiwu.png | collection-fill，叠放资料 | #586B9C |
| nav_spirit.png | person-fill，人物剪影 | #586B9C |
| nav_legacy.png | grid-1x2-fill，分栏网格 | #586B9C |
| stat_today.png | clipboard-data-fill，带柱形的夹板 | #FFA600 |
| stat_progress.png | bar-chart-fill，三根柱形 | #12BFAF |
| stat_days.png | calendar-check-fill，勾选日历 | #087FFF |
| stat_total.png | plus-circle-fill，圆形加号 | #087FFF |
| action_arrow.png | arrow-right，细线右箭头 | 白色 |

来源保留在 `../../icons/`，许可证为该目录的 MIT `LICENSE`。`manifest.json` 逐个列出来源文件。使用 Godot 运行 `res://tools/export_workbench_icons.gd` 可按原图重新导出。
