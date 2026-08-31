---
name: factorio-fff443-research-control
description: "Factorio 2.1 circuit-lab research control mechanics from FFF-443 'Unlimited Throughput' and abucnasty's analysis. Use when working on LilEinstein's research queue management, lab-cluster scheduling, science-pack monitoring, or any 2.1 migration question. Covers set-research circuit command, read-research-cost signal, landing pad throughput changes, red/green wire split, science pack remaining percentage, and worker-robot-speed meta de-prioritization."
version: "1.0.0"
user-invocable: true
compatibility: Pure knowledge reference — no runtime, network, or env vars required.
metadata: {"hermes":{"tags":["factorio","lileinstein","fff443","circuit","research-control","2.1","abucnasty"],"category":"game-modding"}}
---

# Factorio FFF-443 Research Control Knowledge

Reference distillation of Factorio FFF-443 "Unlimited Throughput" and
abucnasty's analysis video. Use this when working on LilEinstein's
research queue management, lab-cluster scheduling, or planning for
Factorio 2.1 migration.

## Source

- **Creator**: abucnasty
- **Video analyzed**: "FFF-443: Unlimited Throughput"
- **Scope**: Factorio 2.1 (upcoming changes announced in FFF-443)
- **Relevance**: High — several 2.1 mechanics directly overlap with
  LilEinstein's core functionality

## New lab circuit control (most relevant to LilEinstein)

### Set research from circuit network

Factorio 2.1 adds the ability to **set the current research from the
circuit network**, enabling conditional research selection:

> "we can set research ... set the current research ... conditionally
> set research based on when something happens to be in stock and when
> it's not"

**LilEinstein impact**: This is native research-queue control that
overlaps with LilEinstein's core autopilot. The mod should:
- Evaluate whether to use the native set-research command or continue
  using the Lua API (`force.research_queue`)
- Consider using circuit signals for conditional research (e.g., only
  queue Gleba-dependent techs when agriculture-science stock > threshold)

### Read research cost from lab

Factorio 2.1 adds the ability to **read the research cost from a lab**,
which reveals the active science-pack set in real time:

> "being able to read the research cost. If you know what the research
> cost is, then you know what current sciences are actively being
> researched ... use a lab effectively to just know what the current
> science is"

**LilEinstein impact**: This replaces the need for inserter-hand-content
monitoring. abucnasty's current (pre-2.1) workaround was:

> "I created this incredibly complex mechanism over on Gleba to go and
> create a science monitor that reads the hand contents of this specific
> inserter and then keeps a memory cell of every single time it has
> swung ... All of that goes away because you can just read the cost of
> the current science."

LilEinstein already uses `LuaForce.current_research` and
`LuaTechnology.research_unit_count` etc. from the Lua API, so this
circuit signal is less critical for the mod itself, but it means player
builds can now natively detect active science without LilEinstein's
help.

### Conditional research and dynamic request sizing

Reading research cost + setting research enables stock-dependent
research selection and per-research supply requests:

- Research can be set "conditionally based on when something happens to
  be in stock"
- Example: "if you have Gleba science coming in from a different planet
  ... research something with Gleba science only when I have it and
  otherwise just use the Nauvis sciences"
- Request sizing: "when I'm running Promethium, I want to request 96,000
  ... for a 60-second research science, I could be requesting double
  that" (~192,000)

**LilEinstein impact**: Supply forecasts can be driven directly from
active research cost. The mod can pre-size supply requests based on
research duration and pack type.

## Still need clocking for stack inserters

Even with native set-research and read-research-cost, labs still need
clocked inserter control:

> "I still think you're going to need clocking in some instances because
> ... you're still going to have issues with stack inserters always
> desyncing if you use a basic clock."

**LilEinstein impact**: Lab-cluster scheduling may still require
per-lab clocking awareness. See companion skill
`factorio-abucnasty-lab-design` for clocking methods.

## Landing pad / cargo bay throughput ("Unlimited Throughput")

The headline feature: new landing-pad loading-bay extraction removes
the bot bottleneck for hub unloading.

> "How do you get maximum throughput through a landing hub? ... this is
  going to ... basically means that bots are dead"

> "Now, what you'll probably see is more just unloading to belts and
  that'll be like directly to belts from these"

**LilEinstein impact**:
- Science-pack unloading from planetary cargo becomes belt-based, not
  bot-limited
- Lab-cluster scheduling can assume higher, less bursty supply from hubs
- Worker-robot-speed research becomes less critical for UPS

## Red/green wire input/output split

The circuit network now has separate red and green filtered
inputs/outputs:

> "You can very clearly set red and green filters on the inputs ... you
  can read it from the output of the machine, and for the inputs when
  you're sending a command, you can go and send that on the separate
  wire."

This solves the "magic self-subtraction" problem — you can now read a
chest's contents and set its requests without the old workaround. This
makes it possible to remove trapped/spoiling items from requester
chests.

**LilEinstein impact**: Useful for monitoring science-pack buffer
chests and turning lab inserters/clusters on/off cleanly. If LilEinstein
ever generates circuit blueprints, this is the correct pattern.

## Science pack remaining percentage / spoilage state

Science packs have a per-pack "remaining percentage" (they are treated
as tools with a drain amount):

> "there's all these like drain like the remaining percentage on
  logistic science packs ... science packs ... they all have this little
  property of their remaining percentage"

This blocks large-inventory / daisy-chain optimizations because packs
are not fungible (each has its own remaining %).

**LilEinstein impact**:
- A consumed or partially-consumed science pack is not a uniform item
- Supply-forecast / scheduling logic should treat science-pack stacks as
  having an internal "remaining use" state
- Packs can be lost to spoilage if left sitting in inserters/chests

## Other 2.1 mechanic changes

| Change | Details | LilEinstein relevance |
|--------|---------|----------------------|
| Boilers/heat exchangers circuit-controllable | Turn on/off via circuit | Indirect — affects power management |
| Land mines circuit-controllable | Trip wires can interrupt circuit network | Indirect — Gleba defense automation |
| Pumps connect to trains in any orientation | "no matter how cursed your station design is" | Indirect — fluid logistics |

## Research meta shifts for 2.1

From abucnasty's analysis of FFF-443:

- **Endgame meta was**: worker robot speed, mining productivity,
  research productivity.
- **Worker-robot-speed becomes less compelling** for UPS because landing-
  pad throughput removes the bot bottleneck. Worker-robot-speed
  megabases may become obsolete.
- **Mining productivity and research productivity remain the meta
  infinite techs** — not affected by throughput changes.
- **Most other infinite techs remain capped at 300% productivity** by
  the game's machine productivity limit.
- "Mining prod always makes sense ... each one keeps on giving you 10%."

### Recommended weight adjustments for 2.1

| Tech | Current weight | Suggested 2.1 weight | Reason |
|------|---------------|---------------------|--------|
| `worker-robot-speed` | 5 | 2-3 | Landing pad removes bot bottleneck |
| `mining-productivity` | 12 | 12 (unchanged) | Still meta |
| `research-productivity` | 20 | 20 (unchanged) | Still meta |

## Specific numbers from FFF-443 analysis

| Value | Meaning |
|-------|---------|
| 96,000 | Agriculture-science request when running Promethium (space platform) |
| ~192,000 | Request for a 60-second research science (double the base) |
| 300% | Productivity cap on most infinite techs |
| 10% | Per-level bonus for mining prod and research prod |
| 15 million ESPM | Scale of worker-robot-speed bases seen in the community |

## How this maps into LilEinstein

| Knowledge | LilEinstein relevance |
|-----------|----------------------|
| Set-research circuit command | Evaluate using native command vs Lua API for queue management |
| Read-research-cost signal | Confirms LilEinstein's approach of using research cost for supply forecasting |
| Landing pad throughput | Supply forecasting can assume higher, less bursty hub supply in 2.1 |
| Worker-robot-speed de-prioritization | Update `research_weights` for 2.1 |
| Science pack remaining percentage | Supply forecast should account for partial consumption |
| Red/green wire split | If LilEinstein generates circuit blueprints, use the new pattern |
| Request sizing (96k/192k) | Supply forecast can pre-size requests by research duration |

## 2.1 migration considerations for LilEinstein

1. **Evaluate native set-research**: Determine if LilEinstein should
   use the circuit-network set-research command or continue with
   `force.research_queue` Lua API. The Lua API is likely still
   preferable for a mod, but the circuit command enables player-side
   conditional research that complements the mod.
2. **Update worker-robot-speed weight**: Lower from 5 to 2-3 for 2.1.
3. **Update railgun-shooting-speed cap**: Already capped at 12 by bug
   fix (was 20 in original skill).
4. **Supply forecasting**: Account for landing-pad throughput
   improvements — hub supply is less bursty, more belt-based.
5. **Spoilage modeling**: Science packs have remaining percentage;
   partially-consumed packs are not fungible.
6. **Circuit blueprint generation**: If LilEinstein ever generates
   circuit blueprints for lab control, use the 2.1 red/green wire split
   pattern.

## Companion skills

- `factorio-abucnasty-science` — ESPM formula, practical caps, tier
  rankings, per-pack difficulty weights, quality recommendations
- `factorio-abucnasty-lab-design` — lab clocking, inserter patterns,
  beacon layouts, UPS benchmarks
- `factorio-abucnasty-megabase-logistics` — planet-specific strategy,
  spoilage management, ship design, production ratios

## Attribution

All quantitative values and quotes are derived from abucnasty's
published FFF-443 analysis video. When referencing these in LilEinstein
source, cite the source video and FFF-443.
