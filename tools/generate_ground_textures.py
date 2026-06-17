#!/usr/bin/env python3
"""Generate procedural PBR ground textures for Aurora Vigil.

Outputs 4 albedo/normal/roughness triplets into assets/textures/ground/:
  - asphalt: dark wet road surface with subtle grit and lane stripes baked into alpha
  - grass: dark muted park grass with sparse tufts
  - plaza: tiled paving-stone pattern with cyan accent seams

The textures are deterministic (seeded) and tileable. Used by the
ground/upgraded city in t_7be80ad0.

Run once at build-prep time. Skips if outputs already exist (idempotent).
"""

from __future__ import annotations

import math
import os
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "textures" / "ground"
OUT_DIR.mkdir(parents=True, exist_ok=True)

SIZE = 1024  # 1024x1024 tiles well; UV1_scale controls in-engine repeat


def _seeded_rng(seed: int) -> random.Random:
    return random.Random(seed)


def _gauss(rng: random.Random, mean: float, stdev: float) -> float:
    return max(0.0, rng.gauss(mean, stdev))


def _normalize_alpha_for_color(img: Image.Image) -> Image.Image:
    """Compress alpha to leave only strongly-non-transparent pixels visible.

    Used for emission maps where we want emission to feel like a discrete layer.
    """
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r, g, b, a))


def gen_asphalt() -> dict[str, Image.Image]:
    """Dark wet asphalt: low-frequency noise + faint lane stripes in emission."""
    rng = _seeded_rng(1701)
    albedo = Image.new("RGBA", (SIZE, SIZE), (28, 30, 36, 255))
    px = albedo.load()

    # Multi-scale noise: dark base with slightly lighter grit speckle.
    for y in range(SIZE):
        for x in range(SIZE):
            # Two octaves of pseudo-random value noise via hashes.
            n1 = (math.sin(x * 0.013 + y * 0.011) * 43758.5453) % 1.0
            n2 = (math.sin(x * 0.071 - y * 0.059) * 12345.6789) % 1.0
            v = 0.55 + 0.30 * abs(n1) + 0.15 * abs(n2)
            jitter = rng.randint(-6, 6)
            r = int(22 + v * 30 + jitter * 0.6)
            g = int(26 + v * 30 + jitter * 0.5)
            b = int(32 + v * 36 + jitter * 0.4)
            px[x, y] = (r, g, b, 255)

    albedo = albedo.filter(ImageFilter.GaussianBlur(0.6))

    # Subtle "wet" streaks: very low-frequency bright bands along Y.
    streak = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(streak)
    for _ in range(60):
        y = rng.randint(-SIZE // 2, SIZE + SIZE // 2)
        thickness = rng.randint(2, 12)
        alpha = rng.randint(10, 30)
        draw.rectangle([0, y, SIZE, y + thickness], fill=(80, 110, 140, alpha))
    streak = streak.filter(ImageFilter.GaussianBlur(8))
    albedo = Image.alpha_composite(albedo, streak)

    # Tiny aggregate specks: 4000 single-pixel grit dots.
    specks = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(specks)
    for _ in range(4000):
        x = rng.randint(0, SIZE - 1)
        y = rng.randint(0, SIZE - 1)
        v = rng.randint(60, 110)
        sdraw.point((x, y), fill=(v, v, v + 8, 220))
    albedo = Image.alpha_composite(albedo, specks)

    # Faint dashed centerline lane stripes baked into emission only — no albedo.
    # This gives an aurora-city "wet neon glow" reading on the avenues.
    emission = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    edraw = ImageDraw.Draw(emission)
    for x in range(0, SIZE, 64):
        edraw.rectangle([x, SIZE // 2 - 4, x + 32, SIZE // 2 + 4], fill=(20, 200, 255, 90))
    emission = emission.filter(ImageFilter.GaussianBlur(2))

    # Roughness: dark, glossy. Mostly low values (wet asphalt).
    roughness = Image.new("L", (SIZE, SIZE), 50)
    rpx = roughness.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = (math.sin(x * 0.011 + y * 0.013) * 9999.0) % 1.0
            rpx[x, y] = int(40 + 40 * abs(n))
    roughness = roughness.filter(ImageFilter.GaussianBlur(0.6))

    # Normal: very gentle, derived from a low-frequency noise heightmap.
    normal = _height_to_normal(_make_height(SIZE, rng, scale=0.005, octaves=2), strength=1.4)

    return {"albedo": albedo, "normal": normal, "roughness": roughness, "emission": emission}


def gen_grass() -> dict[str, Image.Image]:
    """Muted dark grass for park zones with sparse tufts and small pebbles."""
    rng = _seeded_rng(4242)
    albedo = Image.new("RGBA", (SIZE, SIZE), (24, 38, 30, 255))
    px = albedo.load()

    # Cool desaturated green base, slightly bluish to read as night grass.
    for y in range(SIZE):
        for x in range(SIZE):
            n1 = (math.sin(x * 0.019 + y * 0.013) * 11.0) % 1.0
            n2 = (math.sin(x * 0.063 - y * 0.041) * 17.0) % 1.0
            v = 0.45 + 0.30 * abs(n1) + 0.25 * abs(n2)
            jitter = rng.randint(-5, 5)
            r = int(18 + v * 18 + jitter * 0.4)
            g = int(34 + v * 30 + jitter * 0.6)
            b = int(24 + v * 22 + jitter * 0.3)
            px[x, y] = (r, g, b, 255)

    albedo = albedo.filter(ImageFilter.GaussianBlur(0.5))

    # Sparse tuft blobs.
    tufts = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(tufts)
    for _ in range(120):
        cx = rng.randint(0, SIZE - 1)
        cy = rng.randint(0, SIZE - 1)
        rr = rng.randint(8, 26)
        col = (rng.randint(40, 90), rng.randint(100, 150), rng.randint(50, 90), 180)
        tdraw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col)
    tufts = tufts.filter(ImageFilter.GaussianBlur(2))
    albedo = Image.alpha_composite(albedo, tufts)

    # Small pebble specks.
    pebbles = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(pebbles)
    for _ in range(800):
        x = rng.randint(0, SIZE - 1)
        y = rng.randint(0, SIZE - 1)
        rr = rng.randint(1, 3)
        col = (rng.randint(60, 95), rng.randint(60, 95), rng.randint(60, 95), 220)
        pdraw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=col)
    albedo = Image.alpha_composite(albedo, pebbles)

    emission = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))

    # Grass is rougher than asphalt.
    roughness = Image.new("L", (SIZE, SIZE), 180)
    rpx = roughness.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = (math.sin(x * 0.013 + y * 0.017) * 7.0) % 1.0
            rpx[x, y] = int(160 + 60 * abs(n))
    roughness = roughness.filter(ImageFilter.GaussianBlur(0.6))

    normal = _height_to_normal(_make_height(SIZE, rng, scale=0.011, octaves=3), strength=2.2)

    return {"albedo": albedo, "normal": normal, "roughness": roughness, "emission": emission}


def gen_plaza() -> dict[str, Image.Image]:
    """Tiled paving stones with cyan accent seams for plaza districts."""
    rng = _seeded_rng(7777)
    cell = 128  # 8x8 grid of 128px tiles at 1024 size
    albedo = Image.new("RGBA", (SIZE, SIZE), (24, 28, 36, 255))
    px = albedo.load()

    # First fill with concrete-base variation per cell.
    for cy in range(0, SIZE, cell):
        for cx in range(0, SIZE, cell):
            base_r = rng.randint(28, 42)
            base_g = rng.randint(34, 50)
            base_b = rng.randint(44, 62)
            # Inside-cell subtle variation.
            for y in range(cy, cy + cell):
                for x in range(cx, cx + cell):
                    n = (math.sin(x * 0.041 + y * 0.029) * 7.0) % 1.0
                    j = int(8 * (n - 0.5))
                    px[x, y] = (base_r + j, base_g + j, base_b + j, 255)

    # Cyan accent seams (single pixel) between cells. These glow on the
    # emission map to read as inlaid neon strips on plaza paving.
    seams = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(seams)
    for i in range(cell, SIZE, cell):
        sdraw.line([(0, i), (SIZE, i)], fill=(50, 180, 220, 200), width=1)
        sdraw.line([(i, 0), (i, SIZE)], fill=(50, 180, 220, 200), width=1)
    albedo = Image.alpha_composite(albedo, seams)

    # Per-cell weathering spots.
    for cy in range(0, SIZE, cell):
        for cx in range(0, SIZE, cell):
            for _ in range(rng.randint(2, 6)):
                rx = cx + rng.randint(8, cell - 8)
                ry = cy + rng.randint(8, cell - 8)
                rr = rng.randint(2, 7)
                spot = Image.new("RGBA", (rr * 2, rr * 2), (0, 0, 0, 0))
                ImageDraw.Draw(spot).ellipse(
                    [0, 0, rr * 2, rr * 2],
                    fill=(rng.randint(8, 20), rng.randint(10, 22), rng.randint(14, 28), 180),
                )
                spot = spot.filter(ImageFilter.GaussianBlur(1.5))
                albedo.paste(spot, (rx - rr, ry - rr), spot)

    # Emission: cyan seams only, alpha-soft.
    emission = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    edraw = ImageDraw.Draw(emission)
    for i in range(cell, SIZE, cell):
        edraw.line([(0, i), (SIZE, i)], fill=(40, 220, 255, 180), width=1)
        edraw.line([(i, 0), (i, SIZE)], fill=(40, 220, 255, 180), width=1)
    emission = emission.filter(ImageFilter.GaussianBlur(1.0))

    # Roughness: stone, medium-high.
    roughness = Image.new("L", (SIZE, SIZE), 130)
    rpx = roughness.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = (math.sin(x * 0.029 + y * 0.031) * 11.0) % 1.0
            rpx[x, y] = int(110 + 80 * abs(n))
    roughness = roughness.filter(ImageFilter.GaussianBlur(0.6))

    normal = _height_to_normal(_make_height(SIZE, rng, scale=0.015, octaves=2), strength=1.8)

    return {"albedo": albedo, "normal": normal, "roughness": roughness, "emission": emission}


def _make_height(size: int, rng: random.Random, scale: float, octaves: int) -> Image.Image:
    """Cheap pseudo-Perlin-ish heightmap from summed sines."""
    h = Image.new("F", (size, size), 0.0)
    hpx = h.load()
    for y in range(size):
        for x in range(size):
            v = 0.0
            for o in range(octaves):
                freq = scale * (1 << o)
                amp = 1.0 / (1 << o)
                v += amp * math.sin(x * freq + y * freq * 1.3)
            hpx[x, y] = v * 0.5 + 0.5
    return h


def _height_to_normal(height: Image.Image, strength: float = 2.0) -> Image.Image:
    """Convert heightmap (mode F) to a tangent-space normal map (RGB)."""
    w, h = height.size
    src = height.load()
    out = Image.new("RGB", (w, h), (128, 128, 255))
    out_px = out.load()
    for y in range(h):
        for x in range(w):
            xm = (x - 1) % w
            xp = (x + 1) % w
            ym = (y - 1) % h
            yp = (y + 1) % h
            dx = (src[xp, y] - src[xm, y]) * strength
            dy = (src[x, yp] - src[x, ym]) * strength
            # Build normal vector.
            nx = -dx
            ny = -dy
            nz = 1.0
            inv_len = 1.0 / max(1e-6, math.sqrt(nx * nx + ny * ny + nz * nz))
            nx *= inv_len
            ny *= inv_len
            nz *= inv_len
            r = int((nx * 0.5 + 0.5) * 255)
            g = int((ny * 0.5 + 0.5) * 255)
            b = int((nz * 0.5 + 0.5) * 255)
            out_px[x, y] = (r, g, b)
    return out


def write_set(name: str, tex: dict[str, Image.Image]) -> None:
    paths = {
        "albedo": OUT_DIR / f"{name}_albedo.png",
        "normal": OUT_DIR / f"{name}_normal.png",
        "roughness": OUT_DIR / f"{name}_roughness.png",
        "emission": OUT_DIR / f"{name}_emission.png",
    }
    for key, img in tex.items():
        out = paths[key]
        if out.exists():
            print(f"  {out.name} exists, skipping")
            continue
        img.save(out)
        print(f"  wrote {out.name} ({img.size[0]}x{img.size[1]})")


def write_sources() -> None:
    sources_path = OUT_DIR / "SOURCES.md"
    if sources_path.exists():
        return
    text = """# Ground PBR Textures — Sources & Provenance

All textures are procedurally generated with Pillow from seeded
deterministic functions in `tools/generate_ground_textures.py`.

| Material | Seed | Notes |
|----------|------|-------|
| asphalt | 1701 | Dark wet road, low-frequency noise + lane-stripe emission |
| grass   | 4242 | Muted night grass with tufts and pebbles |
| plaza   | 7777 | Tiled paving with cyan accent seams |

License: Generated in-house, free to use, no external models.
"""
    sources_path.write_text(text)


def main() -> int:
    print(f"writing ground textures to {OUT_DIR}")
    for name, fn in (("asphalt", gen_asphalt), ("grass", gen_grass), ("plaza", gen_plaza)):
        print(f"generating {name}:")
        tex = fn()
        write_set(name, tex)
    write_sources()
    print("AURORA_GROUND_TEXTURES: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
