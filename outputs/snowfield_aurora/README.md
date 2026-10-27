# 雪原极光

一枚沿用原标志结构的冬季限定 Logo。冷白与霜蓝构成主体，局部薄雪和霜晶留在轮廓内部，青绿与蓝紫沿原轨道流动。展示背景与核心标志分开保存。

当前为 **v3 连续斜边重建版**。上一次只处理了交界的分色采样，仍保留了上下边缘的细小偏折。此次用一条直线贯穿主体左侧斜边，后景轨道与主体在同一次 32×32 子像素采样中完成遮挡。边缘不再由两段不同斜率的路径拼接。

此次按修复要求调整了斜边窄带内的透明覆盖率，原始 Alpha 变化共 6609 个像素，窄带外变化为 0。实际半覆盖边界对同一直线的最大测量偏差约 0.0894 像素。记录见 `source/straight_edge_validation.json`；与上次版本对照见 `previews/straight_edge_comparison_v3.png`。旧修复记录仅作为历史保留，不代表当前结果。

## 正式交付

| 文件 | 用途 |
| --- | --- |
| `final/logo_snowfield_aurora_transparent.png` | 2048×2048 透明核心版，无背景、无外发光 |
| `final/logo_snowfield_aurora_presentation.png` | 同一核心标志与独立雪夜背景的合成展示版 |
| `final/logo_snowfield_aurora_transparent_v3.png` | 当前透明版的明确版本命名副本 |
| `final/logo_snowfield_aurora_presentation_v3.png` | 当前展示版的明确版本命名副本 |
| `previews/logo_snowfield_aurora_512.png` | 512px 深夜蓝底预览 |
| `previews/logo_snowfield_aurora_256.png` | 256px 深夜蓝底预览 |
| `previews/logo_snowfield_aurora_128.png` | 128px 深夜蓝底预览 |
| `previews/core_transparent_*.png` | 对应尺寸的真正透明小图 |
| `previews/structure_comparison.png` | 原始轮廓、无纹理基础分色和最终核心对照 |
| `previews/edge_checks.png` | 深蓝、浅灰、棋盘格三种底色的边缘检查 |
| `previews/frost_detail_100percent.png` | 原尺寸薄雪与霜面细节 |
| `source/config.json` | 集中的色板、材质、背景参数与固定随机种子 |
| `source/masks/` | 五类部件蒙版、原坐标分区、锁定轮廓 |
| `source/layers/` | 无纹理基础版、材质控制蒙版、部件位图和独立背景层 |
| `source/validation.json` | 透明度、部件合成、同体合成的实际检查结果 |

## 母版与排版

使用的原图是：

`E:\zhengzhi\outputs\HEBUT卡背_团队Logo版_20261019\02_视觉素材\team_logo.png`

原图副本保留为 `source/original_logo.png`，原文件未覆盖。它是 1254×1254 RGBA 位图。检查了当前目录已有 SVG 和横版图，未找到可替代它的团队标志矢量源；带棋盘格的横版图没有参与抠图或蒙版制作。

有效范围通过 Alpha≥8 定位，裁框为 `[21, 235, 1230, 1040]`。裁框外只有 Alpha 不超过 7 的极淡残留；框内像素与透明度全部保留。之后用同一 Lanczos 流程等比排版为 1516×1009，位于 2048 画布的 `(266, 519)`，有效宽度约 74.02%。

`original_cropped.png` 只裁去空白；`original_aligned.png` 是与交付同尺寸、同位置的原图参照。`geometry_reference.png` 是修复左侧斜边后的几何母版。最终核心的 Alpha 取自修复后母版；霜晶、薄雪和映色本身不改变 Alpha。原始图仍完整保留，未覆盖。

## 色板与主要控制

冰雪白 `#F4FAFF`、霜蓝白 `#DCEEFF`、冰川蓝 `#91BCE0`、冷夜蓝 `#294566`、极光青绿 `#6BDDBB`、极光蓝紫 `#8995E8`、背景夜蓝 `#081421`、背景蓝灰 `#132A3D`。

常用设置都在 `source/config.json`，无需逐个修改绘图坐标：

| 想调整的内容 | 配置项 |
| --- | --- |
| 主体颜色 | `palette.body`、`palette.snow`、`palette.glacier` |
| 轨道极光色 | `palette.aurora_green`、`palette.aurora_violet`、`orbit.aurora_strength` |
| 局部霜晶强度 | `material.frost_strength` |
| 薄雪强度 | `material.thin_snow_strength` |
| 表面细磨砂 | `material.surface_grain_strength` |
| 极光映色 | `material.aurora_reflection_strength` |
| 背景主极光 | `background.aurora_strength` |
| 背景辅带 | `background.secondary_aurora_strength` |
| 底部雪雾 | `background.snow_haze_strength` |
| 雪点数量、强度 | `background.snow_points`、`background.snow_point_strength` |

强度设为 0 可关闭相应效果。固定种子 `20261020` 的表面、霜晶、雪点使用独立随机序列；调整颜色和强度不会重新随机分布颗粒。

## 实际运行环境与命令

使用 Python，依赖 **Pillow 12.3.0、NumPy 2.3.5**，没有三维框架、外部渲染器或联网依赖。版本记录在 `source/requirements.txt`。

在本机使用以下命令构建和验证：

```powershell
& 'C:\Users\Legion\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'E:\zhengzhi\outputs\snowfield_aurora\source\prepare.py'
& 'C:\Users\Legion\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'E:\zhengzhi\outputs\snowfield_aurora\source\build.py'
```

`build.py` 默认保留现有部件蒙版，只重新绘制、输出和验证；`--prepare` 才会根据原始图和分区数据重建蒙版。尺寸或裁框参数变动后需要重建。

在已有相同依赖、并将 Python 配到命令行的环境中，可从本文件所在目录运行：

```powershell
python source/build.py
```

也可用简短选项调整单项，选项会写回中央配置文件：

```powershell
python source/build.py --frost 0.30 --snow 0.65 --reflection 0.05
python source/build.py --body-color '#DCEEFF' --orbit-green '#6BDDBB' --orbit-violet '#8995E8'
python source/build.py --background-aurora 0.10 --snow-points 8
```

以上第二组属于可用参数示例；实际交付的参数以 `config.json` 为准。每次运行会在 `progress.md` 追加阶段记录。

## 蒙版与分层说明

`body.png` 包含主体和向火箭延伸的主体细线；`orbit_front.png`、`orbit_back.png` 只包含原图可见的轨道；`dot.png`、`rocket.png` 分别控制圆点和火箭构件。没有补画被主体遮住的轨道。

五张蒙版在抗锯齿处采用归一化分配，合计恰好等于修复后的几何 Alpha。`edge_geometry.py` 对左侧斜边及其轨道交界进行连续路径采样，其余分区来自原始母版。它们是实际渲染使用的灰度蒙版。`part_*.png` 便于单独查看部件，边缘处不宜简单叠加来替代加权合成；精确的最终合成由脚本完成。

背景底、主极光、辅极光、雪雾、雪点均是独立 PNG。`background_complete.png` 是它们的合成。展示图直接将核心透明 PNG 放在该背景上，位置和本体外观完全共用。

## 已验证与真实限制

- 最终核心与修复后的几何母版 Alpha 逐像素比较，误差为 **0**；授权斜边窄带以外，相对于原始 Alpha 的变化像素数为 **0**。
- 五类部件蒙版之和与修复后的几何 Alpha 的最大误差为 **0**。
- 展示版与「独立背景 + 同一核心 PNG」的最大像素误差为 **0**。
- 用全部八个公开命令行选项按交付参数重新生成，两份正式 PNG 的文件哈希完全一致，记录见 `source/reproducibility.json`。
- 已查看深蓝、灰底、棋盘格以及 512、256、128px 预览；保留了原始细窄间隔，没有外发光填缝。
- 这是基于原始位图的高分辨率排版、材质处理和局部边界重建，**不是整枚标志的原生矢量重制**。放大没有恢复原图中不存在的原生细节。
- 主展示环境为深色。浅灰预览用于检查边缘和适配，白底上的冷白主体会相对弱一些，没有为此增加厚外框。
