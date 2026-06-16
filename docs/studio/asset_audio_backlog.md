# Aurora Vigil — Asset & Audio Backlog

> Planning lane. No generation until Producer explicitly green-lights paid generation.
> All items are backlog candidates; actual generation orders must reference this doc with costs/providers confirmed live.
> Last updated: 2026-06-16

---

## 1. Provider & Provenance Rules

### 1.1 Visual Assets

| Priority | Provider | Role | Notes |
|----------|----------|------|-------|
| 1st | **Meshy AI** | Character hero (The Lumen), civilians, drones/enemies | Text-to-3D → refine → remesh → auto-rig → baked GLB animations. Primary for all humanoid/character models. |
| 2nd | **FAL Hunyuan3D / Hyper3D Rodin / Trellis / TripoSR** | Props, buildings, vehicles, weapons | Non-character 3D and environment geometry. Use when Meshy unavailable or for mechanical/environmental objects. |
| Fallback | **Godot CSG + primitives** | Temporary stand-ins | Must be tagged `[STAND-IN]` in manifest. Never ship as final. |

**Scale-verification reminder:** Every GLB export from Meshy (or any text-to-3D provider) must be imported into Godot and measured against a 1.8 m reference capsule before committing to the scene in which it appears. Characters that are proportionally off break the hero fantasy and cause camera/animation issues. Record actual bounding-box height in the manifest entry for each character model.

### 1.2 Audio Assets

| Asset Class | Source | Provider | Endpoint |
|-------------|--------|----------|----------|
| Mechanical/UI SFX (flight whoosh variants, UI clicks, alerts) | **Kenney CC0** | kenney.nl | Download from page, scrape zip URL (never guess hash) |
| Creature/enemy SFX (attack, death, idle), short foley, stingers | **FAL Stable Audio Open** | `fal-ai/stable-audio` | `seconds_total` field, result key `audio_file`, WAV output, 1–6 s |
| Music (menu loop, ambient city, combat BGM, victory theme) | **FAL Stable Audio 2.5** | `fal-ai/stable-audio-25/text-to-audio` | `seconds_total` field, result key `audio`, WAV output, 30 s – 3 min |
| Voice lines, radio barks, NPC dialogue | **FAL ElevenLabs TTS** | `fal-ai/elevenlabs/tts/turbo-v2.5` | Primary. Each recurring character gets a distinct voice. |
| Voice fallback | FAL MiniMax / direct MiniMax | `fal-ai/minimax/speech-2.8-hd` or direct API | Extra voice supply when FAL roster exhausted. |
| Last-resort voice | Google Gemini TTS | `gemini-2.5-flash-preview-tts` | PCM 24 kHz mono. Free tier 3 req/min. |

**Fallback order for music:** FAL `stable-audio-25/text-to-audio` → direct MiniMax `music_generation` → AudioCraft/MusicGen placeholder.
**Fallback order for SFX:** FAL `stable-audio` (Open) → FAL `elevenlabs/sound-effects/v2` → procedural Python synthesis.

### 1.3 Provenance Requirements (from hybrid pipeline)

- Every generated audio file must have its model, endpoint, and prompt recorded in `assets/audio/SOURCES.md`.
- Kenney files: record source pack and original filename.
- Stability AI output: Stability AI Community License — verify current terms before commercial release.
- Kenney output: CC0 — no attribution required but polite to credit.
- Godot audio manifest entry must include: provider, date generated, config hash or prompt.

---

## 2. 3D Character Plan (Meshy-First)

### 2.1 The Lumen (Hero)

| Asset | Description | Animations Needed | Priority |
|-------|-------------|-------------------|----------|
| `lumen_body.glb` | Hero body, teal-black armor, gold ion mantle fins. No caped red-blue iconography. | idle, walk, run, flight_idle, flight_boost, flight_ascend, flight_descend, attack_pose, hit_react, death, rescue_carry | P0 |
| `lumen_costume_variants.glb` | Optional outfit swaps for level-up milestones (gold fin accents level, mantle length) | Same base skeleton | P2 |

**Scale verification:** Import GLB → check bounding-box height ≈ 1.8 m (adult male scale). If off, remesh/re-export from Meshy at correct scale before rigging.

**Meshy workflow:**
1. Prompt with front/side reference images.
2. Refine → remesh to game-res (~15k–30k triangles for hero).
3. Auto-rig (humanoid template).
4. Request idle/walk/run/fall GLB animations.
5. Export as `.glb`, verify in Godot against 1.8 m reference.

### 2.2 Civilians

| Asset | Description | Count | Animations | Priority |
|-------|-------------|-------|------------|----------|
| `civilian_male.glb` | Generic male civilian, casual near-future clothing | 1–3 variants | idle, walk, run, panic_flee, rescue_taken | P1 |
| `civilian_female.glb` | Generic female civilian, casual near-future clothing | 1–3 variants | idle, walk, run, panic_flee, rescue_taken | P1 |
| `civilian_child.glb` | Child civilian variant | 1 variant | idle, walk, cling | P2 |

**Scale verification:** Male/female ≈ 1.7–1.8 m; child ≈ 1.1–1.3 m. Record actual bounds.

### 2.3 Enemies & Drones

| Asset | Description | Animations | Priority |
|-------|-------------|------------|----------|
| `drone_scout.glb` | Small civic drone, repurposed hostile. Glowing teal eye, light armor panels | idle, fly_patrol, fly_attack, hit, death_spiral, deactivated | P0 |
| `drone_heavy.glb` | Large Null Choir acoustic combat drone. Bulky, resonator horns | idle, fly_patrol, charge_attack, hit, death_explode | P1 |
| `null_choir_soldier.glb` | Acoustic disruption infantry. Humanoid in matte-black exo-armor with resonator backpack | idle, walk, run, attack_melee, attack_ranged, hit, death | P1 |
| `heliostat_enforcer.glb` | Corporate energy syndicate goon. Sleek dark green armor with gold trim | idle, walk, run, attack_ranged, hit, death | P2 |
| `storm_child_charger.glb` | Civilian transformed by atmospheric event — unstable energy aura, aggressive | idle, lunge, attack_energy, hit, death_dissipate | P2 |

**Notes:**
- Drones are non-humanoid → use Meshy generic object pipeline or FAL 3D endpoints (Hunyuan3D/TripoSR) instead of Meshy auto-rig.
- For quadruped/insectoid/mechanical enemies not listed, prefer Quaternius pre-rigged CC0 models from poly.pizza over Meshy auto-rig.

---

## 3. City Props, Buildings & VFX Textures

### 3.1 Props (Meshy or FAL 3D)

| Asset | Count | Notes |
|-------|-------|-------|
| `aurora_collector_tower.glb` | 2–3 variants | Tall, teal-glass cylinder with gold base. Signature city element. |
| `transit_line_support.glb` | 4+ | Gold transit rail supports — modular, reusable. |
| `street_lamp_meridian.glb` | 3+ variants | Teal-gold modern street lights. |
| `civic_terminal.glb` | 1–2 | Public kiosk / hologram display. |
| `residential_block_modular.glb` | 4–6 wall/floor/roof pieces | Modular building kit for district blockout → replacement. |
| `commercial_tower_modular.glb` | 3–5 pieces | Glass-and-steel commercial blocks. |
| `construction_crane.glb` | 1–2 | Dynamic city life detail. |
| `fire_escape_ladder.glb` | 1–2 | For rescue event positioning and vertical traversal landing points. |
| `vehicle_parked_car.glb` | 2–3 variants | Street-level detail. Generic, no branded shapes. |
| `vehicle_transit_pod.glb` | 1–2 | Gold transit rail pods. |
| `drone_pad.glb` | 1–2 | Landing/takeoff pad for drone enemy spawns. |
| `null_resonator_emitter.glb` | 1–2 | Null Choir plot device for story missions. |

### 3.2 VFX Textures / Decals

| Asset | Description | Format |
|-------|-------------|--------|
| `vfx_ion_trail.png` | Gold ion flight trail, transparent | 512×512 or 1024×256 transparent PNG |
| `vfx_aurora_beam.png` | Radiant beam VFX card — teal-white gradient burst | 512×512 transparent PNG |
| `vfx_sonic_ring.png` | Sonic burst pressure ring — concentric ripple | 512×512 transparent PNG |
| `vfx_aegis_shield.png` | Aegis field overlay — teal-gold honeycomb energy | 512×512 transparent PNG, additive blend |
| `vfx_explosion_generic.png/spritesheet` | Stylus/generic explosion, 4–8 frame | Sprite sheet PNG |
| `vfx_energy_impact.png` | Impact spark/crack — teal energy strike | 256×256 transparent PNG |
| `decal_scorch_mark.png` | Ground scorch from explosions or beam hits | 256×256 transparent PNG |
| `decal_hologram_flicker.png` | Civic terminal hologram glitch animation | 4–6 frame sprite sheet |
| `ui_hud_power_icon_*.png` | HUD icons for each power: flight, boost, radiant_beam, sonic_burst, aegis, rescue, orbit_sprint | 64×64 or 128×128 transparent PNG, 12 icons |
| `ui_hud_objective_marker.png` | Mission objective world-space marker | 64×64 transparent PNG, multiple states |

---

## 4. Audio Pack Plan

### 4.1 Hero Flight & Power SFX (Kenney + FAL)

| # | File | Source | Duration | Notes |
|---|------|--------|----------|-------|
| 1 | `flight_whoosh_loop.ogg` | Kenney `sci-fi-sounds` or small extension | 3–5 s loop | Continuous flight. Pick from `engineCircular` family. |
| 2 | `flight_boost_burst.ogg` | FAL `stable-audio` | 2 s | "intense flight thrust burst, superhero rocket boost, powerful rush" |
| 3 | `flight_ascend.ogg` | FAL `stable-audio` | 1.5 s | "sharp aerodynamic ascent whoosh, hero launching upward" |
| 4 | `flight_descend.ogg` | Kenney `sci-fi-sounds` (`laserRetro` family, pitched down) | 1.5 s | Deceleration/landing whoosh. |
| 5 | `power_radiant_beam_fire.ogg` | Kenney `sci-fi-sounds` (`laserSmall` variant) | 1 s | Orion beam weapon fire — assign unique variant, not shared with drone lasers. |
| 6 | `power_radiant_beam_charge.ogg` | FAL `stable-audio` | 2 s | "energy weapon charging up, high voltage buildup, teal light hum" |
| 7 | `power_sonic_burst.ogg` | FAL `stable-audio` | 2 s | "sonic boom clap, pressure wave ring, crowd control shockwave" |
| 8 | `power_aegis_activate.ogg` | FAL `stable-audio` | 2 s | "energy shield deploying, teal-gold barrier forming, protective dome" |
| 9 | `power_aegis_impact.ogg` | Kenney `impact-sounds` (`impactGeneric` variant) | 0.5–1 s | Shield absorbing hit. |
| 10 | `power_rescue_lift.ogg` | FAL `stable-audio` | 2 s | "gentle energy lift, civilian being carried, soft teal glow hum" |
| 11 | `power_orbit_sprint.ogg` | FAL `stable-audio` | 3 s | "hypersonic flight streak, gold contrail, city blurring past" |

### 4.2 UI SFX (Kenney `interface-sounds`)

| # | File | Source | Notes |
|---|------|--------|-------|
| 12 | `ui_click.ogg` | Kenney `interface-sounds/click_002.ogg` | Menu click |
| 13 | `ui_confirm.ogg` | Kenney `interface-sounds/confirmation_001.ogg` | Confirm/select |
| 14 | `ui_error.ogg` | Kenney `interface-sounds/error_005.ogg` | Error/invalid |
| 15 | `ui_level_up.ogg` | FAL `stable-audio` | "triumphant level up chime, heroic fanfare, 2 s" |
| 16 | `ui_power_unlock.ogg` | FAL `stable-audio` | "power unlock shimmer, teal energy surge, 2 s" |
| 17 | `ui_mission_start.ogg` | FAL `stable-audio` | "mission briefing alert, civic grid notification, 2 s" |
| 18 | `ui_mission_complete.ogg` | FAL `stable-audio` | "mission success chime, hopeful resolution, 2 s" |

### 4.3 City Ambience & Event Alerts (FAL)

| # | File | Source | Duration | Notes |
|---|------|--------|----------|-------|
| 19 | `ambience_city_base_loop.ogg` | FAL `stable-audio` | 30–60 s | "near-future city ambience, distant traffic, light wind, coastal atmosphere, constant, looping" |
| 20 | `ambience_city_night_loop.ogg` | FAL `stable-audio` | 30–60 s | "night city ambience, quieter, distant sirens, ocean waves, constant, looping" |
| 21 | `event_alert_incoming.ogg` | FAL `stable-audio` | 7 s | "two-tone industrial alert klaxon, base under attack warning" — stinger |
| 22 | `event_alert_rescue_needed.ogg` | FAL `stable-audio` | 5 s | "urgent civilian distress signal, city emergency broadcast" |
| 23 | `event_alert_disaster.ogg` | FAL `stable-audio` | 7 s | "seismic rumble alert, structural danger warning, deep bass" |
| 24 | `event_alert_drone_swarm.ogg` | FAL `stable-audio` | 5 s | "hostile drone swarm detected, rapid beeping alert" |

### 4.4 Mission Stingers (FAL)

| # | File | Source | Duration | Notes |
|---|------|--------|----------|-------|
| 25 | `stinger_mission_intro.ogg` | FAL `stable-audio` | 7 s | "cinematic hero mission start, rising orchestral synth, hopeful" |
| 26 | `stinger_victory.ogg` | FAL `stable-audio` | 7 s | "triumphant short cinematic synth orchestral stinger, hopeful resolution" |
| 27 | `stinger_defeat.ogg` | FAL `stable-audio` | 7 s | "somber defeat stinger, low brass, slow fade" |
| 28 | `stinger_boss_reveal.ogg` | FAL `stable-audio` | 7 s | "dramatic boss reveal, dark synth, tension, low rumble" |

### 4.5 Radio & Civilian Barks (FAL ElevenLabs TTS)

**Rule:** Every recurring character gets a distinct voice. Never use the same speaker for all roles.

| # | Character / Role | Voice Profile | Sample Lines | Count |
|---|-----------------|---------------|--------------|-------|
| 29 | **Civic Grid AI** | Calm synthetic alto, clipped, radio-bandpass processing | "Lumen, structural collapse detected in Sector 7." / "Civilian distress signal confirmed." / "Power grid fluctuation detected." | 10–15 |
| 30 | **Civilian (panicked)** | Young adult female, breathy, urgent | "Help! The building's coming down!" / "Someone call The Lumen!" / "We're trapped on the roof!" | 8–12 |
| 31 | **Civilian (grateful)** | Middle-aged male, warm, relieved | "Thank you, Lumen!" / "You saved us!" / "The hero's here!" | 6–10 |
| 32 | **Null Choir Commander** | Deep male, distorted through resonator mask, threatening | "The aurora ends here, Lumen." / "You protect a broken system." / "Null Choir, engage." | 8–12 |
| 33 | **Heliostat Lieutenant** | Female, corporate-cold, precise | "Syndicate assets are non-negotiable." / "You're costing us credits, hero." / "Fall back to secondary position." | 6–10 |
| 34 | **Emergency Dispatcher** | Male, professional, rapid-fire | "All units, report to Grid Reference 7-7-4." / "Fire team, proceed with caution." / "Medical en route." | 8–12 |

**TTS workflow:**
1. Write 5–20 short barks per character (under 6 words each).
2. Generate with assigned FAL ElevenLabs voice.
3. Convert to OGG, trim silence, normalize to 0.85 peak.
4. Store under `res://assets/audio/voices/<character>/`.

### 4.6 Music (FAL Stable Audio 2.5)

All tracks in **90 BPM, D minor** family for crossfade compatibility.

| # | File | Duration | Prompt Summary |
|---|------|----------|----------------|
| 35 | `music_menu_theme.ogg` | 90 s | "dark ambient sci-fi soundtrack, brooding synth pads, slow pulse, 90 BPM, D minor, atmospheric, instrumental" |
| 36 | `music_city_exploration.ogg` | 120 s | "upbeat heroic exploration music, bright synth arpeggios, hopeful melody, 90 BPM, D minor, cinematic, instrumental" |
| 37 | `music_combat.ogg` | 120 s | "driving aggressive electronic combat music, pounding percussion, dark synth bass, 90 BPM, D minor, instrumental" |
| 38 | `music_story_mission.ogg` | 90 s | "cinematic narrative mission music, emotional strings, building tension, 90 BPM, D minor, instrumental" |
| 39 | `music_victory_theme.ogg` | 60 s | "triumphant victory music, soaring synth melody, heroic resolution, 90 BPM, D minor, instrumental" |

---

## 5. Godot Integration Paths

```
res://assets/
  3d/
    characters/
      lumen/
        lumen_body.glb
        lumen_costume_variants.glb
      civilians/
        civilian_male.glb
        civilian_female.glb
        civilian_child.glb
      enemies/
        drone_scout.glb
        drone_heavy.glb
        null_choir_soldier.glb
        heliostat_enforcer.glb
        storm_child_charger.glb
    props/
      aurora_collector_tower.glb
      transit_line_support.glb
      street_lamp_meridian.glb
      civic_terminal.glb
      residential_block_modular.glb
      commercial_tower_modular.glb
      construction_crane.glb
      fire_escape_ladder.glb
      vehicle_parked_car.glb
      vehicle_transit_pod.glb
      drone_pad.glb
      null_resonator_emitter.glb
    vfx/
      vfx_ion_trail.png
      vfx_aurora_beam.png
      vfx_sonic_ring.png
      vfx_aegis_shield.png
      vfx_explosion_generic.png
      vfx_energy_impact.png
    decals/
      decal_scorch_mark.png
      decal_hologram_flicker.png
  audio/
    sfx/
      flight/
        flight_whoosh_loop.ogg
        flight_boost_burst.ogg
        flight_ascend.ogg
        flight_descend.ogg
      powers/
        power_radiant_beam_fire.ogg
        power_radiant_beam_charge.ogg
        power_sonic_burst.ogg
        power_aegis_activate.ogg
        power_aegis_impact.ogg
        power_rescue_lift.ogg
        power_orbit_sprint.ogg
      ui/
        ui_click.ogg
        ui_confirm.ogg
        ui_error.ogg
        ui_level_up.ogg
        ui_power_unlock.ogg
        ui_mission_start.ogg
        ui_mission_complete.ogg
      events/
        event_alert_incoming.ogg
        event_alert_rescue_needed.ogg
        event_alert_disaster.ogg
        event_alert_drone_swarm.ogg
      stingers/
        stinger_mission_intro.ogg
        stinger_victory.ogg
        stinger_defeat.ogg
        stinger_boss_reveal.ogg
    ambience/
      ambience_city_base_loop.ogg
      ambience_city_night_loop.ogg
    music/
      music_menu_theme.ogg
      music_city_exploration.ogg
      music_combat.ogg
      music_story_mission.ogg
      music_victory_theme.ogg
    voices/
      civic_grid/
        alert_sector7.ogg
        distress_confirmed.ogg
        power_fluctuation.ogg
        ...
      civilian_panicked/
        help_building.ogg
        call_lumen.ogg
        trapped_roof.ogg
        ...
      civilian_grateful/
        thank_you.ogg
        saved_us.ogg
        hero_here.ogg
        ...
      null_choir_cmdr/
        aurora_ends.ogg
        broken_system.ogg
        engage.ogg
        ...
      heliostat_lt/
        assets_non_negotiable.ogg
        costing_credits.ogg
        fall_back.ogg
        ...
      emergency_dispatcher/
        all_units_774.ogg
        fire_team_caution.ogg
        medical_en_route.ogg
        ...
  ui/
    icons/
      hud_power_flight.png
      hud_power_boost.png
      hud_power_radiant_beam.png
      hud_power_sonic_burst.png
      hud_power_aegis.png
      hud_power_rescue.png
      hud_power_orbit_sprint.png
      hud_objective_marker.png
      ...
  prompts/
    (generation prompts archive)
  SOURCES.md
  asset_manifest.json
```

---

## 6. Generation Order Recommendation

When Producer green-lights, generate in this order to unblock gameplay fastest:

1. **P0 — Hero model + flight animations** (Meshy) — unblocks all gameplay testing
2. **P0 — Drone scout model** (Meshy/FAL 3D) — unblocks enemy encounter testing
3. **P0 — Flight SFX + power SFX** (Kenney + FAL) — unblocks audio feedback
4. **P0 — UI SFX** (Kenney) — unblocks menu/HUD testing
5. **P1 — Civilian models** (Meshy) — unblocks rescue events
6. **P1 — Enemy models** (Meshy) — unblocks combat encounters
7. **P1 — City ambience + event alerts** (FAL) — unblocks atmosphere
8. **P1 — Radio/civilian barks** (FAL ElevenLabs TTS) — unblocks event dialogue
9. **P2 — Music** (FAL 2.5) — polish pass
10. **P2 — Props, buildings, VFX textures** — environment polish
11. **P2 — Mission stingers** — narrative polish

---

## 7. Budget Notes

- **Meshy AI:** Character models cost credits. Hero (The Lumen) is highest priority. Batch character requests to minimize API overhead.
- **FAL.ai:** SFX via `stable-audio` (Open) is cheap per call. Music via `stable-audio-25` is several× more expensive — generate only after SFX is locked. TTS via ElevenLabs is per-character; batch all lines per character in one session.
- **Kenney:** Free, CC0. Download once, use forever.
- **Expected dud rate:** ~10–20% for FAL generative audio. Budget one regeneration pass. Delete duds, re-run pipeline (idempotent skip).

---

## 8. Open Questions for Producer

1. Confirm Meshy API key and credit budget for character generation.
2. Confirm FAL_KEY is set and which FAL plan (free vs. paid) to determine rate limits.
3. Confirm ElevenLabs voice roster — which specific voice IDs for each character role.
4. Confirm target polygon budgets for hero (~20k tris), civilians (~15k tris), drones (~8k tris).
5. Confirm whether to generate all 6 music tracks now or defer to polish phase.
6. Confirm Meridian City district count for full release (affects modular building kit scope).
