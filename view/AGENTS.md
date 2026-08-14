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
- The science-throughput details view replaces the normal content chrome with the approved full-window sprite-backed panel so the 1672x941 background remains aligned to the live window bounds
- Throughput details render every lab-accepted science pack as one stable fixed-width row with live item sprites, need/used/produced rates, a signed supply-gap meter, and a native status indicator
- Throughput status is shortage-first: the dominant missing pack is promoted to the warning strip, production shortfalls are separated from delivery bottlenecks, and positive gaps are labeled `OVERPRODUCING*`
- The warning and optional analysis treatments are component backgrounds; the neutral full-window background must not bake in the red warning state
- The Analyze bottleneck action is an explicit opt-in to the heavier science-pack insight heuristic and reports production shortfall versus delivery lag without blocking the normal panel refresh
- Research Health and throughput details keep the last completed report visible during bounded measurement and replace the complete report atomically only after the new snapshot finishes
- Dynamic multi-row LocalisedStrings are composed in chunks of at most Factorio's 20-parameter limit
- Recurring value refreshes reuse validated runtime-only GUI element references and skip unchanged property writes; LuaGuiElement references never enter persistent storage
- The footer research status bar renders a cached, rotating insight immediately on open and only advances every 600 ticks for connected players whose main UI is open; it uses the `lil_einstein-status` locale section and never performs a synchronous model scan
- Available technologies rebuild synchronously only after direct player actions or filter changes; automatic queue/research refreshes do not rescore or repaint that list
- Upcoming background refreshes leave the current list visible, update rows in place when identity/order is unchanged, and replace a changed list completely in one render pass after bounded model calculation
- Upcoming keeps its narrow 525px content width beside the center filter panel, while its rows, technology icons, and drag handles use the 74px Available Technology row scale; its center remains two lines and its right-side timing labels retain the three-line stack
- Background refresh requests coalesce while a repopulation job is active; a queued follow-up starts after the current bounded refresh finishes instead of resetting its calculation state
- Direct open/action rebuilds must never spin on a staged job or wait for a future `on_tick`; use an immediate model read for those event-bound paths
- Initial component population receives the built `lil_einstein_gui` window, matching the anchor used by later refresh and tick jobs
- Research-history graph jobs paint the newest samples first and finish their bounded 200-column redraw within five render passes
- Science inventory and per-minute rates use the shared compact SI formatter (`K`, `M`, `G`, and higher prefixes) with at most one decimal place
- Science-pack icons open a right-side replacement inspector instead of changing technology filters; the inspector keeps Upcoming visible, shows Nauvis-only lab evidence, lists stock by planet including zero-stock rows, lists moving platform/cargo-pod transit, and refreshes only while open with a visible countdown
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
