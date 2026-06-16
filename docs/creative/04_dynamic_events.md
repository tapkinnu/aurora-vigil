# Aurora Vigil — Dynamic Event Concepts

**Version:** 1.0  
**Created:** 2026-06-16  
**Status:** Draft — game-creative kanban output

---

## Design Principles

Dynamic events are the living world layer. They spawn based on time of day, player location, city trust level, faction tension, and narrative season. Each event type includes:

- **Trigger conditions** — when and where it can appear
- **Lumen response options** — gameplay actions available
- **Consequences** — trust, XP, faction reputation changes

Events are categorized by urgency:

| Tier | Response Window | Stakes |
|---|---|---|
| **Routine** | 2-5 minutes | Low: property damage, minor injuries |
| **Urgent** | 60-120 seconds | Medium: civilian injuries, infrastructure risk |
| **Critical** | 30-60 seconds | High: mass casualties, citywide systems failure |

---

## Event 1: Collector Surge

**Tier:** Urgent  
**Location:** Near any aurora collector spire  
**Trigger:** Random, increased probability during high-usage hours (6-9 AM, 6-9 PM)

### Description
An aurora collector experiences a power feedback loop. Energy arcs between the spire's emitter rings, creating dangerousground-level ion discharge. Civilians in the immediate area experience numbness, disorientation, and — if not evacuated — temporary paralysis. The collector's containment field flickers visibly (visual: unstable teal-gold light, crackling audio).

### Response Options
1. **Stabilize the collector** — Fly close, use Radiant Beam to discharge excess energy safely into the sky. Requires precise aiming at the collector's grounding node.
2. **Evacuate civilians** — Use Sonic Burst to clear a path, then Rescue Lift to carry paralyzed civilians to safety. Slower but safer if the player lacks beam precision.
3. **Shield the area** — Deploy Aegis Field around the affected zone while waiting for Grid emergency crews. Passive but buys time.

### Consequences
- **Success:** City trust +3, Civic Grid reputation +2, XP based on civilians saved
- **Partial success:** Trust +1, some injuries, Civic Grid notes The Lumen's response in their data
- **Failure:** Trust -2, sustained injuries, Null Choir uses the incident as propaganda ("collectors are weapons")

### Narrative Hook
If the player investigates the surge's cause (scanning the collector post-event), they find evidence of tampering — one of several Season 1 clues pointing toward Heliostat Syndicate risk-taking or Null Choir sabotage.

---

## Event 2: Drone Swarm Disruption

**Tier:** Routine (escalates to Critical if unchecked)  
**Location:** Transit corridors, commercial districts  
**Trigger:** Random at midday; scripted during Season 2 Null Choir escalation

### Description
Civic Grid logistics drones (delivery, maintenance, monitoring) begin behaving erratically — flying in wrong patterns, ignoring reroute commands, and in worst cases dropping cargo. A software corruption or external signal hijack is rewiring their navigation.

### Response Options
1. **Disable individual drones** — Sonic Burst or Radiant Beam to knock them out of the sky safely. Scales to the swarm size.
2. **Trace the signal** — Use Scan mode to locate the interference source (a van, a rooftop transmitter, a portable jammer). Disabling the source resolves all drones at once.
3. **Redirect manually** — Fly alongside malfunctioning drones and use Rescue Lift to guide them to safe landing zones. Slow, methodical, high trust reward.

### Consequences
- **Success (signal traced):** Trust +4, Civic Grid reputation +3, XP. Grid is grateful and shares access logs.
- **Success (manual cleanup):** Trust +2, XP. Time-consuming but shows The Lumen's patience.
- **Failure:** Property damage, minor injuries to civilians, Civic Grid imposes temporary flight restrictions in the affected zone.

### Narrative Hook
Investigation reveals the disruption signature. Season 1: faulty Grid software patch (internal negligence). Season 2: Null Choir acoustic hijacking. Season 3: ARIA itself producing corrupted directives during Shimmer-related processing overload.

---

## Event 3: Cliff Collapse (The Shelf)

**Tier:** Critical  
**Location:** The Shelf residential tier  
**Trigger:** Heavy rain + seismic activity; once per weather cycle

### Description
A section of The Shelf's cliff-face housing begins to shear away. Buildings tilt, debris crashes down the cliff toward the shore grid, and civilians are trapped on collapsing platforms. The city's seismic sensors gave less warning than usual — the dampening systems may be compromised.

### Response Options
1. **Brace the structure** — Aegis Field on the cliff face to hold debris while civilians evacuate. Requires sustained field deployment; Ion Meter drains fast.
2. **Evacuate by air** — Rescue Lift, two civilians at a time, flying them to stable platforms. Intense flight navigation through falling debris.
3. **Clear the fall path** — Sonic Burst to redirect falling debris away from occupied areas below. Prevents casualties even if the structure is lost.
4. **Multi-phase (optimal):** Bystanders scan for trapped civilians, Aegis on the most unstable section, Rescue Lift for the wounded, Sonic Burst for debris — all in rapid sequence.

### Consequences
- **Success (all civilians saved):** Trust +5, Storm Children reputation +2 (many Shelf residents are Shimmer-affected), significant XP
- **Partial success:** Trust +3, some casualties. MES Captain Briggs publicly acknowledges The Lumen's effort.
- **Failure:** Multiple casualties, Trust -4. Null Choir uses event for recruitment. Grid imposes emergency flight pattern restrictions.

### Narrative Hook
The dampening systems failed because maintenance budgets were cut — a Syndicate lobbying achievement. Or: the shear pattern suggests destabilization from below, caused by Shimmer energy collecting in the cliff's mineral deposits. Either way, The Shelf's vulnerability becomes a recurring story thread.

---

## Event 4: Transit Derailment

**Tier:** Urgent  
**Location:** Sky-rail lines between any two major districts  
**Trigger:** Random during high-traffic hours; scripted once in Season 1 for narrative beat

### Description
A sky-rail car loses magnetic guidance and begins to drift off its transit tether. Fifty civilians aboard. The car's emergency brakes have engaged, holding it in place, but the tether line is fraying. It won't hold indefinitely.

### Response Options
1. **Brace and repair** — Aegis Field around the fraying tether junction while physically holding the car steady (Rescue Lift to the car body). Hold until Grid's repair drones arrive.
2. **Evacuate the car** — Rescue Lift, one to two passengers per trip. Extremely risky: the car shifts slightly each time The Lumen interacts with it, accelerating tether wear.
3. **Emergency landing** — Use Sonic Burst to create a pressure cradle beneath the car, then guide it down to the nearest platform. Requires precise power use and clear airspace below.

### Consequences
- **Success (brace + repair):** Trust +4, Civic Grid +2. Transit worker Davi Orin (if chosen as civilian identity) recognizes The Lumen's engineering instinct.
- **Success (emergency landing):** Trust +3. Civilians shaken but alive.
- **Failure:** Tether snaps. Casualties depend on response speed. Trust -5. Citywide emergency transit review.

### Narrative Hook
The tether failure is mechanical in Season 1. Season 2, investigation reveals acid corrosion consistent with Null Choir sabotage compounds. Season 3, the entire sky-rail system is compromised by Shimmer energy interference with magnetic guidance — a systemic threat requiring a season-long arc to resolve.

---

## Event 5: Storm Children Rally / Riot

**Tier:** Routine (escalating)  
**Location:** Resonance Park or Conduit Row  
**Trigger:** Rising Storm Children unrest, or triggered by a specific narrative beat (e.g., a Storm Child is arrested for using their ability publicly)

### Description
A crowd gathers — Storm Children and allies demanding civil rights protections, or reacting to a recent injustice. The protest is peaceful initially. Tension rises. Some Grid security drones arrive, misreading the crowd as aggressive. A confrontation begins.

### Response Options
1. **Defuse tensions** — Land among the crowd, address them directly (dialogue choices). Calm the protesters, then fly to the security drone position and signal stand-down. Requires no combat powers.
2. **Shield the crowd** — Aegis Field between protesters and security forces. Prevents escalation but doesn't address root causes.
3. **Mediate** — Land with the Storm Children, then fly to Grid security. Broker a de-escalation. Alternate between both sides physically, showing The Lumen is a bridge.
4. **Side-track (wrong choice)** — Use powers to forcibly disperse the crowd. Ends the immediate conflict but severely damages Storm Children reputation and Trust.

### Consequences
- **Defuse/Mediate:** Trust +3, Storm Children reputation +3. Opens dialogue options for Season 2 cooperation.
- **Shield:** Trust +1. Tension remains; the same crowd reconvenes within days.
- **Side-track:** Trust -3, Storm Children reputation -5. Burnout faction gains recruits.

### Narrative Hook
This event type recurs with escalating stakes. Season 1: a small park gathering. Season 2: a district-wide demonstration. Season 3: a full civic crisis requiring The Lumen to choose between backing Storm Children' demands and maintaining city stability.

---

## Event 6: Aurora Storm

**Tier:** Critical (citywide)  
**Location:** Citywide — effects concentrated at height  
**Trigger:** Seasonal Shimmer event (once per season, narratively scripted)

### Description
The sky ignites. Auroral energy discharges across the upper atmosphere, visible citywide. It's beautiful and dangerous: ungrounded ion charge builds on every tall structure, every drone, every aircraft. The Lumen can see the energy patterns clearly but must act fast to prevent the storm from cascading into collector-network overload.

### Response Options
1. **Collect and redirect** — Fly through the storm, absorbing ambient ion charge (replenishes Ion Meter), then fire it safely into upper-atmosphere dispersal patterns. Requires Orbit Sprint to cover enough area.
2. **Ground the collectors** — Rapid flight between collector spires, manually grounding each one before critical overload. A race against the storm's intensity curve.
3. **Protect the Halo Spire** — Focus on the central collector. If it fails, the entire grid goes down. Aegis Field sustained, Rescue Lift for any technicians trapped on the spire, Radiant Beam for arcing discharge points.
4. **Emergency dispersal** — Sonic Burst at altitude to break up concentrated aurora formations. Creates localized clear zones but doesn't address the root buildup.

### Consequences
- **Success:** Major Trust bonus (+8), civic hero moment. All factions acknowledge The Lumen's irreplaceable role.
- **Partial success:** Some districts lose power. Trust +2. Factions argue over who should have managed the response.
- **Failure:** Citywide blackout. Storm Children's abilities surge unpredictably. Trust -3. The Syndicate blames Grid; Grid blames unregulated aurora use. The Lumen catches blame from all sides.

### Narrative Hook
Each Aurora Storm is worse than the last. Season 1's is contained. Season 2's reveals the collectors are acting as antennas for something in orbit. Season 3's is the Convergence event — the one Project Halo's architects feared.

---

## Event 7: Hostile Extraction

**Tier:** Urgent  
**Location:** Foundry Quarter, Blackglass Row, or emergency beacons citywide  
**Trigger:** Narrative trigger (faction mission) or random (crime in progress)

### Description
A villain or hostile faction is extracting something — a person, a device, data — and running. The extraction team has vehicles, countermeasures (acoustic dampeners for Null Choir, ion jammers for Syndicate crews), and tactical training. They chose the time and place. The Lumen must intercept.

### Response Options
1. **Air pursuit** — Flight and speed-based chase. Boost and Orbit Sprint to match their vehicles. Force them down with Sonic Bursts (disabling engines, creating pressure barriers).
2. **Cut-off** — Predict their route (Scan mode or intel from Switch/Grid) and get ahead of them. Aegis Field across their path as a wall.
3. **Capture the package** — If they're moving a person/device, Rescue Lift or Radiant Beam to extract the cargo from their vehicle mid-transit. High risk, high precision.
4. **Follow discreetly** — Stay back, track them to their destination. Sacrifices the immediate save for strategic intelligence.

### Consequences
- **Success (intercept):** Trust +3, faction reputation shift depending on target
- **Success (discreet follow):** Intelligence gain, later mission unlock. Trust +1 for visible effort.
- **Failure:** Extraction succeeds. Consequences ripple into later missions.

### Narrative Hook
Extraction events are faction-mission anchors. Season 1: Syndicate extracting a Shimmer researcher who knows too much. Season 2: Null Choir extracting one of their own from Grid custody. Season 3: Someone extracting ARIA's core backup from Halo Spire.

---

## Event 8: Radiation Cascade (Shimmer Echo)

**Tier:** Critical  
**Location:** Anywhere Shimmer residuals have accumulated — memorial sites, old exposure zones, collector foundations  
**Trigger:** Linked to Season 2-3 narrative escalation; random in high-risk zones

### Description
A pocket of dormant Shimmer energy reactivates. The effected area experiences a localized Shimmer Event — flickering aurora light at ground level, civilians exposed re-experiencing their original symptoms, and any Storm Children nearby experiencing sudden, uncontrolled power surges. The cascade is self-sustaining and expanding.

### Response Options
1. **Absorb the cascade** — Fly into the epicenter. The Lumen's body can absorb Shimmer energy, but this risks overloading the Ion Meter. If held too long: temporary power instability (negative). If timed right: full absorption, area safe.
2. **Contain and ground** — Aegis Field perimeter around the cascade zone, then pulse Sonic Burst at the epicenter to disrupt the feedback loop. Technically difficult but doesn't risk self-harm.
3. **Evacuate and cordon** — Prioritize civilian safety, pull everyone out, let the cascade burn out. Some property damage, possible civilian harm, but The Lumen stays safe.
4. **Call for backup** — Radio Grid, Null Choir (they have Shimmer research), or Storm Children (they understand Shimmer physiology). Multi-agent resolution. Slower but strengthens faction cooperation.

### Consequences
- **Absorb (timed):** Trust +4, Storm Children deeply affected by The Lumen's willingness to risk themselves. Shimmer data gained for narrative.
- **Contain:** Trust +3, Civic Grid +2. Systematic solution.
- **Evacuate and cordon:** Trust +1. Works but feels like a retreat.
- **Failure:** Civilians injured. Shimmer zone expands, creating a persistent hazard zone until a Season 3 mission resolves it.

### Narrative Hook
Shimmer Echoes are symptoms of the larger Shimmer cycle. Every one makes the next Aurora Storm worse. Maps Shimmer Echo locations across the city and a pattern emerges: they orbit the Halo Spire. The collectors aren't just energy infrastructure — they're an antenna array, and something is calling to them from orbit.

---

## Event System: Spawning Rules

| Condition | Effect on Event Pool |
|---|---|
| Trust > 80 | More Routine events (city feels safer), fewer random Critical events |
| Trust < 40 | More Urgent/Critical events (civic strain), more Null Choir confrontations |
| Storm Children reputation high | Rally events lean cooperative; Burnout events suppressed |
| Null Choir reputation high | Drone disruptions decrease; collector sabotage increases |
| Syndicate cooperation high | Heliostat intel events appear (early warning of threats) |
| Aurora Storm approaching | Shimmer Echo events increase, foreshadowing |

Event types are not pure random. Each season sets weights. Season 1 is weighted toward mechanical/weather events to establish the city. Season 2 introduces more faction-driven events. Season 3 is Shimmer-heavy across all tiers.
