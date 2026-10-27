// Recompose the supplied image, editable lettering and shared-outline card back.
const fs=require('fs');
const path=require('path');
const {execFileSync}=require('child_process');
const root=path.resolve(__dirname,'..');
const dest=path.join(root,'07_共用卡背');
const work=path.resolve(root,'../hebut_cards_work');
fs.mkdirSync(dest,{recursive:true});
fs.mkdirSync(work,{recursive:true});
const magick=process.env.CARD_MAGICK || 'F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const cn=process.env.CARD_CN_FONT || 'C:/Windows/Fonts/msyhbd.ttc';
const normal=process.env.CARD_CN_REGULAR || 'C:/Windows/Fonts/msyh.ttc';
const bold=process.env.CARD_LATIN_BOLD || 'C:/Windows/Fonts/arialbd.ttf';
function m(args){return execFileSync(magick,args.map(String),{maxBuffer:40e6,env:{...process.env,MAGICK_THREAD_LIMIT:'2'}});}
function save(args,p){m([...args,'-strip','-depth','8','-define','png:color-type=6',p]);}
function pos(args,img,x,y){args.push(img,'-gravity','NorthWest','-geometry',`+${x}+${y}`,'-compose','Over','-composite');}
function sprite(text,font,size,color,name,spacing=0){const p=path.join(work,name+'.png');save(['-background','none','-fill',color,'-font',font,'-pointsize',size,'-kerning',spacing,`label:${text}`,'-trim','+repage'],p);return p;}
function width(p){return Number(m(['identify','-format','%w',p]).toString());}
const prefix='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="1024" height="1536" viewBox="0 0 1024 1536">';
const frameMarkup=`<defs>
<linearGradient id="ivory" x2="0" y2="1"><stop stop-color="#fffdf0"/><stop offset=".55" stop-color="#f4f3e6"/><stop offset="1" stop-color="#e7e9df"/></linearGradient>
<linearGradient id="rim" x2="0" y2="1"><stop stop-color="#7499b3"/><stop offset=".22" stop-color="#214b70"/><stop offset=".8" stop-color="#214665"/><stop offset="1" stop-color="#153858"/></linearGradient>
</defs>
<path fill="url(#rim)" fill-rule="evenodd" d="M78 8H946Q1016 8 1016 78V1458Q1016 1528 946 1528H78Q8 1528 8 1458V78Q8 8 78 8ZM86 52Q52 52 52 86V1450Q52 1484 86 1484H938Q972 1484 972 1450V86Q972 52 938 52Z"/>
<path fill="url(#ivory)" fill-rule="evenodd" d="M78 21H946Q1003 21 1003 78V1458Q1003 1515 946 1515H78Q21 1515 21 1458V78Q21 21 78 21ZM86 52Q52 52 52 86V1450Q52 1484 86 1484H938Q972 1484 972 1450V86Q972 52 938 52Z"/>
<rect x="29" y="29" width="966" height="1478" rx="48" fill="none" stroke="#fffef7" stroke-width="4"/>
<rect x="38" y="38" width="948" height="1460" rx="42" fill="none" stroke="#b5c7cb" stroke-width="2"/>
<rect x="48" y="48" width="928" height="1440" rx="38" fill="none" stroke="#7598ad" stroke-width="8"/>
<rect x="50" y="50" width="924" height="1436" rx="36" fill="none" stroke="#e9f5f7" stroke-width="3"/>
<rect x="65" y="65" width="894" height="1406" rx="25" fill="none" stroke="#dbc593" stroke-opacity=".6" stroke-width="1.5"/>
<g fill="#e1c991" stroke="#e1c991" stroke-width="1.5">
<path d="M321 306H463M561 306H703" opacity=".75"/>
<path d="M512 299L519 306L512 313L505 306Z" stroke="none"/>
${Array.from({length:7},(_,i)=>`<circle cx="${422+i*30}" cy="1326" r="${i===3?4:2.5}" stroke="none"/>`).join('')}
</g>`;
fs.writeFileSync(path.join(dest,'card_back_frame.svg'),prefix+frameMarkup+'</svg>');
save(['-background','none',path.join(dest,'card_back_frame.svg')],path.join(dest,'card_back_frame.png'));
const texts=`<g id="editable-text" inkscape:groupmode="layer" inkscape:label="文字 · 可编辑">
<text x="512" y="267" text-anchor="middle" font-family="Arial, sans-serif" font-weight="700" font-size="80" letter-spacing="10" fill="#fff4d7">HEBUT</text>
<text x="512" y="1273" text-anchor="middle" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-weight="700" font-size="52" letter-spacing="5" fill="#fff4d7">空天探索系列</text>
</g>`;
fs.writeFileSync(path.join(dest,'card_back_text.svg'),prefix+texts+'</svg>');
const brand=sprite('HEBUT',bold,80,'#fff4d7','back-brand',10);
const series=sprite('空天探索系列',cn,52,'#fff4d7','back-series',5);
const ta=['-size','1024x1536','xc:none'];pos(ta,brand,Math.round((1024-width(brand))/2),209);pos(ta,series,Math.round((1024-width(series))/2),1222);
save(ta,path.join(dest,'card_back_text.png'));
const art=path.join(dest,'card_back_art.png');
const fitted=path.join(work,'card_back_fit.png');
save([art,'-resize','936x1448^','-gravity','Center','-extent','936x1448'],fitted);
const base=path.join(root,'03_通用模板/card_base.png');
fs.copyFileSync(base,path.join(dest,'card_back_base.png'));
const artLayer=['-size','1024x1536','xc:none'];pos(artLayer,fitted,44,44);
save(artLayer,path.join(dest,'card_back_art_layer.png'));
const a=[base];pos(a,fitted,44,44);pos(a,path.join(dest,'card_back_frame.png'),0,0);pos(a,path.join(dest,'card_back_text.png'),0,0);
const final=path.join(dest,'00_HEBUT空天探索_卡背.png');save(a,final);
const editable=prefix+`<defs><clipPath id="art-window"><rect x="44" y="44" width="936" height="1448"/></clipPath></defs>
<g id="base" inkscape:groupmode="layer" inkscape:label="底卡"><rect x="8" y="8" width="1008" height="1520" rx="70" fill="#f7f4e8"/></g>
<g id="illustration" inkscape:groupmode="layer" inkscape:label="星轨插画"><image x="44" y="44" width="936" height="1448" preserveAspectRatio="xMidYMid slice" clip-path="url(#art-window)" xlink:href="data:image/png;base64,${fs.readFileSync(art).toString('base64')}"/></g>
<g id="frame" inkscape:groupmode="layer" inkscape:label="统一外框与装饰">${frameMarkup}</g>`+texts+'</svg>';
fs.writeFileSync(path.join(dest,'card_back_layered.svg'),editable);
const overview=['-size','1700x1470','xc:#E8EEF2'];
pos(overview,sprite('HEBUT 空天探索系列',cn,55,'#244d70','back-preview-title'),80,46);
pos(overview,sprite('正面与共用卡背  ·  相同比例与外轮廓',normal,27,'#627d91','back-preview-sub'),82,127);
overview.push('(',path.join(root,'01_独立卡面/05_空天飞机.png'),'-resize','700x1050',')','-geometry','+100+235','-compose','Over','-composite');
overview.push('(',final,'-resize','700x1050',')','-geometry','+900+235','-compose','Over','-composite');
pos(overview,sprite('05 · 空天飞机',cn,32,'#244d70','back-preview-front'),337,1325);
pos(overview,sprite('共用卡背',cn,32,'#244d70','back-preview-back'),1180,1325);
save(overview,path.join(dest,'01_正背对照.png'));
console.log(JSON.stringify({cardBack:final,size:'1024x1536',layers:4,textEditable:true},null,2));
