const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {execFileSync}=require('child_process');
const root='E:/zhengzhi',out=root+'/outputs/河工知谷_定稿方案_20261019';
const magick='F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const b=JSON.parse(fs.readFileSync(path.join(__dirname,'build-info.json')));
function m(a){return execFileSync(magick,a.map(String),{maxBuffer:30e6,env:{...process.env,MAGICK_THREAD_LIMIT:'2'}});}
function save(a,f){m([...a,'-strip','-depth','8','-define','png:color-type=6',f]);return f;}
const android=out+'/08_Android图标';fs.mkdirSync(android,{recursive:true});
const legacy=save([b.master,'-resize','180x180','-gravity','center','-background','none','-extent','192x192'],android+'/河工知谷_启动图标_192.png');
const foreground=save([b.master,'-resize','264x264','-gravity','center','-background','none','-extent','432x432'],android+'/河工知谷_自适应前景_432.png');
const background=save(['-size','432x432','xc:#F7F9FC'],android+'/河工知谷_自适应背景_432.png');
for(const size of [64,48,32,16])save([b.master,'-resize',`${size}x${size}`],out+`/04_应用图标/河工知谷_彩色透明_${size}.png`);
const mappings={
  'hegong_zhigu_icon.png':b.master,
  'hegong_zhigu_icon.ico':out+'/04_应用图标/河工知谷_桌面图标.ico',
  'hegong_zhigu_android_192.png':legacy,
  'hegong_zhigu_adaptive_foreground.png':foreground,
  'hegong_zhigu_adaptive_background.png':background,
};
const backup=path.join(__dirname,'previous_assets');fs.mkdirSync(backup,{recursive:true});
const results=[];
for(const [name,src] of Object.entries(mappings)){
  const dst=root+'/assets/branding/'+name;
  if(fs.existsSync(dst)&&!fs.existsSync(path.join(backup,name)))fs.copyFileSync(dst,path.join(backup,name));
  fs.copyFileSync(src,dst);
  const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
  if(sha(src)!==sha(dst))throw Error('Copy mismatch: '+name);
  results.push({file:dst,sha256:sha(dst),dimensions:m(['identify','-format','%wx%h ',dst]).toString().trim()});
}
const alpha=m([b.master,'-alpha','extract','-depth','8','gray:-']);
for(const [x,y] of [[0,0],[512,0],[0,512],[1023,512],[512,1023]])if(alpha[y*1024+x]!==0)throw Error('Icon margin is not transparent');
if(alpha[512*1024+512]!==255)throw Error('Icon center must be opaque');
const cfg=fs.readFileSync(root+'/project.godot','utf8'),exp=fs.readFileSync(root+'/export_presets.cfg','utf8');
for(const name of Object.keys(mappings))if(!cfg.includes(name)&&!exp.includes(name))throw Error('Icon is not referenced: '+name);
fs.writeFileSync(path.join(__dirname,'installed-assets.json'),JSON.stringify({status:'passed',results},null,2));
fs.writeFileSync(out+'/使用说明.txt',`河工知谷 · 定稿应用方案\n2026-10-19\n\n方案依据：用户本轮选定的圆形山谷与曲折河道图案。以用户选定原稿为视觉基准，经内置 image_gen 整理透明独立母版，再统一规范圆形边缘并生成各尺寸，不对不同组件分别重新设计。\n\n视觉规范\n1. 主标识：圆形蓝色山谷、白色曲折河道；使用原有蓝色层次。\n2. 中文：河工知谷；英文：HEGONG ZHIGU。组合字标使用微软雅黑 Bold 和 Arial 统一排版，是字标整理稿，并非恢复原图字体。\n3. 配色参考：深蓝 #073D70、中蓝 #1268B4、亮蓝 #54AFF0、浅蓝 #E8F6FF。图形渐变以 PNG 母版为准。\n4. 标识周边建议留出至少图形直径 1/8 的空白，不拉伸、不加描边。\n5. 小尺寸图标仅使用圆形图形，不放中英文；正文及界面文字用常规字体。\n\n文件\n00_组件总览.png：组合和应用效果预览。\n01_图形标识：透明图形，1024/512/256/128 像素。\n02_文字标识：中英文字标，深蓝/白色。\n03_组合标识：横版和竖版，透明背景。\n04_应用图标：透明图标，1024 至 16 像素；ICO 含 256/128/64/48/32/16 六种尺寸。\n05_单色与灰度：阶调版本，保留透明度明暗；不是纯色印章稿。\n06_应用示意：展示效果。\n07_来源与制作记录：用户选定原稿、AI 整理输出、提示词。\n08_Android图标：192 像素启动图标和 432 像素自适应前景/背景，前景图形置于中央安全区域。\n\n项目落地\n项目 PNG、Windows ICO、Android 启动及自适应图标统一从本母版导出，替换 assets/branding/ 的五个现有资源文件。现有图标配置沿用。应用名称、大学校徽及功能保持现状。\n\n格式说明\n全部图形为 sRGB 位图；1024 像素为交付母版尺寸。大幅印刷需另制真正矢量稿。原图仅有合成位图，透明母版经过 AI 整理及边缘规范，不声称与原稿逐像素一致。\n`, 'utf8');
const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>河工知谷 · 定稿方案</title><style>*{box-sizing:border-box}body{margin:0;background:#f3f7fb;color:#073d70;font-family:'Microsoft YaHei',Arial,sans-serif}main{max-width:1120px;margin:auto;padding:56px 28px}header small{letter-spacing:3px;color:#54738f}h1{font-size:44px;margin:14px 0}p{line-height:1.9;color:#536b80}section{background:white;border-radius:24px;margin:24px 0;padding:36px}h2{font-size:23px;margin:0 0 24px}.hero{display:grid;grid-template-columns:1fr 1fr;align-items:center;gap:36px}.hero img{width:100%;max-width:390px}.hero h2{font-size:36px;letter-spacing:8px;margin:0}.hero .en{letter-spacing:5px;font-size:13px}.samples{display:flex;gap:20px;flex-wrap:wrap}.sample{flex:1;min-width:170px;text-align:center;padding:32px;border-radius:18px;background:#f4f8fc}.sample img{width:130px;height:130px;object-fit:contain}.dark{background:#073d70;color:white}.dark p{color:#dcecf9}.swatches{display:flex;gap:12px;flex-wrap:wrap}.swatch{flex:1;min-width:130px;height:100px;padding:15px;border-radius:14px;color:white;display:flex;align-items:flex-end}.full{width:100%;height:auto}li{margin:12px 0;line-height:1.8;color:#536b80}a{color:#1268b4}footer{font-size:13px;color:#6c8296;line-height:1.8}@media(max-width:680px){.hero{grid-template-columns:1fr}h1{font-size:32px}section{padding:24px}}</style><main><header><small>HEGONG ZHIGU / 2026.10.19</small><h1>河工知谷 · 定稿应用方案</h1><p>以选定的圆形山谷为主标识，保留圆润山势与曲折河道。所有应用组件由同一母版生成。</p></header><section class="hero"><img src="01_图形标识/河工知谷_彩色图形_透明_1024.png"><div><h2>河工知谷</h2><p class="en">HEGONG ZHIGU</p><p>山谷承载知识，河流连接持续学习。蓝色层次建立远近关系，白色河道形成视觉中心。</p><p>桌面与小尺寸入口使用独立图形；品牌展示使用中英文字标组合。</p></div></section><section><h2>图标应用</h2><div class="samples"><div class="sample"><img src="01_图形标识/河工知谷_彩色图形_透明_1024.png"><p>浅色环境 · 透明图形</p></div><div class="sample dark"><img src="01_图形标识/河工知谷_彩色图形_透明_1024.png"><p>深色环境 · 透明图形</p></div><div class="sample"><img src="04_应用图标/河工知谷_浅色_圆角_512.png"><p>浅色底板 · 应用示意</p></div></div></section><section><h2>色彩与字标</h2><div class="swatches"><div class="swatch" style="background:#073d70">#073D70</div><div class="swatch" style="background:#1268b4">#1268B4</div><div class="swatch" style="background:#54aff0">#54AFF0</div><div class="swatch" style="background:#e8f6ff;color:#073d70">#E8F6FF</div></div><p>中文组合字标：微软雅黑 Bold。英文组合字标：Arial，以字距形成秩序。图形渐变以透明 PNG 母版为准。</p><img class="full" src="03_组合标识/河工知谷_横版组合_深蓝字_透明.png"></section><section><h2>使用规范</h2><ul><li>安全留白：四周建议不少于图形直径的 1/8。</li><li>小尺寸仅用图形；16–64 像素版本已单独导出。</li><li>保持正圆比例，不横向拉伸，不叠加描边或额外装饰。</li><li>Windows 使用透明 ICO；Android 自适应图标按中央安全区域排布。</li></ul></section><section><h2>组件总览</h2><img class="full" src="00_组件总览.png"></section><footer>全部交付图形为 sRGB 位图。透明母版由内置 image_gen 整理，尺寸转换与组合由同一母版生成。<a href="使用说明.txt">查看完整使用说明</a> · <a href="07_来源与制作记录/用户选定原稿.png">查看选定原稿</a></footer></main></html>`;
fs.writeFileSync(out+'/定稿方案.html',html,'utf8');
console.log(JSON.stringify({status:'passed',replaced:results.length,plan:out+'/定稿方案.html'},null,2));
