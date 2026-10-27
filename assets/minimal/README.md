简约风独立图标素材

参考：用户提供的简约风界面，采用对应的 Lucide 线性图标。
每个按钮图标均为单独的 384px 透明 PNG；source/ 保存原始 SVG 路径，未经形状改绘。使用 Godot SVG 渲染器导出白色遮罩，运行时统一着色。
品牌继续使用用户原有河流图标。界面文字全部由原生控件渲染，不嵌入图标。
来源：https://lucide.dev/icons/ · https://github.com/lucide-icons/lucide · 授权见 LICENSE。
再生成：Godot --headless --path . --script res://tools/export_minimal_icons.gd

Python 图标按参考采用 Tabler brand-python 原始轮廓；来源 https://tabler.io/icons/icon/brand-python ，授权见 TABLER-LICENSE。
PNG 开启 mipmaps，避免缩小显示时图标边缘出现锯齿。

收藏系列展开箭头 `collection-chevron` 为本项目单独绘制的圆角折线素材（2.5px 线宽、24px 设计尺寸），源文件位于 `source/collection-chevron.svg`，白色透明遮罩位于 `icons/collection-chevron.png`（384px）。运行时按页面文字颜色着色，以图标中心旋转 90° 表示展开，避免依赖字体中的箭头字符。旋转时长共用 `scripts/ui_tokens.gd` 的 `CHEVRON`，当前为 0.16 秒。

收藏想要标记使用本项目绘制的实心心形，源文件为 source/heart-filled.svg，白色透明遮罩为 icons/heart-filled.png（384px），运行时统一着为蓝色，叠放在列表卡牌图片右下角。
