# view/

## Purpose

GUI layer for the LilEinstein mod: window lifecycle, layout construction, and presentable-data assembly. Reads models; never mutates model storage directly except player GUI state.

## Ownership

- `gui.lua` — view entry point: open/close, event routing, `init_player`, main window on `screen` target
- `gui/builder.lua` — declarative GUI element builder with `fallback_add` pcall protection for cross-version element properties
- `gui/analyzer.lua` — turns model data (state, tech, queue, lab) into presentable data consumed directly by the GUI
- `gui/gutil.lua` — GUI helpers/utilities
- `gui/components.lua` — shared component library, including the decision-first Research Health card and its focused science-throughput drilldown (largest view file)
- `gui/components/queue.lua`, `gui/components/tech.lua`, `gui/components/upcoming.lua` — per-panel components; available technologies rebuild on direct actions, while Upcoming keeps visible rows during bounded background calculation

## Local Contracts

- View sits at the bottom of the module order (`standard.md`): may require `lib` and `model`, must not be required by model modules (exception: `model/cmd.lua`)
- GUI style prototypes live in `data/style.lua`, not here; reference styles by name
- Player GUI state persists under `storage.players[player_index]` via `state`/`gui.init_player`
- The science-throughput drilldown preserves the root window, keeps headers outside its single vertical scroll pane, and refreshes stable rows in place while cluster membership/order is unchanged
- Throughput cluster rows present working/maximum capacity, every current-research pack's local demand/stock, and missing-pack evidence; force-wide measured SPM is never labeled as cluster output and overlapping missing-pack impacts are not summed
- Throughput details render force-wide demand and per-cluster pack evidence as aligned native tables; missing science is shown as physical packs per minute with the associated negative SPM in parentheses, using normal quality for the pack-count conversion
- The throughput location table is shortage-first: its missing-pack/SPM column leads the capacity evidence, and the Fix first column owns the nested per-pack stock, demand, working, and missing table
- The throughput details summary compares force-wide maximum and currently working pack demand with the latest one-minute production statistics for each required science pack
- Research Health and throughput details keep the last completed report visible during bounded measurement and replace the complete report atomically only after the new snapshot finishes
- Dynamic multi-row LocalisedStrings are composed in chunks of at most Factorio's 20-parameter limit
- Recurring value refreshes reuse validated runtime-only GUI element references and skip unchanged property writes; LuaGuiElement references never enter persistent storage
- Available technologies rebuild synchronously only after direct player actions or filter changes; automatic queue/research refreshes do not rescore or repaint that list
- Upcoming background refreshes leave the current list visible, update rows in place when identity/order is unchanged, and replace a changed list completely in one render pass after bounded model calculation
- Background refresh requests coalesce while a repopulation job is active; a queued follow-up starts after the current bounded refresh finishes instead of resetting its calculation state
- Direct open/action rebuilds must never spin on a staged job or wait for a future `on_tick`; use an immediate model read for those event-bound paths
- Initial component population receives the built `lil_einstein_gui` window, matching the anchor used by later refresh and tick jobs
- Research-history graph jobs paint the newest samples first and finish their bounded 200-column redraw within five render passes
- Science inventory and per-minute rates use the shared compact SI formatter (`K`, `M`, `G`, and higher prefixes) with at most one decimal place
- Upcoming rows mirror effective research order and state the science-supply reason when an entry is not selectable
- New Upcoming LocalisedStrings include literal fallbacks so control-stage reloads cannot render `Unknown key` text

## Work Guidance

- Follow `standard.md` naming and structure
- Validate element properties against the Factorio 2.0 GUI API; use `builder` for element creation

## Verification

- No automated tests; verify in-game (open/close main window, check for script errors)

## Child DOX Index

None. `gui/` and `gui/components/` are owned here.
