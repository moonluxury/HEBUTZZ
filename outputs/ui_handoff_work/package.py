from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageStat
from html import escape
from urllib.parse import quote
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import json
import shutil

OUTPUTS = Path(__file__).resolve().parents[1]
SOURCE = OUTPUTS / 'PC_UI美术交接_20261102'
DEST = OUTPUTS / '河工开物_PC端UI截图_20261102'
DEST.mkdir(exist_ok=True)
EXCLUDE = {
    '01_工作台与题库/04_总题库_下半页.png',
    '03_河工开物/04_征稿公告_下半页.png',
    '05_我的收藏/02_系列展开.png',
}
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
titlefont = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 26)
overview = DEST / '00_缩略总览'
overview.mkdir(exist_ok=True)
records = []
groups = []
for group in sorted(p for p in SOURCE.iterdir() if p.is_dir()):
    files = [p for p in sorted(group.glob('*.png')) if p.relative_to(SOURCE).as_posix() not in EXCLUDE]
    if not files:
        continue
    target = DEST / group.name
    target.mkdir(exist_ok=True)
    rows = []
    for i, path in enumerate(files, 1):
        label = path.stem.split('_', 1)[1]
        name = f'{i:02d}_{label}.png'
        destination = target / name
        shutil.copy2(path, destination)
        with Image.open(destination) as im:
            im.load()
            assert im.size == (1920, 1260), (name, im.size)
            assert sum(ImageStat.Stat(im.convert('RGB')).stddev) > 10, name
        row = {'path': destination.relative_to(DEST).as_posix(), 'name': label,
               'width': 1920, 'height': 1260, 'bytes': destination.stat().st_size,
               'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}
        rows.append(row)
        records.append(row)
    groups.append((group.name, rows))
    width, cellw, cellh = 1500, 500, 365
    sheet = Image.new('RGB', (width, 70 + ((len(rows)+2)//3)*cellh), '#edf0f5')
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 16), f'{group.name}  ·  {len(rows)} 张', font=titlefont, fill='#13213d')
    for i, row in enumerate(rows):
        x, y = (i%3)*cellw+10, 70+(i//3)*cellh
        with Image.open(DEST / row['path']) as im:
            im.thumbnail((480, 315), Image.Resampling.LANCZOS)
            sheet.paste(im, (x,y))
        draw.text((x,y+320), f'{i+1:02d}  {row["name"]}', font=font, fill='#13213d')
    sheet.save(overview / (group.name+'.jpg'), quality=90)

text = f'''河工开物 · PC 端 UI 美术交接
截图日期：2026-11-02

本包包含 {len(records)} 张原尺寸 PNG，分为 {len(groups)} 个功能文件夹。
所有截图均为 1920 × 1260 像素，来自当前 PC 项目的实际 Godot / 内嵌编辑器渲染。
页面位置、布局和原有素材未做重新设计。

交接目标：在现有控件位置与页面结构基础上，更换主题美术素材与动效。

使用方法
1. 解压后打开“页面目录.html”，按模块浏览并点击图片查看原尺寸。
2. “00_缩略总览”适合快速检查页面范围；正式设计对照使用各文件夹中的 PNG。
3. 同一长页面按顶部 / 下半页提供；弹窗保留背景页面，方便判断位置与遮罩关系。

内容范围
工作台、学习记录、总题库、错题库；六类答题、答题反馈、专注模式、题库讨论；
河工开物资源与公告；个人中心、资料、头像、登录注册与安全；
收藏总览、全部 / 想要卡牌、卡牌详情与开卡；好友列表、会话、申请、资料、
备注、赠送、换卡、记录、黑名单；充值与订单、电池明细；
投稿列表、设置、正文编辑、预览、文章阅读、购买及相关确认弹窗。
另附 5 张深色主题参考。

示例数据说明
账号、好友消息、收藏数量、余额、订单、投稿与讨论采用隔离的展示数据。
没有使用个人真实账号或执行真实支付、发消息、赠送、购买、投稿等操作。
部分测试服务会显示“测试 / 隔离”等字样，主题设计以界面结构和控件样式为准。
题库题目和软件已有资源素材沿用项目内容。

动效参考
PNG 为静态图片。收藏文件夹包含等待开卡、翻卡中间帧、开卡结果三个状态。
现有公共动效参数：按下 80ms、悬停 140ms、状态切换 120ms、
页签下划线 700ms、页面 / 弹窗进入 180ms、退出 120ms、
趋势与进度展开 1700ms、系列展开箭头 160ms。
此处仅记录当前基线，供新主题动效设计对照。

文件夹清单
'''
for name, rows in groups:
    text += f'{name}：{len(rows)} 张\n'
(DEST / '先读我_美术交接说明.txt').write_text(text, encoding='utf-8-sig')

parts = ['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>河工开物 · PC UI 截图目录</title>',
'''<style>body{margin:0;background:#f2f4f8;color:#18223a;font:16px/1.65 "Microsoft YaHei",sans-serif}header,main{max-width:1480px;margin:auto;padding:30px}h1{margin:0}header p{color:#596579}nav{display:flex;flex-wrap:wrap;gap:8px}nav a{padding:6px 12px;background:white;border-radius:6px;color:#092c87;text-decoration:none}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px}figure{margin:0;background:white;border:1px solid #dce1ea;border-radius:8px;overflow:hidden}img{display:block;width:100%;height:auto}figcaption{padding:10px 14px}a{color:#092c87}section{margin-bottom:40px}small{color:#65718a}footer{padding:20px;text-align:center;color:#65718a}</style>''',
f'<header><h1>河工开物 · PC UI 截图目录</h1><p>2026-11-02 · {len(records)} 张截图 · 1920 × 1260 · 点击图片打开原尺寸<br>当前真实界面布局，账号与业务内容使用隔离示例数据。<a href="{quote("先读我_美术交接说明.txt")}">阅读交接说明</a></p><nav>']
for index, (name, rows) in enumerate(groups):
    parts.append(f'<a href="#group-{index}">{escape(name)} · {len(rows)}</a>')
parts.append('</nav></header><main>')
for index, (name, rows) in enumerate(groups):
    parts.append(f'<section id="group-{index}"><h2>{escape(name)}</h2><div class="grid">')
    for row in rows:
        path = quote(row['path'], safe='/')
        parts.append(f'<figure><a href="{path}" target="_blank"><img loading="lazy" src="{path}" alt="{escape(row["name"])}"></a><figcaption>{escape(row["name"])}<br><small>1920 × 1260 PNG</small></figcaption></figure>')
    parts.append('</div></section>')
parts.append('</main><footer>静态截图供主题美术与动效设计对照。请使用原图保留准确位置。</footer></html>')
(DEST / '页面目录.html').write_text(''.join(parts), encoding='utf-8')
(OUTPUTS / 'ui_handoff_work/manifest.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')

zip_path = OUTPUTS / (DEST.name + '.zip')
with ZipFile(zip_path, 'w', compression=ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(DEST.rglob('*')):
        if path.is_file() and path.suffix in {'.png','.jpg','.html','.txt'}:
            archive.write(path, Path(DEST.name) / path.relative_to(DEST))
with ZipFile(zip_path) as archive:
    assert archive.testzip() is None
    assert len([n for n in archive.namelist() if n.endswith('.png')]) == len(records)
print(json.dumps({'zip':str(zip_path),'screenshots':len(records),'modules':len(groups),'bytes':zip_path.stat().st_size,'archive_verified':True},ensure_ascii=False))
