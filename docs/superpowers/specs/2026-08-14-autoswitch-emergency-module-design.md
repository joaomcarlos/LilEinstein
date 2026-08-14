# AutoSwitch-Style Emergency Science Detector

## Goal

Give LilEinstein a fast, isolated starvation signal modelled on AutoSwitchTechs,
without replacing its bounded sampler, forecast checks, queue policy, or recovery
logic.

## Design

- Add `model/auto_switch.lua` as the only owner of the direct lab-inventory
  availability scan.
- Scan LilEinstein's already-registered labs; never perform a world-wide
  `find_entities_filtered` search from the emergency path.
- For each valid, powered, enabled lab, count each science pack that is present
  and each accepted pack in the lab prototype. Return per-pack `with`, `allowing`,
  and `fraction` values plus a bounded cache timestamp.
- Reuse the cached scan for a short interval and expose an explicit invalidation /
  refresh seam for lab membership and tests. Do not scan every maintenance call.
- Let the queue use this module only as an emergency current-technology
  pack-bound signal. Normal queue scoring, forecast sufficiency, candidate
  selection, and target recovery remain in `model/queue.lua`.
- The emergency signal must identify a unique missing required pack and must not
  switch on an empty/no-lab/invalid snapshot. Candidate acceptance still goes
  through LilEinstein's existing sufficiency checks.

## Test seams

- Unit-test the standalone scanner with valid, empty, unpowered, disabled, and
  mixed-pack labs; assert exact counts and fractions.
- Unit-test cache reuse and explicit invalidation so a maintenance pass cannot
  multiply inventory work.
- Exercise the public `queue.check_and_switch_temp_research` seam with a
  singleton queued pack-bound technology and a supplied alternate outside the
  queue. Assert the alternate is selected, while a candidate that fails existing
  sufficiency is rejected.
- Extend the disposable Factorio test only if needed to prove the live
  `LuaForce.current_research` switch; keep the save isolated and preserve the
  existing low-but-nonzero progress and recovery assertions.

## Performance and safety

- Keep all scans bounded and cacheable; no new `on_tick` work and no full-world
  searches.
- Validate lab entities and inventories immediately before use.
- Keep all persisted state save-safe; cache only numbers, strings, and tables.
- Preserve the current player-facing diagnostic and explicit queue as the normal
  authority.
