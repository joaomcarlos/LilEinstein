---
name: factorio-abucnasty-lab-design
description: "Lab clocking, inserter patterns, beacon layouts, and UPS benchmarks from abucnasty's lab optimization videos. Use when working on LilEinstein's lab-cluster scheduling, lab supply forecasting, inserter timing logic, or any lab-throughput optimization question. Covers 16-beacon layouts, stack-16 inserter clocking, lead-lab universal clock, desynced/staggered firing, agriculture separate clock, quality-in-labs UPS impact, and buffer thresholds."
version: "1.0.0"
user-invocable: true
compatibility: Pure knowledge reference — no runtime, network, or env vars required.
metadata: {"hermes":{"tags":["factorio","lileinstein","labs","ups","clocking","inserters","beacons","abucnasty"],"category":"game-modding"}}
---

# Factorio abucnasty Lab Design Knowledge

Reference distillation of abucnasty's lab optimization videos. Use this
when working on LilEinstein's lab-cluster scheduling, supply forecasting,
or any lab-throughput question.

## Source

- **Creator**: abucnasty
- **Videos analyzed** (3):
  - "UPS Optimizations: Labs"
  - "Labs Finale (Part 1)"
  - "Hub Redesign & Lab Clocking Experiments"
- **Scope**: Factorio 2.0 + Space Age (base >= 2.0.77)

## Lab layout

- **16-beacon design** is the target. Older hub had 13 beacons; the
  redesign aims for 16 beacons around each lab.
- **Biolabs are NOT used in the UPS lab array.** The speaker only
  mentions having surplus biolab production capacity for crafting.
  Standard labs are the research array.
- **Back-fed science from the rear** is chosen for easier belt routing,
  though front-feeding is slightly more UPS-optimal for inserter timing.
- **Cluster is built around paired inserter groups.** 32 inserter groups
  arranged in chunks of two, labeled A-P. Two inserters per lab share a
  letter and fire together.
- **Benchmark array**: 4,096 labs in 16 columns x 92 rows, producing
  ~20 million science packs/min.
- **Live block sizing**: ~65 labs ~= 240 science/sec per lane. A small
  number of "extra" labs are added to intentionally under-feed the belt
  and maintain back pressure (e.g., 32x8 + 3 = 259 labs).

## Lab clocking methods

| Method | How it works | Pros / Cons |
|--------|-------------|-------------|
| **Wake-list / drain detection** | Inserters activate when science count drops below lab's auto-insert threshold. | Simple; causes desync on research switches, especially breaks for research-productivity (threshold 5 vs 9). |
| **Simple global clock** | Constant timer (e.g., 1 tick every 60 ticks; double to 120 for Promethium). | Easy, ~20% UPS win over wake-list; still fires unused inserters, can't adapt per science. |
| **Lead / follower** | Inserter reads its own hand, sends signal to enable next inserter. | Cuts unused activity; 2-4 tick propagation delay, can oscillate. |
| **Lead-lab universal clock** | Single "lead lab" with stack size 4 is monitored. Hand contents sampled into memory cell, normalized per quality, generates explicit clocks and staggered activation pulses. | Handles all quality mixes and Promethium; eliminates many combinators; complex to build. |
| **Desynced / staggered clock** | 32 inserter groups fire in a wave with A-P offsets. Normal science ~259 ticks, agriculture ~128 ticks, 4-tick pulse for agri, ~20-tick pulse for main sciences. | **Best measured UPS**; flattens max update time vs synchronous pulses. |
| **Agriculture-only clock** | Separate clock for agriculture science; 4 ticks on / 4 ticks off, staggered by 8 ticks. | Majorly improves explosives/agriculture cases (agriculture consumed at ~2x cadence). |

### Key clocking numbers

- Normal research insertion trigger: **9** packs
- Research productivity insertion trigger: **5** packs (different limit
  causes stack inserter desync if not actively resynchronized)
- Lab hard capacity: **25** (9 + 16 from a stack inserter)
- Stack size dropped to **12 or 4** temporarily during transitions to
  resynchronize all labs
- Agriculture clock: 4 ticks on / 4 ticks off, staggered by 8 ticks
- Main science clock: ~20-tick pulse, ~259-tick period (normal), ~128-tick
  period (agriculture)
- Spoilage check: once every **30 minutes** (~24 ticks active)

## Inserter optimization

- **Use stack inserters, stack size 16** — the ideal for UPS. Bulk
  inserters are a fallback.
- A stack inserter needs at least a **20-tick enable window** on a belt
  (4 ticks from a direct chest) to reliably pick up 16 items.
- **Lead lab uses stack size 4** to increase sampling resolution and
  detect science changes faster.
- **Stagger offsets reduce spikes**: 6-tick offsets between 32 inserter
  pairs. Synchronous firing produced ~38ms max update time; desync drops
  it to about a third.
- **Setting inserter filters dynamically is worse for UPS** than using
  fixed, pre-configured filters.
- **Bulk inserters are more forgiving** for research productivity and
  off-by-one cases. Properly clocked stack-16 still wins overall.

## Science pack delivery to labs

- **Nauvis science**: 12 lanes with priority split to first labs, using
  double-facing split turbo and splitters on red belts. Back-belt fed.
- **Space science**: delivered by cargo wagons (240 items/sec, acts as
  buffer/void point for spoilage).
- **Agriculture science**: requester chests feed first 2-3 labs to
  compensate for freshness loss along the belt (~6% loss per long belt
  means ~3 labs miss out).
- **Promethium/agriculture voiding**: dedicated deletion lanes. Spoilage
  goes to heating tower; agriculture science loops to a deletion point.

## UPS benchmarks (4,096 labs, Q1 baseline)

| Research | Wake-list UPS | Best clocked UPS | Q2 improvement |
|----------|---------------|------------------|----------------|
| Steel productivity | 504 | +60% (desync stack) | ~2x UPS |
| Worker robot speed | — | +67% (desync Q1) | +150% (Q2) |
| Research productivity | 268 | +60% (desync) | +100% (Q2) |
| Explosives/agriculture | — | +60% over wake-list | Smaller (2x cadence) |

- Simple bulk-inserter clock: ~20% UPS improvement
- Turning off unused inserters: additional ~10%
- Q2 in labs: research prod ~11% better, mining prod ~20% better, bot
  speed ~34% better, lower standard deviation
- Synchronous vs desynced: synchronous ~38ms max update; desynced ~1/3
  of that

## Quality in labs

- **Run Q2 (uncommon) science in labs for UPS.** Q2 roughly halves
  inserter active time and lab updates, especially for bot speed and
  mining productivity.
- **Quality clock multipliers**: common x1, rare x3, legendary x6. Clock
  periods are scaled accordingly.
- **Keep Promethium and agriculture science common (Q1)** — spoilage/
  freshness management is different. Q2 benchmarks explicitly excluded
  these two.
- **Mixed quality is allowed.** Follower inserters can be configured per
  belt; the controller normalizes around the lead lab.

## Buffer thresholds

| Threshold | Value | Context |
|-----------|-------|---------|
| Inserter swing trigger | 1 remaining pack | Ideal on-demand trigger |
| Normal research insertion limit | 9 packs | Lab auto-insert threshold |
| Research productivity insertion limit | 5 packs | Different limit causes desync |
| Lab hard capacity | 25 packs | 9 + 16 from stack inserter |
| Overflow chest trigger | >24 per type | Remove excess science |
| Full-row overflow | 2,000 | Based on 200-slot chest x ~10 rows |
| Agriculture overflow (logistics) | >150,000 for 20 min | Global void signal |
| Spoilage check interval | 30 minutes | ~24 ticks active per check |
| Saturation strategy | Full belts + labs, then enable once | Keeps progress bars synchronized |

## Bottleneck analysis

- **The lab UPS bottleneck is the inserters, not the labs themselves.**
  This is why Q2 and proper clocking give such large gains.
- **Off-by-one insertion-limit changes** between normal research (9) and
  research productivity (5) cause stack inserters to oscillate and
  desync if not actively resynchronized.
- **Agriculture science is the hardest case**: faster consumption rate +
  freshness decay along belts. Agriculture control is a source of
  remaining performance loss.
- **Belt freshness loss**: 373 tiles of belt loses ~1.37% freshness,
  reducing effective throughput from ~120/sec to ~109/sec for a half lane.
- **Synchronous inserter spikes and large circuit networks** hurt UPS;
  desync and isolated per-science wires help.

## Lab consumption rate

- ~3.704 science packs/sec per lab (from rate calculator)
- Target 240 science/sec ~= 65 labs per lane
- Research productivity is a **120-second research** (vs 60s for all
  others), so consumption is effectively doubled when not on research
  productivity. The base runs at half speed during research productivity
  rather than building double the labs.

## How this maps into LilEinstein

| Knowledge | LilEinstein relevance |
|-----------|----------------------|
| Insertion thresholds (9 normal, 5 research prod) | Lab supply forecasting should account for different consumption rates |
| Research productivity 120s vs 60s | Scoring should weight research-productivity as 2x consumption cost |
| Agriculture 2x cadence | Supply forecasting for agriculture science needs 2x demand multiplier |
| Buffer thresholds | Lab-cluster scheduling can use these as supply-adequate thresholds |
| Quality multipliers (x1/x2/x3/x6) | Supply forecasting should scale demand by quality tier |
| Freshness decay along belts | Long belt runs to labs reduce effective agriculture science throughput |

## Attribution

All quantitative values are derived from abucnasty's published lab
optimization videos. When referencing these in LilEinstein source,
cite the source videos.
