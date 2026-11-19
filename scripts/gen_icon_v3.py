#!/usr/bin/env python3
"""Ruby Invoice launcher icon v3 - RUBY INVOICE wordmark.

Rebuilds assets/icon/app_icon.png (white 1024 canvas: origami R mark from
assets/icon/logo_r.png + RUBY wordmark + thin divider + INVOICE tagline)
and every mipmap-*/ic_launcher.png downscale. The adaptive foreground
(app_icon_fg.png) keeps the bare R and is not touched.
"""
from PIL import Image, ImageDraw, ImageFont

ROOT = "/home/z/my-project/download/ruby_invoice"
ICON = f"{ROOT}/assets/icon"
RES = f"{ROOT}/android/app/src/main/res"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

INK = (58, 58, 58)       # RUBY wordmark
GREY = (158, 158, 158)   # INVOICE tagline
LINE = (208, 208, 208)   # divider


def draw_tracked(draw, cx, cy, text, font, tracking, fill):
    """Letter-by-letter text with tracking, centred on (cx, cy)."""
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    asc, desc = font.getmetrics()
    x = cx - total / 2
    y = cy - (asc + desc) / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill)
        x += w + tracking
    return total


def main():
    canvas = Image.new("RGB", (1024, 1024), "white")

    logo = Image.open(f"{ICON}/logo_r.png").convert("RGBA")
    h = 570
    w = round(logo.width * h / logo.height)
    logo = logo.resize((w, h), Image.LANCZOS)
    canvas.paste(logo, ((1024 - w) // 2, 52), logo)

    d = ImageDraw.Draw(canvas)
    f_word = ImageFont.truetype(FONT, 118)
    f_tag = ImageFont.truetype(FONT, 40)

    draw_tracked(d, 512, 735, "RUBY", f_word, 0.30 * 118, INK)
    d.rectangle([512 - 175, 828, 512 + 175, 831], fill=LINE)
    draw_tracked(d, 512, 875, "INVOICE", f_tag, 0.42 * 40, GREY)

    canvas.save(f"{ICON}/app_icon.png")

    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for q, px in sizes.items():
        canvas.resize((px, px), Image.LANCZOS).save(
            f"{RES}/mipmap-{q}/ic_launcher.png")

    canvas.save(f"{ROOT}/scripts/icon_preview_v3.png")
    print("icon v3 done")


if __name__ == "__main__":
    main()
