const fs=require('fs');
const path=require('path');
let sharp;
try{sharp=require('sharp');}catch{sharp=require('C:/Users/Legion/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');}
const root=path.resolve(__dirname,'..');
(async()=>{
 const input=path.join(__dirname,'porcelain_generated.png');
 const {data,info}=await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 let x0=info.width,y0=info.height,x1=0,y1=0;
 for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++)if(data[(y*info.width+x)*4+3]>=64){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}
 x0=Math.max(0,x0-2);y0=Math.max(0,y0-2);x1=Math.min(info.width-1,x1+2);y1=Math.min(info.height-1,y1+2);
 const crop={left:x0,top:y0,width:x1-x0+1,height:y1-y0+1};
 const width=1536,height=Math.round(width*crop.height/crop.width),left=(2048-width)/2,top=Math.round((2048-height)/2);
 const fitted=await sharp(input).extract(crop).resize(width,height,{kernel:'lanczos3'}).png().toBuffer();
 const transparent=await sharp({create:{width:2048,height:2048,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:fitted,left,top}]).png().toBuffer();
 fs.writeFileSync(path.join(root,'qinghua_chucang_transparent.png'),transparent);
 const light=await sharp(transparent).flatten({background:'#FAF8F4'}).png().toBuffer();
 fs.writeFileSync(path.join(root,'qinghua_chucang_light.png'),light);
 await sharp(light).resize(128,128).png().toFile(path.join(root,'previews/qinghua_chucang_128.png'));
 await sharp(light).extract({left:left+350,top:top+70,width:600,height:600}).png().toFile(path.join(root,'previews/porcelain_detail_100percent.png'));
 const layout={canvas:[2048,2048],generatedSize:[info.width,info.height],generatedCrop:crop,logo:{left,top,width,height},background:'#FAF8F4',method:'Built-in image_gen material edit; export preserves generated alpha and aspect ratio.'};
 fs.writeFileSync(path.join(__dirname,'layout.json'),JSON.stringify(layout,null,2));
 console.log(JSON.stringify(layout,null,2));
})().catch(e=>{console.error(e);process.exit(1);});
