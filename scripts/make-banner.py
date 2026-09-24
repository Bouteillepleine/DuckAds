"""Generates the two banner images.

  module/webroot/banner.png  the module card wash. The manager draws it cropped at
                             alpha 0.18 under a fade, so it carries shapes and colour
                             only, never text.
  docs/banner.png            the README and release header, with the wordmark.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = (10, 12, 18)
AMBER = (255, 200, 87)
GREEN = (74, 222, 128)
TXT = (238, 241, 248)
MUTED = (141, 150, 171)

BOLD = "C:/Windows/Fonts/seguibl.ttf"
SEMI = "C:/Windows/Fonts/seguisb.ttf"
REG = "C:/Windows/Fonts/segoeui.ttf"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size, c1, c2, base=BG, strength=1.0):
    w, h = size
    img = Image.new("RGB", size, base)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.75) + (y / h * 0.25)
            px[x, y] = lerp(c1, c2, min(1.0, max(0.0, t))) if strength >= 1 else lerp(
                base, lerp(c1, c2, t), strength
            )
    return img


def ring(draw, cx, cy, r, width, colour):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=colour, width=width)


def block_mark(draw, cx, cy, r, width, colour):
    ring(draw, cx, cy, r, width, colour)
    d = r * 0.7071
    draw.line([cx - d, cy - d, cx + d, cy + d], fill=colour, width=width)


def make_card_banner(path):
    w, h = 1200, 400
    img = diagonal_gradient((w, h), AMBER, GREEN)

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # a field of dots standing in for domains, thinning out to the right
    for row in range(7):
        for col in range(34):
            x = 40 + col * 35
            y = 34 + row * 56
            fade = max(0.0, 1.0 - (x / w) * 1.15)
            rr = 3 + 5 * fade
            a = int(70 * fade)
            if a <= 2:
                continue
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(10, 12, 18, a))

    # the block mark, big and off to the right where the card has room
    block_mark(d, int(w * 0.78), int(h * 0.5), 132, 26, (10, 12, 18, 190))
    block_mark(d, int(w * 0.78), int(h * 0.5), 186, 8, (10, 12, 18, 90))

    # sweep of light across the middle
    sweep = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sweep)
    sd.polygon([(0, h), (w * 0.42, 0), (w * 0.58, 0), (w * 0.16, h)], fill=(255, 255, 255, 46))
    sweep = sweep.filter(ImageFilter.GaussianBlur(26))
    layer = Image.alpha_composite(layer, sweep)

    img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
    img.save(path, optimize=True)
    return img.size


def make_wordmark_banner(path):
    w, h = 1280, 440
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img, "RGBA")

    # two soft colour washes, same palette as the WebUI header
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-300, -360, 660, 380], fill=AMBER + (108,))
    gd.ellipse([w - 620, -240, w + 360, 460], fill=GREEN + (92,))
    glow = glow.filter(ImageFilter.GaussianBlur(96))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    d = ImageDraw.Draw(img, "RGBA")

    # faint dot field, the same texture as the card banner
    dots = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    for row in range(9):
        for col in range(40):
            dx = 24 + col * 33
            dy = 20 + row * 52
            fade = max(0.0, (dx / w) - 0.35)
            a = int(46 * fade)
            if a <= 2:
                continue
            dd.ellipse([dx - 3, dy - 3, dx + 3, dy + 3], fill=(255, 255, 255, a))
    img = Image.alpha_composite(img.convert("RGBA"), dots).convert("RGB")
    d = ImageDraw.Draw(img, "RGBA")

    # mark: rounded tile with the block symbol, echoing the launcher icon
    tile = 184
    tx, ty = 96, (h - tile) // 2
    tile_img = diagonal_gradient((tile, tile), AMBER, GREEN)
    mask = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile - 1, tile - 1], radius=46, fill=255)
    img.paste(tile_img, (tx, ty), mask)
    td = ImageDraw.Draw(img, "RGBA")
    block_mark(td, tx + tile // 2, ty + tile // 2, 56, 13, BG + (235,))

    x = tx + tile + 58
    title = ImageFont.truetype(BOLD, 96)
    sub = ImageFont.truetype(SEMI, 33)
    small = ImageFont.truetype(REG, 26)

    d.text((x, 118), "DuckAds", font=title, fill=TXT)
    d.text((x + 4, 228), "systemless ad blocking for Android", font=sub, fill=(200, 208, 224))

    chips = ["46 lists", "9 injection modes", "SUSFS autobind", "NoMount", "WebUI"]
    cx = x + 4
    cy = 296
    for i, c in enumerate(chips):
        tw = d.textlength(c, font=small)
        d.rounded_rectangle([cx, cy, cx + tw + 34, cy + 46], radius=23,
                            fill=(255, 255, 255, 18), outline=(255, 255, 255, 38), width=1)
        d.text((cx + 17, cy + 9), c, font=small, fill=MUTED)
        cx += tw + 34 + 14

    # hairline in the brand gradient along the bottom
    for i in range(w):
        d.line([(i, h - 6), (i, h)], fill=lerp(AMBER, GREEN, i / w))

    img.save(path, optimize=True)
    return img.size


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
    card = os.path.join(ROOT, "module", "webroot", "banner.png")
    word = os.path.join(ROOT, "docs", "banner.png")
    print("card banner    ", make_card_banner(card), os.path.getsize(card), "bytes")
    print("wordmark banner", make_wordmark_banner(word), os.path.getsize(word), "bytes")
