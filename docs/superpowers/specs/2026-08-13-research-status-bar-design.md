# Rotating Research Status Bar

## Goal

Add a compact, decisive live insight to the bottom-right footer of the LilEinstein research window. The insight rotates through the most useful current research facts, refreshes approximately every ten seconds, and performs no work while the window is closed.

## User-visible behavior

The footer contains one status-bar label. It uses short, localized captions such as:

- `PACK-BOUND • -198.8k SPM • Agricultural + Cryogenic • 462 labs`
- `MISSING PACK • Agricultural • 247 labs • -106.4k SPM`
- `MISSING PACK • Cryogenic • 217 labs • -93.0k SPM`
- `SWITCH READY • Mining productivity 3 • packs sufficient`
- `RESEARCH • Research productivity • 88.43% • 2h 10m left`
- `SCIENCE RISK • Promethium • depletes in 1m 08s`

Messages rotate in deterministic priority order: dominant operational problem, individual missing-pack evidence, switch readiness, depletion risk, current research progress, then a healthy/on-track fallback. The label tooltip may contain the fuller diagnostic wording. If no useful diagnostic exists, the status bar remains a localized neutral state instead of showing stale data.

## Architecture and lifecycle

- `model.queue` remains the source of research-health, summary, science forecast, and control-state data. The status bar consumes already-cached/display-safe getters; it does not trigger a synchronous health scan.
- `view.gui.builder` adds a named label inside the existing `footer_frame`, aligned to the bottom-right and using native Factorio styles.
- `view.gui.components` owns the pure message selection/formatting and updates the existing label in place. It stores only primitive rotation state; no `LuaGuiElement` is persisted.
- `view.gui` exposes a guarded refresh function that resolves the current anchor and delegates to the component.
- `control.lua` calls the refresh only for connected players whose main UI is open, on a 600-tick cadence. The initial `open` population renders the first message immediately, so the bar is not blank for ten seconds after opening.
- Closing/rebuilding the window clears the component runtime cache so an old anchor or stale rotation cannot be reused.

## Performance and error handling

The periodic path iterates only connected players with the UI open. It reads cached model snapshots and changes the caption/tooltip only when the rendered message changes. Missing or invalid GUI children are treated as a no-op. Policy and research-details panels keep the footer visible and continue to receive the status line without forcing their expensive repopulation paths.

## Testing

- Pure component tests cover deterministic priority, multi-pack rotation, neutral fallback, and formatting of SPM/lab/time values.
- GUI facade tests cover forwarding the refresh call and safe behavior when the anchor is missing.
- Builder/behavior tests cover the named footer label and in-place caption/tooltip updates.
- Control scheduling tests cover that the status refresh is in the open-UI loop at the ten-second cadence rather than a per-tick or closed-UI path.
- Existing Lua unit, Factorio parse, production lint, and disposable in-game checks remain required.
