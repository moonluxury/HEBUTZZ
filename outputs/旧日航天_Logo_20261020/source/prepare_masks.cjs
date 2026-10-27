// Use the supplied alpha silhouette, not a redrawn outline.
const fs=require('fs');
const path=require('path');
let sharp;
try{sharp=require('sharp');}catch{sharp=require('C:/Users/Legion/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');}
const root=path.resolve(__dirname,'..');
(async()=>{
 const cfg=JSON.parse(fs.readFileSync(path.join(__dirname,'settings.json'),'utf8'));
 const {data,info}=await sharp(path.join(__dirname,'original_logo.png')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height,n=w*h;
 const packed=fs.readFileSync(path.join(__dirname,'component_labels.bin'));
 const rawLabels=new Int32Array(packed.buffer,packed.byteOffset,packed.length/4);
 const meta=JSON.parse(fs.readFileSync(path.join(__dirname,'components.json'),'utf8'));
 const valid=new Set(meta.components.map(c=>c.id));
 const owner=new Int32Array(n),dist=new Uint8Array(n).fill(255),queue=new Int32Array(n);
 let head=0,tail=0;
 for(let i=0;i<n;i++)if(valid.has(rawLabels[i])){owner[i]=rawLabels[i];dist[i]=0;queue[tail++]=i;}
 // Restore original antialiased edges within three pixels of substantial components.
 // Discard only detached, almost-transparent generator fringe outside the real mark.
 while(head<tail){
  const p=queue[head++];if(dist[p]>=3)continue;
  const x=p%w,y=Math.floor(p/w);
  for(const q of [x>0?p-1:-1,x<w-1?p+1:-1,y>0?p-w:-1,y<h-1?p+w:-1]){
   if(q>=0&&dist[q]>dist[p]+1){dist[q]=dist[p]+1;owner[q]=owner[p];queue[tail++]=q;}
  }
 }
 const masks=Object.fromEntries(['body','orbit','rocket','dot'].map(k=>[k,Buffer.alloc(n)]));
 let x0=w,y0=h,x1=0,y1=0;
 for(let i=0;i<n;i++){
  const sourceAlpha=data[4*i+3],a=sourceAlpha>=250?255:sourceAlpha,id=owner[i];if(!id||!a)continue;
  const x=i%w,y=Math.floor(i/w),split=cfg.left_orbit_split;
  let role='body';
  // Component 5 is the visible right/front orbit. The left/rear arc joins
  // component 2, so split it along the continuation of the original H edge.
  if(id===5||(id===2&&y>=split.minimum_y&&x<split.boundary_x_intercept+split.boundary_x_per_y*y))role='orbit';
  else if(id===8)role='dot';
  else if([1,3,4].includes(id)||(id===2&&x>780&&y<540))role='rocket';
  masks[role][i]=a;
  if(a>=32){x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);}
 }
 const crop={left:x0,top:y0,width:x1-x0+1,height:y1-y0+1};
 const size=cfg.canvas_size,markW=cfg.effective_width,markH=Math.round(crop.height*markW/crop.width);
 const left=Math.round((size-markW)/2),top=Math.round((size-markH)/2);
 const sum=new Uint16Array(size*size);
 for(const [role,mask] of Object.entries(masks)){
  const fitted=await sharp(mask,{raw:{width:w,height:h,channels:1}}).extract(crop).resize(markW,markH,{kernel:'lanczos3'}).greyscale().raw().toBuffer();
  const out=Buffer.alloc(size*size);
  for(let y=0;y<markH;y++)for(let x=0;x<markW;x++){
   const dst=(y+top)*size+x+left;out[dst]=fitted[y*markW+x];sum[dst]+=out[dst];
  }
  await sharp(out,{raw:{width:size,height:size,channels:1}}).png().toFile(path.join(root,'masks',role+'.png'));
 }
 const silhouette=Buffer.from(sum.map(v=>Math.min(255,v)));
 await sharp(silhouette,{raw:{width:size,height:size,channels:1}}).png().toFile(path.join(root,'masks/silhouette.png'));
 const layout={source_size:[w,h],source_crop:crop,canvas_size:[size,size],mark:{left,top,width:markW,height:markH},scale:markW/crop.width};
 fs.writeFileSync(path.join(__dirname,'layout.json'),JSON.stringify(layout,null,2));
 console.log(JSON.stringify(layout));
})().catch(e=>{console.error(e);process.exit(1);});
