// Recompose existing illustration layers; does not invoke any image-generation API.
const fs=require('fs');
const path=require('path');
const {execFileSync}=require('child_process');
const root=path.resolve(__dirname,'..');
const work=path.resolve(root,'../hebut_cards_work');
fs.mkdirSync(work,{recursive:true});
const magick=process.env.CARD_MAGICK || 'F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const cn=process.env.CARD_CN_FONT || 'C:/Windows/Fonts/msyhbd.ttc';
const normal=process.env.CARD_CN_REGULAR || 'C:/Windows/Fonts/msyh.ttc';
const latin=process.env.CARD_LATIN_FONT || 'C:/Windows/Fonts/arial.ttf';
const bold=process.env.CARD_LATIN_BOLD || 'C:/Windows/Fonts/arialbd.ttf';
const cards=JSON.parse(fs.readFileSync(path.join(__dirname,'cards.json'),'utf8'));
const frame=path.join(root,'03_通用模板/card_frame.png');
const base=path.join(root,'03_通用模板/card_base.png');
function m(args){return execFileSync(magick,args.map(String),{maxBuffer:40e6,env:{...process.env,MAGICK_THREAD_LIMIT:'2'}});}
function save(args,p){m([...args,'-strip','-depth','8','-define','png:color-type=6',p]);}
function pos(args,img,x,y){args.push(img,'-gravity','NorthWest','-geometry',`+${x}+${y}`,'-compose','Over','-composite');}
function textSprite(text,font,size,color,name,spacing=0){const p=path.join(work,name+'.png');save(['-background','none','-fill',color,'-font',font,'-pointsize',size,'-kerning',spacing,`label:${text}`,'-trim','+repage'],p);return p;}
function dim(p){return m(['identify','-format','%w %h',p]).toString().trim().split(' ').map(Number);}
const he=textSprite('HEBUT',bold,54,'#244D70','brand',1);
const series=textSprite('空天探索系列',normal,30,'#52738C','series',0);
function textLayer(c){
 const a=['-size','1024x1536','xc:none'];pos(a,he,151,72);pos(a,series,450,80);
 const number=textSprite(c.id,bold,42,'#FFF8E5','number_'+c.id,0);
 const title=textSprite(c.name,cn,72,'#244D70','title_'+c.id,3);
 const english=textSprite(c.english,latin,26,'#678096','english_'+c.id,4);
 pos(a,number,Math.round(895-dim(number)[0]/2),78);
 pos(a,title,Math.round(512-dim(title)[0]/2),1322);
 pos(a,english,Math.round(512-dim(english)[0]/2),1410);
 const p=path.join(root,'04_独立文字层',`${c.id}_${c.slug}_text.png`);save(a,p);return p;
}
function svgText(c){return `<g id="editable-text" inkscape:groupmode="layer" inkscape:label="文字 · 可编辑">
<text x="151" y="112" font-family="Arial, sans-serif" font-weight="700" font-size="54" letter-spacing="1" fill="#244d70">HEBUT</text>
<text x="450" y="108" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-size="30" fill="#52738c">空天探索系列</text>
<text x="895" y="109" text-anchor="middle" font-family="Arial, sans-serif" font-weight="700" font-size="42" fill="#fff8e5">${c.id}</text>
<text x="512" y="1387" text-anchor="middle" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-weight="700" font-size="72" letter-spacing="3" fill="#244d70">${c.name}</text>
<text x="512" y="1431" text-anchor="middle" font-family="Arial, sans-serif" font-size="26" letter-spacing="4" fill="#678096">${c.english}</text>
</g>`;}
const prefix='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="1024" height="1536" viewBox="0 0 1024 1536">';
const frameMarkup=fs.readFileSync(path.join(root,'03_通用模板/card_frame.svg'),'utf8').replace(/^<svg[^>]*>/,'').replace(/<\/svg>\s*$/,'');
const ready=[];
for(const c of cards){
 const art=path.join(root,'02_插画',`${c.id}_${c.slug}.png`);
 if(!fs.existsSync(art))continue;
 const text=textLayer(c);
 fs.writeFileSync(path.join(root,'04_独立文字层',`${c.id}_${c.slug}_text.svg`),prefix+svgText(c)+'</svg>');
 const fitted=path.join(work,c.id+'_art_fit.png');save([art,'-resize','936x1136^','-gravity','Center','-extent','936x1136'],fitted);
 const a=[base];pos(a,fitted,44,148);pos(a,frame,0,0);pos(a,text,0,0);
 const final=path.join(root,'01_独立卡面',`${c.id}_${c.name}.png`);save(a,final);
 const editable=prefix+`<defs><clipPath id="art-window"><rect x="44" y="148" width="936" height="1136"/></clipPath></defs>
<g id="base" inkscape:groupmode="layer" inkscape:label="底卡"><rect x="8" y="8" width="1008" height="1520" rx="70" fill="#f7f4e8"/></g>
<g id="illustration" inkscape:groupmode="layer" inkscape:label="无字插画"><image x="44" y="148" width="936" height="1136" preserveAspectRatio="xMidYMid slice" clip-path="url(#art-window)" xlink:href="data:image/png;base64,${fs.readFileSync(art).toString('base64')}"/></g>
<g id="frame" inkscape:groupmode="layer" inkscape:label="统一卡框">${frameMarkup}</g>`+svgText(c)+'</svg>';
 fs.writeFileSync(path.join(root,'06_制作源文件',`${c.id}_${c.slug}_layered.svg`),editable);
 ready.push({...c,file:final,art});
}
// The blank standard template has placeholder text in a separate layer.
const templateText=textLayer({id:'00',slug:'template',name:'卡片名称',english:'CARD NAME'});
let a=[base,'(','-size','936x1136','gradient:#D7EAF3-#EDF1E6',')','-geometry','+44+148','-compose','Over','-composite'];pos(a,frame,0,0);pos(a,templateText,0,0);
save(a,path.join(root,'03_通用模板','00_标准卡片模板.png'));
if(ready.length===7){
 const overview=['-size','2280x1880','xc:#E8EEF2'];
 const title=textSprite('HEBUT 空天探索系列',cn,62,'#244D70','overview-title');pos(overview,title,80,45);
 const sub=textSprite('七张原创收藏卡  ·  统一卡框 / 独立插画 / 可编辑文字',normal,27,'#627D91','overview-sub');pos(overview,sub,82,126);
 for(let i=0;i<7;i++){
   const x=i<4?68+i*552:344+(i-4)*552,y=i<4?204:1034;
   overview.push('(',ready[i].file,'-resize','488x732',')','-geometry',`+${x}+${y}`,'-compose','Over','-composite');
 }
 save(overview,path.join(root,'00_七卡总览.png'));
}
console.log(JSON.stringify({composed:ready.map(c=>c.id),size:'1024x1536',textIsSeparate:true},null,2));
