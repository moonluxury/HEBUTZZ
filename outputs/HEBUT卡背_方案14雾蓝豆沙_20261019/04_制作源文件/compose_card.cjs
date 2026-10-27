const fs=require('fs');
const path=require('path');
const {execFileSync}=require('child_process');
const root=path.resolve(__dirname,'..');
const work=path.resolve(root,'../hebut_cards_work/scheme14_mist_rose');
fs.mkdirSync(work,{recursive:true});
const magick='F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
function m(a){return execFileSync(magick,a.map(String),{maxBuffer:32e6,env:{...process.env,MAGICK_THREAD_LIMIT:'2'}});}
function save(a,p){m([...a,'-strip','-depth','8','-define','png:color-type=6',p]);}
function pos(a,p,x,y){a.push(p,'-gravity','NorthWest','-geometry',`+${x}+${y}`,'-compose','Over','-composite');}
const layers=path.join(root,'03_分层素材');
const bg=path.join(root,'02_视觉素材/background.png');
const logo=path.join(root,'02_视觉素材/team_logo.png');
const fit=path.join(work,'background_fit.png');
save([bg,'-resize','936x1448^','-gravity','Center','-extent','936x1448'],fit);
const ba=['-size','1024x1536','xc:none'];pos(ba,fit,44,44);save(ba,path.join(layers,'background_layer.png'));
const mark=path.join(work,'logo_fit.png');
const visibleBox=m([logo,'-alpha','extract','-threshold','8%','-format','%@','info:']).toString().trim();
save([logo,'-crop',visibleBox,'+repage','-resize','504x342'],mark);
const [lw,lh]=m(['identify','-format','%w %h',mark]).toString().trim().split(' ').map(Number);
const lx=Math.round((1024-lw)/2),ly=Math.round(660-lh/2);
const la=['-size','1024x1536','xc:none'];pos(la,mark,lx,ly);save(la,path.join(layers,'logo_layer.png'));
const base=path.join(layers,'card_back_base.png');
const frame=path.join(layers,'card_back_frame.png');
const typography=path.join(layers,'text.png');
const out=[base];pos(out,fit,44,44);pos(out,mark,lx,ly);pos(out,frame,0,0);pos(out,typography,0,0);
const final=path.join(root,'01_独立卡背/HEBUT_团队Logo卡背.png');save(out,final);
const noText=[base];pos(noText,fit,44,44);pos(noText,mark,lx,ly);pos(noText,frame,0,0);save(noText,path.join(root,'01_独立卡背/HEBUT_团队Logo卡背_无字.png'));
function body(p){return fs.readFileSync(p,'utf8').replace(/^<svg[^>]*>/,'').replace(/<\/svg>\s*$/,'');}
const prefix='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="1024" height="1536" viewBox="0 0 1024 1536">';
const b64=p=>fs.readFileSync(p).toString('base64');
const svg=prefix+`<defs><clipPath id="background-window"><rect x="44" y="44" width="936" height="1448"/></clipPath></defs>
<g id="base" inkscape:groupmode="layer" inkscape:label="底卡"><rect x="8" y="8" width="1008" height="1520" rx="70" fill="#f7f4e8"/></g>
<g id="background" inkscape:groupmode="layer" inkscape:label="蓝紫背景"><image x="44" y="44" width="936" height="1448" preserveAspectRatio="xMidYMid slice" clip-path="url(#background-window)" xlink:href="data:image/png;base64,${b64(bg)}"/></g>
<g id="team-logo" inkscape:groupmode="layer" inkscape:label="团队Logo · 独立透明层"><image x="${lx}" y="${ly}" width="${lw}" height="${lh}" xlink:href="data:image/png;base64,${b64(mark)}"/></g>
<g id="frame" inkscape:groupmode="layer" inkscape:label="统一卡框">${body(path.join(layers,'card_back_frame.svg'))}</g>`+body(path.join(layers,'text.svg'))+'</svg>';
fs.writeFileSync(path.join(layers,'HEBUT_团队Logo卡背_layered.svg'),svg);
const preview=['-size','1700x1430','xc:#E8EEF2'];
function label(s,size,color,file){const p=path.join(work,file+'.png');save(['-background','none','-fill',color,'-font','C:/Windows/Fonts/msyhbd.ttc','-pointsize',size,'label:'+s],p);return p;}
pos(preview,label('HEBUT 空天探索 · 方案 14 雾蓝与豆沙',44,'#244d70','title'),65,38);
pos(preview,label('雾蓝渐变 · 豆沙粉暖色 · 灰紫珠光 · 细腻绘画质感',25,'#627d91','sub'),68,115);
preview.push('(',path.resolve(root,'../HEBUT卡背_团队Logo版_20261019/01_独立卡背/HEBUT_团队Logo卡背.png'),'-resize','700x1050',')','-geometry','+95+215','-compose','Over','-composite');
preview.push('(',final,'-resize','700x1050',')','-geometry','+905+215','-compose','Over','-composite');
pos(preview,label('原版 · 深蓝标识',30,'#244d70','front'),335,1300);
pos(preview,label('方案 14 · 雾蓝豆沙',30,'#244d70','back'),1120,1300);
save(preview,path.join(root,'00_方案14上色对比.png'));
fs.writeFileSync(path.join(root,'04_制作源文件/layout.json'),JSON.stringify({canvas:[1024,1536],logo:{x:lx,y:ly,width:lw,height:lh},layers:['base','background','team-logo','frame','text']},null,2));
console.log(JSON.stringify({final,logoBounds:[lx,ly,lw,lh],layers:5},null,2));
