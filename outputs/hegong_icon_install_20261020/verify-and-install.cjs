const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {execFileSync} = require('child_process');
const root = 'E:/zhengzhi';
const work = __dirname;
const magick = 'F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const rgba = file => execFileSync(magick,[file,'-depth','8','rgba:-'],{maxBuffer:12e6});
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const comparisons = [];
for (const [extracted,source] of [
 ['apk-icon.webp','hegong_zhigu_android_192.png'],
 ['apk-icon_foreground.webp','hegong_zhigu_adaptive_foreground.png'],
 ['apk-icon_background.webp','hegong_zhigu_adaptive_background.png']
]) {
 const a=rgba(path.join(work,extracted));
 const b=rgba(root+'/assets/branding/'+source);
 if (a.length!==b.length) throw new Error('APK icon dimension mismatch: '+source);
 let squared=0;
 for(let p=0;p<a.length;p+=4) {
  for(let c=0;c<3;c++) squared+=(a[p+c]*a[p+3]/255-b[p+c]*b[p+3]/255)**2;
  squared+=(a[p+3]-b[p+3])**2;
 }
 const normalizedRmse=Math.sqrt(squared/a.length)/255;
 if (normalizedRmse>0.002) throw new Error('APK icon does not match approved artwork: '+source);
 comparisons.push({extracted,source,normalizedRmse});
}
const big=rgba(path.join(work,'live-jiaoda-blue-big.png'));
const small=rgba(path.join(work,'live-jiaoda-blue-small.png'));
if (!big.equals(small)) throw new Error('Window icon override did not apply to both icon handles');
let translucent=0;
for(let p=3;p<big.length;p+=4) if(big[p]>0&&big[p]<255) translucent++;
if (translucent<80) throw new Error('Runtime icon lost antialiasing');
for(const name of ['export-windows-local.log','export-android-local.log','live-jiaoda-blue.log']) {
 const log=fs.readFileSync(path.join(work,name),'utf8');
 if (/\bERROR:|SCRIPT ERROR:|Parse Error:/i.test(log)) throw new Error('Errors in '+name);
 if (/保存文件：res:\/\/outputs\//.test(log)) throw new Error('Design previews included in export');
}
const buildNames=['河工开物.exe','河工开物.console.exe','河工开物.apk'];
for(const name of buildNames) if(!fs.existsSync(root+'/build/jiaoda-icon-20261020/'+name)) throw new Error('Missing staged artifact: '+name);
const backup=root+'/build/before-jiaoda-icon-20261020';
fs.mkdirSync(backup,{recursive:true});
const installed=[];
for(const name of buildNames) {
 const source=root+'/build/jiaoda-icon-20261020/'+name;
 const dest=root+'/build/'+name;
 const saved=backup+'/'+name;
 if(!fs.existsSync(saved)) fs.copyFileSync(dest,saved);
 fs.copyFileSync(source,dest);
 if(sha(source)!==sha(dest)) throw new Error('Installed artifact hash mismatch: '+name);
 installed.push({file:dest,bytes:fs.statSync(dest).size,sha256:sha(dest)});
}
const report={
 status:'complete',date:'2026-10-20',approved_image:root+'/outputs/河工知谷_交大蓝配色_20261020/河工知谷_交大蓝004E97_透明.png',
 windows:{release_export:'passed',gui_startup:'passed',dpi:96,runtime_big_and_small_icons_match:true,translucent_pixels:translucent,executable_icon:'visually checked',console_wrapper_icon:'Updated existing launcher resource using rcedit and visually checked',other_display_scaling_tested:false},
 android:{debug_export:'passed',signature_v2:true,signature_v3:true,certificate_matches_previous:true,package:'com.zhengzhi.quiz',device_runtime_tested:false,icon_comparisons:comparisons,existing_template_warning:'Unused themed_icon.xml reference warning also occurs in previous APK.'},
 export_configuration:'Exclude outputs/* design-preview files from both export presets; no runtime references to this folder.',
 installed,previous_builds:backup,previous_assets:path.join(work,'previous_assets')
};
fs.writeFileSync(path.join(work,'delivery-status.json'),JSON.stringify(report,null,2));
const approved=root+'/outputs/河工知谷_交大蓝配色_20261020';
const recordPath=approved+'/制作记录.txt';
fs.writeFileSync(recordPath,fs.readFileSync(recordPath,'utf8').replace('原图与项目现用图标未替换。此图是生成式配色提案，渐变和辅助色不是单一固定 HEX。','2026-10-20：用户确认采用本版，已更新项目资源及 Windows / Android 发布文件。原始预览图保留；应用尺寸资源位于“应用图标”目录。此图为生成式配色，渐变和辅助色不是单一固定 HEX。'));
fs.writeFileSync(approved+'/应用替换说明.txt',`河工知谷 · 交大蓝图标应用记录\n2026-10-20\n\n已采用用户选定的交大蓝版本，生成统一的透明 PNG、多尺寸 ICO、Android 启动图标及自适应前景/背景。外圈整理为带抗锯齿的正圆；图案内部颜色与选定图缩放后的像素一致。\n\n更新文件\n${installed.map(x=>x.file).join('\n')}\n\nWindows：重新导出 release，实际启动并检查了窗口大小图标及 EXE 图标，保留 Lanczos 预缩放处理。实测环境为 96 DPI / 100% 缩放。\nAndroid：重新导出 debug 包，v2/v3 签名验证通过，与原包证书一致；包内图标与项目资源比较通过。未在手机上安装运行。\n打包配置：排除 outputs/* 设计预览，避免无关输出进入安装包。\n\n旧版本备份：${backup}\n旧图标备份：${path.join(work,'previous_assets')}\n详细验证：${path.join(work,'delivery-status.json')}\n`);
console.log(JSON.stringify({status:report.status,installed,comparisons,translucent_pixels:translucent,backup},null,2));
