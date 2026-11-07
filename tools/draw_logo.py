"""Draws the Fishing Mastery Forever logo: a float on night water with ripples, a fishing line, a
crescent moon, and a fish below the surface. Original artwork, no game assets.

Usage (repository root): python tools/draw_logo.py docs/images
Writes logo-1024.png and logo-400.png (CurseForge project logo). Needs Pillow; the other tools use
the standard library only.
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 1600  # drawing size; scaled down for smooth edges
OUT = sys.argv[1]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Background: rounded square, dusk sky above the water line, deep water below.
bg = Image.new("RGBA", (S, S))
px = bg.load()
horizon = int(S * 0.56)
for y in range(S):
    if y < horizon:
        c = lerp((24, 38, 74), (64, 86, 140), y / horizon)
    else:
        c = lerp((18, 70, 96), (6, 24, 44), (y - horizon) / (S - horizon))
    for x in range(S):
        px[x, y] = c + (255,)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.2), fill=255)
img.paste(bg, (0, 0), mask)
d = ImageDraw.Draw(img)

# Moon and its glow on the water.
mx, my, mr = int(S * 0.74), int(S * 0.2), int(S * 0.085)
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([mx - mr * 2, my - mr * 2, mx + mr * 2, my + mr * 2],
                             fill=(255, 236, 170, 70))
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.03))
img.alpha_composite(glow)
# Crescent: a disc with an offset disc cut out of its mask.
moon = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(moon)
md.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=255)
off = int(mr * 0.55)
md.ellipse([mx - mr + off, my - mr - int(mr * 0.3), mx + mr + off, my + mr - int(mr * 0.3)], fill=0)
img.paste(Image.new("RGBA", (S, S), (255, 238, 186, 255)), (0, 0), moon)
d = ImageDraw.Draw(img)
for i, w in enumerate((0.16, 0.11, 0.07)):
    yy = horizon + int(S * (0.04 + 0.035 * i))
    d.line([mx - int(S * w), yy, mx + int(S * w), yy], fill=(255, 230, 160, 150 - 35 * i),
           width=int(S * 0.008))

# Fish below the surface.
fx, fy = int(S * 0.36), int(S * 0.8)
fish = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(fish)
fd.ellipse([fx - int(S * 0.13), fy - int(S * 0.05), fx + int(S * 0.11), fy + int(S * 0.05)],
           fill=(120, 200, 210, 120))
fd.polygon([(fx + int(S * 0.09), fy), (fx + int(S * 0.19), fy - int(S * 0.06)),
            (fx + int(S * 0.19), fy + int(S * 0.06))], fill=(120, 200, 210, 120))
fish = fish.filter(ImageFilter.GaussianBlur(S * 0.004))
img.alpha_composite(fish)

# Ripples around the bobber.
bx, by = int(S * 0.5), horizon + int(S * 0.02)
for i, (rx, ry) in enumerate(((0.36, 0.075), (0.27, 0.055), (0.18, 0.036))):
    d.ellipse([bx - int(S * rx), by - int(S * ry), bx + int(S * rx), by + int(S * ry)],
              outline=(150, 220, 235, 90 + 50 * i), width=int(S * 0.012))

# Fishing line from the top left corner down to the bobber.
line_pts = []
for k in range(60):
    t = k / 59
    x = int(S * 0.08 + (bx - S * 0.08) * t)
    y = int(S * 0.05 + (by - S * 0.305 - S * 0.05) * t + math.sin(t * math.pi) * S * 0.08)
    line_pts.append((x, y))
d.line(line_pts, fill=(235, 240, 245, 230), width=int(S * 0.009), joint="curve")

# Bobber: a tall float, red cap over a white body, thin antenna, the lower part under water.
bw, bh = int(S * 0.095), int(S * 0.16)  # half width, half height
bcy = by - int(S * 0.07)  # center
float_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fl = ImageDraw.Draw(float_img)
d.line([bx, bcy - bh - int(S * 0.075), bx, bcy - bh + int(S * 0.02)], fill=(214, 44, 44, 255),
       width=int(S * 0.016))
body = [bx - bw, bcy - bh, bx + bw, bcy + bh]
fl.ellipse(body, fill=(246, 246, 240, 255))
cap = Image.new("L", (S, S), 0)
ImageDraw.Draw(cap).rectangle([0, 0, S, bcy - int(bh * 0.15)], fill=255)
red = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(red).ellipse(body, fill=(214, 44, 44, 255))
float_img.paste(red, (0, 0), Image.composite(cap, Image.new("L", (S, S), 0), red.split()[3]))
fl = ImageDraw.Draw(float_img)
fl.arc([bx - int(bw * 0.72), bcy - int(bh * 0.82), bx + int(bw * 0.2), bcy + int(bh * 0.3)],
       200, 260, fill=(255, 255, 255, 170), width=int(S * 0.014))
img.alpha_composite(float_img)
# Water over the part below the surface: the water gradient, a little see-through.
under = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(under).rectangle([bx - bw - 4, by + int(S * 0.005), bx + bw + 4, bcy + bh + 4],
                                fill=(16, 62, 88, 215))
umask = Image.new("L", (S, S), 0)
ImageDraw.Draw(umask).ellipse(body, fill=255)
img.paste(under, (0, 0), Image.composite(under.split()[3], Image.new("L", (S, S), 0), umask))
d = ImageDraw.Draw(img)
d.arc([bx - int(bw * 1.15), by - int(S * 0.012), bx + int(bw * 1.15), by + int(S * 0.03)], 0, 180,
      fill=(190, 235, 245, 230), width=int(S * 0.01))

img = Image.composite(img, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)
os.makedirs(OUT, exist_ok=True)
for size in (1024, 400):
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, "logo-%d.png" % size))
print("ok")
