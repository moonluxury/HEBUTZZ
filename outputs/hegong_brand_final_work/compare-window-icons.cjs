const fs=require('fs');const {execFileSync}=require('child_process');
const work=__dirname,magick='F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const files=['win32-from-256.png','win32-from-32.png','win32-from-16.png','win32-from-png256.png'];
const details=[];
for(const file of files){
 const data=execFileSync(magick,[work+'/'+file,'-depth','8','rgba:-']);
 let semi=0,opaque=0,transparent=0;
 for(let i=3;i<data.length;i+=4){if(data[i]===0)transparent++;else if(data[i]===255)opaque++;else semi++;}
 details.push({file,semi,opaque,transparent});
 execFileSync(magick,[work+'/'+file,'-background','#202020','-alpha','remove','-filter','point','-resize','800%',work+'/'+file.replace('.png','-8x.png')]);
}
const args=['-size','1100x350','xc:#f2f5f8'];
const labels=['256 DIB -> Win32','32 DIB -> Win32','16 DIB -> Win32','256 PNG -> Win32'];
for(let i=0;i<files.length;i++)args.push('(',work+'/'+files[i].replace('.png','-8x.png'),')','-geometry',`+${10+275*i}+62`,'-compose','over','-composite','-fill','#142a3c','-font','C:/Windows/Fonts/arial.ttf','-pointsize','20','-gravity','NorthWest','-annotate',`+${10+275*i}+20`,labels[i]);
execFileSync(magick,[...args,work+'/runtime-scaling-comparison.png']);
fs.writeFileSync(work+'/runtime-scaling-statistics.json',JSON.stringify(details,null,2));console.log(JSON.stringify(details,null,2));
