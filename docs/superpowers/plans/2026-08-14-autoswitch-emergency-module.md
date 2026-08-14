# AutoSwitch-Style Emergency Module Implementation Plan

> **For agentic workers:** This plan is delegated as a bounded implementation task. The primary Codex agent must inspect the diff and rerun all checks before accepting it.

**Goal:** Add a separate, cached AutoSwitch-style lab-inventory detector that gives the existing starvation switcher a fast current-pack signal without replacing LilEinstein's forecast and policy logic.

**Architecture:** `model/auto_switch.lua` owns direct registered-lab inventory counting and its short-lived per-force cache. `model/queue.lua` consumes that signal only in the emergency current-technology path; normal queue scoring and recovery stay unchanged. Unit tests cover the module seam and the full queue switch seam, while the existing disposable Factorio scenario remains the live-switch authority.

**Tech Stack:** Factorio 2.0.77 Lua 5.2 runtime, existing `tests/testlib.lua` Lua specs, disposable headless Factorio runner.

## Global Constraints

- Do not perform a world-wide `find_entities_filtered` scan from the emergency path.
- Do not add unbounded `on_tick` work or scan every maintenance call; cache per-force results and invalidate explicitly.
- Use registered labs and validate `LuaEntity`/inventory objects immediately before reading them.
- Do not change AutoSwitchTechs, the normal explicit queue authority, candidate sufficiency, or target-recovery semantics.
- Preserve unrelated dirty files and do not commit, push, reset, clean, install, or touch a player save.
- Run Lua 5.2 syntax checks, focused tests, the full unit suite, and the disposable in-game runner as applicable.

---

### Task 1: Extract the standalone scanner

**Files:**
- Create: `model/auto_switch.lua`
- Modify: `model/lab.lua`
- Modify: `model/AGENTS.md`

**Interfaces:**
- Consumes: `lab.get_runtime_lab_content(force_index)` and `env.get_all_sciences()`.
- Produces: `auto_switch.get_availability(force_index, force_refresh, lab_content, all_sciences)` returning per-pack `with`, `allowing`, `fraction`, and cache metadata; `auto_switch.get_missing_sciences(force_index, technology, lab_content, all_sciences)` returning only missing required pack names; `auto_switch.invalidate(force_index)`.

- [x] Move the existing direct-inventory availability behavior out of `lab.lua` into the new module, preserving powered/frozen/disabled/empty-lab guards and accepted-pack counting.
- [x] Add per-force runtime cache with a short bounded interval; explicit refresh must be the only way to bypass it.
- [x] Return safe empty results when the force, lab registry, prototype inputs, inventory, or entity is absent/invalid.
- [x] Update the model DOX index and dependency description for the new module.

### Task 2: Wire the emergency signal

**Files:**
- Modify: `model/queue.lua`
- Modify: `tests/AGENTS.md`

**Interfaces:**
- Consumes: `auto_switch.get_missing_sciences` in the active starvation decision.
- Produces: the existing `queue.check_and_switch_temp_research(force)` behavior, with current candidate sufficiency and bounded emergency selection unchanged.

- [x] Require the new module without creating a circular dependency.
- [x] Use the direct-inventory result only when the current technology is materially pack-bound or the existing sampler/display evidence is temporarily unavailable; do not make it a normal queue reorder signal.
- [x] Keep candidate acceptance delegated to the existing `science_is_sufficient`/forecast path.
- [x] Reuse one cached scan per maintenance pass and avoid a second inventory loop for each candidate.
- [x] Document the new emergency-signal contract in `tests/AGENTS.md`.

### Task 3: Add red-green tests

**Files:**
- Create or modify: `tests/auto_switch_spec.lua`
- Modify: `tests/queue_core_spec.lua`
- Modify: `tests/run_all.lua` only if the suite requires explicit registration

**Interfaces:**
- Tests: `auto_switch.get_availability`, `auto_switch.get_missing_sciences`, `auto_switch.invalidate`, and public `queue.check_and_switch_temp_research`.

- [x] Assert exact mixed-pack `with`/`allowing`/`fraction` values.
- [x] Assert frozen, unpowered, disabled, empty, invalid, and no-lab entries do not count.
- [x] Assert cache reuse prevents a second inventory read and invalidation refreshes it.
- [x] Assert a singleton queued starving technology switches to a supplied alternate outside the explicit queue.
- [x] Assert an alternate that fails existing sufficiency remains rejected.

### Task 4: Run verification and inspect scope

**Files:**
- No additional source files.

- [x] Run `luac52 -p model/auto_switch.lua model/lab.lua model/queue.lua`.
- [x] Run `lua52 .\\tests\\auto_switch_spec.lua` and `lua52 .\\tests\\queue_core_spec.lua`.
- [x] Run `lua52 .\\tests\\run_all.lua` and record any unrelated pre-existing failure separately.
- [x] Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\run_tests.ps1 -RequireInGame`.
- [x] Run `git diff --check` and inspect only the allowed paths plus the pre-existing dirty files.
