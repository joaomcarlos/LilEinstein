---
name: factorio-abucnasty-megabase-logistics
description: "Planet-specific megabase strategy, spoilage management, ship design, production ratios, and logistics decisions from abucnasty's megabase tour videos. Use when working on LilEinstein's per-planet science supply forecasting, spoilage modeling, ship scheduling, or any cross-planet logistics question. Covers Gleba spoilage throttling, Aquilo botless design, Promethium ship sizing, Vulcanus mining breakpoints, quality per pack, and buffer thresholds."
version: "1.0.0"
user-invocable: true
compatibility: Pure knowledge reference — no runtime, network, or env vars required.
metadata: {"hermes":{"tags":["factorio","lileinstein","megabase","logistics","gleba","aquilo","promethium","vulcanus","abucnasty"],"category":"game-modding"}}
---

# Factorio abucnasty Megabase Logistics Knowledge

Reference distillation of abucnasty's megabase tour and planet-strategy
videos. Use this when working on LilEinstein's per-planet supply
forecasting, spoilage modeling, ship scheduling, or cross-planet
logistics.

## Source

- **Creator**: abucnasty
- **Videos analyzed** (5):
  - "Fin [2.5 Million ESPM Megabase]"
  - "Aquillo & Prom [Road to 2.5 Million ESPM]"
  - "Gleba [Road to 2.5 Million ESPM]"
  - "Nauvis & Vulcanus & Space [Road to 2.5 Million ESPM]"
  - "Factorio Space Age: 4 million SPM Mega Base Tour"
- **Scope**: Factorio 2.0 + Space Age (base >= 2.0.77)

## ESPM/SPM targets achieved

| Base | Target | Achieved | UPS | Notes |
|------|--------|----------|-----|-------|
| 2.5M ESPM (Road series) | 2.5M ESPM | ~2.6M ESPM, ~115k SPM | ~90 UPS | Running all sciences for research productivity |
| 4M SPM (Tour) | 4M SPM | ~4.0-4.4M SPM | 60 FPS/UPS | 7800X3D; not optimized for research productivity |
| Normal (60s) science | ~5M SPM | — | — | Research productivity runs at half this speed (120s research) |

### Headroom by research type (from "Fin" video)

| Research | UPS | Scale factor |
|----------|-----|-------------|
| Mining productivity | 257 | 4.3x |
| Physical projectile damage | 241 | 4.0x |
| Artillery | 210 | 3.5x |
| Worker robot speed | 176 | 2.93x |
| Research productivity | 104 | 1.7x |

## Research priority decisions

- **Optimize for the seven base sciences, not just research productivity.**
  The 4M base is "intentionally designed to be optimal for running every
  seven base science" — physical projectile damage, laser/energy weapon
  damage, etc.
- **Worker robot speed is "probably the best thing you can be researching
  at any point in time"** (pre-2.1; see 2.1 meta shift in companion skill).
- **Mining productivity is grinded first** to unlock other planets and
  make Vulcanus tungsten viable. He uses an auto-research mod for this.
- **Physical projectile damage is prioritized for Promethium asteroid
  defense** — one level away from two-shotting very large Promethium
  asteroids.
- **Research productivity is deliberately run at half speed** because
  it's a 120-second research (all others are 60s), so consumption is
  doubled. The base turns off half the lanes rather than building double
  the labs.

## Infinite tech levels achieved

| Tech | Level reached | Notes |
|------|---------------|-------|
| Mining productivity | ~24,000 (old base ~20,111) | Magic breakpoint: **26,658** for clean 240 Q2 tungsten/sec with no speed beacons |
| Research productivity | ~75-76, then stopped | "Not fun"; Promethium rocket cost prohibitive at this level |
| Worker robot speed | High (120-176 UPS range) | Best general-purpose infinite pre-2.1 |
| Physical projectile damage | Near L33 | Close to two-shot breakpoint for large Promethium asteroids |
| Railgun shooting speed | Capped at **12** by bug fix | "Highest you have to realistically research" |

## Planet-specific strategy

### Gleba (agriculture / spoilage)

- **Spoilage is the biggest problem**: was making ~114,000 spoilage/min
  with 730 inserters just to remove spoilage.
- **Solution**: dump agriculture science into space while ship velocity
  <300 km/s for 860 ticks, then resume. Keeps freshness high, eliminates
  700-inserter spoilage army.
- **Check for spoilage only every 1,800 ticks (~30 seconds)** with a
  short pulse.
- **Iron bacteria recipe**: makes up to 645 spoilage/sec.
- **Freshness targets**: >=90% in labs, ~97% produced on Gleba.
- **Trains on Gleba**: abucnasty wants trains "because I love trains",
  not because it's UPS optimal.

### Gleba Science Monitor (monitoring strategy)

- **A single normal-quality lab on Gleba acts as the science sensor.**
  Consumes 147 packs/hour (~2 SPM). Fast inserter with stack size 1
  reads hand contents.
- **Recipe switching triggered at chest count <16 per science.**
- **One red-wire signal per science** is broadcast via radar network.
- **Yumako network demand levels**:
  - Idle: 1.5k trigger -> pulse 6,000
  - Promethium active: 24,000
  - Full agriculture active: 48,000
- **Agriculture-science request on Nauvis**: 5,000 idle vs 245,000 active
  (target: 5,000,000)
- **Production rate**: 70,000/min agriculture science when constantly
  running.
- **Ramp-up time**: ~5 minutes to almost full production after enabling.
- **Pentapod eggs expire after ~10 minutes** if held in buffers.
- **Throttling saves UPS**: 170 -> 200 UPS, pollution 25k -> 13k/min.
- **4 ships** deliver agriculture science for 60-second research at full
  speed.

### Aquilo (cryogenic / botless)

- **Bots on Aquilo have 5x energy consumption** = shorter range, more
  charging. Moved to **completely botless** science block.
- **"Ice platform" recycling** instead of straight ice recycling gives
  ~30% UPS improvement.
- **Q2 cryogenic science blocks**: target 40 uncommon science/sec, shared
  clock at 240/sec.
- **Quantum processor blade**: 11 plants produce 110/sec, consuming 80
  lithium plates/sec.
- **Quality recommendation**: Q2 for Aquilo science.

### Promethium (space / solar system edge)

- **The global bottleneck** for 2.5M/4M bases. Old: 32,000 packs/min;
  upgraded to 115,200 packs/min; still limiting.
- **6 small "runner" ships** spaced 6 minutes apart, carrying 776k packs
  per trip. Buffer only 2.0-2.5M packs.
- **Ship design mistake**: six tiny runners waste UPS from side
  asteroids. Would prefer **2 ships, 3x as wide**.
- **Directly belting only 4 Promethium pack lanes** caps at 20,000
  packs/min.
- **Large Promethium asteroids have 100% physical resistance** — rare
  laser turrets + legendary gun turrets for mixed coverage.
- **Quality recommendation**: always Q1 (common) — spoilage/freshness +
  ship logistics make quality impractical.

### Vulcanus (lava / tungsten)

- **Mining productivity breakpoint**: 26,658 for clean 240 Q2 tungsten/sec
  with no speed beacons. Below this, speed beacons needed on miners.
- **Foundries**: 48/sec x 5 = 240/sec.
- **Stone voiding**: stack inserter dumping into lava does 800 stone/swing.
- **Efficiency modules** used not for pollution but to reduce
  distribution efficiency of beacons.
- **Mixes speed + efficiency modules** until mining productivity is high
  enough to remove speed.
- **Old build had absurd number of rocket silos** launching all at once;
  new design is much smaller, belting rocket materials.

### Nauvis (hub / multi-science)

- **Six sciences produced here.** Master radar/circuit network detects
  which science is active and **turns off half the lanes** when research
  productivity is running.
- **Promethium request buffer**: when Promethium science drops below
  10,000, emit a barrel request.
- **Transition to research productivity** creates a ~2-minute dip in
  agricultural science freshness — "a nothing burger" over a 90-hour run.
- **Four extra labs** absorb dumped science after a transition; buffer
  takes ~20 minutes to clear.
- **Isolated bot networks**: ~200 bots for calcite, ~1,000 total during
  research productivity.

## Module / quality decisions

- **Default science quality in 4M base is Q2 (uncommon).**
- **Quality modules over speed** where possible. ~24.8% quality chance
  for ~25% uncommon ore.
- **Mining modules by productivity threshold**: ~1,000 viable; 2,000-
  3,000 can drop speed modules and use efficiency + quality.
- **Productivity module balancing**: in Promethium upcycler, does NOT
  use max productivity (creates too much carbon). Uses one productivity
  module for back pressure, voids excess.
- **Turret quality on Promethium ships**: rare laser + legendary gun
  turrets for overlapping range.

### Quality per pack summary

| Pack | Quality | Source |
|------|---------|--------|
| Space science | **Q3 (rare)** | Best UPS balance |
| Aquilo (cryogenic) | **Q2 (uncommon)** | Recommended |
| Fulgora (electromagnetic) | **Q2 (uncommon)** | Recommended |
| Gleba (agricultural) | **Q1 (common)** | Spoilage management |
| Promethium | **Q1 (common)** | Ship logistics + spoilage |
| Red/green/blue | Q1 or Q2 | <1% difference |
| Vulcanus (metallurgic) | Q1 or Q2 | "Still a question" |

## Key quantitative breakpoints

| Value | Meaning |
|-------|---------|
| 16 belts of science | Total target (8 for uncommon, 640/sec for legendary) |
| 240 items/sec | Recurring "full belt" design target |
| 48/sec x 5 = 240/sec | Vulcanus foundries |
| 110/sec quantum processors | Per 11-plant Aquilo blade (80 lithium/sec) |
| 40 uncommon science/sec | Per Aquilo block (shared 240/sec cryogenic clock) |
| 115,200 packs/min | Promethium capacity (up from 32,000) |
| 2-2.5M pack buffer | Promethium with 6 ships, 6-min spacing |
| 26,658 mining productivity | Clean 240 Q2 tungsten/sec, no speed beacons |
| 800 hp large asteroid | Two-shot breakpoint (needs >400 effective physical damage) |
| 90% freshness in labs | Gleba target |
| 97% freshness produced | Gleba production target |
| 120s vs 60s | Research productivity is 2x consumption |
| 5,000 idle / 245,000 active | Agriculture science buffer on Nauvis |
| 70,000/min | Agriculture science production at full speed |
| ~5 min | Ramp-up to full production after enabling |
| ~10 min | Pentapod egg expiration timer |
| 4 ships | Delivering agriculture science for 60s research |

## Logistics decisions

- **Belts direct-feed science into labs for UPS; avoid bots where possible.**
  On Nauvis "everything is belted in."
- **Rocket silos used as giant chests/buffers** — one inserter pulls 120
  items/sec from a silo, faster than belt offloading.
- **Aquilo redesign cut bot usage ~10x** (robo energy 150 -> 15) by going
  botless.
- **Nauvis hub uses isolated bot networks** for calcite and side inputs.
- **Trains**: 4M base has "no trains really except for Gleba." Fulgora
  uses train voiding design (~11% UPS improvement).
- **Sushi belts disliked; dedicated belts preferred.** Single dedicated
  belt per item with back-pressure latches.

## Lessons learned and mistakes

1. **Don't let agriculture science rot on Gleba** — created 223,000/min
   spoilage removal waves. Solution: constant small production + dump to
   space.
2. **Lasers for transport defense were a UPS mistake** — switched to red
   ammo / physical damage turrets.
3. **Research productivity base design is limiting** — "if I ever scale
   up, I'm going to have to redesign it again. I've redesigned the hub
   so many times."
4. **Promethium ship size was wrong** — six tiny runners waste UPS on
   side asteroids. Would make ships ~3x wider and use 2 ships.
5. **Old 13-beaconed labs and simple clocking cost UPS** vs 16-beaconed,
   properly clocked labs.
6. **Mining productivity should be auto-queued** — "I have better things
   to do with my life" than click 8,000 times.
7. **Quality science for Aquilo/Fulgora should have been Q2 from the
   start**; Gleba/Promethium should stay common.

## How this maps into LilEinstein

| Knowledge | LilEinstein relevance |
|-----------|----------------------|
| Per-planet quality recommendations | Supply forecasting should scale demand by quality tier |
| Spoilage thresholds (16-pack, 30s check) | Gleba supply forecasting and spoilage modeling |
| Buffer thresholds (5k idle / 245k active ag science) | Lab-cluster scheduling thresholds |
| Ramp-up latency (~5 min Gleba, ~10 min eggs) | Supply forecast should include stabilization time |
| Ship sizing (2 wide > 6 small) | Promethium supply forecasting |
| Mining productivity breakpoint (26,658) | Tech scoring for mining-productivity priority |
| Research productivity 120s = 2x consumption | Scoring should weight research-prod as 2x cost |
| Per-planet production rates | Supply forecasting calibration |
| Pollution impact of quality (Q1 = 2x pollution) | If pollution is modeled, quality affects scoring |

## Companion skills

- `factorio-abucnasty-science` — ESPM formula, practical caps, tier
  rankings, per-pack difficulty weights
- `factorio-abucnasty-lab-design` — lab clocking, inserter patterns,
  beacon layouts, UPS benchmarks
- `factorio-fff443-research-control` — Factorio 2.1 circuit lab control

## Attribution

All quantitative values are derived from abucnasty's published megabase
tour videos. When referencing these in LilEinstein source, cite the
source videos.
