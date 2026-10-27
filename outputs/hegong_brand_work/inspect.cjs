const {execFileSync}=require('child_process');
const p='C:/Users/Legion/.codex/generated_images/01a151ff-5b88-7140-956a-c4c22cabbc69/exec-d8be2b0a-0534-4d92-bad0-5d47912a608a.png';
const b=execFileSync('F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe',[p,'-alpha','extract','-depth','8','gray:-'],{maxBuffer:10e6});
const w=1254;
const rows=[];
for(let y=0;y<w;y++){let first=-1,last=-1;for(let x=0;x<w;x++){if(b[y*w+x]>240){if(first<0)first=x;last=x;}}if(y%50===0 || (y>45&&y<65) ||(y>1190&&y<1205))rows.push({y,first,last});}
console.log(JSON.stringify(rows));
