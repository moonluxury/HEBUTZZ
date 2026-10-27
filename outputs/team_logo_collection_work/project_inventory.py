from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont
root=Path('E:/zhengzhi'); out=Path(__file__).resolve().parent
paths=list((root/'assets').glob('hebut-aerospace-research-center-logo*.png'))
paths+=list((root/'outputs').glob('HEBUT卡背_*/02_视觉素材/team_logo.png'))
paths+=list((root/'outputs').glob('HEBUT卡背_*/03_分层素材/logo_layer.png'))
paths+=list((root/'outputs').glob('HEBUT卡背_*/04_制作源文件/team_homepage_icon.png'))
paths+=list((root/'outputs/hebut_cards_work').glob('*/logo_fit.png'))
paths+=list((root/'tools').glob('quiz_logo*.png'))
items=[]
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
for i,p in enumerate(paths,1):
    im=Image.open(p).convert('RGBA'); alpha=im.getchannel('A')
    items.append({'index':i,'path':str(p),'size':list(im.size),'alpha_range':list(alpha.getextrema()),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for page in range((len(items)+11)//12):
    canvas=Image.new('RGB',(1200,4*285),'#E8EAF0'); d=ImageDraw.Draw(canvas)
    for j,item in enumerate(items[page*12:(page+1)*12]):
        x=j%3*400; y=j//3*285
        p=Path(item['path']); im=Image.open(p).convert('RGBA'); im.thumbnail((384,210),Image.Resampling.LANCZOS)
        bg=Image.new('RGBA',(384,210),'#526074'); bg.alpha_composite(im,((384-im.width)//2,(210-im.height)//2)); canvas.paste(bg.convert('RGB'),(x+8,y+6))
        label=p.parent.parent.name if p.name in ('team_logo.png','logo_layer.png') else p.parent.name
        d.text((x+8,y+220),f"{item['index']:02d} {label}",font=font,fill='#18283B')
        d.text((x+8,y+245),p.name,font=font,fill='#18283B')
    canvas.save(out/f'project_page_{page+1}.png')
(out/'project_inventory.json').write_text(json.dumps(items,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(items,ensure_ascii=False,indent=2))
