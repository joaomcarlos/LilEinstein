# Research Control Center Decision Console Implementation Plan

> **For agentic workers:** The standalone demo was approved as the visual reference on 2026-08-14. Live integration is now authorized, using isolated model/view worktrees and the contract below. The demo remains the visual review gate for each live slice.

**Goal:** Turn selected visual direction 3 into a sprite-backed, exact-size standalone demo and a live Factorio Decision Console backed by authoritative planning, forecasting, reservation, history, and collaboration state.

**Architecture:** Use the selected 1672x941 image as the visual source, derive a deterministic cleaned background and atomic sprite crops, and register the asset contract without contaminating live controls with baked text or sample rows. Build an interactive offline HTML demo over the cleaned background so tabs, radio controls, checkboxes, steppers, and the Back to research action can be reviewed at the same scale as the game window. After feedback, reuse the same measured rectangles and sprite names in `data/sprites.lua`, `data/style.lua`, `view/gui/builder.lua`, and `view/gui/components.lua`.

**Tech Stack:** Factorio 2.0.77+ Lua data/control stages, existing PNG sprite assets, Pillow-based deterministic cleanup/crops, standalone HTML/CSS/JavaScript demo, existing Lua unit harness.

## Global Constraints

- Preserve all existing uncommitted user changes; do not touch `diagnostics/`.
- Use the selected generated reference at 1672x941 as the authoritative visual target.
- Static artwork may be baked only into cleaned background/sprite assets; dynamic labels, controls, rows, science icons, timers, and tabs must remain live in the future Factorio GUI.
- Register only existing PNG files; every registered sprite path must be checked after generation.
- Keep Factorio data-stage code free of runtime APIs and validate new style fields against Factorio 2.0.
- Live integration must preserve the existing bounded refresh and save-safe storage contracts; the standalone demo remains a visual reference, not a source of runtime truth.
- Devin owns model/data-stage changes in an isolated worktree; Codex owns view/control/locale changes in the main checkout. Do not edit the same file from both workspaces.
- Freeze these additive seams before view wiring: `policy.get_history(force_index, filters)`, `policy.get_setting(force_index, "reserve_for_type")`, `policy.get_setting(force_index, "replan_interval_seconds")`, `policy.get_setting(force_index, "instant_switch_override")`, and `queue.get_plan_snapshot(force_index)`.

---

### Task 1: Freeze the asset contract and measured layout

**Files:**
- Reference: `C:\Users\silent\.codex\generated_images\019fff97-c95c-7750-a938-6b07dd24292d\exec-d46d5d20-8ace-4d11-9edb-7225d12aef23.png`
- Create: `output/research-control-center-demo/asset-plan.json`
- Create: `output/research-control-center-demo/README.md`

**Interfaces:**
- `asset-plan.json` records the source path, target size, clean rectangles, sprite crop rectangles, and intended consumer for each asset.
- `README.md` explains the demo command, the sprite/background layering contract, and the live-integration boundary.

- [x] **Step 1: Record the exact 1672x941 source and mark dynamic regions.** Keep the header/chrome art, clear the live summary controls, stage controls, tab labels, evidence/history rows, and footer status text.
- [x] **Step 2: Record atomic crops only where the crop contains no sample data.** Reuse existing registered Factorio UI sprites for toggles, checkboxes, radios, steppers, and science/technology icons where possible; do not register contaminated crops from the generated screenshot.
- [x] **Step 3: Review the plan for overlaps, stale paths, and width contracts before generating assets.**

### Task 2: Generate deterministic cleaned background and sprite crops

**Files:**
- Create: `output/research-control-center-demo/assets/decision-console-background-clean.png`
- Create: `output/research-control-center-demo/assets/decision-console-stage-arrow.png`
- Create: `output/research-control-center-demo/assets/decision-console-step-badge.png`
- Create: `scripts/clean_decision_console_assets.py`

**Interfaces:**
- `scripts/clean_decision_console_assets.py` accepts the selected reference path and `asset-plan.json`, writes only the declared PNG outputs, and fails on missing source or invalid rectangles.
- The cleaned background preserves the industrial window chrome while removing baked dynamic text, controls, science icons, sample technology rows, and history entries.

- [x] **Step 1: Implement the deterministic cleanup/crop script with Pillow and explicit rectangles.** Do not use generative editing or CSS/drawing substitutes for image assets.
- [x] **Step 2: Run the script and verify every output has the planned dimensions and a valid PNG header.**
- [x] **Step 3: Inspect the generated images visually and correct any halos, leftover text, clipped borders, or contaminated sprite crops.**

### Task 3: Assemble the interactive standalone demo

**Files:**
- Create: `output/research-control-center-demo/index.html`
- Create: `output/research-control-center-demo/demo.css`
- Create: `output/research-control-center-demo/demo.js`
- Use: `output/research-control-center-demo/assets/*`
- Use: existing `graphics/icons/*` and `graphics/ui/*` assets through relative paths where their dimensions match the plan.

**Interfaces:**
- The demo renders one 1672x941 Decision Console frame without browser chrome or a second concept.
- Tabs switch the focused lower content; radio buttons, checkboxes, steppers, and Back to research provide visible state changes; the demo remains offline and requires no dependency install. The checkpoint covers Automation, Plan budget, Science policies, Manual objectives, Plan presets, and History.
- The demo mirrors the current code units (20s minimum switch time, 120s supply horizon, 5 parallel slots when enabled) and explicitly labels proposed runtime behavior: bounded Reserve for type, delivery-aware depletion runtime, 30s switch cap with instant plan-demand override, and immediate replanning on plan/settings changes.

- [x] **Step 1: Build the page shell over the cleaned background at the exact reference dimensions.** Use real image assets for the background and icons; do not replace sprites with emoji, inline SVG, gradients, or CSS drawings.
- [x] **Step 2: Add the top summary strip, three numbered decision stages, tab row, and Automation content using the measured geometry.**
- [x] **Step 3: Wire the core interactions and visible states without adding unrelated product features.**
- [x] **Step 4: Open the demo locally, capture a 1672x941 screenshot, and compare it directly with the selected reference.**

### Task 4: Asset and demo verification checkpoint

**Files:**
- Create: `output/research-control-center-demo/verification.md`

- [x] **Step 1: Verify all declared files exist and all dimensions match `asset-plan.json`.**
- [x] **Step 2: Run the demo’s interaction smoke checks and inspect the final screenshot at 100% scale.**
- [ ] **Step 3: Run `lua52 .\\tests\\run_all.lua` to confirm the existing mod behavior remains green.** Initial baseline passed with 226 tests; the final rerun is blocked by unrelated concurrent `tests.queue_core_spec` failure (`checks=804`).
- [x] **Step 4: Record remaining live-integration work without claiming the Factorio panel is wired yet.**

### Task 5: After user feedback, integrate into Factorio

**Files:**
- Modify: `data/sprites.lua`
- Modify: `data/style.lua`
- Modify: `view/gui/builder.lua`
- Modify: `view/gui/components.lua`
- Modify: relevant locale files and tests under `tests/`

- [x] **Step 1: Devin — add the model foundation: bounded policy settings, `Megabase` strategy semantics, structured/filterable history, plan snapshot read API, and the instant-switch/replan contract. Add focused tests without touching view files.**
- [x] **Step 2: Codex — add the live six-tab policy shell: persistent tab selection, named tab routing, and visible sections matching the approved demo while preserving current handlers. Do not claim the new plan/reservation values are authoritative until the model seam exists.**
- [x] **Step 3: Codex — add localized tab/filter/collaboration strings and route the new controls through validated GUI tags and player state.**
- [ ] **Step 4: Merge/review the isolated model and view slices, then implement delivery-aware planning, bounded Reserve for type, minute-based plan allocation, and manual objectives as separate follow-up slices.**
- [ ] **Step 5: Register only approved clean background and atomic sprites, then run unit, parser, locale, production lint, disposable in-game, and actual live visual smoke checks.**

Current implementation checkpoint: the first model/view slice is merged as commits `24ba04a` and `ff0f526`. The live panel now has persistent six-tab routing, History filtering, reserve/replan/instant-switch controls, a 30-second switch cap, a five-minute forecast setting cap, a minute-based plan-horizon setting seam, and runtime-to-depletion that includes committed in-transit science with explicit infinity when supply does not deplete. Delivery ETA/route reachability, the actual bounded Reserve-for-type allocator, and minute-based plan allocation remain explicitly unimplemented follow-up work.

### Parallel implementation contract

- **Devin worktree:** `model/research_policy.lua`, `model/queue.lua`, and focused model tests. No view, control, locale, or data-stage edits.
- **Codex checkout:** `view/gui/builder.lua`, `view/gui/components.lua`, `control.lua`, locale files, and focused GUI tests. No model edits until the model slice is reviewed.
- **Cross-review:** Codex reviews Devin's model diff and reruns model tests; Devin reviews Codex's GUI diff read-only against the frozen seams. Any seam change is resolved before merging.
