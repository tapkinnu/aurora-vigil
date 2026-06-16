# Aurora Vigil — Asset Sources & Provenance

All assets are original IP for Aurora Vigil. No third-party superhero names,
logos, costumes, capes, cities, villains, or story beats are used.

## 3D Actors (Meshy AI)

Generated with the reusable pipeline in `tools/meshy_assets.py`, driven by
`data/manifest/meshy_assets.json`. Each asset goes through
text-to-3D **preview → refine (PBR textured) → remesh** before integration.
The remesh stage is mandatory: it normalises topology/polycount and resizes
the mesh to a target real-world height. Per-run task IDs, prompts, polycounts,
hashes, and byte sizes are recorded in `data/manifest/meshy_provenance.json`.

| Asset | Path | Role |
|-------|------|------|
| The Lumen (hero) | `assets/3d/characters/lumen/lumen_body.glb` | Player hero actor |
| Rogue Civic Drone | `assets/3d/characters/enemies/drone_rogue.glb` | Rogue-drone event actor |

Scale is verified empirically in Godot with `tools/verify_glb_scale.gd`
(loads each GLB, measures the combined AABB height, reports the scale factor
to the target height). Scale is **not** hard-coded blindly.

License: Meshy AI generated content, used per Meshy's Terms of Service.

## Regenerating

```bash
python3 tools/meshy_assets.py            # all assets in the manifest
python3 tools/meshy_assets.py --only lumen
godot --headless --path . -s tools/verify_glb_scale.gd
```

The Meshy API key is read from `$MESHY_KEY` (or `$MESY_API_KEY`) and is never
printed or committed.
