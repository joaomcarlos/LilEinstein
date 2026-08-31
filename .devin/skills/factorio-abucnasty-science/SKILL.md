---
name: factorio-abucnasty-science
description: "Reference knowledge from abucnasty's Factorio megabase / ESPM analysis across 13 videos. Use when working on LilEinstein research scoring, infinite-tech caps, per-pack difficulty weights, ESPM targeting, quality science decisions, or any Factorio megabase research-strategy question. Provides the ESPM formula, practical infinite-tech breakpoints, per-pack UPS cost tiers, expert tier rankings, per-pack quality recommendations, and 2.1 meta shifts."
version: "2.0.0"
user-invocable: true
compatibility: Pure knowledge reference — no runtime, network, or env vars required.
metadata: {"hermes":{"tags":["factorio","lileinstein","research","espm","megabase","abucnasty","science-packs"],"category":"game-modding"}}
---

# Factorio abucnasty Science Knowledge

Reference distillation of abucnasty's megabase / ESPM analysis (YouTube:
"What is ESPM? How I define a Megabase"). Use this when tuning
LilEinstein's `model/research_weights.lua`, `model/queue.lua` scoring, or
when reasoning about Factorio 2.0 Space Age research strategy.

## Source

- **Creator**: abucnasty
- **Primary video**: "What is ESPM? How I define a Megabase"
- **Additional videos analyzed** (13 total):
  - "Fin [2.5 Million ESPM Megabase]"
  - "Aquillo & Prom [Road to 2.5 Million ESPM]"
  - "Gleba [Road to 2.5 Million ESPM]"
  - "Nauvis & Vulcanus & Space [Road to 2.5 Million ESPM]"
  - "Factorio Space Age: 4 million SPM Mega Base Tour"
  - "UPS Optimizations: Labs"
  - "Labs Finale (Part 1)"
  - "Hub Redesign & Lab Clocking Experiments"
  - "Which Quality Space Science is best for UPS?"
  - "Quality Science Conclusion: Core Sciences"
  - "FFF-443: Unlimited Throughput"
  - "Gleba Science Monitor"
- **Scope**: Factorio 2.0 + Space Age (base >= 2.0.77), with 2.1前瞻 notes
- **Status in LilEinstein**: Initial ESPM/caps/weights applied in commit
  `7b7b3b1` to `model/research_weights.lua` and `model/queue.lua`.
  Expanded knowledge (v2.0) adds quality recs, 2.1 meta shifts, and
  cross-references to companion skills.

## SPM vs ESPM

- **SPM** (Science Per Minute): raw science-pack production rate, before
  any lab-side multipliers. What your factory physically makes.
- **ESPM** (Effective Science Per Minute): the rate at which research
  actually progresses, after lab drain, module productivity, and
  research-productivity levels. This is the number that determines how
  fast infinite techs climb.

### ESPM Formula (Space Age, biolabs + 4 legendary prod modules)

```
ESPM = raw_SPM * lab_drain_multiplier * (1 + module_productivity + research_prod_level * per_level_bonus)
```

With canonical Space Age endgame values:

| Constant                  | Value | Notes                                            |
|---------------------------|-------|--------------------------------------------------|
| `lab_drain_multiplier`    | 2.0   | 50% drain = 2x output per pack consumed          |
| `module_productivity`     | 1.0   | 4x legendary prod modules = +100%                |
| `research_prod_per_level` | 0.10  | research-productivity: +10% per level            |

Simplified:

```
ESPM = raw_SPM * 2 * (2 + 0.1 * research_prod_level)
```

Worked examples:

| Research productivity level | ESPM multiplier | ESPM at 100k raw SPM |
|-----------------------------|-----------------|----------------------|
| 0                           | 4x              | 400k                 |
| 30                          | 10x             | 1M                   |
| 100                         | 24x             | 2.4M                 |
| 150                         | 34x             | 3.4M                 |

### Megabase milestone

- **1 million ESPM** is the "true megabase" threshold in Space Age.
- At research-productivity L30, this requires ~100k raw SPM.
- At L100, only ~42k raw SPM is needed — research productivity is the
  single highest-ROI infinite tech because it multiplies every pack.

> Runtime note: LilEinstein's runtime must read live API values
> (`force.laboratory_productivity_bonus`,
> `lab_entity.productivity_bonus`,
> `prototype.science_pack_drain_rate_percent`) rather than these
> constants. The constants in `research_weights.lua` are reference only.

## Practical infinite-tech caps

Infinite techs have exponential cost curves. Most hit a practical wall
where continued investment is futile (research time measured in months,
years, or "longer than human lifespans"). Only two are practically
unbounded.

### Practically unbounded (no useful cap)

| Tech                      | Why it stays worth it                          |
|---------------------------|------------------------------------------------|
| `research-productivity`   | Multiplies ESPM itself; ROI compounds. Practical limit ~L100-150 only because cost eventually outpaces gain, but it remains the highest-priority infinite. |
| `mining-productivity`     | Flat cost scaling, cheap UPS, buffs all ore/oil. Effectively no wall. |

### Practical caps (abucnasty breakpoints)

These are the levels beyond which diminishing returns make further
investment impractical. Values are encoded in
`M.research_caps` in `model/research_weights.lua`.

| Tech                              | Cap | Rationale                                                          |
|-----------------------------------|-----|--------------------------------------------------------------------|
| `physical-projectile-damage`      | 33  | L33: one-shot medium promethium asteroids with red ammo. Beyond = exponential wall. |
| `stronger-explosives`             | 31  | L31: one-shot big promethium asteroids. Beyond = exponential wall. |
| `railgun-damage`                  | 30  | L30: months of research; beyond is "years" territory.              |
| `railgun-shooting-speed`          | 12  | Bug fix capped it at 12; most aggressive exponential. (Fixed in code from 20 to 12 per "Fin" video) |
| `worker-robot-speed`              | 40  | Exponential cost wall; millions of years by L60. **2.1 note**: landing-pad throughput changes may make worker-robot-speed bases obsolete, further lowering priority. |
| `laser-weapons-damage`            | 10  | Rarely useful — laser beam cost exceeds ammo cost.                 |
| `electric-weapons-damage`         | 20  | Diminishing returns on Gleba defense.                              |

### Recipe-based productivity caps (game mechanic, not abucnasty)

These are capped by Factorio's 300% productivity limit (4 legendary prod
modules = +100%, so level 20 supplies the remaining 200%). Listed here
for completeness since they sit in the same `research_caps` table:

| Tech                                    | Cap |
|-----------------------------------------|-----|
| `processing-unit-productivity`          | 25  |
| `rocket-part-productivity`              | 30  |
| `low-density-structure-productivity`    | 25  |
| `steel-plate-productivity`             | 25  |
| `plastic-bar-productivity`             | 30  |
| `rocket-fuel-productivity`             | 30  |
| `scrap-recycling-productivity`         | 30  |
| `asteroid-productivity`                | 30  |
| `artillery-shell-shooting-speed`       | 10  |

## Per-pack difficulty / UPS cost

Different science packs have vastly different real production cost in
UPS, logistics, and complexity. Ingredient count alone does not capture
this — an 8-pack tech with promethium is genuinely ~5x harder than a
4-pack Nauvis tech, not just 2x.

Values encoded in `M.pack_difficulty` in `model/research_weights.lua`,
used by `queue.score_tech_detailed` as
`total_cost = cost * num_ingredients * avg_pack_difficulty`.

| Science pack                    | Difficulty | Notes                                              |
|---------------------------------|------------|----------------------------------------------------|
| `automation-science-pack`       | 1.0        | Nauvis, trivial                                    |
| `logistic-science-pack`         | 1.0        | Nauvis, trivial                                    |
| `military-science-pack`         | 1.0        | Nauvis, cheap                                      |
| `chemical-science-pack`         | 1.2        | Nauvis, oil processing overhead                    |
| `production-science-pack`       | 1.5        | Nauvis, complex chain                              |
| `utility-science-pack`          | 1.5        | Nauvis, complex chain                              |
| `space-science-pack`            | 2.0        | Orbit, rocket launch overhead                      |
| `agricultural-science-pack`     | 3.0        | Gleba, spoilage mechanics, UPS-heavy               |
| `electromagnetic-science-pack`  | 2.5        | Fulgora, scrap recycling chains                    |
| `metallurgic-science-pack`      | 2.5        | Vulcanus, foundry + casting chains                 |
| `cryogenic-science-pack`        | 3.0        | Aquilo, extreme cold, cryo plant                   |
| `promethium-science-pack`       | 5.0        | Solar system edge, most expensive UPS per pack     |

## Expert tier rankings for infinite techs

These inform the weight values in `M.research_weights`. Higher weight =
the autopilot prioritises the tech more.

| Tier | Tech                              | Weight | Reasoning                                                |
|------|-----------------------------------|--------|----------------------------------------------------------|
| S    | `research-productivity`           | 20     | Infinite, no 300% cap on research output; ESPM multiplier |
| S    | `mining-productivity`             | 12     | Infinite, buffs all ore/oil; flat cost, cheap UPS         |
| S    | `transport-belt-capacity`         | 10     | Strong but finite (stack size up to 4)                    |
| S    | `processing-unit-productivity`    | 9      | High-value finite productivity                            |
| A    | `rocket-part-productivity`        | 8      | Directly reduces rocket cost; high late-game value        |
| A    | `low-density-structure-productivity` | 7   |                                                           |
| A    | `steel-plate-productivity`        | 7      |                                                           |
| A    | `plastic-bar-productivity`        | 6      |                                                           |
| A    | `rocket-fuel-productivity`        | 6      |                                                           |
| A    | `asteroid-productivity`           | 6      | Infinite but recipe-based; huge for late asteroid chains |
| A    | `scrap-recycling-productivity`    | 6      | Strong if leaning on recycling loops                      |
| B    | `worker-robot-speed`              | 5      | Infinite but exponential cost wall; practical limit ~40   |
| B    | `physical-projectile-damage`      | 5      | Key breakpoints: L13, L18, L33 (one-shot promethium)      |
| B    | `stronger-explosives`             | 5      | Key breakpoint: L31 (one-shot big promethium asteroids)   |
| B    | `railgun-damage`                  | 4      | Useful to L20-30; years territory beyond                  |
| C    | `electric-weapons-damage`         | 3      |                                                           |
| C    | `refined-flammables`              | 3      | Strong on Gleba                                           |
| C    | `laser-weapons-damage`            | 1      | Rarely used; beam cost exceeds ammo cost                  |
| D    | `health`                          | -1     |                                                           |
| D    | `follower-robot-count`            | -10    |                                                           |
| Neg  | `artillery-shell-shooting-speed`  | -5     | Finite levels; past that useless                          |
| Neg  | `artillery-shell-range`           | -3     |                                                           |
| Neg  | `artillery-shell-damage`          | -3     |                                                           |
| Neg  | `railgun-shooting-speed`          | -2     | Most aggressive exponential; impractical beyond ~20        |

## How this maps into LilEinstein

| Knowledge             | LilEinstein location                                  |
|-----------------------|-------------------------------------------------------|
| ESPM formula          | `M.espm_constants`, `M.espm_multiplier` (reference)   |
| Practical caps        | `M.research_caps`                                     |
| Per-pack difficulty   | `M.pack_difficulty` (consumed in `queue.score_tech_detailed`) |
| Tier rankings         | `M.research_weights`                                  |

## Per-pack quality recommendations

From "Which Quality Space Science is best for UPS?" and "Quality Science
Conclusion: Core Sciences". Quality affects how many packs labs consume
(higher quality = fewer packs needed = fewer inserter swings = better
UPS), but also affects production cost (upcycling, asteroid collection).

| Pack                        | Recommended quality | Reasoning                                              |
|-----------------------------|---------------------|--------------------------------------------------------|
| `space-science-pack`        | **Rare (Q3)**       | Best UPS balance: 1/3 the bot/inserter activity of Q1, far less upcycling than Q5. Q2 and Q4 nearly identical. |
| `automation-science-pack`   | Q1 or Q2 (either)   | <1% UPS difference at megabase scale. Q1 = simpler, Q2 = fewer inserters. |
| `logistic-science-pack`     | Q1 or Q2 (either)   | Same as automation.                                    |
| `chemical-science-pack`     | Q1 or Q2 (either)   | Same as automation.                                    |
| `production-science-pack`   | Q2 (uncommon)       | Recommended for megabase; Q2 halves inserter activity. |
| `utility-science-pack`      | Q2 (uncommon)       | Same as production.                                    |
| `military-science-pack`     | Q1 or Q2 (either)   | Low volume; quality doesn't matter.                    |
| `agricultural-science-pack` | **Q1 (common)**     | Spoilage management makes quality impractical.         |
| `electromagnetic-science-pack` | **Q2 (uncommon)** | Recommended for Fulgora.                             |
| `metallurgic-science-pack`  | Q1 or Q2            | "Still a question" per abucnasty.                      |
| `cryogenic-science-pack`    | **Q2 (uncommon)**   | Recommended for Aquilo.                                |
| `promethium-science-pack`   | **Q1 (common)**     | Always common — spoilage/freshness + ship logistics.   |

### Quality throughput multipliers (packs needed vs Q1)

| Quality | Multiplier | Notes                                              |
|---------|------------|----------------------------------------------------|
| Q1 (common)    | 1x  | Baseline                                           |
| Q2 (uncommon)  | 2x  | Half the packs, half the inserter swings           |
| Q3 (rare)      | 3x  | 1/3 the packs (space science sweet spot)           |
| Q5 (legendary) | 6x  | 1/6 the packs but extreme upcycling cost (space)   |

### Pollution impact of quality (core sciences)

- Q2 base: ~26,000 pollution/min
- Q1 red+green: ~37,000/min
- Q1 red+green+blue: ~44,000/min (almost 2x Q2)
- If LilEinstein models pollution, Q1 core packs should get a small
  pollution penalty on Nauvis.

## Research productivity: practical stop point

From the 4M SPM tour: abucnasty stopped research-productivity at **L75-76**,
saying "I've stopped. I very rarely get Promethium anymore" and "it's
not a fun way to play." The tech remains the highest-ROI infinite in
principle, but at L75+ the Promethium consumption for each level becomes
prohibitively expensive in rocket costs. Consider this a soft cap for
scoring purposes — the autopilot should not endlessly prioritize
research-productivity past ~L75 if other infinite techs are available.

## Factorio 2.1 meta shifts (from FFF-443 analysis)

The 2.1 update ("Unlimited Throughput") changes research strategy:

- **Worker-robot-speed de-prioritized**: New landing-pad/cargo-bay
  throughput removes the bot bottleneck for hub unloading. Worker-robot-
  speed megabases may become obsolete. Consider lowering its weight from
  5 to 3 or lower in 2.1.
- **Mining productivity and research productivity remain the meta
  infinite techs** — they are not affected by the throughput changes.
- **Most other infinite techs remain capped at 300% productivity** by
  the game's machine productivity limit.
- See the companion skill `factorio-fff443-research-control` for full
  2.1 circuit-lab mechanics.

## Companion skills

This skill is the research-scoring reference. Related knowledge:

- `factorio-abucnasty-lab-design` — lab clocking, inserter patterns,
  beacon layouts, buffer thresholds, UPS benchmarks
- `factorio-abucnasty-megabase-logistics` — planet-specific strategy,
  spoilage management, ship design, quality per pack, production ratios
- `factorio-fff443-research-control` — Factorio 2.1 circuit lab control
  (set research, read research cost), landing pad throughput, red/green
  wire split

## When to revisit

- If abucnasty publishes updated analysis (new video, patch changes
  balance), re-derive the breakpoint table and update `research_caps` /
  `pack_difficulty` / `research_weights` together.
- If Factorio changes the 300% productivity cap, recipe-based caps in
  `research_caps` need recomputation (4 legendary prod modules = +100%,
  so cap = 20 + recipe-specific slack).
- If a new science pack is added (modded or expansion), add a
  `pack_difficulty` entry before scoring techs that consume it, or
  `queue.score_tech_detailed` will treat the unknown pack as difficulty
  0 and under-cost the tech.

## Attribution

All quantitative values here are derived from abucnasty's published
analysis. When these values appear in LilEinstein source, the file
headers and inline comments cite the source. Do not strip those
citations when editing `research_weights.lua`.
