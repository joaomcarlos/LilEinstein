# Rotating Research Status Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cached, rotating research insight to the existing footer while the research UI is open.

**Architecture:** Add a named label to the existing footer. Keep message selection and formatting in the GUI component layer using cached queue getters, expose a guarded facade refresh, and invoke it only for open connected-player UIs every 600 ticks. Render once during open and update only when the rendered caption/tooltip changes.

**Tech Stack:** Factorio 2.0 Lua 5.2 control stage, native LuaGuiElement styles, repository Lua unit harness.

## Global Constraints

- Refresh only while `gui.is_open(player_index)` is true.
- Periodic refresh cadence is 600 ticks (approximately 10 seconds).
- Never synchronously scan research health from the status-bar refresh.
- Never store `LuaGuiElement` references in persistent state.
- Preserve unrelated pre-existing worktree changes and do not touch `diagnostics/`.

---

### Task 1: Add failing pure insight-selection tests

**Files:**
- Test: `tests/components_behavior_spec.lua`

**Interfaces:**
- Expected component seam: `components.build_research_status_insights(diagnostic, summary, control_state, forecast)` returns an ordered array of renderable insight records with `caption` and optional `tooltip`.

- [ ] **Step 1: Write tests for dominant pack-bound loss, missing-pack rotation, neutral fallback, and SI/time formatting.** Use the existing fixture helpers and assert the returned captions/localised-string arguments rather than GUI implementation details.
- [ ] **Step 2: Run `lua52 .\\tests\\run_all.lua` and confirm the new tests fail because the formatter does not exist.**

### Task 2: Implement the pure insight formatter

**Files:**
- Modify: `view/gui/components.lua`
- Modify: `tests/components_behavior_spec.lua`

**Interfaces:**
- `build_research_status_insights(diagnostic, summary, control_state, forecast)` reads only supplied data and returns deterministic insight records.
- Rotation is represented by array order; no model scan or GUI element is touched by this helper.

- [ ] **Step 1: Implement the smallest formatter that emits the approved priority order and uses existing localised captions/number/time formatters.**
- [ ] **Step 2: Run the focused component tests and confirm they pass.**
- [ ] **Step 3: Add any necessary edge-case assertion for absent diagnostic/summary values, then rerun the focused tests.**

### Task 3: Add the footer label and guarded GUI refresh

**Files:**
- Modify: `view/gui/builder.lua`
- Modify: `view/gui.lua`
- Modify: `view/gui/components.lua`
- Test: `tests/builder_spec.lua`
- Test: `tests/gui_spec.lua`
- Test: `tests/components_behavior_spec.lua`

**Interfaces:**
- Builder creates `research_status_bar` under `footer_frame` as a label.
- `gui.refresh_research_status_bar(player_index)` resolves the current main anchor and delegates safely.
- Component refresh updates `research_status_bar.caption` and `.tooltip` only when rendered text changes.

- [ ] **Step 1: Extend builder and GUI facade tests with the named footer label and missing-anchor guard.**
- [ ] **Step 2: Run the focused GUI tests and confirm the new assertions fail.**
- [ ] **Step 3: Add the label, facade, runtime cache, and in-place component refresh.**
- [ ] **Step 4: Run the focused GUI/component tests and confirm they pass.**

### Task 4: Schedule the open-only ten-second refresh

**Files:**
- Modify: `control.lua`
- Test: `tests/gui_spec.lua`
- Test: `tests/locale_spec.lua`

**Interfaces:**
- The existing open-player periodic path invokes `gui.refresh_research_status_bar(p.index)` only when `game.tick % 600 == 0`, or an equivalent `on_nth_tick(600)` open-player loop.
- `gui.open` performs the initial status-bar render.

- [ ] **Step 1: Extend the GUI facade coverage for the status-bar refresh and use the disposable in-game harness to verify the loaded control script and 600-tick registration.**
- [ ] **Step 2: Run the focused GUI/locale tests and confirm they fail before the hook and locale section exist.**
- [ ] **Step 3: Add the minimal open-only schedule and initial render call.**
- [ ] **Step 4: Run the focused control test and then the complete unit suite.**

### Task 5: Localize, document, and validate

**Files:**
- Modify: `locale/en/en.cfg`
- Modify: `locale/de/de.cfg`
- Modify: `locale/fr/fr.cfg`
- Modify: `locale/pt-PT/pt-PT.cfg`
- Modify: `view/AGENTS.md` only if the durable status-bar contract is not already covered.

- [ ] **Step 1: Add localized status-bar captions/tooltips for every emitted insight kind.**
- [ ] **Step 2: Run `lua52 .\\tests\\run_all.lua`.**
- [ ] **Step 3: Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\run_tests.ps1 -RequireInGame`.**
- [ ] **Step 4: Run production-only Factorio lint, Lua 5.2 parsing, and `git diff --check`.**
- [ ] **Step 5: Inspect the final diff and verify no diagnostics submodule or unrelated file changed.**
