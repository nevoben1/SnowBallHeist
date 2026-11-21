"""Generates placeholder 512x512 store icons for gamepasses and developer products.

Original, simple art: a gradient badge, a snowball, and a symbol + short label per item.
Run:  python tools/make_icons.py   ->  art/icons/<Key>.png
Replace with real art any time; icons can change without changing the product/pass IDs.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "icons")
FONT = r"C:\Windows\Fonts\segoeuib.ttf"

# key: (label, top color, bottom color, symbol)
ICONS = {
    "TwoXGrowth": ("2x GROW", (90, 200, 255), (30, 90, 200), "grow"),
    "TwoXCoins": ("2x COINS", (255, 215, 90), (210, 120, 20), "coin"),
    "VIP": ("VIP", (255, 220, 110), (150, 70, 200), "crown"),
    "ExtraCarrySlots": ("+2 CARRY", (130, 230, 160), (30, 130, 90), "plus"),
    "AutoCollect": ("AUTO", (255, 190, 90), (40, 150, 200), "magnet"),
    "BlizzardLuck": ("LUCK", (190, 230, 255), (80, 80, 190), "flake"),
    "CoinPackS": ("POUCH", (255, 225, 120), (200, 140, 40), "coin1"),
    "CoinPackM": ("SACK", (255, 215, 100), (200, 120, 30), "coin2"),
    "CoinPackL": ("CHEST", (255, 205, 80), (190, 100, 20), "coin3"),
    "CoinPackXL": ("VAULT", (255, 195, 60), (170, 70, 10), "coin4"),
    "StarterPack": ("STARTER", (150, 240, 210), (220, 90, 160), "star"),
}


def gradient(top, bottom):
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (SIZE, y)], fill=color)
    return img


def rounded_mask():
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=96, fill=255)
    return mask


def snowball(draw, cx, cy, r):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(248, 252, 255), outline=(170, 200, 230), width=8)
    # soft shading + sparkle
    draw.ellipse([cx - r * 0.55, cy - r * 0.65, cx - r * 0.15, cy - r * 0.3], fill=(255, 255, 255))
    draw.ellipse([cx + r * 0.2, cy + r * 0.25, cx + r * 0.6, cy + r * 0.6], fill=(225, 238, 250))


def coin(draw, cx, cy, r):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 205, 50), outline=(170, 110, 10), width=7)
    draw.ellipse([cx - r * 0.65, cy - r * 0.65, cx + r * 0.65, cy + r * 0.65], outline=(200, 140, 20), width=5)


def star(draw, cx, cy, r, fill):
    points = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        points.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    draw.polygon(points, fill=fill, outline=(120, 70, 10))


def flake(draw, cx, cy, r):
    for i in range(6):
        a = i * math.pi / 3
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        draw.line([(cx, cy), (x, y)], fill=(255, 255, 255), width=14)
        for s in (0.55, 0.8):
            bx, by = cx + math.cos(a) * r * s, cy + math.sin(a) * r * s
            for d in (-0.6, 0.6):
                ex = bx + math.cos(a + d) * r * 0.22
                ey = by + math.sin(a + d) * r * 0.22
                draw.line([(bx, by), (ex, ey)], fill=(255, 255, 255), width=10)


def symbol(draw, kind):
    if kind == "grow":
        snowball(draw, 200, 270, 70)
        snowball(draw, 330, 240, 110)
        draw.polygon([(300, 95), (360, 95), (330, 50)], fill=(255, 255, 255))
    elif kind == "coin":
        coin(draw, 210, 250, 95)
        coin(draw, 310, 230, 95)
    elif kind == "crown":
        snowball(draw, 256, 280, 115)
        draw.polygon(
            [(170, 175), (190, 95), (225, 140), (256, 80), (287, 140), (322, 95), (342, 175)],
            fill=(255, 210, 60),
            outline=(150, 90, 10),
        )
    elif kind == "plus":
        snowball(draw, 220, 260, 110)
        draw.rounded_rectangle([320, 130, 360, 290], radius=10, fill=(255, 255, 255))
        draw.rounded_rectangle([260, 190, 420, 230], radius=10, fill=(255, 255, 255))
    elif kind == "magnet":
        draw.arc([150, 110, 362, 322], start=180, end=360, fill=(220, 50, 60), width=60)
        draw.rectangle([150, 215, 210, 300], fill=(220, 50, 60))
        draw.rectangle([302, 215, 362, 300], fill=(220, 50, 60))
        draw.rectangle([150, 270, 210, 310], fill=(235, 235, 240))
        draw.rectangle([302, 270, 362, 310], fill=(235, 235, 240))
        coin(draw, 256, 345, 40)
    elif kind == "flake":
        flake(draw, 256, 240, 140)
    elif kind.startswith("coin") and kind[4:].isdigit():
        n = int(kind[4:])
        spots = [(256, 250), (190, 280), (322, 280), (256, 190)][:n]
        for x, y in reversed(spots):
            coin(draw, x, y, 72)
    elif kind == "star":
        snowball(draw, 230, 270, 105)
        star(draw, 345, 160, 70, (255, 220, 70))


def label(img, text):
    draw = ImageDraw.Draw(img)
    size = 92
    font = ImageFont.truetype(FONT, size)
    while draw.textlength(text, font=font) > SIZE - 60 and size > 40:
        size -= 4
        font = ImageFont.truetype(FONT, size)
    w = draw.textlength(text, font=font)
    x, y = (SIZE - w) / 2, 380
    # drop shadow, then outline, then fill
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x + 4, y + 6), text, font=font, fill=(0, 0, 0, 140))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(4)))
    draw.text((x, y), text, font=font, fill=(255, 255, 255), stroke_width=8, stroke_fill=(30, 40, 80))


# Roblox shows gamepass icons cropped to a circle, so the art is shrunk into the circle-safe middle.
SAFE_SCALE = 0.78


def make(key, text, top, bottom, kind):
    art = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    symbol(ImageDraw.Draw(art), kind)
    label(art, text)
    inner = int(SIZE * SAFE_SCALE)
    art = art.resize((inner, inner), Image.LANCZOS)
    base = gradient(top, bottom).convert("RGBA")
    offset = (SIZE - inner) // 2
    base.alpha_composite(art, (offset, offset))
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(base, (0, 0), rounded_mask())
    out.save(os.path.join(OUT, key + ".png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for key, (text, top, bottom, kind) in ICONS.items():
        make(key, text, top, bottom, kind)
    print(f"Wrote {len(ICONS)} icons to {os.path.normpath(OUT)}")
