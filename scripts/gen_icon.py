"""Generate StockAI cube launcher icon — 1024×1024 PNG."""
from PIL import Image, ImageDraw
import math

SIZE = 1024
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Blue gradient background
for y in range(SIZE):
    t = y / SIZE
    r = int(0x1a + t * (0x0d - 0x1a))
    g = int(0x3a + t * (0x2a - 0x3a))
    b = int(0x8a + t * (0x6a - 0x8a))
    draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

# Rounded rectangle mask
mask = Image.new("L", (SIZE, SIZE), 0)
mask_draw = ImageDraw.Draw(mask)
radius = int(SIZE * 0.22)
mask_draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
img.putalpha(mask)

# Cube geometry (matches _CubeLogoPainter)
w, h = SIZE, SIZE
pts = [
    (w * 0.5,  h * 0.08),   # 0 top
    (w * 0.92, h * 0.29),   # 1 top-right
    (w * 0.92, h * 0.71),   # 2 bottom-right
    (w * 0.5,  h * 0.92),   # 3 bottom
    (w * 0.08, h * 0.71),   # 4 bottom-left
    (w * 0.08, h * 0.29),   # 5 top-left
]
center = (w * 0.5, h * 0.5)
stroke = int(w * 0.055)
color = (255, 255, 255, 235)

def draw_line_rounded(d, p1, p2, width, fill):
    d.line([p1, p2], fill=fill, width=width)
    r = width // 2
    for px, py in (p1, p2):
        d.ellipse([px - r, py - r, px + r, py + r], fill=fill)

# Hexagon edges
for i in range(len(pts)):
    draw_line_rounded(draw, pts[i], pts[(i + 1) % len(pts)], stroke, color)

# Three inner lines: top(0), bottom-right(2), bottom-left(4) → center
for idx in (0, 2, 4):
    draw_line_rounded(draw, pts[idx], center, stroke, color)

out = "/home/yaakov/code/inventory/stockai/assets/icon/launcher_icon.png"
import os; os.makedirs(os.path.dirname(out), exist_ok=True)
img.save(out)
print(f"Saved {out}")
