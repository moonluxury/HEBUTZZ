from pathlib import Path
from zipfile import ZipFile
from io import BytesIO
import hashlib,json,csv,shutil
from PIL import Image,ImageDraw,ImageFont

WORK=Path(__file__).resolve().parent
BASE=Path('E:/zhengzhi')
GEN=Path('C:/Users/Legion/.codex/generated_images/01a151ff-5b88-7140-956a-c4c22cabbc69')
STAGE=WORK/'HEBUT先进空天'
STAGE.mkdir(parents=True,exist_ok=True)
entries=[]

def file(relative,target,notes=''):
    p=BASE/relative
    entries.append({'source':str(p),'data':p.read_bytes(),'target':target,'notes':notes})

def generated(name,target,notes=''):
    p=GEN/name
    entries.append({'source':str(p),'data':p.read_bytes(),'target':target,'notes':notes})

def archived(archive,member,target,notes=''):
    p=BASE/archive
    with ZipFile(p) as z: data=z.read(member)
    entries.append({'source':str(p)+' :: '+member,'data':data,'target':target,'notes':notes})

file('outputs/HEBUT卡背_团队Logo版_20261019/02_视觉素材/team_logo.png','01_原版图形/团队Logo_原版蓝色渐变_透明_1254.png')
file('outputs/HEBUT卡背_团队Logo版_20261019/04_制作源文件/team_homepage_icon.png','01_原版图形/团队官网_原始小图标_透明_192.png')
file('assets/hebut-aerospace-research-center-logo-v1.png','02_带团队名称/HEBUT先进空天_亮蓝横版_v1_棋盘格底.png','棋盘格已写入像素，不是真透明。')
file('assets/hebut-aerospace-research-center-logo-v2.png','02_带团队名称/HEBUT先进空天_深蓝横版_v2_棋盘格底.png','棋盘格已写入像素，不是真透明。')
file('assets/hebut-aerospace-research-center-logo-v2-white.png','02_带团队名称/HEBUT先进空天_深蓝横版_v2_白底.png')
file('outputs/HEBUT卡背_纯奶油白_20261020/02_视觉素材/team_logo.png','03_配色变种/纯奶油白_透明.png')
file('outputs/HEBUT卡背_方案14雾蓝豆沙_20261019/02_视觉素材/team_logo.png','03_配色变种/方案14_雾蓝豆沙_透明.png')
generated('exec-26027c68-5a03-4e16-8c13-54932460d7f1.png','03_配色变种/淡蓝紫主体_奶油色轨道_透明.png','早期配色探索；按实际配色命名。')
archived('outputs/HEBUT卡背_团队Logo冷暖对比版_20261019.zip','HEBUT卡背_团队Logo冷暖对比版_20261019/02_视觉素材/team_logo.png','03_配色变种/冷暖对比_金橙主体蓝绿轨道_透明.png')
archived('outputs/HEBUT卡背_团队Logo交大灰_DCDCDD_20261019.zip','HEBUT卡背_团队Logo交大灰_DCDCDD_20261019/02_视觉素材/团队Logo_DCDCDD_透明.png','03_配色变种/交大灰_DCDCDD_透明.png')
for src,name in [('retro_aerospace_transparent.png','旧日航天_轻做旧_透明.png'),('retro_aerospace_cream.png','旧日航天_轻做旧_奶油底.png'),('retro_aerospace_flat_transparent.png','旧日航天_无做旧分色_透明.png'),('retro_aerospace_flat_cream.png','旧日航天_无做旧分色_奶油底.png')]:
    file('outputs/旧日航天_Logo_20261020/'+src,'04_艺术变种/01_旧日航天/'+name)
file('outputs/青花出舱_Logo_20261020/qinghua_chucang_transparent.png','04_艺术变种/02_青花出舱/青花出舱_透明_2048.png')
file('outputs/青花出舱_Logo_20261020/qinghua_chucang_light.png','04_艺术变种/02_青花出舱/青花出舱_浅暖白底_2048.png')
file('outputs/重返大气层_Logo_20261020/reentry_transparent.png','04_艺术变种/03_重返大气层/重返大气层_透明_2048.png')
file('outputs/重返大气层_Logo_20261020/reentry_dark.png','04_艺术变种/03_重返大气层/重返大气层_深色底_2048.png')
file('outputs/snowfield_aurora/final/logo_snowfield_aurora_transparent_v3.png','04_艺术变种/04_雪原极光/雪原极光_v3斜边修正版_透明_2048.png','采用最后修复斜边的 v3。')
file('outputs/snowfield_aurora/final/logo_snowfield_aurora_presentation_v3.png','04_艺术变种/04_雪原极光/雪原极光_v3斜边修正版_雪夜展示_2048.png','采用最后修复斜边的 v3。')
file('outputs/青花出舱_Logo_20261020/source/first_pass_reference.png','05_历史草稿/青花出舱_早期海浪纹样稿_透明.png','探索草稿，正式版本见艺术变种。')
file('outputs/重返大气层_Logo_20261020/source/first_pass_reference.png','05_历史草稿/重返大气层_早期高亮纹理稿_透明.png','探索草稿，正式版本见艺术变种。')
file('outputs/青花出舱_Logo_20261020/source/porcelain_generated.png','06_原始尺寸备份/青花出舱_选定稿_生成原尺寸1254_透明.png','2048 交付版的选定生成原图。')
file('outputs/重返大气层_Logo_20261020/source/reentry_generated.png','06_原始尺寸备份/重返大气层_选定稿_生成原尺寸1254_透明.png','2048 交付版的选定生成原图。')

manifest=[]; seen={}
for item in entries:
    digest=hashlib.sha256(item['data']).hexdigest()
    if digest in seen:
        continue
    seen[digest]=item['target']
    target=STAGE/item['target']
    assert target.resolve().is_relative_to(STAGE.resolve())
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists() and target.read_bytes()!=item['data']:
        raise RuntimeError('Staging collision: '+str(target))
    target.write_bytes(item['data'])
    image=Image.open(BytesIO(item['data']))
    image.verify()
    image=Image.open(BytesIO(item['data'])).convert('RGBA')
    transparency='有透明通道' if image.getchannel('A').getextrema()[0]<255 else '不透明背景'
    manifest.append({'文件':item['target'],'尺寸':f'{image.width}×{image.height}','透明情况':transparency,'说明':item['notes'],'来源':item['source'],'SHA256':digest})

with (STAGE/'文件清单.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(manifest[0])); writer.writeheader(); writer.writerows(manifest)
(WORK/'collection_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(STAGE/'整理说明.txt').write_text('HEBUT 先进空天团队 Logo PNG 合集\n整理日期：2026-10-25\n\n共 '+str(len(manifest))+' 张独立 Logo PNG，另有一张总览索引。\n\n01 原版图形；02 带团队名称；03 配色变种；04 艺术变种；05 历史草稿；06 原始尺寸备份。\n各图按现有源文件原样复制，没有重新上色、改形或压缩转换；相同文件按 SHA256 去重。\n雪原极光采用最后修复左侧斜边的 v3。早期青花与再入探索稿放在历史草稿，避免与正式版混淆。\n带团队名称的两个“棋盘格底”横版，棋盘格已写入图像像素，不是真透明；另有白底横版可直接使用。\n独立 Logo 与已有展示底版本均已收录。卡片整张卡面、空白背景、蒙版、文字碎片和诊断截图未混入 Logo 文件。\n“原始尺寸备份”保留青花出舱与重返大气层的 1254px 选定原图，2048px 排版版位于艺术变种。\n详细源路径、尺寸和校验值见文件清单.csv。\n',encoding='utf-8')

font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
canvas=Image.new('RGB',(1440,90+((len(manifest)+3)//4)*270),'#E8EAF0')
draw=ImageDraw.Draw(canvas); draw.text((28,26),'HEBUT 先进空天 · 团队 Logo PNG 索引',font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',30),fill='#142C4D')
for i,item in enumerate(manifest):
    x=(i%4)*360; y=90+(i//4)*270
    im=Image.open(STAGE/item['文件']).convert('RGBA')
    a=im.getchannel('A'); bbox=a.point(lambda v:255 if v>=8 else 0).getbbox()
    if a.getextrema()[0]<255 and bbox: im=im.crop(bbox)
    im.thumbnail((330,192),Image.Resampling.LANCZOS)
    bg=Image.new('RGBA',(340,200),'#526074'); bg.alpha_composite(im,((340-im.width)//2,(200-im.height)//2)); canvas.paste(bg.convert('RGB'),(x+10,y))
    name=Path(item['文件']).stem
    lines=[name[:19],name[19:38]]
    draw.text((x+10,y+205),lines[0],font=small,fill='#142C4D')
    if lines[1]: draw.text((x+10,y+227),lines[1],font=small,fill='#142C4D')
canvas.save(STAGE/'00_Logo总览索引.png')
print(json.dumps({'stage':str(STAGE),'logo_png_count':len(manifest),'all_png_count':len(list(STAGE.rglob('*.png'))),'files':len(list(p for p in STAGE.rglob('*') if p.is_file()))},ensure_ascii=False,indent=2))
