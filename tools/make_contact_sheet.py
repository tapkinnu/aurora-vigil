#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw
import sys
indir = Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts/screenshots")
out = Path(sys.argv[2] if len(sys.argv) > 2 else indir / "contact_sheet.jpg")
paths = [p for p in sorted(indir.glob("*.png")) if p.name != out.name]
if not paths:
    raise SystemExit("no screenshots found")
thumb_w, thumb_h = 426, 240
sheet = Image.new("RGB", (thumb_w * len(paths), thumb_h + 26), (10, 14, 24))
d = ImageDraw.Draw(sheet)
for i, p in enumerate(paths):
    im = Image.open(p).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
    x = i * thumb_w
    sheet.paste(im, (x, 26))
    d.text((x + 8, 6), p.stem, fill=(230, 240, 255))
out.parent.mkdir(parents=True, exist_ok=True)
sheet.save(out, quality=92)
print(f"AURORA_CONTACT_SHEET: PASS {out} images={len(paths)}")
