const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {execFileSync} = require('child_process');
const root = 'E:/zhengzhi';
const work = __dirname;
const approved = root + '/outputs/河工知谷_交大蓝配色_20261020';
const source = approved + '/河工知谷_交大蓝004E97_透明.png';
const output = approved + '/应用图标';
const previous = path.join(work, 'previous_assets');
const magick = 'F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
for (const dir of [output, previous]) fs.mkdirSync(dir, {recursive: true});
const run = args => execFileSync(magick, args.map(String), {maxBuffer: 24e6, env: {...process.env, MAGICK_THREAD_LIMIT: '2'}});
const save = (args, file) => {run([...args, '-strip', '-depth', '8', '-define', 'png:color-type=6', file]);return file;};
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

// Normalize the outer alpha edge for app use; retain the approved interior colors.
const mask = save(['-size','4096x4096','xc:black','-fill','white','-draw','circle 2046,2046 4046,2046','-filter','Lanczos','-resize','1024x1024'],path.join(work,'circle-mask.png'));
const master = save([source,'-alpha','off','-filter','Lanczos','-resize','1024x1024!',mask,'-alpha','off','-compose','CopyOpacity','-composite'],output+'/河工知谷_交大蓝_1024.png');
for (const size of [512,256,128,64,48,32,16]) save([master,'-filter','Lanczos','-resize',`${size}x${size}`],output+`/河工知谷_交大蓝_${size}.png`);
const ico = output+'/河工知谷_交大蓝.ico';
run([master,'-filter','Lanczos','-define','icon:auto-resize=256,128,64,48,32,16',ico]);
const legacy = save([master,'-filter','Lanczos','-resize','180x180','-gravity','center','-background','none','-extent','192x192'],output+'/河工知谷_Android_192.png');
const foreground = save([master,'-filter','Lanczos','-resize','264x264','-gravity','center','-background','none','-extent','432x432'],output+'/河工知谷_Android_前景432.png');
const background = save(['-size','432x432','xc:#F7F9FC'],output+'/河工知谷_Android_背景432.png');

const alpha = run([master,'-alpha','extract','-depth','8','gray:-']);
const expectedAlpha = run([mask,'-depth','8','gray:-']);
if (!alpha.equals(expectedAlpha)) throw new Error('Master alpha does not match antialiased circle');
for (const [x,y] of [[0,0],[511,0],[0,511],[1023,511],[511,1023]]) if (alpha[y*1024+x] !== 0) throw new Error('Missing transparent margin');
if (alpha[511*1024+511] !== 255) throw new Error('Center must be opaque');
const sourceRgb = run([source,'-alpha','off','-filter','Lanczos','-resize','1024x1024!','-depth','8','rgb:-']);
const masterRgb = run([master,'-alpha','off','-depth','8','rgb:-']);
let checked = 0, maxChannelDifference = 0;
for (let p=0;p<alpha.length;p++) if (alpha[p] === 255) {
  checked++;
  for(let c=0;c<3;c++) maxChannelDifference = Math.max(maxChannelDifference,Math.abs(sourceRgb[p*3+c]-masterRgb[p*3+c]));
}
if (maxChannelDifference > 1) throw new Error('Approved interior colors changed');
const mappings = {
 'hegong_zhigu_icon.png': master,
 'hegong_zhigu_icon.ico': ico,
 'hegong_zhigu_android_192.png': legacy,
 'hegong_zhigu_adaptive_foreground.png': foreground,
 'hegong_zhigu_adaptive_background.png': background
};
const config = fs.readFileSync(root+'/project.godot','utf8') + fs.readFileSync(root+'/export_presets.cfg','utf8');
const results = [];
for (const [name, src] of Object.entries(mappings)) {
 const dst = root+'/assets/branding/'+name;
 if (!config.includes(name)) throw new Error('Asset not referenced: '+name);
 const backup = path.join(previous,name);
 if (fs.existsSync(dst) && !fs.existsSync(backup)) fs.copyFileSync(dst,backup);
 fs.copyFileSync(src,dst);
 if (sha(src)!==sha(dst)) throw new Error('Asset copy mismatch');
 results.push({file: dst, sha256: sha(dst), size: run(['identify','-format','%wx%h ',dst]).toString().trim()});
}
const exporter = fs.readFileSync(root+'/outputs/hegong_brand_final_work/export.ps1','utf8')
 .replaceAll('build\\icon-refresh-20261019','build\\jiaoda-icon-20261020')
 .replaceAll('outputs\\hegong_brand_final_work\\export-','outputs\\hegong_icon_install_20261020\\export-');
fs.writeFileSync(path.join(work,'export.ps1'),exporter);
const report = {source,source_sha256:sha(source),master,checked_interior_pixels:checked,max_rgb_difference:maxChannelDifference,alpha_verified:true,results};
fs.writeFileSync(path.join(work,'asset-installation.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
