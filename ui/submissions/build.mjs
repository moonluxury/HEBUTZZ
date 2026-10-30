import {build} from 'esbuild';
import {createHash} from 'node:crypto';
import {mkdir,copyFile,writeFile,readFile,readdir} from 'node:fs/promises';
await mkdir('dist',{recursive:true});
await build({entryPoints:['src/app.js'],bundle:true,format:'iife',target:['chrome110'],outfile:'dist/app.js',minify:true,legalComments:'eof',loader:{'.woff':'file','.woff2':'file','.ttf':'file','.svg':'text'},assetNames:'fonts/[name]-[hash]'});
const version=createHash('sha256').update(await readFile('dist/app.js')).update(await readFile('dist/app.css')).digest('hex').slice(0,16);
await writeFile('dist/index.html',(await readFile('src/index.html','utf8')).replace('app.js','app.js?v='+version).replace('app.css','app.css?v='+version));
await writeFile('dist/build.json',JSON.stringify({version}));
const packages=['@tiptap/core','@tiptap/starter-kit','@tiptap/extension-table','@tiptap/extension-task-list','@tiptap/extension-task-item','katex','dompurify','esbuild'];
const notices=[];
for(const name of packages){const p=JSON.parse(await readFile(`node_modules/${name}/package.json`,'utf8'));let license='';for(const filename of ['LICENSE','LICENSE.md','LICENSE.txt']){try{license=await readFile(`node_modules/${name}/${filename}`,'utf8');break;}catch{}}notices.push(`${name} ${p.version}\nLicense: ${p.license}\n${license}`);}
await writeFile('dist/THIRD_PARTY_LICENSES.txt',notices.join('\n\n----------------\n\n'));

await copyFile('vendor/NotoSansSC-OFL.txt','dist/NotoSansSC-OFL.txt');

for (const file of await readdir('dist/fonts')) {if(!file.endsWith('.import')) await writeFile(`dist/fonts/${file}.import`,'[remap]\nimporter="keep"\n');}
