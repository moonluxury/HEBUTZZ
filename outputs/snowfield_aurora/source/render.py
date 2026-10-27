"""Deterministic winter material and atmosphere, confined to source masks."""
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from common import *


def main(base_only=False):
    ensure_dirs()
    cfg = read_config()
    layout = json.loads((SOURCE / "layout.json").read_text(encoding="utf-8"))
    S = cfg["canvas_size"]
    W = layout["logo"]["width"]
    unit = W / 1500
    color = {name: rgb(value) for name, value in cfg["palette"].items()}
    alpha = np.asarray(Image.open(MASKS / "silhouette.png"), dtype=np.uint8)
    masks = {name: np.asarray(Image.open(MASKS / f"{name}.png"), dtype=np.uint8) for name in ROLES}
    # Keep texture placement fixed during local mask maintenance.
    sampling_path = MASKS / "frost_sampling_body.png"
    frost_sampling_mask = np.asarray(Image.open(sampling_path), dtype=np.uint8) if sampling_path.exists() else masks["body"]
    assert np.array_equal(sum(m.astype(np.uint16) for m in masks.values()), alpha)
    yy, xx = np.indices((S, S), dtype=np.float32)
    sx = (xx - layout["logo"]["left"]) / layout["scale"] + layout["crop_xyxy"][0]
    sy = (yy - layout["logo"]["top"]) / layout["scale"] + layout["crop_xyxy"][1]
    material = cfg["material"]
    rng_grain = np.random.default_rng(cfg["seed"] + 11)

    def patch(x, y, rx, ry):
        return np.exp(-0.5 * (((sx - x) / rx) ** 2 + ((sy - y) / ry) ** 2))

    def solid(value):
        return np.broadcast_to(value, (S, S, 3)).copy()

    def edges(name):
        m = masks[name].astype(np.float32) / 255
        hi = blur(np.maximum(m - shift(m, round(4 * unit), round(4 * unit)), 0), 1.5 * unit)
        sh = blur(np.maximum(m - shift(m, -round(10 * unit), -round(9 * unit)), 0), 7 * unit)
        return m, hi, sh

    # Phase 3: clean opaque bases, one broad upper-left soft light.
    body = solid(color["body"])
    body = blend(body, color["snow"], 0.14 + 0.58 * patch(475, 430, 255, 310))
    body = blend(body, color["glacier"], 0.17 * np.clip((sx + sy - 1050) / 950, 0, 1))
    m_body, hi_body, sh_body = edges("body")
    body = blend(body, color["snow"], hi_body * 0.48)
    body = blend(body, color["glacier"], sh_body * material["inner_shading_strength"])

    dot = solid(color["body"])
    down_right = np.clip(((sx - 251) + (sy - 981) + 50) / 130, 0, 1)
    dot = blend(dot, color["glacier"], down_right * 0.43)
    dot = blend(dot, color["snow"], 0.55 * patch(230, 954, 38, 39))

    rocket = solid(color["body"])
    rocket = blend(rocket, color["snow"], 0.35 + 0.19 * patch(1040, 270, 110, 160))
    m_rocket, hi_rocket, sh_rocket = edges("rocket")
    rocket = blend(rocket, color["glacier"], sh_rocket * 0.18)
    rocket = blend(rocket, color["snow"], hi_rocket * 0.45)
    rocket = blend(rocket, color["snow"], 0.74 * patch(1121, 241, 17, 18))

    seg = cfg["segmentation"]
    axis_angle = np.deg2rad(seg["ellipse_reference_angle_degrees"])
    center_x, center_y = seg["ellipse_reference_center"]
    axis_v = -(sx - center_x) * np.sin(axis_angle) + (sy - center_y) * np.cos(axis_angle)
    front_base = solid(color["glacier"])
    back_base = front_base * (1 - 0.09 * np.clip(-axis_v / 75, 0, 1))[..., None]
    base_fields = {"body": body, "orbit_front": front_base, "orbit_back": back_base,
                   "dot": dot, "rocket": rocket}
    base = composite_fields(base_fields, masks, alpha)
    base.save(LAYERS / "base_transparent.png")
    flatten(base, cfg["palette"]["night"]).save(PREVIEWS / "base_night.png")
    flatten(base, "#9099A2").save(PREVIEWS / "base_neutral_gray.png")
    flatten(base, cfg["palette"]["night"]).resize((256, 256), RESAMPLE).save(PREVIEWS / "base_256.png")
    progress("阶段三：无纹理基础分色已生成",
             "当前几何母版的 Alpha 未变；基础色和柔和左上光已建立。已输出深夜蓝、中性灰底及 256 像素预览。"
             "主体和连接结构为霜蓝白，轨道为冰川蓝，火箭尖端有小面积冷白提亮。",
             "检查基础分色；随后叠加轮廓内薄雪、霜晶、轨道极光和微弱映色。")
    if base_only:
        print("Base stage ready.")
        return

    # Phase 4: low-contrast, locally clustered frost; no holes or alpha changes.
    grain = rng_grain.normal(0, 1, (S, S)).astype(np.float32)
    coarse = np.asarray(
        Image.fromarray(np.uint8(rng_grain.uniform(50, 205, (44, 44))))
        .resize((S, S), Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(6 * unit)),
        dtype=np.float32
    ) / 255 - 0.5
    clusters = np.clip(
        0.88 * patch(537, 405, 82, 55) +
        0.72 * patch(855, 680, 99, 75) +
        0.58 * patch(390, 812, 64, 75), 0, 1)
    base_grain = grain * material["surface_grain_strength"] * 40
    body += (base_grain + coarse * 4.0 * clusters)[..., None]
    body = np.clip(body, 0, 255)
    body = blend(body, color["glacier"], clusters * 0.065)

    rng_frost = np.random.default_rng(cfg["seed"] + 22)
    frost = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(frost)
    count = 0
    for _ in range(36000):
        x, y = int(rng_frost.integers(0, S)), int(rng_frost.integers(0, S))
        if frost_sampling_mask[y, x] < 240 or rng_frost.random() > clusters[y, x] * 0.83:
            continue
        d = float(rng_frost.uniform(0.8, 2.7)) * unit
        light = int(rng_frost.integers(65, 230))
        draw.ellipse((x, y, x + d, y + d * rng_frost.uniform(0.55, 1.05)), fill=light)
        count += 1
        if rng_frost.random() < 0.08:
            for _ in range(3):
                px, py = x + rng_frost.normal(0, 5 * unit), y + rng_frost.normal(0, 4 * unit)
                draw.line((px, py, px + 1.5 * unit, py - 1.0 * unit), fill=light // 2, width=1)
    frost_field = np.asarray(frost, dtype=np.float32) / 255
    frost_field *= m_body
    Image.fromarray(np.uint8(frost_field * 255)).save(LAYERS / "frost_crystal_mask.png")
    body = blend(body, color["snow"], frost_field * material["frost_strength"])
    crystal_microshadow = shift(frost_field, 1, 1) * (1 - frost_field)
    body = blend(body, color["glacier"], crystal_microshadow * material["frost_strength"] * 0.08)
    # A faint frosty bloom makes the small grains belong to a surface, not dust.
    body = blend(body, color["snow"], clusters * 0.09 * material["frost_strength"])

    # Select only two upward-facing broad edge areas. Snow stays inside alpha.
    snow_regions = np.clip(
        patch(565, 329, 85, 15) + 0.9 * patch(891, 593, 100, 80), 0, 1)
    upward_edge = np.maximum(m_body - shift(m_body, 0, round(5 * unit)), 0)
    taper = np.clip(0.82 + coarse * 0.45, 0.5, 1)
    snow_field = blur(upward_edge * snow_regions * taper, 0.5 * unit) * m_body
    Image.fromarray(np.uint8(np.clip(snow_field, 0, 1) * 255)).save(LAYERS / "thin_snow_mask.png")
    body = blend(body, color["snow"], snow_field * material["thin_snow_strength"])
    under_snow = blur(shift(snow_field, 0, round(3 * unit)), 2.0 * unit)
    body = blend(body, color["glacier"], under_snow * 0.10 * material["thin_snow_strength"])
    dot += (grain * 0.52)[..., None]
    dot = blend(dot, color["snow"], 0.025 * np.clip(grain, 0, 2))
    progress("阶段四：雪霜材质完成",
             f"薄雪限制在两处上缘内部，固定种子生成 {count} 个局部霜粒种子；"
             "轻磨砂与霜晶均只改变 RGB，未挖透明孔，未扩展雪帽。",
             "沿既有轨道路径布置青绿与蓝紫，再加入少量主体映色。")

    # Phase 5: theta is only a color coordinate; it never creates or alters paths.
    seg = cfg["segmentation"]
    a = np.deg2rad(seg["ellipse_reference_angle_degrees"])
    cx, cy = seg["ellipse_reference_center"]
    rx, ry = seg["ellipse_reference_radii"]
    u = (sx - cx) * np.cos(a) + (sy - cy) * np.sin(a)
    v = -(sx - cx) * np.sin(a) + (sy - cy) * np.cos(a)
    theta = np.arctan2(v / ry, u / rx)
    radius = np.sqrt((u / rx) ** 2 + (v / ry) ** 2)
    stops = [
        (-np.pi, color["glacier"]),
        (-2.25, color["glacier"] * 0.91),
        (-0.62, color["aurora_violet"]),
        (-0.10, color["glacier"]),
        (0.68, color["aurora_green"]),
        (1.24, color["aurora_green"] * 0.86 + color["body"] * 0.14),
        (2.47, color["glacier"]),
        (np.pi, color["glacier"])
    ]
    orbit_rgb = solid(color["glacier"])
    for (start, c0), (end, c1) in zip(stops[:-1], stops[1:]):
        region = (theta >= start) & (theta < end)
        t = np.clip((theta - start) / (end - start), 0, 1)
        t = t * t * (3 - 2 * t)
        interpolation = c0 + (c1 - c0) * t[..., None]
        orbit_rgb[region] = interpolation[region]
    orbit_rgb = blend(solid(color["glacier"]), orbit_rgb, cfg["orbit"]["aurora_strength"])
    # Two broad, fading, streamwise variations; neither runs around the whole ring.
    ribbon1 = np.exp(-((radius - (0.94 + 0.035 * np.sin(theta * 2))) / 0.075) ** 2)
    ribbon1 *= np.exp(-((theta - 1.10) / 0.73) ** 4)
    ribbon2 = np.exp(-((radius - 1.06) / 0.11) ** 2) * np.exp(-((theta + 0.35) / 0.42) ** 2)
    variation = np.clip(ribbon1 + ribbon2 * 0.45, 0, 1)
    orbit_rgb = blend(orbit_rgb, color["body"], variation * cfg["orbit"]["flow_variation_strength"])
    orbit_rgb += (grain * 0.38)[..., None]
    orbit_front = orbit_rgb
    # Smooth rear falloff at split boundaries so there is no hard color seam.
    rear_drop = (1 - cfg["orbit"]["rear_brightness"]) * np.clip(-v / 75, 0, 1)
    orbit_back = orbit_rgb * (1 - rear_drop[..., None])
    orbit_alpha = (masks["orbit_front"].astype(np.uint16) + masks["orbit_back"]).astype(np.uint8)
    rgba(orbit_rgb, orbit_alpha).save(LAYERS / "aurora_orbit.png")

    reflection_green = patch(720, 894, 185, 93)
    reflection_violet = patch(941, 588, 150, 120)
    reflection_strength = material["aurora_reflection_strength"]
    Image.fromarray(np.uint8(reflection_green * m_body * 255)).save(LAYERS / "reflection_green_mask.png")
    Image.fromarray(np.uint8(reflection_violet * m_body * 255)).save(LAYERS / "reflection_violet_mask.png")
    body = blend(body, color["aurora_green"], reflection_green * reflection_strength)
    body = blend(body, color["aurora_violet"], reflection_violet * reflection_strength * 0.75)
    dot = blend(dot, color["aurora_green"], 0.04 * patch(280, 982, 24, 32))
    rocket = blend(rocket, color["aurora_violet"], 0.025 * patch(910, 495, 92, 86))
    progress("阶段五：轨道极光与映色完成",
             "青绿沿前景弧段中右部展开，右上回绕段使用蓝紫；弧向两条宽淡变化带在两端渐隐。"
             f"主体环境映色强度为 {reflection_strength:.0%}，轨道依然使用原始不透明色带蒙版。",
             "确认圆点与火箭亮度主次，保存核心透明版。")
    final_fields = {
        "body": body, "orbit_front": orbit_front, "orbit_back": orbit_back,
        "dot": dot, "rocket": rocket
    }
    core = composite_fields(final_fields, masks, alpha)
    core.save(FINAL / "logo_snowfield_aurora_transparent.png")
    for name in ROLES:
        rgba(final_fields[name], masks[name]).save(LAYERS / f"part_{name}.png")
    progress("阶段六：圆点、火箭及核心标志完成",
             "圆点采用左上亮、右下暗的柔和霜蓝；火箭使用更浅的本色并只在尖端小面积提亮。"
             "连接细线保留在主体系统；核心没有外光、尾焰或透明质感。所有效果均未改变 Alpha。",
             "生成独立低对比背景，直接与同一张核心 PNG 合成；检查多背景和小尺寸。")

    # Phase 7: independent quiet night, one main curtain, faint secondary veil.
    bg_cfg = cfg["background"]
    nx, ny = xx / S, yy / S
    ambient = 0.16 + 0.35 * ny + 0.14 * np.exp(-((nx - 0.58) / 0.54) ** 2)
    background_base = blend(solid(color["night"]), color["night_soft"], ambient)
    rgba(background_base, np.full((S, S), 255, np.uint8)).save(LAYERS / "background_base.png")
    curve = S * (0.32 - 0.19 * (nx - 0.27) + 0.035 * np.exp(-((nx - 0.48) / 0.13) ** 2))
    curtain_width = S * (0.045 + 0.018 * np.exp(-((nx - 0.56) / 0.24) ** 2))
    curtain = np.exp(-0.5 * ((yy - curve) / curtain_width) ** 2)
    curtain += 0.28 * np.exp(-0.5 * ((yy - curve + S * 0.08) / (S * 0.095)) ** 2)
    end_fade = np.exp(-((nx - 0.56) / 0.43) ** 6)
    gentle_folds = 0.88 + 0.065 * np.sin(nx * 64) + 0.04 * np.sin(nx * 117 + 0.4)
    curtain = np.clip(curtain * end_fade * gentle_folds, 0, 1)
    curtain_alpha = np.uint8(np.clip(curtain * bg_cfg["aurora_strength"], 0, 1) * 255)
    aurora = rgba(solid(color["aurora_green"]), curtain_alpha)
    aurora.save(LAYERS / "background_aurora.png")
    secondary = np.exp(-0.5 * ((yy - curve + S * 0.075) / (S * 0.045)) ** 2)
    secondary *= np.exp(-((nx - 0.74) / 0.28) ** 4)
    secondary_layer = rgba(solid(color["aurora_violet"]),
                           np.uint8(secondary * bg_cfg["secondary_aurora_strength"] * 255))
    secondary_layer.save(LAYERS / "background_aurora_secondary.png")
    haze = np.clip((ny - 0.67) / 0.33, 0, 1) ** 1.9
    haze *= 0.7 + 0.3 * np.exp(-((nx - 0.38) / 0.65) ** 2)
    haze_layer = rgba(solid(color["glacier"]), np.uint8(haze * bg_cfg["snow_haze_strength"] * 255))
    haze_layer.save(LAYERS / "background_snow_haze.png")
    snow_points = Image.new("RGBA", (S, S))
    sd = ImageDraw.Draw(snow_points)
    rng_points = np.random.default_rng(cfg["seed"] + 33)
    exclusion = blur(alpha.astype(np.float32) / 255, 12 * unit)
    placed = 0
    for _ in range(400):
        if placed >= bg_cfg["snow_points"]:
            break
        x, y = int(rng_points.uniform(0.10, 0.90) * S), int(rng_points.uniform(0.12, 0.90) * S)
        if exclusion[y, x] > 0.002:
            continue
        diameter = float(rng_points.uniform(1, 3)) * unit
        opacity = int(255 * bg_cfg["snow_point_strength"] * rng_points.uniform(0.4, 0.9))
        sd.ellipse((x, y, x + diameter, y + diameter), fill=(*map(int, color["snow"]), opacity))
        placed += 1
    snow_points.save(LAYERS / "background_snow_points.png")
    background = Image.open(LAYERS / "background_base.png").convert("RGBA")
    for layer in [aurora, secondary_layer, haze_layer, snow_points]:
        background = Image.alpha_composite(background, layer)
    background.convert("RGB").save(LAYERS / "background_complete.png")
    presentation = Image.alpha_composite(background, core).convert("RGB")
    presentation.save(FINAL / "logo_snowfield_aurora_presentation.png")
    progress("阶段七：展示背景完成",
             f"深夜底、低强度青绿主幕、蓝紫辅带、底部淡雾与 {placed} 个雪点独立保存。"
             "没有外发光层；展示版直接合成已保存的透明核心，未另画一枚 Logo。",
             "核验透明通道、同体合成、512／256／128 预览与深蓝／灰／棋盘格边缘。")

    # Previews are made from the same core, without sharpening or geometry edits.
    night_core = flatten(core, cfg["palette"]["night"])
    for size in [512, 256, 128]:
        night_core.resize((size, size), RESAMPLE).save(PREVIEWS / f"logo_snowfield_aurora_{size}.png")
        core.resize((size, size), RESAMPLE).save(PREVIEWS / f"core_transparent_{size}.png")
    night_core.save(PREVIEWS / "core_night_2048.png")
    flatten(core, "#C4CBD1").save(PREVIEWS / "core_light_gray.png")
    check = np.where(((xx // 48 + yy // 48) % 2)[..., None] == 0, rgb("#A9B3BF"), rgb("#CAD2DC"))
    checker = Image.alpha_composite(rgba(check, np.full((S, S), 255, np.uint8)), core).convert("RGB")
    checker.save(PREVIEWS / "core_checkerboard.png")
    panel([Image.open(SOURCE / "silhouette_reference.png"), base, core],
          ["原始轮廓基准", "无纹理基础分色", "最终透明核心"], PREVIEWS / "structure_comparison.png")
    panel([night_core, flatten(core, "#C4CBD1"), checker],
          ["深夜蓝", "浅灰", "棋盘格"], PREVIEWS / "edge_checks.png")
    # Full-resolution detail: left upper edge and frost, orbit green/white border.
    x = int(layout["logo"]["left"] + (465 - layout["crop_xyxy"][0]) * layout["scale"])
    y = int(layout["logo"]["top"] + (315 - layout["crop_xyxy"][1]) * layout["scale"])
    night_core.crop((x, y, x + 520, y + 520)).save(PREVIEWS / "frost_detail_100percent.png")
    save_json(SOURCE / "render_metrics.json", {
        "canvas": [S, S], "effective_width": W, "effective_width_percent": 100 * W / S,
        "frost_seed_count": count, "snow_points": placed, "seed": cfg["seed"],
        "external_glow": False, "background_strengths": bg_cfg,
        "processing": "Pillow and NumPy; source alpha is immutable; procedural material fields."
    })
    print("Rendered core, presentation, independent layers and previews.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-only", action="store_true")
    main(parser.parse_args().base_only)
