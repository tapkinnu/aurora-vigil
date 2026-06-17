#!/usr/bin/env python3
"""Generate 5 PBR facade texture sets for Aurora Vigil city buildings."""

import os, sys, time, json, requests, math
from PIL import Image, ImageDraw, ImageFilter
import io

FAL_KEY = os.environ.get("FAL_KEY", "")
if not FAL_KEY:
    env_path = os.path.expanduser("~/.hermes/profiles/coder/.env")
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("FAL_KEY="):
                    FAL_KEY = line.split("=", 1)[1].strip()
                    break
if not FAL_KEY:
    print("ERROR: FAL_KEY not found"); sys.exit(1)

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures", "facades")
os.makedirs(OUT_DIR, exist_ok=True)

HEADERS = {"Authorization": f"Key {FAL_KEY}", "Content-Type": "application/json"}
FAL_URL = "https://fal.run/fal-ai/fast-sdxl"

FACADE_PROMPTS = {
    "glass_curtain_wall": "seamless tileable texture of a dark cyberpunk glass curtain wall building facade at night, tinted blue-black glass panels with reflections, thin metal mullions grid pattern, some windows glowing with cyan and magenta neon light, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark, dark moody atmosphere",
    "concrete_panel": "seamless tileable texture of a brutalist concrete panel building facade, dark gray concrete with horizontal seam lines between panels, subtle weathering and stains, a few windows with warm orange glow, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark, dark cyberpunk mood",
    "brick": "seamless tileable texture of a dark cyberpunk brick building facade at night, dark red-brown brickwork with mortar lines, some windows glowing with warm amber and cool blue light, weathered urban texture, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark",
    "metal_cladding": "seamless tileable texture of a brushed metal cladding building facade, dark steel-gray metal panels with vertical seams and rivets, subtle anodized blue tint, industrial cyberpunk architecture, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark",
    "commercial_facade": "seamless tileable texture of an illuminated commercial building facade at night, glowing neon signage strips in cyan magenta and amber, storefront glass, metallic trim around display windows, dark building surface, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark, vibrant cyberpunk aesthetic",
}

MATERIAL_PROPS = {
    "glass_curtain_wall": {"roughness": 0.15, "metallic": 0.85, "glow": (80, 200, 255), "threshold": 60},
    "concrete_panel": {"roughness": 0.85, "metallic": 0.02, "glow": (255, 180, 80), "threshold": 90},
    "brick": {"roughness": 0.75, "metallic": 0.05, "glow": (255, 160, 60), "threshold": 85},
    "metal_cladding": {"roughness": 0.25, "metallic": 0.90, "glow": (120, 180, 220), "threshold": 100},
    "commercial_facade": {"roughness": 0.35, "metallic": 0.60, "glow": (255, 100, 200), "threshold": 50},
}

def generate_albedo(prompt, out_path):
    payload = {"prompt": prompt, "image_size": {"width": 1024, "height": 1024}, "num_inference_steps": 30, "guidance_scale": 7.5, "num_images": 1}
    for attempt in range(3):
        try:
            resp = requests.post(FAL_URL, json=payload, headers=HEADERS, timeout=120)
            if resp.status_code != 200:
                print(f"  FAL error {resp.status_code}: {resp.text[:200]}"); time.sleep(3*(attempt+1)); continue
            data = resp.json()
            img_url = None
            if "images" in data and isinstance(data["images"], list) and len(data["images"]) > 0:
                img_url = data["images"][0].get("url")
            elif "image" in data and isinstance(data["image"], dict):
                img_url = data["image"].get("url")
            elif "image_url" in data:
                img_url = data["image_url"]
            if not img_url:
                print(f"  No URL: {json.dumps(data)[:300]}"); time.sleep(3); continue
            img_resp = requests.get(img_url, timeout=60)
            if img_resp.status_code != 200:
                print(f"  Download failed: {img_resp.status_code}"); time.sleep(3); continue
            img = Image.open(io.BytesIO(img_resp.content)).convert("RGB").resize((1024, 1024), Image.LANCZOS)
            img.save(out_path, "PNG")
            print(f"  Saved albedo: {out_path}")
            return True
        except Exception as e:
            print(f"  Exception: {e}"); time.sleep(3*(attempt+1))
    return False

def make_normal_map(albedo_path, out_path, strength=0.8):
    img = Image.open(albedo_path).convert("L").resize((512, 512), Image.LANCZOS)
    img_blur = img.filter(ImageFilter.GaussianBlur(1))
    px = img_blur.load()
    w, h = img.size
    normal_img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(normal_img)
    for y in range(h):
        for x in range(w):
            xl = max(0, x-1); xr = min(w-1, x+1)
            yt = max(0, y-1); yb = min(h-1, y+1)
            dx = float(px[xl, y]) - float(px[xr, y])
            dy = float(px[x, yt]) - float(px[x, yb])
            nx = dx * strength / 255.0; ny = dy * strength / 255.0; nz = 1.0
            length = math.sqrt(nx*nx + ny*ny + nz*nz)
            nx /= length; ny /= length; nz /= length
            r = int((nx*0.5+0.5)*255); g = int((ny*0.5+0.5)*255); b = int((nz*0.5+0.5)*255)
            draw.point((x, y), (r, g, b))
    normal_img = normal_img.resize((1024, 1024), Image.LANCZOS)
    normal_img.save(out_path, "PNG")
    print(f"  Saved normal: {out_path}")

def make_roughness_map(albedo_path, out_path, base_roughness):
    img = Image.open(albedo_path).convert("L").resize((512, 512), Image.LANCZOS)
    px = img.load()
    w, h = img.size
    rough_img = Image.new("L", (w, h))
    draw = ImageDraw.Draw(rough_img)
    for y in range(h):
        for x in range(w):
            v = px[x, y] / 255.0
            r = int(max(0, min(1, base_roughness * 0.6 + v * base_roughness * 0.8)) * 255)
            draw.point((x, y), r)
    rough_img = rough_img.filter(ImageFilter.GaussianBlur(0.5)).resize((1024, 1024), Image.LANCZOS)
    rough_img.save(out_path, "PNG")
    print(f"  Saved roughness: {out_path}")

def make_emission_map(albedo_path, out_path, glow_color, threshold=80):
    img = Image.open(albedo_path).convert("RGB").resize((512, 512), Image.LANCZOS)
    px = img.load()
    w, h = img.size
    emit_img = Image.new("RGB", (w, h), (0, 0, 0))
    draw = ImageDraw.Draw(emit_img)
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            brightness = (r + g + b) / 3
            if brightness > threshold:
                factor = min((brightness - threshold) / (255 - threshold), 1.0)
                draw.point((x, y), (int(glow_color[0]*factor), int(glow_color[1]*factor), int(glow_color[2]*factor)))
    emit_img = emit_img.filter(ImageFilter.GaussianBlur(0.8)).resize((1024, 1024), Image.LANCZOS)
    emit_img.save(out_path, "PNG")
    print(f"  Saved emission: {out_path}")

def main():
    sources = []
    for name, prompt in FACADE_PROMPTS.items():
        print(f"\n=== Generating {name} ===")
        albedo_path = os.path.join(OUT_DIR, f"{name}_albedo.png")
        normal_path = os.path.join(OUT_DIR, f"{name}_normal.png")
        roughness_path = os.path.join(OUT_DIR, f"{name}_roughness.png")
        emission_path = os.path.join(OUT_DIR, f"{name}_emission.png")
        if not os.path.exists(albedo_path):
            ok = generate_albedo(prompt, albedo_path)
            if not ok:
                print(f"FAILED to generate albedo for {name}"); sys.exit(1)
        else:
            print(f"  Albedo already exists: {albedo_path}")
        props = MATERIAL_PROPS[name]
        if not os.path.exists(normal_path):
            make_normal_map(albedo_path, normal_path)
        if not os.path.exists(roughness_path):
            make_roughness_map(albedo_path, roughness_path, props["roughness"])
        if not os.path.exists(emission_path):
            make_emission_map(albedo_path, emission_path, props["glow"], props["threshold"])
        sources.append({"name": name, "prompt": prompt, **props})
    sources_path = os.path.join(OUT_DIR, "SOURCES.md")
    with open(sources_path, "w") as f:
        f.write("# PBR Facade Textures — Sources & Provenance\n\n")
        f.write("All albedo textures generated via FAL.ai `fal-ai/fast-sdxl`.\n")
        f.write("Normal, roughness, and emission maps derived procedurally from albedo using Pillow.\n\n")
        f.write("License: FAL/ Stability AI community license terms apply to albedo generations.\n")
        f.write("Derived maps (normal/roughness/emission) are procedural transformations of the albedo.\n\n")
        f.write("| Material | Roughness | Metallic | Glow Color | Emission Threshold |\n")
        f.write("|----------|-----------|----------|------------|-------------------|\n")
        for s in sources:
            f.write(f"| {s['name']} | {s['roughness']} | {s['metallic']} | RGB{tuple(s['glow'])} | {s['threshold']} |\n")
        f.write("\n## Generation Prompts\n\n")
        for s in sources:
            f.write(f"### {s['name']}\n```\n{s['prompt']}\n```\n\n")
    print(f"\nSOURCES.md written: {sources_path}")
    print("\nAll facade textures generated successfully!")

if __name__ == "__main__":
    main()