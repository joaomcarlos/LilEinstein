# view/

## Purpose

GUI layer for the LilEinstein mod: window lifecycle, layout construction, and presentable-data assembly. Reads models; never mutates model storage directly except player GUI state.

## Ownership

- `gui.lua` — view entry point: open/close, event routing, `init_player`, main window on `screen` target
- `gui/builder.lua` — declarative GUI element builder with `fallback_add` pcall protection for cross-version element properties
- `gui/analyzer.lua` — turns model data (state, tech, queue, lab) into presentable data consumed directly by the GUI
- `gui/gutil.lua` — GUI helpers/utilities
- `gui/components.lua` — shared component library (largest view file)
- `gui/components/queue.lua`, `gui/components/tech.lua`, `gui/components/upcoming.lua` — per-panel components

## Local Contracts

- View sits at the bottom of the module order (`standard.md`): may require `lib` and `model`, must not be required by model modules (exception: `model/cmd.lua`)
- GUI style prototypes live in `data/style.lua`, not here; reference styles by name
- Player GUI state persists under `storage.players[player_index]` via `state`/`gui.init_player`

## Work Guidance

- Follow `standard.md` naming and structure
- Validate element properties against the Factorio 2.0 GUI API; use `builder` for element creation

## Verification

- No automated tests; verify in-game (open/close main window, check for script errors)

## Child DOX Index

None. `gui/` and `gui/components/` are owned here.
