# Aurora Vigil — Capture-Distance Content Polish Spec

## Purpose

This document defines the **art-direction target** and **prioritized implementation checklist** for Meridian City's visual state as seen from **gameplay camera distance, capture screenshots, contact-sheet views, and drone/overview altitude**. It does not concern close-up or editor inspection — every change here is judged by what a player sees during normal flight and what appears in the automated screenshot gate.

---

## 1. Art-Direction Target: "Teal-Gold Metropolis at Dusk"

### Target statement

Meridian City at capture distance should read as **a warm-teal-and-black skyline with gold accent lighting, distinct architectural silhouette bands, and inhabited windows that feel recessed and reflective — not greybox blocks with flat stickers.**

### Reference detail levels (from current screenshots)

| View | Current state | Target state |
|------|--------------|--------------|
| `city.png` (wide flyover) | Uniform brown-orange box forest, flat windows, repetitive texture grid, minimal roof detail | Varied silhouette bands (low/mid/high), teal-tinted glass bands, warm gold transit/bridge light trails, recessed-lit windows visible as vertical bands, distinct roof greebles resolving at full-res capture |
| `gameplay.png` (hero flight) | Flat sticker windows, obvious texture tiling, brown-grey uniform facades, sparse streets | Window depth visible as dark-recessed panes with sky-tint center, sub-tile facade variation via stronger blend, gold accent stripes or column bands on mid/high buildings, street-level glow strips |
| `drone.png` (high altitude) | Grey-brown mass with no landmark distinctness | Atmospheric depth fog separating near/mid/far bands, roof-level gold maintenance-access lights resolving as tiny dots, at least 3 colour-tinted building groups (teal glass, warm concrete, dark metal) to create navigation landmarks |
| `contact_sheet.jpg` (all four) | Low-detail across all panels, strongest in closeup but still flat | City/drone/gameplay panels all show recessed windows, roof detail, colour banding; only closeup gains extra street-level decals |

### Colour target per building tier

- **Low-rise (≤5 floors, street-facing):** Warm concrete/brick base (current brown-orange is acceptable) + teal awning stripes or sign-band accents. Gold canopy lights at entrances.
- **Mid-rise (6–15 floors):** Teal-tinted glass facade segments (the teal identity colour at ~30% saturation on glass), dark metal structural columns, gold accent strips at floor transitions.
- **High-rise (>15 floors):** Full teal-black curtain wall with gold spire/antenna tips. Upper floors get brighter window emission to create a "crown" effect.

### Why this target preserves Aurora Vigil identity

- Teal is the hero's suit primary — reflecting it in the city grounds the world in the IP's colour language.
- Black/dark metal provides contrast and grounds the skyline (current brown-orange reads warm but muddy).
- Gold accents tie to the hero's ion mantle fins, contrails, and power effects, creating visual harmony.
- No red, no blue, no cape shapes, no S-curves, no Metropolis/Daily Planet/Krypton visual cues.

---

## 2. Prioritized Checklist (P0 → P2)

### P0 — Must have for next capture gate

These changes are directly visible in ALL four capture views and address the most common critique ("greybox/low-detail at play distance").

| # | Change | Visible in | Why it's P0 |
|---|--------|-----------|-------------|
| P0.1 | **Scale up window depth and glass reflectivity by 2–3× at gameplay distance** | city.png, gameplay.png, drone.png, contact_sheet.jpg | Current `window_depth` (0.3–0.6) and `glass_reflectivity` (0.1–0.25) were tuned for close-up. At capture distance these values produce no visible recess or reflection. Double both: `window_depth` → range 0.8–1.5; `glass_reflectivity` → 0.4 for glass sets, 0.2 for others. The shader's `recess` computation should scale by a `capture_depth_multiplier` uniform so the effect is pronounced at distance without breaking close-up. |
| P0.2 | **Increase detail-texture blend factor from 0.3 to 0.55** | city.png, gameplay.png | The second albedo layer blends at 0.3, which is too subtle to break tiling at capture distance. Raising to 0.55 makes the detail layer dominant enough to visibly disrupt the base pattern. Also increase `uv_scale_2` ratio from 2.7 to 3.5 so the two scales diverge more sharply. |
| P0.3 | **Add colour-tinted building groups (3 groups: teal-glass, warm-concrete, dark-metal)** | city.png, drone.png, gameplay.png | Currently all buildings use one of 5 texture sets that all read brown/orange from distance. Use the existing `_facade_texture_index_for()` to deterministically assign a **colour group** per building. Modulate the shader's `albedo_tint` toward teal (group 0), warm concrete (group 1), or dark metal (group 2) at 25–35% strength so the hue shift is visible at distance but doesn't overpower the base texture. |
| P0.4 | **Scale up greeble sizes by 3–5× for capture-distance visibility** | city.png, gameplay.png, drone.png | Current greeble dimensions (ledge 0.15 m, parapet 0.3 m, antenna 0.08 m thick) are sub-pixel at capture distance. Scale: ledges → 0.6 m depth, parapets → 1.0 m height, antennas → 0.3 m thick. Roof HVAC boxes → 1.5× size. This is the single cheapest change that produces visible roof silhouette variation in the screenshots. |

### P1 — Strongly recommended (next after P0)

| # | Change | Visible in | Why it's P1 |
|---|--------|-----------|-------------|
| P1.1 | **Add gold accent light strips at floor transitions on mid/high-rise buildings** | city.png, gameplay.png | A horizontal gold-emissive band (thin box, `_matte(Color(0.9, 0.7, 0.1), 0.3, 0.0)` with emission 0.6) at 33 % and 66 % building height. 0.3 m tall, full building width. Creates horizontal rhythm across the skyline. Only on mid-rise and high-rise buildings. |
| P1.2 | **Add atmospheric depth fog (colour-matched to teal-black gradient)** | city.png, drone.png | Currently no distance fog. Add a fog that starts at 200 m and becomes fully opaque at 600 m. Fog colour: dark teal `RGB(0.08, 0.12, 0.14)` at far end, fading to warm sky colour near. This creates depth banding that separates near/mid/far rows. |
| P1.3 | **Increase window emission intensity on upper floors (crown effect)** | city.png, gameplay.png, drone.png | For buildings >15 floors, top 25 % of floors get `window_intensity` multiplied by 2.5. Creates a visible "lit crown" on high-rises that reads as inhabited upper-city activity. |
| P1.4 | **Add gold entrance canopy light strip** | gameplay.png (street level) | The existing entrance canopy greeble (currently dark metal) should have a gold-emissive underside: `_matte(Color(0.9, 0.7, 0.1), 0.3, 0.0)` with emission 0.5. Visible when the player is near street level. |

### P2 — Desired but can defer

| # | Change | Visible in | Why it's P2 |
|---|--------|-----------|-------------|
| P2.1 | **Street-level glow strips on major roads** | gameplay.png | Thin emissive gold lines along road centerlines. Requires a new mesh or decal pass. Lower priority because roads are mostly empty at current sandbox stage. |
| P2.2 | **Bridge/transit light trails** | city.png, drone.png | Gold animated light trails between building clusters (simulated elevated transit). More complex to implement — deferred. |
| P2.3 | **Decal-based facade wear (grime near base, streaks)** | gameplay.png, closeup | Subtle detail that only resolves at closer distances. Not visible in most capture views. |
| P2.4 | **Variable roofline setbacks (stepped building tops)** | city.png, drone.png | Would require modifying imported building geometry or adding procedural cap meshes. Higher risk, less tested. |

---

## 3. Identity Constraints

### Must preserve

- **Teal (#00B4A0), black (#0A0A0F), and gold (#E8A828) colour palette.** All new emissive elements use gold, not white. All glass-tinted elements use teal, not cyan or blue. Dark metal uses near-black, not charcoal.
- **Aurora energy motif.** Window emission should suggest aurora-energized infrastructure — soft teal or gold, never cold white or neon.
- **Original architecture language.** Buildings remain boxy/modular kit assets with procedural dressing. The spec does not call for new bespoke models.
- **Powers-to-city visual harmony.** Gold accent strips match the hero's gold contrails. Teal glass matches the Aegis Field colour. The city should visually echo the hero's power set.

### Must avoid

| Don't | Why |
|-------|-----|
| Red or cyan accent colours | Reads as Superman/Iron Man visual language |
| Blue-and-red building palette | Direct Metropolis copy |
| S-curves, shield shapes, or cape forms on architecture | Superman iconography |
| "Daily Planet" style globe or newspaper-branded buildings | DC trademark territory |
| White/blue cold lighting | Generic superhero — undermines teal/gold identity |
| Krpytonite/alien-crystal architecture | Inverse of the aurora-energy aesthetic |
| Gotham dark-gothic stone | Different brand — Aurora Vigil is hopeful and kinetic |
| Any text sign that says "METROPOLIS", "DAILY PLANET", "LEX", "WAYNE", "STARK" | Clear IP violation |

### How to verify identity compliance

1. Run `python3 tools/check_audio_wiring.py --require-existing-audio` (existing gate, still applies)
2. Visual inspection of `city.png`, `gameplay.png`, `drone.png` — no red/blue/cyan dominance
3. Gold emission must be `#E8A828` range (warm gold), not yellow `#FFFF00` or white
4. Teal glass must be `#00B4A0` range, not cyan `#00FFFF` or blue `#0000FF`

---

## 4. Implementation Acceptance Criteria

Each criterion is formatted as: **visible outcome** → which screenshot to inspect → PASS/BLOCKED condition.

### P0.1 — Window depth scaling

```
AC-01: Window Depth Visible
Inspect: gameplay.png (building full-width in center third)
PASS: Dark recessed panes are clearly visible as darker rectangles within each window
      band at full 1080p resolution. Window centers show a subtle blue-teal sky tint.
BLOCKED: Windows appear as flat bright or dark stickers with no visible depth.

AC-02: Glass Reflectivity
Inspect: gameplay.png, city.png
PASS: Window panes on glass-texture buildings show a visible glossy highlight that
      shifts with viewing angle. Non-glass buildings show subtler but still visible
      reflection.
BLOCKED: All windows are uniformly matte with no specular variation.
```

### P0.2 — Tiling break

```
AC-03: Texture Tiling Broken
Inspect: gameplay.png (large facade filling >25% of frame)
PASS: The dominant repeating grid pattern is disrupted by a visibly different
      secondary pattern at ~3.5× scale. No single grid repeat occupies more than
      15% of the building face without being broken up by the detail blend.
BLOCKED: A single repeating grid pattern is clearly visible across any building face.

AC-04: Capture-Distance Blend
Inspect: city.png (medium-distance buildings)
PASS: At city-capture distance the facade still shows visible texture variation
      (not a uniform solid colour). The building blocks do not resolve to flat
      grey/brown blobs.
BLOCKED: Buildings at city-capture distance appear as single-colour blocks.
```

### P0.3 — Colour groups

```
AC-05: Building Colour Banding
Inspect: city.png, drone.png
PASS: At least 3 distinct colour groups are visible among buildings (teal-tinted,
      warm concrete, dark metal). Adjacent buildings of the same height must have
      different colour groups to create contrast.
BLOCKED: All buildings read as the same brown-orange hue from distance.

AC-06: Teal Identity Presence
Inspect: city.png
PASS: Teal-tinted buildings occupy at least 20% of the visible skyline area.
      The teal hue is recognisable as the same family as the hero's suit (#00B4A0
      range, not cyan or blue).
BLOCKED: No teal is visible anywhere in the skyline.
```

### P0.4 — Greeble scaling

```
AC-07: Roof Greebles Resolve at Capture Distance
Inspect: city.png (roof lines of foreground buildings)
PASS: Roof parapets, ledges, and HVAC units are clearly visible as distinct
      geometric shapes (not sub-pixel noise) on buildings occupying >5% frame area.
      Antennas are visible as thin vertical lines.
BLOCKED: Roofs appear flat with no visible secondary geometry.

AC-08: Silhouette Variation
Inspect: city.png (skyline silhouette)
PASS: The top-edge silhouette of the city shows visible bumps/notches from
      roof greebles. No two adjacent high-rise buildings have identical rooflines.
BLOCKED: The skyline silhouette is a smooth continuous box shape.
```

### P1.1 — Gold accent strips

```
AC-09: Gold Floor Transitions
Inspect: city.png (mid/high-rise buildings at 50–70% frame height)
PASS: Horizontal gold-emissive bands are visible at ~⅓ and ~⅔ height on
      mid-rise and high-rise buildings. Each band is distinct and warm-gold
      coloured.
BLOCKED: No horizontal accent lines visible on building facades.
```

### P1.2 — Atmospheric fog

```
AC-10: Depth Banding via Fog
Inspect: city.png, drone.png
PASS: Distant buildings (>400 m) show visible atmospheric desaturation and
      colour shift toward dark teal. The city reads as having distinct near,
      mid, and far depth layers.
BLOCKED: All buildings from closest to farthest have the same contrast and
      saturation.
```

### P1.3 — Crown effect

```
AC-11: High-Rise Crown Lighting
Inspect: city.png (buildings >15 floors in center-right area)
PASS: The top 25% of high-rise buildings is visibly brighter than the lower
      75% due to increased window emission. The effect reads as "lit upper
      floors" not "glowing top."
BLOCKED: All floors on all buildings have uniform window intensity.
```

---

## 5. Non-Goals

The following are explicitly out of scope for this polish spec:

| Non-goal | Rationale |
|----------|-----------|
| New paid/API-generated 3D models | No Meshy, no external generation, no new asset purchases |
| Character rigging or animations | Hero/civilians/enemies are handled in separate tracks |
| Broad architecture rewrite | Changes must be within `_apply_facade_texture_overlay()`, `_add_building_greebles()`, `building_facade.gdshader`, or new small helper files only |
| New external APIs or services | All changes are local to the Godot project |
| Street-level NPC behaviour | Future spec — not visible in capture screenshots |
| UI/HUD redesign | The HUD is functional; visual polish is deferred |
| Particle or VFX systems | Powers and environmental effects are separate |
| Audio changes | Audio wiring is gated separately |
| Save/load modification | Progression system is complete |
| Adding new city districts | Content expansion, not polish |
| Rebuilding the contact sheet layout | Screenshot output format is stable |

---

## 6. Verification

After implementation:

```bash
# Build + existing facade tests must still pass
./tools/validate_build.sh

# Capture new screenshots
./tools/capture_screenshots.sh /tmp/aurora_vigil_polish/screens

# Visual inspection against the AC table above
# Use vision_analyze on city.png, gameplay.png, drone.png, contact_sheet.jpg
```

All PASS conditions in Section 4 must be met. Any BLOCKED condition stops the polish — the item goes back to the implementation worker with the specific AC ID.

---

## Appendix: Current screenshot inventory (baseline)

| File | Camera | What it shows |
|------|--------|---------------|
| `/tmp/aurora_vigil_cron_20260701_110529/screens/city.png` | Wide flyover, ~250 m altitude | Skyline, roof detail, overall colour balance |
| `/tmp/aurora_vigil_cron_20260701_110529/screens/gameplay.png` | Hero flight, ~80 m altitude, 3rd person | Facade texture readability, window depth, tiling |
| `/tmp/aurora_vigil_cron_20260701_110529/screens/drone.png` | High altitude, ~400 m | City massing, depth fog, landmark distinction |
| `/tmp/aurora_vigil_cron_20260701_110529/screens/contact_sheet.jpg` | Montage of all four views | Cross-view consistency |
| `/tmp/aurora_vigil_cron_20260701_110529/screens/closeup.png` | ~15 m, hero interaction | Character + nearby detail (not primary polish target) |
