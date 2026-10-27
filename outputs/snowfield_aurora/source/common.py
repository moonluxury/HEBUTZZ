from pathlib import Path
from datetime import datetime
import json
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "source"
MASKS = SOURCE / "masks"
LAYERS = SOURCE / "layers"
PREVIEWS = ROOT / "previews"
FINAL = ROOT / "final"
ROLES = ["body", "orbit_front", "orbit_back", "dot", "rocket"]
RESAMPLE = Image.Resampling.LANCZOS


def read_config():
    return json.loads((SOURCE / "config.json").read_text(encoding="utf-8"))


def save_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def rgb(value):
    return np.array([int(value[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


def shift(array, dx, dy):
    out = np.zeros_like(array)
    h, w = array.shape[:2]
    xa, xb = max(0, dx), min(w, w + dx)
    ya, yb = max(0, dy), min(h, h + dy)
    out[ya:yb, xa:xb] = array[ya - dy:yb - dy, xa - dx:xb - dx]
    return out


def blur(field, radius):
    a = np.uint8(np.clip(field, 0, 1) * 255 + 0.5)
    return np.asarray(Image.fromarray(a).filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255


def blend(base, color, strength):
    t = np.clip(strength, 0, 1)
    if np.ndim(t) == 2:
        t = t[..., None]
    return base * (1 - t) + np.asarray(color, dtype=np.float32) * t


def rgba(colors, alpha):
    out = np.empty((*alpha.shape, 4), dtype=np.uint8)
    out[..., :3] = np.uint8(np.clip(colors, 0, 255) + 0.5)
    out[..., 3] = alpha
    out[alpha == 0, :3] = 0
    return Image.fromarray(out)


def flatten(image, background):
    base = Image.new("RGBA", image.size, background)
    return Image.alpha_composite(base, image).convert("RGB")


def composite_fields(fields, masks, alpha):
    result = np.zeros((*alpha.shape, 3), dtype=np.float32)
    denom = np.maximum(alpha.astype(np.float32), 1)
    for role in ROLES:
        weight = masks[role].astype(np.float32) / denom
        result += fields[role] * weight[..., None]
    return rgba(result, alpha)


def font(size):
    for file in ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/arial.ttf"]:
        if Path(file).exists():
            return ImageFont.truetype(file, size)
    return ImageFont.load_default(size=size)


def panel(images, labels, path, tile=512):
    canvas = Image.new("RGB", (len(images) * tile, tile + 64), "#081421")
    draw = ImageDraw.Draw(canvas)
    for i, (im, label) in enumerate(zip(images, labels)):
        im = im.convert("RGBA").resize((tile, tile), RESAMPLE)
        canvas.paste(flatten(im, "#081421"), (i * tile, 64))
        draw.text((i * tile + 24, 20), label, fill="#DCEEFF", font=font(22))
    canvas.save(path)


def progress(stage, result, next_step):
    text = (
        f"\n## {datetime.now().isoformat(timespec='seconds')} · {stage}\n\n"
        f"{result}\n\n下一步：{next_step}\n"
    )
    with (ROOT / "progress.md").open("a", encoding="utf-8") as handle:
        handle.write(text)


def ensure_dirs():
    for directory in (MASKS, LAYERS, PREVIEWS, FINAL):
        directory.mkdir(parents=True, exist_ok=True)
