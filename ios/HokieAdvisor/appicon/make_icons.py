#!/usr/bin/env python3
"""
Clean icon extraction from the ChatGPT reference sheet.

Pixel analysis findings:
  y=0–311:   Header/shadow above icon zone (dark for all three panels)
  y=312–795: Icon content zone

Column boundaries (verified at y=400):
  Light:  x=0–415    (x=416-417 is right-edge shadow, x=418 is dark col start)
  Dark:   x=420–833  (x=418-419 left shadow, x=834-835 right shadow)
  Tinted: x=840–1252 (x=836-837 dark border, x=838-839 is shadow)
"""

from PIL import Image

REF = "/Users/rehobothkebede/GitHub/Fcounselors/ios/HokieAdvisor/appicon/ChatGPT Image May 18, 2026 at 05_16_01 PM.png"
OUT = "/Users/rehobothkebede/GitHub/Fcounselors/ios/HokieAdvisor/HokieAdvisor/Assets.xcassets/AppIcon.appiconset"

sheet = Image.open(REF).convert("RGB")

TOP    = 312
BOTTOM = 796

icons = [
    # name,                  x_start, x_end, bg_color
    ("AppIcon-Light.png",    0,       414,   (243, 239, 236)),  # cream
    ("AppIcon-Dark.png",     420,     833,   (11,  1,   4)),    # near-black
    ("AppIcon-Tinted.png",   840,     1252,  (221, 220, 221)),  # light gray
]

for name, x_start, x_end, bg in icons:
    crop = sheet.crop((x_start, TOP, x_end, BOTTOM))
    cw, ch = crop.size

    # Pad to square, centered
    side = max(cw, ch)
    canvas = Image.new("RGB", (side, side), bg)
    canvas.paste(crop, ((side - cw) // 2, (side - ch) // 2))

    final = canvas.resize((1024, 1024), Image.LANCZOS)
    out_path = f"{OUT}/{name}"
    final.save(out_path)
    print(f"{name}: {cw}×{ch} crop → 1024×1024  bg={bg}")

print("Done.")
