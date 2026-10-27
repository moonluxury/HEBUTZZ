// Deterministic two-ink artwork from independent editable masks.
// Edit settings.json for colors and wear, or edit masks/*.png, then rerun.
const fs=require('fs');
const path=require('path');
let sharp;
try{sharp=require('sharp');}catch{sharp=require('C:/Users/Legion/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');}
const root=path.resolve(__dirname,'..');
const cfg=JSON.parse(fs.readFileSync(path.join(__dirname,'settings.json'),'utf8'));
const wearStrength=process.argv.includes('--flat-only')?0:cfg.wear_strength;
const layout=JSON.parse(fs.readFileSync(path.join(__dirname,'layout.json'),'utf8'));
const S=cfg.canvas_size,N=S*S;
const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16));
const cream=rgb(cfg.colors.cream),navy=rgb(cfg.colors.navy),orange=rgb(cfg.colors.orbit);
let state=cfg.wear_seed>>>0;
function random(){state+=0x6D2B79F5;let t=state;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return ((t^t>>>14)>>>0)/4294967296;}
function distanceToEdge(mask){
 const d=new Float32Array(N);
 for(let i=0;i<N;i++)d[i]=mask[i]>=230?10000:0;
 const diag=Math.SQRT2;
 for(let y=1;y<S;y++)for(let x=1;x<S-1;x++){
  const i=y*S+x;d[i]=Math.min(d[i],d[i-1]+1,d[i-S]+1,d[i-S-1]+diag,d[i-S+1]+diag);
 }
 for(let y=S-2;y>=0;y--)for(let x=S-2;x>=1;x--){
  const i=y*S+x;d[i]=Math.min(d[i],d[i+1]+1,d[i+S]+1,d[i+S-1]+diag,d[i+S+1]+diag);
 }
 return d;
}
const toCanvas=(x,y)=>[layout.mark.left+(x-layout.source_crop.left)*layout.scale,layout.mark.top+(y-layout.source_crop.top)*layout.scale];
async function saveRgba(data,file,w=S,h=S){await sharp(data,{raw:{width:w,height:h,channels:4}}).png().toFile(path.join(root,file));}
(async()=>{
 const masks={};
 for(const k of ['body','orbit','rocket','dot'])masks[k]=await sharp(path.join(root,'masks',k+'.png')).greyscale().raw().toBuffer();
 const silhouette=Buffer.alloc(N),wear=Buffer.alloc(N),roleRemoved={};
 for(let i=0;i<N;i++)silhouette[i]=Math.min(255,masks.body[i]+masks.orbit[i]+masks.rocket[i]+masks.dot[i]);
 function cut(i,coverage,role){
  const next=Math.max(wear[i],Math.round(255*Math.min(1,coverage)));
  const removed=(next-wear[i])*masks[role][i]/65025;wear[i]=next;
  return removed;
 }
 function blot(cx,cy,rx,ry,angle,role,dist,protect=2){
  const extent=Math.ceil(Math.max(rx,ry)+1),co=Math.cos(angle),si=Math.sin(angle);
  let removed=0;
  for(let y=Math.floor(cy)-extent;y<=Math.ceil(cy)+extent;y++)for(let x=Math.floor(cx)-extent;x<=Math.ceil(cx)+extent;x++){
   if(x<0||x>=S||y<0||y>=S)continue;
   const i=y*S+x;if(dist[i]<protect||masks[role][i]<230)continue;
   let count=0;
   for(const oy of [.2,.7])for(const ox of [.2,.7]){
    const dx=x+ox-cx,dy=y+oy-cy,u=(dx*co+dy*si)/rx,v=(-dx*si+dy*co)/ry;
    const a=Math.atan2(v,u),boundary=1+0.12*Math.sin(3*a+.8);
    if(u*u+v*v<=boundary*boundary)count++;
   }
   if(count)removed+=cut(i,count/4,role);
  }
  return removed;
 }
 function scratch(points,width,role,dist){
  let removed=0;
  for(let k=1;k<points.length;k++){
   const a=points[k-1],b=points[k],len=Math.hypot(b[0]-a[0],b[1]-a[1]),steps=Math.ceil(len*2);
   for(let j=0;j<=steps;j++){
    const t=j/steps;
    removed+=blot(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,width/2,width/2,0,role,dist,2);
   }
  }
  return removed;
 }
 const metrics={};
 let localPlateEdgePixels=0;
 for(const [role,mask] of Object.entries(masks)){
  const dist=distanceToEdge(mask),eligible=[];
  let inkArea=0;
  for(let i=0;i<N;i++){inkArea+=mask[i]/255;if(dist[i]>3.2)eligible.push(i);}
  const patches=Array.from({length:7},()=>({x:layout.mark.left+random()*layout.mark.width,y:layout.mark.top+random()*layout.mark.height,r:80+random()*210,weight:.3+random()*.6}));
  const target=inkArea*Math.min(.08,Math.max(0,wearStrength))*cfg.wear_multipliers[role];
  let removed=0,attempts=0;
  if(target>0){
   // Five short scratches total: two on the broad H, two along the front orbit,
   // and one following the rocket nose direction. No long cuts or outline wear.
   const sourceScratches={
    body:[[[485,465],[491,462],[498,459]],[[719,792],[725,789],[732,786]]],
    orbit:[[[477,973],[484,972],[490,971]],[[930,849],[936,846],[942,843]]],
    rocket:[[[1040,309],[1045,305],[1050,300]]],
    dot:[]
   };
   for(const line of sourceScratches[role])removed+=scratch(line.map(p=>toCanvas(...p)),1.4,role,dist);
   // Two short, one-pixel exposure irregularities on broad gap-facing H edges.
   // These open the existing gap slightly; they never shift an entire color plate.
   if(role==='body')for(const sourcePoint of [[720,900],[831,859]]){
    const [cx,cy]=toCanvas(...sourcePoint);
    for(let x=Math.round(cx)-5;x<=Math.round(cx)+5;x++){
     if((x-Math.round(cx)+5)%4===1)continue;
     for(let y=Math.round(cy)-5;y<=Math.round(cy)+5;y++){
      const i=y*S+x;
      if(mask[i]>=128&&mask[i+S]<128){
       removed+=cut(i,.7,role);
       removed+=cut(i-S,.2,role);
       localPlateEdgePixels++;
       break;
      }
     }
    }
   }
   // A short broken worn crescent INSIDE the upper-left edge of the small dot.
   if(role==='dot')for(const [a0,a1] of [[204,219],[224,234],[240,250]]){
    const pts=[];for(let a=a0;a<=a1;a+=2){const t=a*Math.PI/180;pts.push(toCanvas(251+48*Math.cos(t),981+48*Math.sin(t)));}
    removed+=scratch(pts,1.5,role,dist);
   }
   while(removed<target&&attempts++<eligible.length*3){
    const i=eligible[Math.floor(random()*eligible.length)],x=i%S,y=Math.floor(i/S);
    let density=.12;
    for(const p of patches)density+=p.weight*Math.exp(-((x-p.x)**2+(y-p.y)**2)/(2*p.r*p.r));
    if(random()>Math.min(.9,density))continue;
    const draw=random();
    const diameter=draw<.88?1+random()*2:draw<.98?2.7+random()*.7:4+random()*1.7;
    const rx=diameter/2,ry=rx*(.65+random()*.35);
    if(dist[i]<Math.max(rx,ry)+2.5)continue;
    removed+=blot(x+random(),y+random(),rx,ry,random()*Math.PI,role,dist);
   }
  }
  roleRemoved[role]=removed;
  metrics[role]={inkAreaPixels:Math.round(inkArea),removedPixels:Math.round(removed),removedPercent:+(100*removed/inkArea).toFixed(3)};
 }
 await sharp(wear,{raw:{width:S,height:S,channels:1}}).png().toFile(path.join(root,'masks/wear.png'));
 const navyMask=Buffer.alloc(N);
 for(let i=0;i<N;i++)navyMask[i]=Math.min(255,masks.body[i]+masks.rocket[i]+masks.dot[i]);
 await sharp(navyMask,{raw:{width:S,height:S,channels:1}}).png().toFile(path.join(root,'masks/navy.png'));
 const flat=Buffer.alloc(N*4),aged=Buffer.alloc(N*4),flatCream=Buffer.alloc(N*4),agedCream=Buffer.alloc(N*4);
 let totalInk=0,totalLoss=0,fullHoles=0,maxCompositeError=0;
 for(let i=0;i<N;i++){
  const alpha=silhouette[i],sum=navyMask[i]+masks.orbit[i],oa=sum?masks.orbit[i]/sum:0;
  const ink=navy.map((v,c)=>Math.round(v*(1-oa)+orange[c]*oa));
  const a=Math.round(alpha*(1-wear[i]/255));
  totalInk+=alpha/255;totalLoss+=(alpha-a)/255;if(alpha>230&&a===0)fullHoles++;
  for(let c=0;c<3;c++){
   flat[4*i+c]=ink[c];aged[4*i+c]=ink[c];
   flatCream[4*i+c]=Math.round(ink[c]*alpha/255+cream[c]*(1-alpha/255));
   agedCream[4*i+c]=Math.round(ink[c]*a/255+cream[c]*(1-a/255));
   maxCompositeError=Math.max(maxCompositeError,Math.abs(agedCream[4*i+c]-Math.round(aged[4*i+c]*a/255+cream[c]*(1-a/255))));
  }
  flat[4*i+3]=alpha;aged[4*i+3]=a;flatCream[4*i+3]=agedCream[4*i+3]=255;
 }
 await saveRgba(flat,'retro_aerospace_flat_transparent.png');
 await saveRgba(flatCream,'retro_aerospace_flat_cream.png');
 await saveRgba(aged,'retro_aerospace_transparent.png');
 await saveRgba(agedCream,'retro_aerospace_cream.png');
 await sharp(agedCream,{raw:{width:S,height:S,channels:4}}).resize(128,128).png().toFile(path.join(root,'previews/retro_aerospace_128.png'));
 await sharp(aged,{raw:{width:S,height:S,channels:4}}).resize(128,128).png().toFile(path.join(root,'previews/retro_aerospace_transparent_128.png'));
 const p=toCanvas(380,365);
 await sharp(agedCream,{raw:{width:S,height:S,channels:4}}).extract({left:Math.round(p[0]),top:Math.round(p[1]),width:560,height:560}).png().toFile(path.join(root,'previews/ink_detail_100percent.png'));
 const outputMetrics={canvas:[S,S],effectiveLogoWidth:layout.mark.width,effectiveWidthPercent:100*layout.mark.width/S,colors:cfg.colors,inkAreaPixels:Math.round(totalInk),missingInkPercent:+(100*totalLoss/totalInk).toFixed(3),fullyTransparentPinholes:fullHoles,creamCompositeMaxPixelError:maxCompositeError,parts:metrics,registration:{globalOffset:0,localPlateEdgePixels,description:'Two very short gap-facing edge exposures, about one pixel deep; original gaps never reduced.'}};
 fs.writeFileSync(path.join(__dirname,'validation.json'),JSON.stringify(outputMetrics,null,2));
 console.log(JSON.stringify(outputMetrics,null,2));
})().catch(e=>{console.error(e);process.exit(1);});
