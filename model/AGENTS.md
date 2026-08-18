# model/

## Purpose

Runtime data model and research-autopilot logic for the LilEinstein Factorio mod. Owns all `storage`-backed state per force and per player.

## Ownership

- `env.lua` — cached environment: `all_sciences`, `tech_meta` prototype metadata
- `state.lua` — player/force settings backing the GUI; `state/translate.lua` handles localized-string translation caching per player
- `tech.lua` — extended technology state (`state_ext`) layered over `LuaTechnology`
- `queue.lua` — core queue engine: force queue, current tech selection, science budgets/deficits, research-rate history, temp-tech switching with pinned/score/priority rules, discounted scoring for unavailable techs, depletion-horizon supply checks, and plan import/export. Largest and most sensitive module
- `queue/modqueue.lua` — documented data-model stub for the per-force queue entries; `queue/parser.lua` is a placeholder
- `lab.lua` — lab discovery, supply clusters, logistic-network awareness, per-prototype accepted packs; `get_science_availability` is a thin compatibility wrapper delegating to `auto_switch`
- `auto_switch.lua` — AutoSwitch-style emergency science detector: sole owner of the direct registered-lab inventory availability scan with a bounded per-force cache; consumed by `queue.lua` only as an emergency fallback when the current technology is materially pack-bound and the staggered sampler/display evidence is temporarily unavailable
- `research_policy.lua` — strategy profiles (`policy.strategy_order`), infinite-research repeat policies
- `research_weights.lua` — editable AI scoring tables for tech prioritization; designed to be regenerated via external AI chat (see file header)
- `cmd.lua` — chat/console commands; wires model + gui

## Local Contracts

- Data model follows `standard.md`: `storage.<module>.<key>`, `storage.forces[force_index].<module>.<key>`, `storage.players[player_index].<module>.<key>`
- Module dependency order (must not be violated by new requires): env, state → tech → queue → cmd/lab; `cmd.lua` is the only model file allowed to require `view.gui`. `auto_switch.lua` requires `env` only (as a fallback when callers omit `all_sciences`); `queue.lua` and `lab.lua` both require `auto_switch` at the top level without creating a circular dependency
- Temp-tech switching respects pinned techs, science priority, and a symmetric score margin; unavailable techs are scored with a discount and never act as runtime candidates
- The explicit queue remains authoritative for normal selection; only a materially PACK-BOUND active technology may widen the temporary-candidate search to a fixed-size scored slice of eligible technologies outside that queue, while preserving the original queued target for recovery
- There is no finish-current threshold override; near-complete research can still yield to a higher-priority or supplied alternate when the switching rules select it
- Event/request-driven reselection passes an explicit force flag so active temporary switches and queue changes update `LuaForce.research_queue`; periodic maintenance compares the cached and live technology names, and bookkeeping follows the queue Factorio actually accepted
- Runtime candidates exclude hidden, disabled, triggered, avoided, and finite/infinite capped technologies
- Active science-supply checks use staggered live lab-starvation snapshots and the same material-loss threshold as the player-facing PACK-BOUND diagnostic; the bottleneck only includes sciences whose individual per-pack lost SPM exceeds the material threshold, so a trivially-starved science (e.g. 1 of 500 labs missing automation) does not block switching to candidates that also use it. Inactive checks share one full-capacity estimate for physical demand and completion horizon, and cluster-mode recovery requires enough stock in the sole compatible consuming scope rather than counting incompatible remote stock, force-wide production, or a one-time delivery burst
- When the bounded lab sampler temporarily has less than 80% fresh coverage, active science-supply checks may use a completed PACK-BOUND display snapshot for the same live technology; future snapshots are ignored. A stale same-technology PACK-BOUND snapshot is still authoritative while its replacement is building, because an actively starving technology does not recover without intervention
- Transit science used by health and depletion forecasts is aggregated once per force per bounded refresh window from platform hubs and cargo-pod inventories; callers reuse the cached per-pack totals instead of scanning every surface once per science
- Emergency fallback reuses one availability snapshot, one forecast, and one precomputed per-science cluster-scope stock map across its bounded candidate slice; candidate count must not hide a technologies-by-sciences-by-clusters maintenance spike
- `auto_switch.lua` is the sole owner of the direct registered-lab inventory availability scan; it uses LilEinstein's already-registered lab runtime data and never performs a world-wide `find_entities_filtered` search. It caches per-force results for a short bounded interval and exposes explicit `invalidate`/`force_refresh` seams. The queue consumes `auto_switch.get_missing_sciences` only as an emergency supplement when the staggered sampler/display bottleneck is temporarily empty; it must not reorder a healthy queue, replace `queue.get_science_availability`'s cluster/policy semantics, or treat a stale or no-lab scan as starvation. A lab with an empty inventory is still an accepting lab and counts in the `allowing` denominator for every pack it accepts, so completely starved labs lower the availability fraction and flag the pack missing. Candidate acceptance still passes the existing sufficiency/forecast path
- The per-force research diagnostic measures only samples for the current technology, classifies decision states from named material-loss thresholds, and emits deterministic semantic display clusters without persisting logistic networks
- The per-force research diagnostic also emits exact science-pack demand per minute for all current-research ingredients, separating maximum compatible-lab demand from currently working-lab demand; pack demand uses lab/quality science-pack drain with research-unit consumption and is not inflated by productivity bonuses
- Missing-science evidence also records the physical normal-quality science-pack rate for the affected labs; its parenthesized SPM remains capacity-loss evidence and overlapping pack impacts are not additive
- Open decision views consume a shared per-force snapshot assembled in bounded lab, network, forecast, and cluster slices; player refreshes must never synchronously aggregate every lab
- Health snapshots finish the technology captured at job start; display consumers retain the last completed snapshot while a replacement is measured, then atomically swap in the new complete report so research rotation cannot repeatedly starve a bounded job
- Upcoming display plans scan and score technologies in bounded slices before the view renders them; synchronous plan generation remains available for direct player actions
- Lab membership is discovered once during force initialization and maintained from build, clone, and revive events; GUI refreshes must never rescan every surface
- Bounded lab sampling persists its force/lab cursors across scheduler calls so factories larger than one batch receive fresh starvation observations without increasing per-call work
- Lab inventory observations come from the staggered lab updater; count and diagnostic consumers share stable runtime-only descriptors, while logistic-network references remain short-lived module-local cache entries
- Research diagnostic display clusters group logistic labs by surface/network and direct-fed labs by surface; cluster values are capacity and local-stock evidence, never inferred actual cluster throughput
- Research diagnostic clusters include deterministic, save-safe lab descriptors for affected-lab inspection; descriptors contain identity, surface/position, status, compatibility, and missing-pack names only, never LuaEntity references
- Upcoming research plans put the active technology first and prefer science-supplied candidates before science-blocked fallbacks
- Science-flow history is bounded to the current two-minute window plus the current sample; it is sampled once per minute only for forces with an open LilEinstein view and remains save-safe
- Science-pack insights are runtime-only and open-scoped: they combine retained research-health data with per-planet and in-transit stock scans only while a pack inspector is visible, cache for the five-second panel interval, and return only save-safe strings and numbers
- Read-only queue control-state access may expose live-vs-cached research names, temporary targets, stored queue names, and the runtime queue for diagnostics; it must not mutate queue state
- `<module>.init` does not trigger `<module>.init_force`/`init_player`; `control.lua` calls those directly
- Everything in `storage` must be save/load-safe (no LuaObject references persisted across saves except valid entity refs handled defensively)

## Work Guidance

- Follow `standard.md` naming: `t`/`T` for tech/prototype, `meta`, `tech_state_ext`, `queue_names`, etc.
- Validate all Factorio API usage against the 2.0 runtime API; guard nil (`storage`, invalid entities, missing forces)

## Verification

- Run `lua52 .\tests\run_all.lua` for model and cross-layer unit coverage.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame`
  for disposable Factorio 2.0.77+ runtime verification.

## Child DOX Index

None. `queue/` and `state/` are small and owned here.
