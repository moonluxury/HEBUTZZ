"""Delivery checks against the original, not against a previous art version."""
import hashlib
import numpy as np
from PIL import Image
from common import *


def main():
    cfg = read_config()
    layout = json.loads((SOURCE / "layout.json").read_text(encoding="utf-8"))
    original = Image.open(SOURCE / "original_logo.png").convert("RGBA")
    crop = original.crop(layout["crop_xyxy"])
    fitted = crop.resize((layout["logo"]["width"], layout["logo"]["height"]), RESAMPLE)
    reference = Image.new("RGBA", tuple(layout["canvas"]))
    reference.paste(fitted, (layout["logo"]["left"], layout["logo"]["top"]))
    reference_alpha = np.asarray(reference.getchannel("A"), dtype=np.int16)
    core = Image.open(FINAL / "logo_snowfield_aurora_transparent.png").convert("RGBA")
    core_array = np.asarray(core)
    core_alpha = core_array[..., 3].astype(np.int16)
    masks_sum = sum(np.asarray(Image.open(MASKS / f"{name}.png"), dtype=np.uint16) for name in ROLES)
    geometry_alpha = np.asarray(Image.open(MASKS / "silhouette.png"), dtype=np.int16)
    allowed_path = MASKS / "geometry_authorized_region.png"
    authorized = np.asarray(Image.open(allowed_path)) > 0 if allowed_path.exists() else np.zeros_like(reference_alpha, dtype=bool)
    alpha_error = np.abs(core_alpha - reference_alpha)
    geometry_error = np.abs(core_alpha - geometry_alpha)
    mask_error = np.abs(masks_sum.astype(np.int16) - geometry_alpha)
    background = Image.open(LAYERS / "background_complete.png").convert("RGBA")
    expected = np.asarray(Image.alpha_composite(background, core).convert("RGB"), dtype=np.int16)
    actual = np.asarray(Image.open(FINAL / "logo_snowfield_aurora_presentation.png").convert("RGB"), dtype=np.int16)
    composite_error = np.abs(expected - actual)
    outside = core_array[core_alpha == 0, :3]
    bg_pixels = np.asarray(background)[..., :3].astype(np.float32)
    opaque = core_alpha > 240
    luma_weight = np.array([0.2126, 0.7152, 0.0722], np.float32)
    rocket_mask = np.asarray(Image.open(MASKS / "rocket.png")) > 240
    x0, y0, x1, y1 = layout["crop_xyxy"]
    original_alpha = np.asarray(original.getchannel("A"))
    outside_crop = original_alpha.copy()
    outside_crop[y0:y1, x0:x1] = 0
    report = {
        "canvas": list(core.size),
        "source_size": list(original.size),
        "effective_logo_width_percent": 100 * layout["logo"]["width"] / cfg["canvas_size"],
        "source_original_sha256": hashlib.sha256((SOURCE / "original_logo.png").read_bytes()).hexdigest(),
        "source_alpha_max_outside_effective_crop": int(outside_crop.max()),
        "final_alpha_vs_scaled_original_max_error": int(alpha_error.max()),
        "final_alpha_vs_scaled_original_changed_pixels": int(np.sum(alpha_error != 0)),
        "final_alpha_vs_repaired_geometry_max_error": int(geometry_error.max()),
        "original_alpha_changes_outside_authorized_edge_region": int(np.sum((alpha_error != 0) & ~authorized)),
        "part_mask_sum_vs_repaired_geometry_max_error": int(mask_error.max()),
        "presentation_vs_background_plus_exact_core_max_error": int(composite_error.max()),
        "fully_transparent_pixel_rgb_max": int(outside.max()) if outside.size else 0,
        "source_opaque_pixels_made_transparent": int(np.sum((reference_alpha >= 128) & (core_alpha == 0))),
        "background_luma_max": float(np.max(bg_pixels @ luma_weight)),
        "rocket_luma_max": float(np.max(core_array[..., :3][rocket_mask] @ luma_weight)),
        "logo_luma_mean": float(np.mean(core_array[..., :3][opaque] @ luma_weight)),
        "previews": {
            str(s): list(Image.open(PREVIEWS / f"logo_snowfield_aurora_{s}.png").size)
            for s in [512, 256, 128]
        },
        "core_sha256": hashlib.sha256((FINAL / "logo_snowfield_aurora_transparent.png").read_bytes()).hexdigest(),
        "presentation_sha256": hashlib.sha256((FINAL / "logo_snowfield_aurora_presentation.png").read_bytes()).hexdigest(),
        "limitations": [
            "Original is a 1254-pixel raster; 2048-pixel output is resampled, not recovered native vector detail.",
            "The effective crop discards only outlying alpha values below 8.",
            "The left H edge and its orbit occlusion are explicitly reconstructed as a continuous straight boundary; other source alpha is preserved.",
            "Light backgrounds are inspection/adaptation references; the primary presentation is dark."
        ]
    }
    assert report["final_alpha_vs_repaired_geometry_max_error"] == 0
    assert report["original_alpha_changes_outside_authorized_edge_region"] == 0
    assert report["part_mask_sum_vs_repaired_geometry_max_error"] == 0
    assert report["presentation_vs_background_plus_exact_core_max_error"] == 0
    assert report["fully_transparent_pixel_rgb_max"] == 0
    assert report["source_alpha_max_outside_effective_crop"] < cfg["effective_bbox_alpha_threshold"]
    assert tuple(core.size) == (2048, 2048)
    save_json(SOURCE / "validation.json", report)
    progress("阶段八：自动验收通过",
             "透明核心与修复后几何母版的 Alpha 差异为 0；原始轮廓的变化仅限于授权修复的斜边区域；五张蒙版合成误差为 0；"
             "展示版与独立背景＋同一核心 PNG 的合成误差为 0。"
             "已生成 512／256／128 预览及深蓝、灰底、棋盘格检查图。",
             "人工查看预览与对照图，完成可编辑文件说明、复现验证和压缩包。")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
