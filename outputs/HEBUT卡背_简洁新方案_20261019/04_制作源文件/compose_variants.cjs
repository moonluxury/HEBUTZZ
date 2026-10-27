const fs=require('fs');
const path=require('path');
const {execFileSync}=require('child_process');
const root=path.resolve(__dirname,'..');
const work=path.resolve(root,'../hebut_cards_work/simple_back_variants');
fs.mkdirSync(work,{recursive:true});
const data=JSON.parse(fs.readFileSync(path.join(__dirname,'designs.json'),'utf8'));
const magick=process.env.CARD_MAGICK || 'F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const cn=process.env.CARD_CN_FONT || 'C:/Windows/Fonts/msyhbd.ttc';
const normal=process.env.CARD_CN_REGULAR || 'C:/Windows/Fonts/msyh.ttc';
const bold=process.env.CARD_LATIN_BOLD || 'C:/Windows/Fonts/arialbd.ttf';
function m(args){return execFileSync(magick,args.map(String),{maxBuffer:40e6,env:{...process.env,MAGICK_THREAD_LIMIT:'2'}});}
function save(args,p){m([...args,'-strip','-depth','8','-define','png:color-type=6',p]);}
function pos(args,img,x,y){args.push(img,'-gravity','NorthWest','-geometry',`+${x}+${y}`,'-compose','Over','-composite');}
function sprite(text,font,size,color,name,spacing=0){const p=path.join(work,name+'.png');save(['-background','none','-fill',color,'-font',font,'-pointsize',size,'-kerning',spacing,`label:${text}`,'-trim','+repage'],p);return p;}
function dim(p){return m(['identify','-format','%w %h',p]).toString().trim().split(' ').map(Number);}
const frame=path.join(root,'03_分层素材/card_back_frame.png');
const base=path.join(root,'03_分层素材/card_back_base.png');
const frameMarkup=fs.readFileSync(path.join(root,'03_分层素材/card_back_frame.svg'),'utf8').replace(/^<svg[^>]*>/,'').replace(/<\/svg>\s*$/,'');
const prefix='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="1024" height="1536" viewBox="0 0 1024 1536">';
const ready=[];
for(const d of data.designs){
const stem=d.id+'_'+d.slug;
const folder=path.join(root,'03_分层素材',d.id+'_'+d.name);
fs.mkdirSync(folder,{recursive:true});
const art=path.join(root,'02_无字插画',stem+'.png');
const fitted=path.join(work,stem+'_fit.png');
save([art,'-resize','936x1448^','-gravity','Center','-extent','936x1448'],fitted);
const artLayer=['-size','1024x1536','xc:none'];pos(artLayer,fitted,44,44);
save(artLayer,path.join(folder,'art_layer.png'));
const t=d.text;
const brand=sprite('HEBUT',bold,t.brandSize,t.color,stem+'_brand',4);
const series=sprite('空天探索系列',cn,t.seriesSize,t.color,stem+'_series',2);
const ta=['-size','1024x1536','xc:none'];pos(ta,brand,Math.round((1024-dim(brand)[0])/2),t.brandY);pos(ta,series,Math.round((1024-dim(series)[0])/2),t.seriesY);
const textPng=path.join(folder,'text.png');save(ta,textPng);
const textGroup=`<g id="text" inkscape:groupmode="layer" inkscape:label="文字 · 可编辑">
<text x="512" y="${t.brandY+Math.round(t.brandSize*.735)}" text-anchor="middle" font-family="Arial, sans-serif" font-size="${t.brandSize}" font-weight="700" letter-spacing="4" fill="${t.color}">HEBUT</text>
<text x="512" y="${t.seriesY+Math.round(t.seriesSize*.97)}" text-anchor="middle" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-size="${t.seriesSize}" font-weight="700" letter-spacing="2" fill="${t.color}">空天探索系列</text>
</g>`;
fs.writeFileSync(path.join(folder,'text.svg'),prefix+textGroup+'</svg>');
const svg=prefix+`<defs><clipPath id="art-window"><rect x="44" y="44" width="936" height="1448"/></clipPath></defs>
<g id="base" inkscape:groupmode="layer" inkscape:label="底卡"><rect x="8" y="8" width="1008" height="1520" rx="70" fill="#f7f4e8"/></g>
<g id="art" inkscape:groupmode="layer" inkscape:label="无字插画"><image x="44" y="44" width="936" height="1448" preserveAspectRatio="xMidYMid slice" clip-path="url(#art-window)" xlink:href="data:image/png;base64,${fs.readFileSync(art).toString('base64')}"/></g>
<g id="frame" inkscape:groupmode="layer" inkscape:label="统一卡框">${frameMarkup}</g>`+textGroup+'</svg>';
fs.writeFileSync(path.join(folder,stem+'_layered.svg'),svg);
const a=[base];pos(a,fitted,44,44);pos(a,frame,0,0);pos(a,textPng,0,0);
const final=path.join(root,'01_独立卡背',d.id+'_'+d.name+'.png');save(a,final);
ready.push({...d,final});
}
const preview=['-size','2420x1130','xc:#E8EEF2'];
pos(preview,sprite('HEBUT 空天探索 · 简洁卡背方案',cn,54,'#244d70','variants-title'),58,38);
pos(preview,sprite('延续已认可卡面的绘画质感  /  单一主体  /  低对比背景  /  文字独立排版',normal,26,'#627d91','variants-sub'),61,116);
for(let i=0;i<ready.length;i++){
const d=ready[i],x=64+i*598;
preview.push('(',d.final,'-resize','500x750',')','-geometry',`+${x}+190`,'-compose','Over','-composite');
const name=sprite(d.id+' · '+d.name,cn,32,'#244d70','preview-name-'+d.id);
pos(preview,name,x+Math.round((500-dim(name)[0])/2),973);
const sub=sprite(d.description,normal,22,'#627d91','preview-desc-'+d.id);
pos(preview,sub,x+Math.round((500-dim(sub)[0])/2),1030);
}
save(preview,path.join(root,'00_四款卡背对比.png'));
console.log(JSON.stringify({cards:ready.map(d=>d.id+' '+d.name),size:'1024x1536',editableLayers:true},null,2));

