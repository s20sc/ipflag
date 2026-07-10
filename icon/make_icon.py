#!/usr/bin/env python3
"""Build the macOS master icon (1024x1024) from the clean squircle artwork.

The source `ipflag_icon_clean.png` is already a full-canvas squircle with
transparent corners, so no cropping/masking is needed. We just scale it into
Apple's 824px content box, center it on a 1024 canvas, and add a soft shadow so
it matches the sizing of stock macOS app icons.
"""
from pathlib import Path

from PIL import Image, ImageFilter

SRC = Path("icon/ipflag_icon_clean.png")
OUT = Path("icon/icon_1024.png")

CANVAS = 1024
CONTENT = 824  # Apple HIG content box within a 1024 grid


def main() -> None:
    squircle = Image.open(SRC).convert("RGBA").resize((CONTENT, CONTENT), Image.LANCZOS)
    off = (CANVAS - CONTENT) // 2  # 100

    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Soft drop shadow: blurred silhouette nudged down, semi-transparent.
    alpha = squircle.split()[3]
    sh = Image.new("L", (CANVAS, CANVAS), 0)
    sh.paste(alpha, (off, off + 12))
    sh = sh.filter(ImageFilter.GaussianBlur(18)).point(lambda p: int(p * 0.35))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.putalpha(sh)
    out = Image.alpha_composite(out, shadow)

    out.alpha_composite(squircle, (off, off))
    out.save(OUT)
    print("wrote", OUT, out.size)


if __name__ == "__main__":
    main()
