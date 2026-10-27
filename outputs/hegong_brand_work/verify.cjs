const fs=require('fs');
const path=require('path');
const assert=require('assert/strict');
const {execFileSync}=require('child_process');
const root='E:/zhengzhi/outputs/河工知谷_品牌组件';
const b=JSON.parse(fs.readFileSync(path.join(__dirname,'build-info.json')));
function m(args){return execFileSync('F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe',args,{maxBuffer:30e6,env:{...process.env,MAGICK_THREAD_LIMIT:'2'}});}
function walk(p){return fs.readdirSync(p,{withFileTypes:true}).flatMap(x=>x.isDirectory()?walk(path.join(p,x.name)):[path.join(p,x.name)]);}
const files=walk(root),pngs=files.filter(x=>x.endsWith('.png'));
const dimensions=pngs.map(p=>({file:path.relative(root,p),dimensions:m(['identify','-format','%wx%h',p]).toString()}));
const alpha=m([b.master,'-alpha','extract','-depth','8','gray:-']);
const mask=m([path.join(__dirname,'circle-mask.png'),'-colorspace','Gray','-depth','8','gray:-']);
assert.equal(Buffer.compare(alpha,mask),0,'Master boundary must exactly equal the common circle mask');
for(const [x,y] of [[0,0],[512,0],[0,512],[1023,512],[512,1023]])assert.equal(alpha[y*1024+x],0,'Outer margin must be transparent');
const expected=m([b.master,'-resize','820x820!','-depth','8','rgba:-']);
let exactOpaquePixels=0;
for(const file of [b.icons['浅色圆角'],b.icons['深色圆角']]){
 const got=m([file,'-crop','820x820+102+102','+repage','-depth','8','rgba:-']);
 let checked=0,maxDifference=0;
 for(let i=0;i<expected.length;i+=4){const pixel=i/4,x=pixel%820,y=Math.floor(pixel/820);if(expected[i+3]===255 && Math.hypot(x-409.5,y-409.5)<390){for(let c=0;c<3;c++)maxDifference=Math.max(maxDifference,Math.abs(got[i+c]-expected[i+c]));checked++;}}
 assert.ok(maxDifference<=1,`Icon must reuse exact master RGB: ${file}, difference ${maxDifference}`);exactOpaquePixels+=checked;
}
for(const kind of ['中文字标','中英文字标']){
 const navy=path.join(root,'02_文字标识',`河工知谷_${kind}_深蓝.png`);
 const white=path.join(root,'02_文字标识',`河工知谷_${kind}_白色.png`);
 assert.equal(Buffer.compare(m([navy,'-alpha','extract','-depth','8','gray:-']),m([white,'-alpha','extract','-depth','8','gray:-'])),0,'Text variants must share exact geometry');
}
const result={status:'passed',pngFiles:pngs.length,independentComponentPngs:pngs.filter(x=>/0[1-6]_/.test(x)).length,exactOpaquePixels,dimensions};
fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify({status:result.status,pngFiles:result.pngFiles,independentComponentPngs:result.independentComponentPngs,exactOpaquePixels},null,2));
m([b.master,'-background','#E7EEF4','-alpha','remove','-alpha','off',path.join(__dirname,'master-on-light.png')]);
