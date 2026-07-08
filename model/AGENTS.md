# model/

## Purpose

Runtime data model and research-autopilot logic for the LilEinstein Factorio mod. Owns all `storage`-backed state per force and per player.

## Ownership

- `env.lua` — cached environment: `all_sciences`, `tech_meta` prototype metadata
- `state.lua` — player/force settings backing the GUI; `state/translate.lua` handles localized-string translation caching per player
- `tech.lua` — extended technology state (`state_ext`) layered over `LuaTechnology`
- `queue.lua` — core queue engine: force queue, current tech selection, science budgets/deficits, research-rate history, temp-tech switching, plan import/export. Largest and most sensitive module
- `queue/modqueue.lua` — documented data-model stub for the per-force queue entries; `queue/parser.lua` is a placeholder
- `lab.lua` — lab discovery, supply clusters, logistic-network awareness, per-prototype accepted packs
- `research_policy.lua` — strategy profiles (`policy.strategy_order`), infinite-research repeat policies
- `research_weights.lua` — editable AI scoring tables for tech prioritization; designed to be regenerated via external AI chat (see file header)
- `cmd.lua` — chat/console commands; wires model + gui

## Local Contracts

- Data model follows `standard.md`: `storage.<module>.<key>`, `storage.forces[force_index].<module>.<key>`, `storage.players[player_index].<module>.<key>`
- Module dependency order (must not be violated by new requires): env, state → tech → queue → cmd/lab; `cmd.lua` is the only model file allowed to require `view.gui`
- `<module>.init` does not trigger `<module>.init_force`/`init_player`; `control.lua` calls those directly
- Everything in `storage` must be save/load-safe (no LuaObject references persisted across saves except valid entity refs handled defensively)

## Work Guidance

- Follow `standard.md` naming: `t`/`T` for tech/prototype, `meta`, `tech_state_ext`, `queue_names`, etc.
- Validate all Factorio API usage against the 2.0 runtime API; guard nil (`storage`, invalid entities, missing forces)

## Verification

- No automated tests; verify in-game against Factorio 2.0.77+

## Child DOX Index

None. `queue/` and `state/` are small and owned here.
