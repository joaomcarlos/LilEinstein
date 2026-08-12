# model/

## Purpose

Runtime data model and research-autopilot logic for the LilEinstein Factorio mod. Owns all `storage`-backed state per force and per player.

## Ownership

- `env.lua` — cached environment: `all_sciences`, `tech_meta` prototype metadata
- `state.lua` — player/force settings backing the GUI; `state/translate.lua` handles localized-string translation caching per player
- `tech.lua` — extended technology state (`state_ext`) layered over `LuaTechnology`
- `queue.lua` — core queue engine: force queue, current tech selection, science budgets/deficits, research-rate history, temp-tech switching with pinned/score/priority rules, discounted scoring for unavailable techs, depletion-horizon supply checks, and plan import/export. Largest and most sensitive module
- `queue/modqueue.lua` — documented data-model stub for the per-force queue entries; `queue/parser.lua` is a placeholder
- `lab.lua` — lab discovery, supply clusters, logistic-network awareness, per-prototype accepted packs
- `research_policy.lua` — strategy profiles (`policy.strategy_order`), infinite-research repeat policies
- `research_weights.lua` — editable AI scoring tables for tech prioritization; designed to be regenerated via external AI chat (see file header)
- `cmd.lua` — chat/console commands; wires model + gui

## Local Contracts

- Data model follows `standard.md`: `storage.<module>.<key>`, `storage.forces[force_index].<module>.<key>`, `storage.players[player_index].<module>.<key>`
- Module dependency order (must not be violated by new requires): env, state → tech → queue → cmd/lab; `cmd.lua` is the only model file allowed to require `view.gui`
- Temp-tech switching respects pinned techs, science priority, and a symmetric score margin; unavailable techs are scored with a discount and never act as runtime candidates
- Event/request-driven reselection passes an explicit force flag so active temporary switches and queue changes update `LuaForce.research_queue`; periodic maintenance compares the cached and live technology names, and bookkeeping follows the queue Factorio actually accepted
- Runtime candidates exclude hidden, disabled, triggered, avoided, and finite/infinite capped technologies
- Active science-supply checks use staggered live lab-starvation snapshots; non-active candidate checks cap depletion forecasts at the remaining research time
- The per-force research diagnostic measures only samples for the current technology, classifies decision states from named material-loss thresholds, and emits deterministic semantic display clusters without persisting logistic networks
- The per-force research diagnostic also emits exact science-pack demand per minute for all current-research ingredients, separating maximum compatible-lab demand from currently working-lab demand; pack demand uses lab/quality science-pack drain with research-unit consumption and is not inflated by productivity bonuses
- Missing-science evidence also records the physical normal-quality science-pack rate for the affected labs; its parenthesized SPM remains capacity-loss evidence and overlapping pack impacts are not additive
- Open decision views consume a shared per-force snapshot assembled in bounded lab, network, forecast, and cluster slices; player refreshes must never synchronously aggregate every lab
- Health snapshots finish the technology captured at job start; display consumers retain the last completed snapshot while a replacement is measured, then atomically swap in the new complete report so research rotation cannot repeatedly starve a bounded job
- Upcoming display plans scan and score technologies in bounded slices before the view renders them; synchronous plan generation remains available for direct player actions
- Lab membership is discovered once during force initialization and maintained from build, clone, and revive events; GUI refreshes must never rescan every surface
- Lab inventory observations come from the staggered lab updater; count and diagnostic consumers share stable runtime-only descriptors, while logistic-network references remain short-lived module-local cache entries
- Research diagnostic display clusters group logistic labs by surface/network and direct-fed labs by surface; cluster values are capacity and local-stock evidence, never inferred actual cluster throughput
- Upcoming research plans put the active technology first and prefer science-supplied candidates before science-blocked fallbacks
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
