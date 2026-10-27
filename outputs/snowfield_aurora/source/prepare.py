"""Lock original alpha, build five mutually partitioned component masks."""
import hashlib
import numpy as np
from PIL import Image
from common import *


def main():
    ensure_dirs()
    cfg = read_config()
    original_path = SOURCE / "original_logo.png"
    original = Image.open(original_path).convert("RGBA")
    source = np.array(original)
    alpha = source[..., 3]
    yy, xx = np.indices(alpha.shape)
    visible_y, visible_x = np.where(alpha >= cfg["effective_bbox_alpha_threshold"])
    box = [int(visible_x.min()), int(visible_y.min()), int(visible_x.max() + 1), int(visible_y.max() + 1)]
    cropped = original.crop(tuple(box))
    cropped.save(SOURCE / "original_cropped.png")

    size, width = cfg["canvas_size"], cfg["effective_width"]
    height = round(width * cropped.height / cropped.width)
    left, top = (size - width) // 2, (size - height) // 2
    master = Image.new("RGBA", (size, size))
    master.paste(cropped.resize((width, height), RESAMPLE), (left, top))
    master.save(SOURCE / "original_aligned.png")
    master_alpha = np.array(master.getchannel("A"))
    Image.fromarray(master_alpha).save(MASKS / "original_silhouette.png")
    Image.fromarray(master_alpha).save(MASKS / "silhouette.png")
    silhouette = rgba(np.broadcast_to(rgb("#DCEEFF"), (size, size, 3)), master_alpha)
    silhouette.save(SOURCE / "silhouette_reference.png")

    # Existing source-coordinate labels come from the same original file.
    # They only assign materials; source alpha, including antialiasing, is never replaced.
    raw_labels = np.fromfile(SOURCE / "component_labels.bin", dtype="<i4").reshape(alpha.shape)
    labels = np.where(np.isin(raw_labels, np.arange(1, 9)), raw_labels, 0)
    for _ in range(4):
        old = labels.copy()
        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            near = shift(old, dx, dy)
            select = (labels == 0) & (near > 0)
            labels[select] = near[select]
    seg = cfg["segmentation"]
    orbit = (
        (labels == 5) |
        ((labels == 2) & (yy >= seg["left_orbit_minimum_y"]) &
         (xx < seg["left_orbit_boundary_x_intercept"] + seg["left_orbit_boundary_x_per_y"] * yy))
    )
    dot = labels == 8
    rocket = np.isin(labels, [1, 3, 4]) | ((labels == 2) & (xx > 780) & (yy < 540))
    theta = np.deg2rad(seg["ellipse_reference_angle_degrees"])
    cx, cy = seg["ellipse_reference_center"]
    v = -(xx - cx) * np.sin(theta) + (yy - cy) * np.cos(theta)
    orbit_front = orbit & (labels == 5) & (v >= 0)
    orbit_back = orbit & ~orbit_front
    role = np.zeros(alpha.shape, dtype=np.uint8)
    role[orbit_front] = 1
    role[orbit_back] = 2
    role[dot] = 3
    role[rocket] = 4
    Image.fromarray(role).save(MASKS / "source_part_ids.png")

    # Resize all parts identically, then normalize them to the independently
    # resized original alpha. Cumulative rounding guarantees exact integer sums.
    fitted = []
    for i, name in enumerate(ROLES):
        source_mask = Image.fromarray(np.where(role == i, alpha, 0).astype(np.uint8))
        source_mask.crop(tuple(box)).save(MASKS / f"source_{name}.png")
        canvas = Image.new("L", (size, size))
        canvas.paste(source_mask.crop(tuple(box)).resize((width, height), RESAMPLE), (left, top))
        fitted.append(np.asarray(canvas, dtype=np.float32))
    total = sum(fitted)
    fitted[0][(total == 0) & (master_alpha > 0)] = 1
    total = sum(fitted)
    denom = np.maximum(total, 1)
    cumulative = np.zeros((size, size), dtype=np.float32)
    prior = np.zeros((size, size), dtype=np.uint8)
    masks = {}
    for i, name in enumerate(ROLES):
        cumulative += fitted[i]
        target = np.uint8(np.clip(np.rint(cumulative / denom * master_alpha), 0, 255))
        if i == len(ROLES) - 1:
            target = master_alpha.copy()
        mask = target.astype(np.int16) - prior.astype(np.int16)
        assert mask.min() >= 0
        masks[name] = mask.astype(np.uint8)
        Image.fromarray(masks[name]).save(MASKS / f"{name}.png")
        prior = target
    # Refine only the material junction where the rear orbit passes under the H.
    # Fit the existing H edge above/below the crossing, then supersample its
    # occlusion coverage. The silhouette alpha and every other part stay fixed.
    edge_metrics = {"enabled": False}
    refinement = seg.get("left_crossing_edge_refinement", {})
    if refinement.get("enabled"):
        def fit_edge(row_limits):
            points = []
            for row in range(row_limits[0], row_limits[1] + 1):
                estimate = seg["left_orbit_boundary_x_intercept"] + seg["left_orbit_boundary_x_per_y"] * row
                start, end = int(estimate) - 12, int(estimate) + 13
                values = alpha[row, start:end + 1].astype(float) / 255
                crossings = np.where((values[:-1] < 0.5) & (values[1:] >= 0.5))[0]
                if len(crossings):
                    j = int(crossings[np.argmin(np.abs(start + crossings - estimate))])
                    x = start + j + (0.5 - values[j]) / (values[j + 1] - values[j])
                    points.append((row, x))
            return np.polyfit(np.array(points)[:, 0], np.array(points)[:, 1], 1)

        upper, lower = fit_edge(refinement["upper_fit_rows"]), fit_edge(refinement["lower_fit_rows"])
        scale = width / cropped.width
        rx0, ry0, rx1, ry1 = refinement["local_source_box"]
        lx = max(0, int(np.floor(left + (rx0 - box[0]) * scale)))
        ly = max(0, int(np.floor(top + (ry0 - box[1]) * scale)))
        ux = min(size, int(np.ceil(left + (rx1 - box[0]) * scale)))
        uy = min(size, int(np.ceil(top + (ry1 - box[1]) * scale)))
        py, px = np.indices((uy - ly, ux - lx), dtype=np.float64)
        px += lx
        py += ly
        samples = refinement["supersampling"]
        coverage = np.zeros_like(px)
        ystart, yend = refinement["blend_rows"]
        for oy in (np.arange(samples) + 0.5) / samples - 0.5:
            sample_y = (py + oy - top + 0.5) / scale + box[1] - 0.5
            t = np.clip((sample_y - ystart) / (yend - ystart), 0, 1)
            t = t * t * (3 - 2 * t)
            edge_x = np.polyval(upper, sample_y) * (1 - t) + np.polyval(lower, sample_y) * t
            for ox in (np.arange(samples) + 0.5) / samples - 0.5:
                sample_x = (px + ox - left + 0.5) / scale + box[0] - 0.5
                coverage += sample_x >= edge_x
        coverage /= samples * samples
        body_old = masks["body"][ly:uy, lx:ux].copy()
        back_old = masks["orbit_back"][ly:uy, lx:ux].copy()
        pair = body_old.astype(np.uint16) + back_old.astype(np.uint16)
        nearby_back = np.asarray(
            Image.fromarray(masks["orbit_back"]).filter(ImageFilter.MaxFilter(9))
        )[ly:uy, lx:ux]
        affected = (nearby_back > 64) & (pair > 0)
        proposed = np.uint8(np.rint(pair * coverage))
        body_new = np.where(affected, proposed, body_old).astype(np.uint8)
        back_new = (pair - body_new).astype(np.uint8)
        masks["body"][ly:uy, lx:ux] = body_new
        masks["orbit_back"][ly:uy, lx:ux] = back_new
        for name in ["body", "orbit_back"]:
            Image.fromarray(masks[name]).save(MASKS / f"{name}.png")
        edge_metrics = {
            "enabled": True, "source_box": refinement["local_source_box"],
            "upper_fitted_edge": upper.tolist(), "lower_fitted_edge": lower.tolist(),
            "supersampling": samples, "changed_mask_pixels": int(np.sum(body_new != body_old)),
            "silhouette_alpha_changed_pixels": 0
        }
    straight_metrics = {"enabled": False}
    if seg.get("straight_edge_rebuild", {}).get("enabled"):
        from edge_geometry import straighten_edge
        master_alpha, straight_metrics = straighten_edge(
            alpha, raw_labels, masks, master_alpha,
            {"size": size, "left": left, "top": top, "width": width, "height": height,
             "crop": box, "scale": width / cropped.width},
            seg["straight_edge_rebuild"]
        )
        for name in ROLES:
            Image.fromarray(masks[name]).save(MASKS / f"{name}.png")
        Image.fromarray(master_alpha).save(MASKS / "silhouette.png")
        rgba(np.broadcast_to(rgb("#DCEEFF"), (size, size, 3)), master_alpha).save(SOURCE / "geometry_reference.png")
    assert np.array_equal(sum(m.astype(np.uint16) for m in masks.values()), master_alpha)
    fields = dict(zip(ROLES, map(rgb, ["#F1CE4B", "#F76B83", "#45AFD2", "#B284F1", "#80D58C"])))
    segmentation = composite_fields(fields, masks, master_alpha)
    flatten(segmentation, "#081421").save(PREVIEWS / "part_separation.png")
    layout = {
        "source": {"file": "original_logo.png", "size": list(original.size), "mode": "RGBA",
                   "sha256": hashlib.sha256(original_path.read_bytes()).hexdigest()},
        "crop_xyxy": box,
        "bbox_alpha_threshold": cfg["effective_bbox_alpha_threshold"],
        "canvas": [size, size],
        "logo": {"left": left, "top": top, "width": width, "height": height},
        "scale": width / cropped.width,
        "alpha_policy": "Crop only; preserve original alpha inside crop; resize with Lanczos. All masks partition this exact final alpha.",
        "unassigned_nonzero_source_pixels_inside_crop": int(np.sum(
            (labels[box[1]:box[3], box[0]:box[2]] == 0) &
            (alpha[box[1]:box[3], box[0]:box[2]] > 0)
        )),
        "mask_partition_max_error": 0
    }
    layout["left_crossing_edge_refinement"] = edge_metrics
    layout["straight_edge_rebuild"] = {k: v for k, v in straight_metrics.items() if k != "crossing_edge_samples"}
    if seg.get("straight_edge_rebuild", {}).get("enabled"):
        layout["alpha_policy"] = "Original alpha preserved except the explicitly repaired left H edge and its rear-orbit occlusion; all parts partition the repaired master."
    save_json(SOURCE / "layout.json", layout)
    progress("阶段一、二通过：母版与部件蒙版",
             f"使用原始 PNG 的 Alpha；裁框 {box}；标志排版 {width}×{height}。"
             "主体、前景轨道、后景轨道、圆点、火箭五张蒙版之和与当前几何母版 Alpha 逐像素相同。"
             "先前旧日航天的原坐标分区数据仅用于识别部件，未使用其做旧或归一化透明通道。",
             "检查分区图，建立无纹理基础色、柔和左上光和深蓝／灰底预览。")
    print(json.dumps(layout, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
