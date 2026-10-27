const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const crypto = require('crypto');
const root = 'E:/zhengzhi';
const work = __dirname;
const magick = 'F:/ImageMagick-7.1.2-Q16-HDRI/magick.exe';
const stats = [];
for (const state of ['before', 'after']) {
  for (const kind of ['big', 'small']) {
    const name = `live-${state}-${kind}.png`;
    const rgba = execFileSync(magick, [path.join(work, name), '-depth', '8', 'rgba:-']);
    let transparent = 0, translucent = 0, opaque = 0;
    for (let i = 3; i < rgba.length; i += 4) {
      if (rgba[i] === 0) transparent++;
      else if (rgba[i] === 255) opaque++;
      else translucent++;
    }
    stats.push({ state, kind, transparent, translucent, opaque });
  }
}
const args = ['-size', '720x670', 'xc:#f2f5f8', '-font', 'C:/Windows/Fonts/msyh.ttc', '-fill', '#173447', '-gravity', 'NorthWest'];
args.push('-pointsize', '27', '-annotate', '+38+22', '运行中的图标：修复前 / 修复后');
for (let row = 0; row < 2; row++) {
  const kind = row ? 'small' : 'big';
  const y = 110 + row * 270;
  args.push('-pointsize', '18', '-annotate', `+38+${y - 35}`, row ? '窗口左上角 · 16 像素（放大 12 倍）' : '任务栏 · 32 像素（放大 6 倍）');
  for (let col = 0; col < 2; col++) {
    const state = col ? 'after' : 'before';
    const x = 90 + col * 340;
    args.push('(', path.join(work, `live-${state}-drawn-${kind}.png`), '-filter', 'point', '-resize', '192x192!', ')', '-geometry', `+${x}+${y}`, '-compose', 'over', '-composite');
    args.push('-pointsize', '18', '-annotate', `+${x + 65}+${y + 200}`, col ? '修复后' : '修复前');
  }
}
args.push('-pointsize', '15', '-annotate', '+38+636', '实测环境：Windows，96 DPI / 100% 缩放；放大仅用于观察像素边缘。');
execFileSync(magick, [...args, path.join(work, '窗口图标_修复前后.png')]);

const backup = path.join(root, 'build/before-window-icon-fix-20261019');
fs.mkdirSync(backup, { recursive: true });
const builds = [];
for (const name of ['河工开物.exe', '河工开物.console.exe']) {
  const target = path.join(root, 'build', name);
  const staged = path.join(root, 'build/icon-refresh-20261019', name);
  const saved = path.join(backup, name);
  if (!fs.existsSync(saved)) fs.copyFileSync(target, saved);
  fs.copyFileSync(staged, target);
  const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
  if (hash(staged) !== hash(target)) throw new Error('Installed build differs from checked build');
  builds.push({ file: target, bytes: fs.statSync(target).size, sha256: hash(target) });
}
const report = {
  status: 'complete', dpi: 96, scale_percent: 100,
  fix: 'Resize the accepted source with Lanczos at system icon size before calling DisplayServer.set_icon on Windows.',
  verified: ['Windows release export', 'GUI startup', 'WM_GETICON handles for big and small icons', 'Win32 DrawIconEx at 32px and 16px', 'Installed executable hash matches verified executable'],
  limitations: ['Other display scaling settings have not been tested on a physical display.'],
  artwork_changed: false, android_changed: false, backup, builds, icon_alpha_statistics: stats
};
fs.writeFileSync(path.join(work, 'window-icon-fix-status.json'), JSON.stringify(report, null, 2));
const deliveryPath = path.join(work, 'delivery-status.json');
const delivery = JSON.parse(fs.readFileSync(deliveryPath, 'utf8'));
delivery.windows.runtime_icon_fix = report;
fs.writeFileSync(deliveryPath, JSON.stringify(delivery, null, 2));
console.log(JSON.stringify({ builds, stats, report: path.join(work, 'window-icon-fix-status.json') }, null, 2));
