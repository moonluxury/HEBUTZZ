const fs=require('fs');
const path=require('path');
let sharp;
try{sharp=require('sharp');}catch{sharp=require('C:/Users/Legion/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');}
const root=path.resolve(__dirname,'..');
(async()=>{
 const {data,info}=await sharp(path.join(__dirname,'original_logo.png')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height,n=w*h,labels=new Int32Array(n),queue=new Int32Array(n),components=[];
 for(let i=0;i<n;i++){
  if(labels[i]||data[4*i+3]<128)continue;
  const id=components.length+1;let head=0,tail=1;queue[0]=i;labels[i]=id;
  let x0=w,y0=h,x1=0,y1=0,sx=0,sy=0;
  while(head<tail){
   const p=queue[head++],x=p%w,y=Math.floor(p/w);
   x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);sx+=x;sy+=y;
   for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){
    const xx=x+dx,yy=y+dy;if(xx<0||xx>=w||yy<0||yy>=h)continue;
    const j=yy*w+xx;if(!labels[j]&&data[4*j+3]>=128){labels[j]=id;queue[tail++]=j;}
   }
  }
  components.push({id,area:tail,bbox:[x0,y0,x1-x0+1,y1-y0+1],centroid:[sx/tail,sy/tail]});
 }
 const large=components.filter(c=>c.area>30).sort((a,b)=>b.area-a.area);
 const colors=[[62,120,205],[239,125,65],[74,170,90],[169,95,194],[225,173,40],[40,180,180],[223,75,117],[100,100,100]];
 const out=Buffer.alloc(n*4);
 const ids=new Map(large.map((c,i)=>[c.id,colors[i%colors.length]]));
 for(let i=0;i<n;i++){const c=ids.get(labels[i]);out[4*i]=c?c[0]:241;out[4*i+1]=c?c[1]:232;out[4*i+2]=c?c[2]:215;out[4*i+3]=255;}
 await sharp(out,{raw:{width:w,height:h,channels:4}}).png().toFile(path.join(root,'previews/components.png'));
 fs.writeFileSync(path.join(__dirname,'components.json'),JSON.stringify({width:w,height:h,components:large},null,2));
 fs.writeFileSync(path.join(__dirname,'component_labels.bin'),Buffer.from(labels.buffer));
 console.log(JSON.stringify({width:w,height:h,components:large},null,2));
})();
