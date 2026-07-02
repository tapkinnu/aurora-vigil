# Creative Delta Brief: District 2, Multi-Step Mission Arcs & Recurring Cast Expansion

**Version:** 1.0
**Created:** 2026-07-02
**Status:** Draft — game-creative kanban output
**Card:** t_c3d4758c

---

## Table of Contents

1. [District 2 — The Flats](#1-district-2--the-flats)
2. [Deeper Mission Arcs](#2-deeper-mission-arcs)
3. [Recurring Cast Expansion](#3-recurring-cast-expansion)
4. [Asset Needs](#4-asset-needs)
5. [Integration Plan](#5-integration-plan)

---

## 1. District 2 — The Flats

### District Name

**The Flats** — the original sea-level industrial quarter of Meridian City, built before the tier-platform system was engineered. Named for its flat, sprawling layout at the base of the cliff city, where canals cut through old factory districts and stormwater drains into the dark ocean beyond.

### District Concept

The Flats is Meridian City's underbelly — an industrial canal district built on reclaimed tidal flats at the base of the Shelf's cliff face. Where the upper tiers gleam with teal-glass and gold transit, The Flats is low, dense, and wet. Narrow brick-and-concrete alleys thread between repurposed factories and tenement blocks. Canals (some open, some roofed by elevated transit viaducts) serve as the district's arterial infrastructure — stormwater management that also functions as shipping lanes for Heliostat Syndicate off-the-books cargo. The air smells of brine, rust, and ozone from the aurora collector sub-station that hums beneath the eastern basin.

The Null Choir recruits heavily here — the Shimmer Event's health effects hit the working poor hardest. The Storm Children maintain a community kitchen and safehouse in a converted cannery on the southern canal. The Heliostat Syndicate uses the canal network for undocumented shipping into and out of Meridian's lower transit ports. The Lumen must navigate tight, vertical spaces, canal-side rescues, and ambush alleys — a stark contrast to the open sky patrolling of upper Meridian.

### Visual Identity

**Color Palette:**
- **Primary:** Warm rust-orange (aged brick, corrugated metal), deep teal (canal water, algae-slicked stone), amber (street-level sodium lamps, window glow)
- **Secondary:** Tarnished copper (old piping, factory fixtures), moss green (canal algae, damp stone), dirty white (salt-stained concrete)
- **Accent:** Neon green (illegal Storm Children marker paint), sickly magenta (Null Choir resonator glow on canal walls)

**Not a copy of:** Venice (no gondolas, no grand architecture, no tourism), London Docklands (no warehouse conversions for luxury), Kowloon Walled City (no unlit vertical squalor — The Flats has working infrastructure, just lower and grimmer).

### District Geometry Specs

| Property | The Flats | Meridian City Downtown (Existing) |
|---|---|---|
| Building height | 2–8 stories (mode: 4) | 6–40+ stories (mode: 18) |
| Building footprint | 60–80% lot coverage, tight block packing | 30–50% lot coverage, plazas and setbacks |
| Street width | 3–8 m (narrow alleys + 10 m canals) | 15–30 m (boulevards) |
| Block size | 40×60 m irregular | 80×120 m rectilinear |
| Canals | 6–10 m wide, 2–3 m deep, tidal influence | None |
| Roof profile | Flat with water towers, HVAC, satellite dishes | Crown-lit tapering spires, antenna clusters |
| Sky visibility | 30–50% (narrow alleys, bridge cover) | 80–90% (open air) |

### Lighting / Atmosphere

- **Default:** Overcast golden-hour — amber sodium streetlights against a bruised violet sky. Wet surfaces reflect warm light.
- **Storm:** Teal-black clouds, rain sheeting off corrugated roofs, canal water choppy and dark. Amber lights strobe under the heaving sky.
- **Aurora event:** The canals glow teal — the water reflects the ionized sky. Building edges rim with aurora-green corona. Creepy-beautiful.
- **Night:** Almost no ambient light from the wider city — The Flats sits in the shadow of the Shelf above. Pools of amber cone light from security lamps. The canals are black mirrors.

### Connection to Existing District

The Flats is accessed from **The Shelf** (the lowest Meridian tier) via three links:

1. **The Climb** — a winding stair-street with switchbacks descending 40 m of cliff face. Original pedestrian link. Narrow, atmospheric, used for patrol missions.
2. **The Cargo Tram** — a funicular rail line running freight and residents between the Shelf terminus and the Flats' eastern canal station. Functional but worn. Gold transit accents are faded and graffitied.
3. **The Weir Bridge** — a heavy road-and-pedestrian bridge crossing the storm-canal outflow at the southern edge. Connects Flats emergency responders to main city routes. This is the route Civil Defense uses.

### Signature Visual Landmarks (Screenshot-Readable)

1. **The Weir** — A massive stormwater control structure at the southern edge where the main canal meets the ocean. Three arched sluice gates, rust-stained industrial concrete, amber hazard beacons flashing at night. Visible from the Shelf above. Functions as a district boundary marker.

2. **The Needle Stack** — A cluster of four decommissioned factory smokestacks, 60–80 m tall, painted in faded maritime warning bands (red-white-red). One stack has been retrofitted as an aurora collector sub-station antenna — teal corona rings pulse at the top. The Needle Stack is the district's highest point and a reference landmark visible from the Shelf edge.

3. **Syndicate Smuggling Dock** — A canal-side loading bay hidden under a elevated transit viaduct. Green tarnished copper roof, a mobile crane, shipping crates stamped with Heliostat Energy Partners insignia. The dock has a submerged gate — boats enter from the ocean via a concealed channel. One of several Syndicate black-market offload points.

4. **Canal Arches** — Decorative but functional cast-iron footbridges crossing the main canals every 2–3 blocks. Each arch has integrated amber strip lighting. The arches read clearly as "The Flats district" in screenshots — no other Meridian district has them.

5. **Storm Drain Grates** — Oversized circular grates (3 m diameter) set into the street at intersections. During storms they vent excess water; during Null Choir operations they serve as access hatches to the under-city drain network. The grates' pattern (concentric rings with a central meridian compass rose) is a signature visual motif.

### Faction Presence in The Flats

| Faction | Presence | Notes |
|---|---|---|
| **Null Choir** | Heavy | Recruiting ground. Safehouses in old factory basements. Their acoustic resonator workshops operate in abandoned canal-side buildings where noise is masked by water flow. |
| **Heliostat Syndicate** | Moderate (influential) | Controls the smuggling docks and two legitimate warehouses. Their canalside security patrols are the only armed private force in the district. |
| **Storm Children** | Moderate (community) | A converted cannery serves as a community center and health clinic. The Changed gather here. Strong community trust. |
| **Civic Grid** | Low | Understaffed Grid office in the eastern canal station. Grid worker presence is thin; the district feels underserved. |

---

## 2. Deeper Mission Arcs

### Design Notes

Each arc below takes an existing single-objective mission and expands it to 2–4 **steps** with branching objectives, mid-mission dialogue beats, and failure/recovery paths. Steps are linear within a mission (no full-open-world branching — the step sequence is fixed), but the **success/failure path at each step** changes which subsequent steps fire and what radio dialogue plays.

### Arc Format Legend

```
Step N: [Title]
  Objective: [What the player must do]
  Target Event Kind: [event from events.json to spawn]
  Success Condition: [what counts as "pass"]
  Failure Consequence: [what happens on fail, and how it affects later steps]
  Radio Beat: [in-character radio bark that plays on step start / during step]
```

---

### Arc 1: awakening_patrol → "First Light" (Tutorial, 3 Steps)

**Current:** Single objective — fly through Meridian and answer the first emergency.

**Expanded Arc:**

```
Step 1: The Jump
  Objective: Launch from the Shelf observation platform and complete the flight tutorial circuit
  Target Event Kind: none (flight corridor)
  Success Condition: Complete flight corridor (3 check rings) within time
  Failure Consequence: Timer expires — rings reset, civilian radio quips ("They're still learning, give 'em a sec"). Retry until pass.
  Radio Beat: Civic Grid AI: "Lumen, flight corridor calibrated and green. Take it easy on the boost — the Shelf's turbulence can catch you off-guard."

Step 2: First Call
  Objective: Respond to a collapsing scaffolding incident on Conduit Row
  Target Event Kind: rescue_signal [variant: scaffolding_trap]
  Success Condition: Reach the trapped worker before the scaffolding gives way (15s timer)
  Failure Consequence: Scaffolding collapses — worker falls. MES catches them with emergency netting. No injury, but The Lumen sees civilians protect each other. Trust -0 (tutorial), but bark changes to gratitude-with-edge.
  Radio Beat (success): Civilian (grateful): "You're real. You're actually real. Thank you!"
  Radio Beat (failure): MES Dispatcher: "Lumen, we've got them. They're shaken but safe — that was close."

Step 3: First Debrief
  Objective: Arrive at Grid Control to receive your emergency channel
  Target Event Kind: none (dialogue scene)
  Success Condition: Land at Grid Control marker within 30s
  Failure Consequence: None (narrative-only step, no fail state)
  Radio Beat: Director Tanek (via Grid channel): "Lumen, welcome to the network. From now on, when this city calls — you answer on our channel. Don't make me regret it."
```

---

### Arc 2: null_choir_rising → "Noise Floor" (Faction Intro, 3 Steps)

**Current:** Single objective — survive a wave of Null Choir ground units.

**Expanded Arc:**

```
Step 1: Investigation
  Objective: Patrol Foundry Quarter and trace the acoustic interference disrupting aurora maintenance
  Target Event Kind: null_resonator [variant: foundry_disturbance]
  Success Condition: Fly through 3 scan points to triangulate the signal
  Failure Consequence: Signal goes cold — first scan fails, but second point reveals location anyway (the interference is too strong to hide). Step continues with weakened intel — fewer context clues in dialogue.
  Radio Beat: Grid Worker (scanner tech): "Lumen, we're picking up a weird harmonic in the Foundry. Not a fault — someone's broadcasting on our maintenance frequency."

Step 2: Discovery
  Objective: Track signal to concealed Null Choir workshop
  Target Event Kind: null_resonator [variant: workshop_reveal]
  Success Condition: Enter workshop detection radius unnoticed
  Failure Consequence: Null Choir Cadre detects approach — they trigger a sonic dampener early, making Step 3 harder (debuff: all powers recharge 20% slower for the rest of the mission).
  Radio Beat: Wren Osei (Null Choir cadre leader, discovered): "Lumen. Of course. You feel it too, don't you? That collector's singing at an unsafe pitch. We're only trying to bring it down for a tune-up."

Step 3: Resolution (Choice Moment)
  Objective: Decide how to handle the collector fault Wren has identified
  Target Event Kind: power_surge [variant: collector_fault]
  Success Condition: Resolve the collector fault by one of three methods
    - Option A: Shut down the Null Choir device and report the fault to Grid (Grid method)
    - Option B: Assist in a controlled shutdown (assist method)
    - Option C: Contain the surge with Aegis Field (containment method)
  Failure Consequence: Collector reaches critical — minor explosion damages the block. Civilians evacuated but property damage. Trust -1. Step auto-resolves with Grid blaming the incident.
  Radio Beat (Option A): Director Tanek: "We'll launch an inspection. Null Choir tactics aren't the answer — but their data will be reviewed. Stand down, Lumen."
  Radio Beat (Option B): Wren Osei: "You cooperated. That — wasn't expected. The Flats might have some of our people who'll talk to you now."
  Radio Beat (Option C): Grid Controller: "Containment holding. Good work, Lumen. But that device of theirs shouldn't have been there in the first place."
```

---

### Arc 3: civic_grid_down → "Blackwater" (District Rescue, 3 Steps)

**Current:** Single objective — restore power to a blacked-out district and calm panicking crowds.

**This arc moves to The Flats.**

```
Step 1: Blackout
  Objective: Respond to total grid failure in The Flats — the canal district auxiliary station has gone dark
  Target Event Kind: power_surge [variant: sub_station_dark]
  Success Condition: Reach the sub-station and diagnose the fault (scan for energy signature)
  Failure Consequence: No power — first 30s of Step 2 are in darkness (limited visibility). Civilians more panicked.
  Radio Beat: Pavla Jezek (Flats civic engineer, first appearance): "Lumen, this is Pavla at the East Canal Station. We've lost everything. Main breaker tripped and— hold on. I hear something in the drain below the sub-station."

Step 2: Canal Search
  Objective: Navigate the dark canal tunnels beneath the station to find the fault source
  Target Event Kind: rogue_drone [variant: canal_drone_ambush]
  Success Condition: Clear 3 rogue maintenance drones sabotaging the conduit
  Failure Consequence: A drone escapes — it damages a second conduit farther down. Power restoration takes longer. More grid workers are at risk in Step 3.
  Radio Beat (during stealth canal descent): Pavla Jezek: "Those drones aren't ours. They were reprogrammed — I can see the resonance signature. Null Choir? No... this is cleaner. More corporate."

Step 3: Restore / Defend
  Objective: Hold the sub-station while Pavla brings the grid back online
  Target Event Kind: power_surge [variant: sub_station_flood]
  Success Condition: Survive 60s of surging energy / drone distractions while Pavla resets main breakers
  Failure Consequence: Power comes back but the sub-station is damaged — The Flats gets intermittent power for 2 missions. District trust -1.
  Radio Beat (success): Pavla Jezek: "We're live! Lights are back in the Basin. Lumen — thank you. That was... that was too close. The Flats owes you one."
```

---

### Arc 4: stormwall → "Stormwall Protocol" (Midgame Surge, 2 Steps)

**Current:** Single objective — use unlocked powers to protect Meridian during a citywide surge.

**Expanded Arc:**

```
Step 1: Surge Assessment
  Objective: Fly a rapid assessment of 3 collector station statuses across upper Meridian and The Flats
  Target Event Kind: power_surge [variant: cascade_warning]
  Success Condition: Scan all 3 stations within time limit (45s)
  Failure Consequence: One station goes unassessed — that station's collector will go critical before it can be addressed, adding a civilian-evacuation sub-objective to Step 2.
  Radio Beat: Civic Grid AI: "Aurora density rising past Tier 3 threshold. Stormwall barrier at 62% capacity. Collectors one, three, and six are in the red. Lumen — we need a flyover. Now."

Step 2: Stormwall Hold
  Objective: Stabilize the outgoing collectors using the correct powers at each site
  Target Event Kind: power_surge (x3)
  Success Condition: Use Radiant Beam (vent heat) at station A, Aegis Field (contain surge) at station B, Sonic Burst (clear resonance lock) at station C
  Failure Consequence: Wrong power at a station = that collector goes offline. Power rationing in that district for 1 mission.
  Radio Beat: Emergency Dispatcher: "Stormwall breach imminent. Lumen, all three stations are your priority — we're stretched too thin to reinforce."
```

---

### Arc 5: the_long_night → "The Long Night" (Climactic Cross-District, 4 Steps)

**Current:** Single objective — hold an extended patrol as emergencies escalate across Meridian.

**This arc spans both districts and is the penultimate pre-finale peak.**

```
Step 1: First Wave — The Flats
  Objective: Respond to a canal flood surge that's breaching residential basements
  Target Event Kind: power_surge [variant: canal_flood]
  Success Condition: Use Aegis Field at 4 canal-breach points to seal bulkhead doors
  Failure Consequence: One basement floods — civilian rescue sub-objective unlocks. Rescue 3 civilians using Rescue Lift during flood.
  Radio Beat: Storm Child (canal safehouse): "The water's rising fast. We've got 23 people on the upper floor of the cannery — Lumen, the stairwell's already under!"

Step 2: Escalation — The Shelf
  Objective: A Shimmer Echo erupts in the Foundry Quarter on the Shelf, shaking the platform foundations
  Target Event Kind: shimmer_echo [variant: tier_shock]
  Success Condition: Contain the Echo with Aegis Field (hold for 20s)
  Failure Consequence: Echo destabilizes — Foundry Quarter loses structural integrity in one building. Evacuation sub-objective. Null Choir uses the chaos to make a statement.
  Radio Beat: Wren Osei (Null Choir): "The grid is eating itself. You feel that, Lumen? That's your precious aurora infrastructure trying to kill the people who built it."

Step 3: Peak — Halo Spire
  Objective: The cascading failures hit Halo Spire. The main collector is overloading.
  Target Event Kind: solar_array_overload [variant: spire_overload]
  Success Condition: Use Radiant Beam to vent the overload, then Aegis Field to protect the spire's crew (simultaneous — hold Aegis while firing Beam)
  Failure Consequence: Spire overload damages the crew level — 2 Grid workers injured. They survive but are out of action for subsequent missions. Trust -2.
  Radio Beat: Director Tanek: "Lumen — the Spire just went Code Red. I'm ordering evacuation of floors 40 through 52. If you can't hold it, tell me now so I can clear the zone."

Step 4: Resolution — Citywide Assessment
  Objective: A final review flight across both districts to confirm stabilization
  Target Event Kind: none (dialogue + flight)
  Success Condition: Fly a stabilization circuit (touch 3 checkpoints across both districts)
  Failure Consequence: One checkpoint missed — the player gets incomplete data but the mission ends. Slightly reduced rewards.
  Radio Beat (The Flats survivor): Pavla Jezek: "The Flats held, Lumen. We're patching the last breach point now. I don't know how you did both districts at once."
  Radio Beat (Shelf survivor): Captain Briggs (MES): "Lumen... that was all of it. Every sector. I don't know how you pulled it off either. But thank you. Get some rest."
```

---

### Arc 6: first_contact → "First Contact" (Season 1 Climax, 2 Steps)

**Current:** Single objective — confront a Null Choir commander at the heart of the surge.

**Expanded Arc:**

```
Step 1: Surge Core
  Objective: Find the Null Choir commander at the center of the Foundry Quarter surge
  Target Event Kind: null_resonator [variant: surge_core]
  Success Condition: Navigate the surge-affected Foundry Quarter and reach the center platform
  Failure Consequence: Surge damage — 15s delay before reaching the commander. She addresses The Lumen first, setting terms.
  Radio Beat: Null Choir Commander (via resonator-amplified voice): "You're persistent. Good. That means you care. Now let's see if you care enough to listen."

Step 2: Confrontation
  Objective: Face the Null Choir Commander and choose a response
  Target Event Kind: none (dialogue encounter)
  Success Condition: Reach the commander within time
  Failure Consequence: Commander escapes before full confrontation — leaves a data chip with collector vulnerability schematics. The Lumen learns the same information, but misses the faction-intro dialogue with the commander.
  Radio Beat (full confrontation): Null Choir Commander: "You think I'm the enemy. But ask yourself — who built the collectors? Who profits when they tremble? We're just trying to survive what your power source is doing to us."
  Note: Full outcome branching for this mission is already detailed in docs/creative/05_story_missions.md Mission 2 entry. This arc just breaks it into clear steps.
```

---

### Arc 7: solar_cascade → "Solar Cascade" (Finale, 3 Steps)

**Current:** Single objective — stabilize overloaded solar arrays.

**Expanded Arc — now takes place partially in The Flats (the solar array feeds into the Flats sub-station).**

```
Step 1: Cascade Detection
  Objective: Fly to the Flats-based solar array substation where the overload began
  Target Event Kind: solar_array_overload [variant: cascade_origin]
  Success Condition: Reach the sub-station and scan the energy feed path
  Failure Consequence: Delayed arrival — second cascade node activates on the Shelf. Now the player must manage two cascading failures simultaneously (time-sharing between districts).
  Radio Beat: Pavla Jezek: "Lumen, the cascade started here — someone bypassed the regulator safeties on the Flats array. I've got the schematics. They're... they look like Heliostat routing codes."

Step 2: Containment Sprint
  Objective: Vent three cascade nodes along the feed line between The Flats and Halo Spire
  Target Event Kind: solar_array_overload (x3, positioned along canal transit line)
  Success Condition: Use Radiant Beam at each node within 90s total
  Failure Consequence: One node overloads fully — minor explosion, local fire. Grid responds. XP reduced.
  Radio Beat: Maren Voss (Syndicate): "Lumen, if you're listening — those routing codes are legitimate. They're from my own division. Someone inside Heliostat is making a power play. The cascade is a diversion."

Step 3: The Spire Finale
  Objective: Reach Halo Spire and stabilize the main array before the cascade reaches the civic grid
  Target Event Kind: solar_array_overload [variant: spire_finale]
  Success Condition: Use Radiant Beam + Aegis Field combo to vent and contain simultaneously
  Failure Consequence: Cascade reaches the grid — citywide short blackout (5s). Trust -3. This is an intentional near-miss even on failure: the grid recovers but confidence is shaken.
  Radio Beat (success): Civic Grid AI: "Cascade neutralized. Grid integrity at 97%. The Flats sub-station reports nominal. Well done, Lumen."
  Radio Beat (failure): Civic Grid AI, strained: "Grid breach isolated. Emergency bulkheads engaged. The blackout was contained to two sectors. Casualties: none. Lumen — the margin was too thin."
```

---

### Arc 8: skyway_runaway_response → "Skyway Runaway" (Midgame Chase, 2 Steps)

**Current:** Single objective — overtake the runaway skyway capsule and stabilize it.

**Expanded Arc — the chase path now passes over The Flats.**

```
Step 1: Intercept
  Objective: Use Orbit Sprint to overtake the runaway skyway capsule
  Target Event Kind: skyway_runaway [variant: upper_skyway]
  Success Condition: Catch up to the capsule before it reaches the Flats transfer station
  Failure Consequence: Capsule enters the Flats transfer station at speed — collision with a stationary pod. Damage to the station, minor injuries.
  Radio Beat: Emergency Dispatcher: "Skyway pod Lima-6 is non-responsive! It's accelerating through the Shelf transfer — Lumen, it's heading for the Flats line. That station is packed with shift workers!"

Step 2: Stabilize
  Objective: Attach to the capsule and use Aegis Field to brace it before the tether snaps
  Target Event Kind: skyway_runaway [variant: tether_snap]
  Success Condition: Hold Aegis Field on the capsule for 10s while MES cuts emergency brakes
  Failure Consequence: Tether snaps — capsule falls 20 m into a canal. Water cushions the fall. All passengers survive but are soaked and shaken. Capsule is a total loss. XP reduced.
  Radio Beat (success): MES Rescue Lead: "She's stable! Cutting brakes now — stand clear! Lumen, you've got her. Good catch."
  Radio Beat (failure, canal impact): Pavla Jezek: "We've got people in the water — Flats emergency services are pulling them out. They're alive, Lumen. Banged up, but alive."
```

---

### Summary: Which Missions Get Upgraded

| Mission ID | Title | Steps | Priority |
|---|---|---|---|
| awakening_patrol | First Light | 3 | P0 (tutorial) |
| null_choir_rising | Noise Floor | 3 | P0 (faction intro) |
| civic_grid_down | Blackwater | 3 | P0 (district rescue, moved to The Flats) |
| stormwall | Stormwall Protocol | 2 | P1 |
| the_long_night | The Long Night | 4 | P0 (climactic, spans both districts) |
| first_contact | First Contact | 2 | P1 |
| solar_cascade | Solar Cascade | 3 | P0 (finale) |
| skyway_runaway_response | Skyway Runaway | 2 | P1 |

**Total: 8 missions upgraded, 22 total steps across all arcs.**

Unchanged (keep single-step for now, may upgrade in future pass):
- spire_rescue (The Burning Spire)
- drone_chase (Ghosts in the Grid)
- tether_rescue (Tether Rescue)
- dawn_aftershock (Dawn Aftershock)

---

## 3. Recurring Cast Expansion

### Current Cast (5 characters — DO NOT REPLACE, add to this)

| Character | Voice | Faction | Role |
|---|---|---|---|
| Civic Grid AI | Aria | Civic Grid | City system voice |
| Civilian (Panicked) | Sarah | Unaligned | Crisis civilian |
| Civilian (Grateful) | Charlie | Unaligned | Post-rescue civilian |
| Emergency Dispatcher | Callum | MES | Radio dispatch |
| Null Choir Commander | George | Null Choir | Antagonist |

### New Recurring Characters (5 characters added)

Each character gets: name, role, voice profile, bark lines, and mission appearances.

---

#### Character 1: Sol Vance — Storm Children Envoy

**Role:** Ambiguous ally. A Changed individual (low-grade electromagnetic field sensitivity) who serves as an informal bridge between the Storm Children community and The Lumen. Sol is pragmatic, weary, and deeply protective of their people — they don't trust The Lumen at first, but they trust institutions even less. Their help always comes with a cost.

**Voice Profile**

| Property | Value |
|---|---|
| ElevenLabs Voice | Laura |
| Age / Gender | 30s, female |
| Accent | Neutral urban, slight coastal drawl |
| Pitch | Medium-low |
| Pace | Measured, with pauses for emphasis |
| Emotional Range | Skeptical warmth → urgent protectiveness → quiet gratitude |
| Post-Processing | Light radio-bandpass when communicating from Flats safehouse |

**Bark Lines**

| Context | Line |
|---|---|
| Idle (safehouse) | "You flew over the canal earlier. The kids thought you were a firework. I told 'em not to get used to it." |
| Idle (skeptical) | "You saved six of us last week. That means something. But one rescue doesn't make you family." |
| Alert (danger near safehouse) | "Lumen — the Null Choir's been spotted near the cannery. Again. I'm moving my people to the basement." |
| Alert (Flats flood) | "The water's rising on the south canal. We've got elders who can't climb. I need you." |
| Combat (close support) | "I can feel the resonator from here — three blocks east, in the old pump station. Don't let them power it up." |
| Rescue (someone saved) | "You got them out. Okay. Okay, I believe you now — you're the real thing." |
| Rescue (after helping) | "One of ours. You brought one of ours back. I... don't know how to thank you for that." |
| Victory (mission complete) | "Safehouse is dry. People are safe. If you ever need a place to land in The Flats — you're welcome here." |

**Mission Appearances:** civic_grid_down (Blackwater), the_long_night, stormwall (when in The Flats portions)

---

#### Character 2: Kaelith Vorn — Heliostat Syndicate Fixer

**Role:** Rival / smugger contact. Vorn is a mid-level Heliostat logistics specialist who operates out of the Flats smuggling dock. Clean-cut, corporate-calm, but always running two angles. He provides The Lumen with useful intel about Syndicate operations — not out of altruism, but because he's positioning himself. Playing both sides is his job. He has a dry cynicism that never completely hides his competence.

**Voice Profile**

| Property | Value |
|---|---|
| ElevenLabs Voice | Roger |
| Age / Gender | 40s, male |
| Accent | Cultivated, vaguely Atlantic-coast corporate |
| Pitch | Medium, smooth |
| Pace | Deliberate, unhurried |
| Emotional Range | Corporate calm → veiled threat → reluctant respect |
| Post-Processing | Slight hollow reverb when in the dock warehouse |

**Bark Lines**

| Context | Line |
|---|---|
| Idle (dock) | "Lumen. You keep showing up here. People are starting to talk. In my line of work, talk is expensive." |
| Idle (transactional) | "I have information. You have speed. Let's not pretend this is a friendship." |
| Alert (Smuggling Dock raid) | "Syndicate auditors incoming. If I'm not at my desk with the right paperwork in five minutes, this dock disappears — and so does my intel." |
| Alert (security sweep) | "Corporate security just pinged me. They know something's in the canals tonight. Stay off the main channel." |
| Combat (self-defense) | "That drone was Syndicate property. I'll have to file a loss report. Please don't make a habit of breaking my inventory." |
| Rescue (civilians from Syndicate area) | "You pulled civilians out of a restricted zone. That's going on my incident log. I'll make it look like a maintenance error." |
| Rescue (after Syndicate threat) | "You got them clear. That's the only reason I'm not reporting this. Next time... next time, call me first." |
| Victory (mission complete) | "The dock's still standing. My records are clean. If you need something off the books — and I mean something minor — you know where I am." |

**Mission Appearances:** solar_cascade, the_long_night (Step 3 involving Syndicate angle), potential future Syndicate-focused missions

---

#### Character 3: Pavla Jezek — Flats Civic Engineer

**Role:** Recurring rescue contact. Pavla is the senior grid engineer assigned to the East Canal Station in The Flats. She's been working in Meridian's lower infrastructure for 20 years — she knows every pipe, conduit, and back-alley junction. She's practical, blunt, and perpetually tired but never resigned. She becomes The Lumen's eyes on the ground in The Flats, providing technical intel and civilian coordination.

**Voice Profile**

| Property | Value |
|---|---|
| ElevenLabs Voice | Lily |
| Age / Gender | 50s, female |
| Accent | Regional coastal (faint, like a lifetime of coastal industrial towns) |
| Pitch | Medium-low, slightly gravelly |
| Pace | Quick, clipped — used to radio brevity |
| Emotional Range | Exasperated practicality → focused urgency → genuine pride |
| Post-Processing | Radio-filtered when speaking from the station; clean when in-person |

**Bark Lines**

| Context | Line |
|---|---|
| Idle (station) | "This station was built in '98. It wasn't designed for aurora loads. Every time the sky flickers, I lose an hour of sleep." |
| Idle (Flats pride) | "People think The Flats is just the city's basement. They're wrong. This district keeps the water out and the lights on. We earn our place." |
| Alert (sub-station fault) | "Lumen — we've got a pressure drop in the main conduit. If that line goes, half the Flats loses water treatment. I need eyes on the canal junction." |
| Alert (security breach) | "Unauthorized access at the East regulator. Security cams are dark. I'm locking down the station doors — but I can't hold it alone." |
| Combat (Null Choir near grid) | "Those resonator signatures are playing havoc with the telemetry. I can't tell what's a fault and what's their equipment. Lumen — physical inspection needed." |
| Rescue (civilian trapped in infrastructure) | "There's a maintenance crawl under the junction — one of my team got trapped when the surge hit. They can hear me but I can't reach them. The hatch is warped shut." |
| Rescue (after infrastructure fix) | "Conduit's stable. Water treatment nominal. You just saved about forty thousand people from a boil-water order. Not bad for a day's work." |
| Victory (mission complete) | "Station log: Flats grid restored. No casualties. Lumen departure confirmed. Get some rest, hero — tomorrow's forecast says aurora activity's picking up again." |

**Mission Appearances:** civic_grid_down (Blackwater — first appearance), the_long_night, solar_cascade, stormwall (Flats portions)

---

#### Character 4: Cinder (real name: Maro Tenn) — Null Choir Defector

**Role:** Mid-game turncoat. Cinder was a Null Choir Resonance Cadre technician who left after a mission crossed lines they couldn't accept. They now operate as an independent information broker in The Flats, hunted by both the Null Choir (for leaving) and the Syndicate (for what they know about past joint ops). They approach The Lumen with cautious, frightened offers of help — always watching over their shoulder.

**Voice Profile**

| Property | Value |
|---|---|
| ElevenLabs Voice | Will |
| Age / Gender | 20s, non-binary (they/them) |
| Accent | Neutral urban, slight flattening (from years of voice modulation training in the Null Choir) |
| Pitch | Medium, nervous energy |
| Pace | Quick, sometimes stumbling — overcaffeinated |
| Emotional Range | Anxious eagerness → breathless urgency → haunted stillness |
| Post-Processing | Voice breaks slightly under stress. No radio filter — they don't use Grid channels. |

**Bark Lines**

| Context | Line |
|---|---|
| Idle (nervous) | "I shouldn't be here. I really shouldn't be here. The Conductor's people patrol this canal every third day." |
| Idle (survivor's guilt) | "I helped calibrate those resonators. Before I left. Some of them are still out there, tuned to my old frequencies." |
| Alert (Null Choir patrol) | "They're here. They found me. Lumen — they have a portable dampener. Your powers will flicker within 50 meters. I have to move." |
| Alert (Syndicate + Null Choir convergence) | "I picked up Heliostat chatter mixed with Null Choir codes. They're working together on something. This is new. This is bad." |
| Combat (supporting The Lumen) | "I can spoof their resonator frequency — give you a 10-second window where their dampener won't affect you. That's all I've got." |
| Rescue (being rescued themselves) | "You came back for me. You — okay. Okay, I have data. A lot of data. It's yours. All of it. Just get me out of this district." |
| Rescue (rescuing others) | "There's a Null Choir safehouse two canals over — they're holding four Grid workers inside. I know the layout. I can get us in." |
| Victory (mission complete) | "We made it. I can't believe we made it. I need to disappear for a few days. But I'll be back. I owe you." |

**Mission Appearances:** the_long_night (post-defection, from Step 2 onward), solar_cascade (provides intel on Heliostat routing codes), first_contact (optional — if player opens dialogue path)

---

#### Character 5: Mira Adani — Retired Emergency Responder (The Calm)

**Role:** Veteran mentor figure — NOT a copy of any known superhero mentor. Mira is a retired Meridian Emergency Services district chief who spent 35 years running rescue operations across the Shelf and The Flats. She never had powers. She saved thousands of people with protocols, grit, and trust in her teams. She acts as an informal advisor to The Lumen — not by dispensing hero wisdom, but by showing them how the city's systems work from the ground level. She lives in a small apartment above a canal-side café in The Flats and volunteers at the Storm Children's community kitchen.

**Voice Profile**

| Property | Value |
|---|---|
| ElevenLabs Voice | Jessica |
| Age / Gender | 60s, female |
| Accent | Warm regional coastal (fuller version of the accent heard in younger Flats residents) |
| Pitch | Medium, warm |
| Pace | Slow, deliberate — the unhurried calm of someone who has seen everything |
| Emotional Range | Dry warmth → stern protectiveness → profound empathy |
| Post-Processing | None — clean, human voice. No radio filter, no reverb. She doesn't need tech to command attention. |

**Bark Lines**

| Context | Line |
|---|---|
| Idle (canal café) | "You fly fast. I'll give you that. But speed doesn't save everyone — knowing when to slow down does. Took me twenty years to learn that." |
| Idle (Flats pride) | "I've pulled bodies out of those canals. I've delivered babies in the Flats station during a blackout. This district is tough because it has to be." |
| Alert (civilian danger) | "Lumen. There's a fire in the old textile mill on Western canal. That building's got substandard exits — if anyone's above the second floor, they're trapped." |
| Alert (weather) | "The storm's going to hit the Flats harder than the upper tiers. We always catch the runoff. If the drains back up, check the residential blocks first — the basements fill before the street floods." |
| Combat (during null_choir_rising) | "I've faced worse than kids with loudspeakers. They're angry, not evil. Remember that when you're deciding how hard to hit." |
| Rescue (post-rescue debrief) | "You got them out. Good. Now sit down, drink this coffee, and let someone else handle the paperwork for once." |
| Rescue (after a tough call) | "You made the best call you could with the information you had. That's all anyone can do. The guilt you're feeling? That means you care. Don't lose that." |
| Victory (mission complete) | "The café's still standing. The Flats is still breathing. You did good, Lumen. Now go do it again tomorrow. That's the job." |

**Mission Appearances:** awakening_patrol (tutorial — appears in a brief after-action scene at the Flats café), null_choir_rising (provides perspective on faction history), the_long_night (coordination role in Flats evacuation), stormwall (advises on Flats infrastructure vulnerabilities)

---

### ElevenLabs Voice Mapping Summary

| Existing Character | Voice | New Character | Voice |
|---|---|---|---|
| Civic Grid AI | **Aria** | — | — |
| — | — | Sol Vance | **Laura** |
| — | — | Kaelith Vorn | **Roger** |
| Civilian (Panicked) | Sarah | — | — |
| Civilian (Grateful) | Charlie | — | — |
| — | — | Pavla Jezek | **Lily** |
| — | — | Cinder | **Will** |
| — | — | Mira Adani | **Jessica** |
| Emergency Dispatcher | Callum | — | — |
| Null Choir Commander | George | — | — |

**Unused ElevenLabs voices** (reserve for future expansion): Matilda, Charlotte, Alice, Eric, Chris, Brian, Daniel, Bill, River, Liam, Matilda

---

## 4. Asset Needs

### 4A. New 3D Assets for The Flats

Per the FREE-FIRST rule: all assets listed here default to Quaternius CC0 or Kenney CC0. Meshy is only authorized where no CC0 equivalent exists.

| Asset | Count | CC0 Source | Meshy Needed? | Notes |
|---|---|---|---|---|
| Canal water plane / animated material | 1 | Godot shader (built-in) | No | Animated water shader with reflection. No external model needed. |
| Canal bridge arch (cast-iron style) | 2–3 variants | Quaternius Cyberpunk Game Kit — `Platforms/Rail_Long.gltf` can be repurposed as bridge span; Kit has `Sign_1` for arch decorations | No | Repurpose existing rail platforms + add godot material for amber strip lights |
| Factory building (low-rise, corrugated) | 3–5 modular pieces | Quaternius Ultimate Buildings Pack — existing 2-6 story models can be retextured with rust/corrugated material palette | No | Re-texture existing building models. New texture palette only. |
| Factory smokestack (The Needle) | 1 | Quaternius Cyberpunk Game Kit — `Antenna_1.gltf` scaled up 20× forms the base needle; combine with cylinder CSG for stack body | No | Composite build. Needle top needs a custom teal corona ring (material effect, not new mesh). |
| Storm drain grate (3 m circular) | 1 | Kenney Sci-Fi Elements (circular grate) OR Quaternius Sci-Fi modular floor tiles repurposed | No | Place on street mesh as decal / separate mesh. Pattern: concentric rings with meridian compass rose. |
| Canal wall / quayside modular | 4–6 pieces | Quaternius Ultimate Modular Sci-Fi — `Details_Pipes_Long.fbx` + packing crate variants; Kenney City Kit (road curbs, canal walls) | No | Modular wall + pier set. Use existing industrial props for dressing. |
| Warehouse roll-up door | 1–2 | Kenney Architecture Kit (industrial doors); Quaternius Cyberpunk Kit's `Computer_Large.gltf` as control panel | No | Re-texture with rust and Heliostat insignia. |
| Smuggling Dock crane | 1 | Quaternius Cyberpunk Game Kit — `Antenna_1.gltf` modified + CSG boom arm | No | Composite model. Needs custom Syndicate-colored material. |
| Canal boat / barge (generic) | 1–2 | Quaternius Ultimate Spaceships Pack — a small ship (e.g. Striker at reduced scale, industrial paint) can serve as canal barge | No | Re-texture as working canal barge. Remove weapons. |
| Water tower (Flats rooftop) | 2–3 | Kenney City Kit (water towers) OR Quaternius buildings pack roof accessories | No | Simple cylinder + cone. Place on rooftops as silhouette detail. |

**Total new 3D geometry needing purchase or generation:** 0
**Total existing assets needing re-texture or composite build:** ~15–20 items
**Meshy credits required:** 0

### 4B. New Audio Assets

| Asset | Class | Pipeline | Lines / Duration | Notes |
|---|---|---|---|---|
| Canal water ambience loop | Ambience | FAL stable-audio (Open) | 30 s loop | "slow moving canal water ambience, gentle lapping against stone walls, distant industrial hum, no voices" |
| Flats wind-through-alleys ambience | Ambience | FAL stable-audio (Open) | 30 s loop | "wind blowing through narrow alleyways, distant traffic rumble, occasional metal creak, atmospheric" |
| Storm drain water rush SFX | SFX | FAL stable-audio (Open) | 3–5 s | "rushing stormwater through concrete drain, heavy water flow, flooding pressure" |
| Canal splash / rescue water entry SFX | SFX | Kenney CC0 (underwater / splash from `sci-fi-sounds`) | 1–2 s | Free — Kenney CC0 pack `sci-fi-sounds` has splash variants |
| Industrial door / grate open SFX | SFX | Kenney CC0 (`mechanical-sounds`) | 2–3 s | Free — Kenney CC0 `mechanical-sounds` pack |
| Sol Vance — 8 bark lines | Voice | FAL ElevenLabs TTS (Laura) | 8 × 3–6 words | See Section 3 |
| Kaelith Vorn — 8 bark lines | Voice | FAL ElevenLabs TTS (Roger) | 8 × 4–8 words | See Section 3 |
| Pavla Jezek — 8 bark lines | Voice | FAL ElevenLabs TTS (Lily) | 8 × 5–10 words | See Section 3 |
| Cinder — 8 bark lines | Voice | FAL ElevenLabs TTS (Will) | 8 × 4–8 words | See Section 3 |
| Mira Adani — 8 bark lines | Voice | FAL ElevenLabs TTS (Jessica) | 8 × 6–12 words | See Section 3 |
| Flats music variant (lower, industrial, minor-key ambient) | Music | FAL stable-audio-25 | 120 s | Defer — use existing exploration track re-pitched / filtered for The Flats initially |

**Total new audio files:** ~13
**Total FAL credit cost:** ~$2–3 (ambience + voice lines) — all within free tier limits if batched.

---

## 5. Integration Plan

### 5A. Data Files Requiring New Entries

| File | What to Add |
|---|---|
| `data/missions/missions.json` | Add `district` field (string: `"meridian_core"` or `"the_flats"` or `"both"`) to each mission. Update all 12 missions. Add `steps` array to the 8 upgraded missions (see Section 2). Steps schema: `{id: int, title: string, objective: string, target_event_kind: string, success_condition: string, failure_consequence: string, dialogue_beat: string}`. Existing 4 unchanged missions get `steps: []`. |
| `data/events/events.json` | Add 6 new event `kind` entries (they are sub-variants, not full new event archetypes): `scaffolding_trap`, `foundry_disturbance`, `sub_station_dark`, `canal_drone_ambush`, `canal_flood`, `cascade_origin`. Each is a color variant of an existing kind with a Flats-themed display_name. Add new `spawn_positions` for The Flats zone. |
| `data/powers/powers.json` | No changes needed — all required powers already exist (Radiant Beam, Sonic Burst, Aegis Field, Rescue Lift, Orbit Sprint). |
| `assets/audio/audio_manifest.json` | Add entries for all 13 new audio assets (see Section 4B). Add `district` tag to existing and new audio entries. |
| `data/objective_markers.json` | Add marker entries for new event kinds. Add Flats-zone placement entries. |
| `docs/creative/03_faction_roster.md` | Update to mention The Flats as Storm Children / Null Choir territory (already referenced in story bible as "The Shelf" area). Add Kaelith Vorn as a named Syndicate contact. |
| `docs/creative/06_bark_lines.md` | Add bark line metadata tables for the 5 new cast members. |
| `assets/audio/SOURCES.md` | Add new audio source entries for Flats ambience and character barks. |
| `data/manifest/asset_manifest.json` | Add re-textured and composite 3D assets for The Flats. |

### 5B. Schema Extensions

| Extension | Details |
|---|---|
| `mission.district` | New required field on every mission: `"district": "meridian_core"` (downtown existing), `"the_flats"`, or `"both"`. Missions.json schema validator needs updating. |
| `mission.steps` | New optional array (`[]` if single-objective). Each step: `{id: int, title: string, objective: text, target_event_kind: string, success_condition: text, failure_consequence: text, dialogue_beat: text}`. |
| `events.kind` | Add new event kinds with `district` tag for Flats-only spawning. |
| `event_kind.variant_of` | Optional field linking a Flats variant back to its parent event kind (e.g., `canal_flood` variant_of `power_surge`) to simplify spawner logic. |
| `audio_manifest.entry.district` | Optional tag: `"meridian_core"`, `"the_flats"`, or unset for universal audio. |

### 5C. Coder Integration Card — What to Build

The next coder card should implement:

1. **District spawning system:**
   - Load The Flats district geometry on game boot (separate blockout node or toggle).
   - Add Flats-specific event spawn positions to the timed spawner.
   - Gate events by `district` tag — Flats-only events don't spawn in meridian_core and vice versa.

2. **Mission step system:**
   - Parse `steps` array from `missions.json`.
   - Track current step per active mission.
   - Advance step when `success_condition` is met (or handle `failure_consequence`).
   - Update HUD objective text per step.
   - Trigger step-specific audio barks.

3. **Cast voice wiring:**
   - Add 5 new character bark arrays to the audio manifest.
   - Wire bark context selection (idle/alert/combat/rescue/victory) for each new character.
   - Apply `district` tag filtering so Flats-only barks only fire when The Lumen is in The Flats.

4. **Volume / interaction layer:**
   - No new InteractionVolume schemas needed — existing system works for Flats-based events.
   - Add bridge/skyway connections between districts as InteractionVolume triggers that switch district context.

5. **Data validators:**
   - Update `tools/validate_data.py` to check `district` field on missions.
   - Add step validation: step IDs are sequential, target_event_kind resolves to a real kind, success/failure conditions are non-empty.
   - Update `tools/validate_volumes.py` for new objective markers.

### 5D. Implementation Priority

| Order | Workstream | Depends On |
|---|---|---|
| 1 | Add `district` field to missions.json schema and all 12 missions | None |
| 2 | Add Flats event kinds to events.json + spawn positions | None |
| 3 | District spawning system (The Flats blockout in Godot) | 1 |
| 4 | Mission step system (parse steps, advance on success) | 1 |
| 5 | Step arc content (8 missions, 22 steps) | 4 |
| 6 | Audio manifest updates + 5 new cast entries | 4 |
| 7 | Pavla Jezek + Mira Adani bark wiring (P0 characters) | 6 |
| 8 | Sol + Kaelith bark wiring (P1 characters) | 6 |
| 9 | Cinder bark wiring (P2 — appears later in game) | 6 |
| 10 | Data validator updates | 1, 2 |

---

## Appendix A: Existing IP Consistency Check

This brief extends the Aurora Vigil IP without violating the anti-copy policy:

- **No DC/Marvel names** — Sol, Kaelith, Pavla, Cinder, Mira are original.
- **No Metropolis/Smallville** — The Flats is an industrial canal district, original concept.
- **No Superman archetype copying** — Mira Adani is a retired emergency responder, not an alien mentor or all-powerful elder; her value is procedural knowledge, not power.
- **No color copying** — The Flats palette (rust, teal water, amber) avoids red-blue-cape iconography.
- **Factions remain original** — Null Choir stays an anti-aurora activist network; Heliostat stays a corporate energy cartel; Storm Children stay a Shimmer-affected mutual-aid collective.

## Appendix B: Flats Mission Flow — District Context Diagram

```
                    ┌─────────────────────┐
                    │   MERIDIAN CITY      │
                    │   (Downtown Core)    │
                    │   teal-glass towers  │
                    │   gold transit       │
                    └──────────┬──────────┘
                               │
                    [The Climb] │ [Cargo Tram]
                    [pedestrian]│ [funicular]
                               │
                    ┌──────────▼──────────┐
                    │    THE SHELF         │
                    │   (transition tier)  │
                    │   Foundry Quarter    │
                    └──────────┬──────────┘
                               │
                    [The Weir Bridge]
                    [road + pedestrian]
                               │
                    ┌──────────▼──────────┐
                    │    THE FLATS         │
                    │   (canal district)   │
                    │   rust + teal + amber│
                    │   narrow alleys      │
                    │   industrial         │
                    └─────────────────────┘
```

Mission arcs that cross districts (`the_long_night`, `solar_cascade`, `skyway_runaway`) use the transit links as in-game travel corridors. The step system tracks which district the player is in and filters objectives/audio accordingly.
