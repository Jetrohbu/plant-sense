"""Generate legacy PNG launcher icons for PlantSense."""

from PIL import Image, ImageDraw
import math
import os

BASE_DIR = os.path.join(os.path.dirname(__file__), "android", "app", "src", "main", "res")

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size / 2, size / 2
    r = size / 2

    # Green gradient circle (simulate with concentric circles)
    for i in range(int(r), 0, -1):
        t = 1 - (i / r)  # 0 at edge, 1 at center
        # Gradient from #1B5E20 (dark) at top-left to #4CAF50 (light) at bottom-right
        r_c = int(27 + t * (76 - 27))
        g_c = int(94 + t * (175 - 94))
        b_c = int(32 + t * (80 - 32))
        draw.ellipse(
            [cx - i, cy - i, cx + i, cy + i],
            fill=(r_c, g_c, b_c, 255),
        )

    # Scale factor
    s = size / 108.0

    # Draw white leaf
    leaf_points = [
        (44, 72), (36, 64), (30, 52), (34, 40), (38, 28),
        (48, 24), (54, 22), (60, 20), (68, 22), (72, 28),
        (76, 34), (74, 44), (70, 52), (66, 60), (58, 66),
        (54, 70), (50, 74), (46, 74), (44, 72),
    ]
    scaled_leaf = [(x * s, y * s) for x, y in leaf_points]
    draw.polygon(scaled_leaf, fill=(255, 255, 255, 255))

    # Leaf center vein (green line)
    vein_points = [(54, 24), (52, 36), (50, 48), (48, 60), (47, 64), (46, 68), (44, 72)]
    scaled_vein = [(x * s, y * s) for x, y in vein_points]
    vein_width = max(1, int(1.5 * s))
    for i in range(len(scaled_vein) - 1):
        draw.line([scaled_vein[i], scaled_vein[i + 1]], fill=(76, 175, 80, 255), width=vein_width)

    # Side veins
    side_veins = [
        ((52, 34), (44, 40)),
        ((51, 42), (42, 50)),
        ((50, 50), (43, 58)),
    ]
    sv_width = max(1, int(1.0 * s))
    for start, end in side_veins:
        draw.line(
            [(start[0] * s, start[1] * s), (end[0] * s, end[1] * s)],
            fill=(76, 175, 80, 255),
            width=sv_width,
        )

    # Water drop
    drop_points = [
        (42, 68), (40, 72), (38, 76), (39, 79), (42, 80),
        (45, 79), (46, 76), (44, 72), (42, 68),
    ]
    scaled_drop = [(x * s, y * s) for x, y in drop_points]
    draw.polygon(scaled_drop, fill=(255, 255, 255, 180))

    # BLE signal arcs
    arc_configs = [
        # (center_x_offset, radius, alpha)
        (0, 8, 255),
        (0, 13, 200),
        (0, 18, 150),
    ]
    arc_cx = 68 * s
    arc_cy = 38 * s
    arc_width = max(1, int(2 * s))
    for _, radius, alpha in arc_configs:
        r_px = radius * s
        bbox = [arc_cx - r_px, arc_cy - r_px, arc_cx + r_px, arc_cy + r_px]
        draw.arc(bbox, start=-60, end=60, fill=(255, 255, 255, alpha), width=arc_width)

    return img


for folder, px in SIZES.items():
    out_dir = os.path.join(BASE_DIR, folder)
    os.makedirs(out_dir, exist_ok=True)
    icon = draw_icon(px)
    out_path = os.path.join(out_dir, "ic_launcher.png")
    icon.save(out_path, "PNG")
    print(f"Generated {out_path} ({px}x{px})")

print("Done!")
