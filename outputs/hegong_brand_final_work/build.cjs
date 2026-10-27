const fs=require('fs');
const path=require('path');
const {execFileSync}=require('child_process');
const out="E:/zhengzhi/outputs/河工知谷_定稿方案_20261019";
const work=__dirname;
const magick='F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const raw="C:/Users/Legion/.codex/generated_images/01a1529f-813e-7f11-bccf-b405da9b23ac/exec-7544f85c-e793-42d5-af8e-ef0dccf8f809.png";
const source="C:/Users/Legion/AppData/Local/Temp/codex-clipboard-ec1ab79f-9a30-48d5-b9eb-b01d3ada0744.png";
const navy='#073D70';
const cnfont='C:/Windows/Fonts/msyhbd.ttc';
const enfont='C:/Windows/Fonts/arial.ttf';
const uifont='C:/Windows/Fonts/msyh.ttc';
function m(args){return execFileSync(magick,args.map(String),{maxBuffer:30e6,env:{...process.env,MAGICK_THREAD_LIMIT:'2'}});}
function dest(dir,name){const d=path.join(out,dir);fs.mkdirSync(d,{recursive:true});return path.join(d,name);}
function save(args,file){m([...args,'-strip','-depth','8','-define','png:color-type=6',file]);return file;}
function canvas(w,h,color='none'){return ['-size',`${w}x${h}`,`xc:${color}`];}
function place(args,img,w,h,x,y){args.push('(',img,'-resize',`${w}x${h}!`,')','-geometry',`+${x}+${y}`,'-compose','Over','-composite');}
function wh(file){return m(['identify','-format','%w %h',file]).toString().trim().split(' ').map(Number);}
function txt(str,font,size,color,file,spacing=0){return save(['-background','none','-fill',color,'-font',font,'-pointsize',size,'-kerning',spacing,`label:${str}`,'-trim','+repage'],file);}
function recolor(file,color,target){return save([file,'-fill',color,'-colorize','100'],target);}
function label(args,text,x,y,size=26,color='#53677C'){args.push('-font',uifont,'-pointsize',size,'-fill',color,'-gravity','NorthWest','-annotate',`+${x}+${y}`,text);}
fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'.gdignore'),'');fs.writeFileSync(path.join(work,'.gdignore'),'');
const mask=path.join(work,'circle-mask.png');
save([...canvas(4096,4096,'black'),'-fill','white','-draw','circle 2046,2046 4046,2046','-resize','1024x1024'],mask);
const master=dest('01_图形标识','河工知谷_彩色图形_透明_1024.png');
save([raw,'-crop','1064x1064+94+115','+repage','-alpha','off','-resize','1024x1024!',mask,'-alpha','off','-compose','CopyOpacity','-composite'],master);
for(const size of [512,256,128])save([master,'-resize',`${size}x${size}`],dest('01_图形标识',`河工知谷_彩色图形_透明_${size}.png`));
const cn=dest('02_文字标识','河工知谷_中文字标_深蓝.png');
const en=dest('02_文字标识','HEGONG_ZHIGU_英文字标_深蓝.png');
const cntmp=txt('河工知谷',cnfont,260,navy,path.join(work,'cn.png'),24);
const entmp=txt('HEGONG ZHIGU',enfont,70,navy,path.join(work,'en.png'),30);
save([cntmp,'-resize','1400x'],cn);save([entmp,'-resize','1240x'],en);
const [cw,ch]=wh(cn),[ew,eh]=wh(en);
const wordH=ch+42+eh;
const words=dest('02_文字标识','河工知谷_中英文字标_深蓝.png');
let a=canvas(1400,wordH);place(a,cn,cw,ch,0,0);place(a,en,ew,eh,80,ch+42);save(a,words);
const cnWhite=recolor(cn,'white',dest('02_文字标识','河工知谷_中文字标_白色.png'));
const enWhite=recolor(en,'white',dest('02_文字标识','HEGONG_ZHIGU_英文字标_白色.png'));
const wordsWhite=recolor(words,'white',dest('02_文字标识','河工知谷_中英文字标_白色.png'));
const combos={};
for(const [variant,wordfile] of [['深蓝字',words],['白字',wordsWhite]]){
  let h=canvas(2304,768);place(h,master,640,640,64,64);place(h,wordfile,1400,wordH,800,Math.round((768-wordH)/2));
  combos['横版_'+variant]=save(h,dest('03_组合标识',`河工知谷_横版组合_${variant}_透明.png`));
  const vWordH=Math.round(wordH*1100/1400);
  let v=canvas(1200,1480);place(v,master,1000,1000,100,32);place(v,wordfile,1100,vWordH,50,1104);
  combos['竖版_'+variant]=save(v,dest('03_组合标识',`河工知谷_竖版组合_${variant}_透明.png`));
}
const icons={};
for(const [variant,color] of [['浅色','#F7F9FC'],['深色',navy]]){
  for(const style of ['圆角','直角']){
    let a=style==='圆角'? [...canvas(2048,2048),'-fill',color,'-draw','roundrectangle 0,0 2047,2047 360,360','-resize','1024x1024'] : canvas(1024,1024,color);
    place(a,master,820,820,102,102);
    const file=save(a,dest('04_应用图标',`河工知谷_${variant}_${style}_1024.png`));icons[variant+style]=file;
  }
  for(const size of [512,256])save([icons[variant+'圆角'],'-resize',`${size}x${size}`],dest('04_应用图标',`河工知谷_${variant}_圆角_${size}.png`));
}
m([master,'-define','icon:auto-resize=256,128,64,48,32,16',dest('04_应用图标','河工知谷_桌面图标.ico')]);
fs.copyFileSync(dest('04_应用图标','河工知谷_桌面图标.ico'),dest('04_应用图标','河工知谷_彩色透明.ico'));
for(const size of [1024,512,256,128])fs.copyFileSync(dest('01_图形标识',`河工知谷_彩色图形_透明_${size}.png`),dest('04_应用图标',`河工知谷_彩色透明_${size}.png`));
const monoAlpha=path.join(work,'mono-alpha.png');
save([master,'-background','white','-alpha','remove','-alpha','off','-colorspace','Gray','-negate'],monoAlpha);
const monos={};
for(const [variant,color] of [['深蓝单色',navy],['黑色单色','#111111'],['白色反白','#FFFFFF']]){
  monos[variant]=save([...canvas(1024,1024,color),monoAlpha,'-alpha','off','-compose','CopyOpacity','-composite'],dest('05_单色与灰度',`河工知谷_${variant}_阶调_透明.png`));
}
monos['灰度']=save([master,'-colorspace','Gray','-colorspace','sRGB'],dest('05_单色与灰度','河工知谷_灰度图形_透明.png'));
// A standalone application preview reuses the exact exported icon.
const mock=dest('06_应用示意','河工知谷_桌面应用示意.png');
a=['-size','1440x960','gradient:#E8F2F8-#B8CAD9'];
a.push('-fill','#DAE7EF','-draw','roundrectangle 72,72 1368,888 48,48');
a.push('(',icons['浅色圆角'],'-resize','480x480','-background','#13375A','-shadow','18x22+0+20',')','-geometry','+458+164','-compose','Over','-composite');
place(a,icons['浅色圆角'],480,480,480,180);
const [ww,hh]=[520,Math.round(wordH*520/1400)];place(a,words,ww,hh,460,698);save(a,mock);
// Contact sheet: all assets are referenced directly; no duplicate drawings.
const preview=path.join(out,'00_组件总览.png');
a=canvas(1920,1500,'#F1F5F9');
label(a,'河工知谷',72,44,52,navy);label(a,'定稿应用方案  /  HEGONG ZHIGU',74,118,25);
a.push('-fill','white','-draw','roundrectangle 48,192 650,1015 28,28','-draw','roundrectangle 680,192 1872,580 28,28','-draw','roundrectangle 680,610 1258,1015 28,28','-fill',navy,'-draw','roundrectangle 1288,610 1872,1015 28,28');
label(a,'竖版组合',78,214,23);
place(a,combos['竖版_深蓝字'],540,666,79,294);
label(a,'横版组合',710,214,23);place(a,combos['横版_深蓝字'],1116,372,719,228);
label(a,'浅色应用图标',710,632,23);place(a,icons['浅色圆角'],280,280,829,695);
label(a,'深色应用图标',1318,632,23,'#D9EAF8');place(a,icons['深色圆角'],280,280,1439,695);
const titles=['彩色图形','深蓝单色 · 阶调','黑色单色 · 阶调','灰度版','白色反白 · 阶调'];
const files=[master,monos['深蓝单色'],monos['黑色单色'],monos['灰度'],monos['白色反白']];
for(let i=0;i<5;i++){
  const x=48+i*370;
  a.push('-fill',i===4?navy:'white','-draw',`roundrectangle ${x},1045 ${x+344},1398 22,22`);
  place(a,files[i],244,244,x+50,1070);label(a,titles[i],x+30,1346,22,i===4?'#D9EAF8':'#53677C');
}
label(a,'统一母版  ·  统一圆形边界  ·  统一中英文字标  ·  PNG 透明底',72,1437,23);
save(a,preview);
fs.copyFileSync(source,dest('07_来源与制作记录','用户选定原稿.png'));
fs.copyFileSync(raw,dest('07_来源与制作记录','AI整理母版_原始输出.png'));
const readme=`河工知谷 · 品牌组件包\n\n交付日期：2026-10-19\n\n一、统一原则\n以原始展示板左侧大圆形山谷标识为基准，经内置 image_gen 工具整理独立母版。所有正式组件均从同一份母版导出，没有分别生成不同造型。图形已规范圆形边界，移除展示背景和雾化效果。\n中文统一为“河工知谷”；英文统一为“HEGONG ZHIGU”。中文按微软雅黑 Bold 重新排版，英文按 Arial 排版；字标、字距、比例在横竖组合中统一。文字为 PNG 像素，不需要收件人安装字体。\n\n二、文件说明\n00_组件总览.png：快速查看各版本。\n01_图形标识：透明 PNG，1024 / 512 / 256 / 128 像素。\n02_文字标识：中文、英文、中英组合，各有深蓝与白色版本。\n03_组合标识：横版 2304×768、竖版 1200×1480，均为透明底，分别提供深蓝字与白字。\n04_应用图标：浅色/深色，圆角透明版与直角满底版；圆角版另有 512 / 256 像素，以及多尺寸 ICO。\n05_单色与灰度：深蓝、黑色、白色的单色阶调版，以及灰度版。单色阶调使用透明度保留同一母版的明暗；它不是无灰阶的单色印章稿。\n06_应用示意：桌面图标展示效果，仅用于预览。\n07_来源与制作记录：原始参考、AI 原始整理输出和生成提示词。该目录不作为正式组件使用。\n\n三、统一色彩与使用\n品牌深蓝：#062D55；浅色图标底色：#F7F9FC。山谷内部沿用母版蓝色渐变。\n浅色背景用深蓝字组合；深色背景用白字组合。\n圆形母版在 1024 画布中保留约 12 像素透明边距；应用图标中的实际圆形直径约为画布的 78%。\n所有文件为 RGB/sRGB 位图。1024 为标准图形导出尺寸，组合图中的图形不会超过该分辨率。大幅印刷需要另行建立真正的矢量稿；本包未将位图伪装为 SVG。\n\n四、来源说明\n原始文件为一张合成 PNG，无法直接恢复原来的字体文件和可编辑图层。本包是对认可方案的统一整理与组件化导出，并非逐像素恢复原始工程。\n`;
fs.writeFileSync(path.join(out,'使用说明.txt'),readme,'utf8');
fs.writeFileSync(path.join(work,'build-info.json'),JSON.stringify({master,wordH,ch,eh,preview,icons,combos,monos},null,2));
console.log(JSON.stringify({out,preview,wordH,ch,eh},null,2));
