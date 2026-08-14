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
- The science-throughput drilldown preserves the root window, keeps headers outside its single vertical scroll pane, and refreshes stable rows in place while cluster membership/order is unchanged; incomplete rows from an older GUI shape are rebuilt before refresh
- Throughput cluster rows present working/maximum capacity, every current-research pack's local demand/stock, and missing-pack evidence; force-wide measured SPM is never labeled as cluster output and overlapping missing-pack impacts are not summed
- Throughput details render force-wide demand and per-cluster pack evidence as aligned native tables; missing science is shown as physical packs per minute with the associated negative SPM in parentheses, using normal quality for the pack-count conversion
- The throughput location table is shortage-first: its missing-pack/SPM column leads the capacity evidence, and the Fix first column owns the nested per-pack stock, demand, working, and missing table
- Throughput rows use the same fixed-width table style as the header; a visible affected-labs action opens a replacement single-scroll inspection view listing the lab identity, location, status, and missing packs for the selected cluster
- The throughput details summary compares force-wide maximum and currently working pack demand with the latest one-minute production statistics for each required science pack
- Research Health and throughput details keep the last completed report visible during bounded measurement and replace the complete report atomically only after the new snapshot finishes
- Dynamic multi-row LocalisedStrings are composed in chunks of at most Factorio's 20-parameter limit
- Recurring value refreshes reuse validated runtime-only GUI element references and skip unchanged property writes; LuaGuiElement references never enter persistent storage
- The footer research status bar renders a cached, rotating insight immediately on open and only advances every 600 ticks for connected players whose main UI is open; it uses the `lil_einstein-status` locale section and never performs a synchronous model scan
- Available technologies rebuild synchronously only after direct player actions or filter changes; automatic queue/research refreshes do not rescore or repaint that list
- Upcoming background refreshes leave the current list visible, update rows in place when identity/order is unchanged, and replace a changed list completely in one render pass after bounded model calculation
- Background refresh requests coalesce while a repopulation job is active; a queued follow-up starts after the current bounded refresh finishes instead of resetting its calculation state
- Direct open/action rebuilds must never spin on a staged job or wait for a future `on_tick`; use an immediate model read for those event-bound paths
- Initial component population receives the built `lil_einstein_gui` window, matching the anchor used by later refresh and tick jobs
- Research-history graph jobs paint the newest samples first and finish their bounded 200-column redraw within five render passes
- Science inventory and per-minute rates use the shared compact SI formatter (`K`, `M`, `G`, and higher prefixes) with at most one decimal place
- Upcoming rows mirror effective research order and state the science-supply reason when an entry is not selectable
- New Upcoming LocalisedStrings include literal fallbacks so control-stage reloads cannot render `Unknown key` text
- The Research Health header exposes a copy-debug-report action; because Factorio mods cannot write arbitrary text to the OS clipboard, the action opens a focused, read-only text box with the full report selected for Ctrl+C
- Debug reports include live/current queue state, score components, pack-sufficiency decisions, the last 2 minutes of graph samples, bounded science-flow samples, and all current diagnostic warnings
- Debug reports also include the live Research Health details subtree: outer row caption states, inspect-button visibility, and nested pack-table child counts
- Debug-report technology tables distinguish globally present packs (`packs_available`) from the switcher's live/forecast decision (`switch_sufficient`)
- Debug-report focus and selection calls must guard the element's validity inside the protected call; research-detail row controls may only receive properties supported by their native element style type

## Work Guidance

- Follow `standard.md` naming and structure
- Validate element properties against the Factorio 2.0 GUI API; use `builder` for element creation

## Verification

- No automated tests; verify in-game (open/close main window, check for script errors)

## Child DOX Index

None. `gui/` and `gui/components/` are owned here.
