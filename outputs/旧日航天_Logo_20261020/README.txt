旧日航天 · 双色旧油墨 Logo

最终文件
retro_aerospace_cream.png
  2048×2048，背景 #F1E8D7，完整展示图。
retro_aerospace_transparent.png
  2048×2048，与展示图位置、比例相同，缺墨处是真透明。
retro_aerospace_flat_cream.png / retro_aerospace_flat_transparent.png
  无做旧的蓝橙分色版本，方便核对分区。
previews/retro_aerospace_128.png
  128×128 缩小预览。
previews/ink_detail_100percent.png
  原尺寸局部预览，查看针孔和短擦痕。

配色与构图
海军蓝 #3C4D5D：字母主体、连接火箭的斜线、火箭、左下圆点。
砖橙 #B86140：原图实际可见的椭圆轨道。
奶油白 #F1E8D7：展示背景；透明版不把此颜色填进缺墨处。
标志依据原透明通道裁出有效范围，等比例放到 2048 方画布中央，有效宽度 1536，即 75%。
实际缺墨约 3.2%；轨道、火箭与圆点的做旧比宽阔主体更克制。
没有整体错版投影；仅在两处宽阔主体与轨道相邻的边缘加入约一像素的短小露底，不缩小原有间隙。

源文件与独立蒙版
source/original_logo.png：原始图像备份，原文件未覆盖。
masks/body.png：字母主体及蓝色斜向连接结构。
masks/rocket.png：火箭鼻锥、尾翼、前段连接。
masks/dot.png：左下圆点。
masks/orbit.png：可见轨道区域。
masks/navy.png：全部海军蓝区域的合并蒙版。
masks/silhouette.png：总体轮廓。
masks/wear.png：缺墨强度蒙版，黑色完整、白色完全缺墨、灰色部分缺墨。
四个分区蒙版位于同一 2048 画布；不以全局颜色替换来猜测橙色区域。
左侧轨道与主体相接的位置按原主体边缘分区，其他主体斜线仍归入海军蓝。
主轮廓使用原始透明通道；仅排除有效轮廓以外、与真实图形分离的极低透明度散点。

修改方法
1. 在 source/settings.json 中分别修改 colors.navy、colors.orbit、colors.cream。
2. wear_strength 控制整体缺墨目标强度，当前 0.033；wear_multipliers 控制各部分的相对强度。
3. wear_seed 决定纹理位置；固定此数值可重复输出相同版本。
4. 在 source 目录运行 node render.cjs，重新输出最终图、无做旧图、预览和校验记录。
5. 只看无做旧版本可运行 node render.cjs --flat-only；之后再次运行 node render.cjs 恢复做旧版本。
6. 可以直接编辑 body/orbit/rocket/dot 四张蒙版，然后运行 render.cjs；渲染不会重建这些分区蒙版。
7. 修改画布、标志有效宽度或需要重建原图分区时，依次运行：
   node inspect_components.cjs
   node prepare_masks.cjs
   node render.cjs
   重建会重新导出 masks 中的分区文件，请先备份手动改过的蒙版。

运行环境
Node.js 与 sharp。当前工作环境可直接运行。
其他电脑在 source 目录执行 npm install，安装 package.json 中声明的 sharp 后即可运行。
无需图像生成 API 或密钥。此次采用指定的独立蒙版与处理脚本流程，原图结构不重新生成。

校验
source/layout.json 保存原图有效范围和最终排版坐标。
source/validation.json 保存尺寸、色值、缺墨面积、真透明孔洞数量和透明版叠奶油底的一致性记录。
previews/components.png 是原图连通分区的辅助检查图，随机颜色仅用于诊断，不是设计稿。
