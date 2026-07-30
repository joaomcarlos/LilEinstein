# view/

## Purpose

GUI layer for the LilEinstein mod: window lifecycle, layout construction, and presentable-data assembly. Reads models; never mutates model storage directly except player GUI state.

## Ownership

- `gui.lua` — view entry point: open/close, event routing, `init_player`, main window on `screen` target
- `gui/builder.lua` — declarative GUI element builder with `fallback_add` pcall protection for cross-version element properties
- `gui/analyzer.lua` — turns model data (state, tech, queue, lab) into presentable data consumed directly by the GUI
- `gui/gutil.lua` — GUI helpers/utilities
- `gui/components.lua` — shared component library, including the decision-first Research Health card and its focused science-throughput drilldown (largest view file)
- `gui/components/queue.lua`, `gui/components/tech.lua`, `gui/components/upcoming.lua` — per-panel components; technology and upcoming panels expose staged automatic rebuild jobs

## Local Contracts

- View sits at the bottom of the module order (`standard.md`): may require `lib` and `model`, must not be required by model modules (exception: `model/cmd.lua`)
- GUI style prototypes live in `data/style.lua`, not here; reference styles by name
- Player GUI state persists under `storage.players[player_index]` via `state`/`gui.init_player`
- The science-throughput drilldown preserves the root window, keeps headers outside its single vertical scroll pane, and refreshes stable rows in place while cluster membership/order is unchanged
- Throughput cluster rows present working/maximum capacity and local stock evidence only; force-wide measured SPM is never labeled as cluster output and overlapping missing-pack impacts are not summed
- Recurring value refreshes reuse validated runtime-only GUI element references and skip unchanged property writes; LuaGuiElement references never enter persistent storage
- Automatic queue/research rebuilds stage technology scoring and render one technology or upcoming-research row per tick; direct player actions may still repopulate immediately
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
