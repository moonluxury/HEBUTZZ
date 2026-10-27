from pathlib import Path
import json, hashlib
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
ROOT.mkdir(parents=True, exist_ok=True)
generated = Path('C:/Users/Legion/.codex/generated_images/01a151ff-5b88-7140-956a-c4c22cabbc69')
items=[]
for index,p in enumerate(sorted(generated.glob('*.png')),1):
    im=Image.open(p)
    items.append({'index':index,'path':str(p),'size':list(im.size),'mode':im.mode,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(ROOT/'generated_inventory.json').write_text(json.dumps(items,ensure_ascii=False,indent=2),encoding='utf-8')
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
for page in range((len(items)+17)//18):
    subset=items[page*18:(page+1)*18]
    canvas=Image.new('RGB',(1080,6*260),'#E8EAF0')
    draw=ImageDraw.Draw(canvas)
    for n,item in enumerate(subset):
        x=(n%3)*360; y=(n//3)*260
        im=Image.open(item['path']).convert('RGBA'); im.thumbnail((344,220),Image.Resampling.LANCZOS)
        base=Image.new('RGBA',(344,220),'#526074')
        base.alpha_composite(im,((344-im.width)//2,(220-im.height)//2))
        canvas.paste(base.convert('RGB'),(x+8,y+5))
        draw.text((x+10,y+228),f"{item['index']:02d}  {Path(item['path']).stem[5:13]}",fill='#18283B',font=font)
    canvas.save(ROOT/f'generated_page_{page+1}.png')
print(json.dumps([{'index':i['index'],'file':Path(i['path']).name,'size':i['size']} for i in items],ensure_ascii=False))
