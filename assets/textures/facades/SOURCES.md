# PBR Facade Textures — Sources & Provenance

All albedo textures generated via FAL.ai `fal-ai/fast-sdxl`.
Normal, roughness, and emission maps derived procedurally from albedo using Pillow.

License: FAL/ Stability AI community license terms apply to albedo generations.
Derived maps (normal/roughness/emission) are procedural transformations of the albedo.

| Material | Roughness | Metallic | Glow Color | Emission Threshold |
|----------|-----------|----------|------------|-------------------|
| glass_curtain_wall | 0.15 | 0.85 | RGB(80, 200, 255) | 60 |
| concrete_panel | 0.85 | 0.02 | RGB(255, 180, 80) | 90 |
| brick | 0.75 | 0.05 | RGB(255, 160, 60) | 85 |
| metal_cladding | 0.25 | 0.9 | RGB(120, 180, 220) | 100 |
| commercial_facade | 0.35 | 0.6 | RGB(255, 100, 200) | 50 |

## Generation Prompts

### glass_curtain_wall
```
seamless tileable texture of a dark cyberpunk glass curtain wall building facade at night, tinted blue-black glass panels with reflections, thin metal mullions grid pattern, some windows glowing with cyan and magenta neon light, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark, dark moody atmosphere
```

### concrete_panel
```
seamless tileable texture of a brutalist concrete panel building facade, dark gray concrete with horizontal seam lines between panels, subtle weathering and stains, a few windows with warm orange glow, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark, dark cyberpunk mood
```

### brick
```
seamless tileable texture of a dark cyberpunk brick building facade at night, dark red-brown brickwork with mortar lines, some windows glowing with warm amber and cool blue light, weathered urban texture, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark
```

### metal_cladding
```
seamless tileable texture of a brushed metal cladding building facade, dark steel-gray metal panels with vertical seams and rivets, subtle anodized blue tint, industrial cyberpunk architecture, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark
```

### commercial_facade
```
seamless tileable texture of an illuminated commercial building facade at night, glowing neon signage strips in cyan magenta and amber, storefront glass, metallic trim around display windows, dark building surface, top-down orthographic view of the facade surface, PBR albedo texture, game asset, no text no watermark, vibrant cyberpunk aesthetic
```

