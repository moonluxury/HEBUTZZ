const fs = require('fs');
const path = require('path');
let sharp;
try {
  sharp = require('sharp');
} catch {
  sharp = require('C:/Users/Legion/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
}
const root = path.resolve(__dirname, '..');

(async () => {
  const input = path.join(__dirname, 'reentry_generated.png');
  const { data, info } = await sharp(input).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let x0 = info.width, y0 = info.height, x1 = -1, y1 = -1;
  for (let y = 0; y < info.height; y++) {
    for (let x = 0; x < info.width; x++) {
      if (data[(y * info.width + x) * 4 + 3] >= 64) {
        x0 = Math.min(x0, x); y0 = Math.min(y0, y);
        x1 = Math.max(x1, x); y1 = Math.max(y1, y);
      }
    }
  }
  if (x1 < x0) throw new Error('No visible logo pixels.');
  x0 = Math.max(0, x0 - 2); y0 = Math.max(0, y0 - 2);
  x1 = Math.min(info.width - 1, x1 + 2); y1 = Math.min(info.height - 1, y1 + 2);
  const crop = { left: x0, top: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 };
  const width = 1536;
  const height = Math.round(width * crop.height / crop.width);
  const left = Math.round((2048 - width) / 2), top = Math.round((2048 - height) / 2);
  const fitted = await sharp(input).extract(crop).resize(width, height, { kernel: 'lanczos3' }).png().toBuffer();
  const transparent = await sharp({
    create: { width: 2048, height: 2048, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } }
  }).composite([{ input: fitted, left, top }]).png().toBuffer();
  fs.writeFileSync(path.join(root, 'reentry_transparent.png'), transparent);
  const dark = await sharp(transparent).flatten({ background: '#060B18' }).png().toBuffer();
  fs.writeFileSync(path.join(root, 'reentry_dark.png'), dark);
  fs.mkdirSync(path.join(root, 'previews'), { recursive: true });
  await sharp(dark).resize(128, 128).png().toFile(path.join(root, 'previews/reentry_128.png'));
  await sharp(dark).extract({
    left: left + 850, top: Math.max(0, top - 10), width: 640, height: 640
  }).png().toFile(path.join(root, 'previews/heat_detail.png'));
  const layout = {
    canvas: [2048, 2048],
    generatedSize: [info.width, info.height],
    generatedCrop: crop,
    logo: { left, top, width, height },
    background: '#060B18',
    method: 'Built-in image_gen color and surface edit; proportional export preserves generated alpha. Generated raster, not a pixel-locked vector reconstruction.'
  };
  fs.writeFileSync(path.join(__dirname, 'layout.json'), JSON.stringify(layout, null, 2));
  console.log(JSON.stringify(layout, null, 2));
})().catch(error => { console.error(error); process.exit(1); });
