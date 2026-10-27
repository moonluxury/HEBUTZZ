"""Rebuild one straight H edge and the small rear-orbit occlusion junction."""
import numpy as np
from PIL import Image
from common import MASKS, SOURCE, save_json


def straighten_edge(source_alpha, raw_labels, masks, original_canvas_alpha, layout, options):
    a = source_alpha.astype(np.float64) / 255
    points = []
    for y in range(355, 891):
        if 650 <= y <= 705:
            continue
        estimate = 608 - 0.406 * y
        start = int(estimate) - 14
        values = a[y, start:start + 30]
        crossings = np.where((values[:-1] < 0.5) & (values[1:] >= 0.5))[0]
        if len(crossings):
            j = int(crossings[np.argmin(abs(start + crossings - estimate))])
            x = start + j + (0.5 - values[j]) / (values[j + 1] - values[j])
            points.append((y, x))
    points = np.array(points)
    line = np.polyfit(points[:, 0], points[:, 1], 1)

    # The visible, unobstructed rear-arc edges immediately left of the crossing
    # determine their short continuation into the occlusion junction.
    upper, lower = [], []
    rows = np.arange(a.shape[0])
    for x in range(270, 327):
        candidates = np.where(
            (a[:, x] > 0.5) & (raw_labels[:, x] == 2) &
            (rows >= 650) & (x < 608 - 0.406 * rows)
        )[0]
        if len(candidates):
            top, bottom = int(candidates.min()), int(candidates.max())
            upper.append((x, top - 1 + (0.5 - a[top - 1, x]) / (a[top, x] - a[top - 1, x])))
            lower.append((x, bottom + (a[bottom, x] - 0.5) / (a[bottom, x] - a[bottom + 1, x])))
    upper, lower = np.array(upper), np.array(lower)
    top_curve = np.polyfit(upper[:, 0], upper[:, 1], 2)
    bottom_curve = np.polyfit(lower[:, 0], lower[:, 1], 2)

    size = layout["size"]
    left, top = layout["left"], layout["top"]
    x0, y0 = layout["crop"][:2]
    scale = layout["scale"]
    yscale = layout["height"] / (layout["crop"][3] - layout["crop"][1])
    yy, xx = np.indices((size, size), dtype=np.float64)
    sx = (xx - left + 0.5) / scale + x0 - 0.5
    sy = (yy - top + 0.5) / yscale + y0 - 0.5
    distance = sx - np.polyval(line, sy)
    region = (sy > 340) & (sy < 910) & (np.abs(distance) < 6.5)
    py, px = np.where(region)
    coverage_body = np.zeros(len(px), dtype=np.float64)
    coverage_back = np.zeros(len(px), dtype=np.float64)
    sub = options.get("supersampling", 32)
    offsets = (np.arange(sub) + 0.5) / sub - 0.5
    for oy in offsets:
        sample_y = (py + oy - top + 0.5) / yscale + y0 - 0.5
        boundary = np.polyval(line, sample_y)
        for ox in offsets:
            sample_x = (px + ox - left + 0.5) / scale + x0 - 0.5
            is_body = sample_x >= boundary
            is_orbit = (
                (sample_y >= np.polyval(top_curve, sample_x)) &
                (sample_y <= np.polyval(bottom_curve, sample_x)) &
                (sample_x > 270) & (sample_x < 365) &
                (sample_y > 640) & (sample_y < 740)
            )
            coverage_body += is_body
            coverage_back += is_orbit & ~is_body
    coverage_body /= sub * sub
    coverage_back /= sub * sub

    def smooth(t):
        t = np.clip(t, 0, 1)
        return t * t * (3 - 2 * t)

    gate = smooth((sy[py, px] - 340) / 30) * smooth((910 - sy[py, px]) / 30)
    gate *= smooth(6.5 - np.abs(distance[py, px]))
    old_body = masks["body"][py, px].astype(np.float64)
    old_back = masks["orbit_back"][py, px].astype(np.float64)
    # Keep the source's nearly opaque material coverage (253/255); sample
    # geometric coverage once, rather than multiplying two antialiased edges.
    new_body = np.rint(old_body * (1 - gate) + 253 * coverage_body * gate).astype(np.uint8)
    new_back = np.rint(old_back * (1 - gate) + 253 * coverage_back * gate).astype(np.uint8)
    masks["body"][py, px] = new_body
    masks["orbit_back"][py, px] = new_back
    total = sum(m.astype(np.uint16) for m in masks.values())
    assert total.max() <= 255
    result_alpha = total.astype(np.uint8)
    Image.fromarray(np.uint8(region) * 255).save(MASKS / "geometry_authorized_region.png")
    changed_alpha = result_alpha != original_canvas_alpha
    Image.fromarray(np.uint8(changed_alpha) * 255).save(MASKS / "geometry_alpha_changes.png")

    # Check the actual 50%-coverage H edge through the crossing and on both
    # sides against the SAME straight line. This catches a smooth but bent seam.
    residuals, edge_samples = [], []
    for row in range(size):
        original_y = (row - top + 0.5) / yscale + y0 - 0.5
        if not 390 <= original_y <= 860:
            continue
        source_edge = np.polyval(line, original_y)
        expected_x = (source_edge - x0 + 0.5) * scale + left - 0.5
        start = int(np.floor(expected_x)) - 3
        values = masks["body"][row, start:start + 8].astype(float) / 253
        crossings = np.where((values[:-1] < 0.5) & (values[1:] >= 0.5))[0]
        assert len(crossings) == 1
        j = int(crossings[0])
        actual_x = start + j + (0.5 - values[j]) / (values[j + 1] - values[j])
        residuals.append(abs(actual_x - expected_x))
        if 650 <= original_y <= 710:
            edge_samples.append([row, expected_x, actual_x])
    # Linear interpolation of box-filtered coverage has a phase-dependent
    # subpixel bias; 0.10 px bounds that bias without admitting a geometric kink.
    assert max(residuals) < 0.10, max(residuals)
    metrics = {
        "method": "One continuous straight edge, jointly supersampled with rear-orbit occlusion",
        "body_edge_x_of_y": line.tolist(),
        "rear_arc_upper_y_of_x": top_curve.tolist(),
        "rear_arc_lower_y_of_x": bottom_curve.tolist(),
        "supersampling": sub,
        "maximum_measured_edge_deviation_pixels": max(residuals),
        "changed_alpha_pixels": int(changed_alpha.sum()),
        "alpha_changes_outside_authorized_region": int(np.sum(changed_alpha & ~region)),
        "crossing_edge_samples": edge_samples
    }
    save_json(SOURCE / "straight_edge_validation.json", metrics)
    return result_alpha, metrics
