# Research Control Center Decision Console Implementation Plan

> **For agentic workers:** This plan is executed inline in the current shared checkout. The standalone demo is the review gate; live Factorio GUI wiring is intentionally deferred until the user approves the demo.

**Goal:** Turn selected visual direction 3 into a sprite-backed, exact-size standalone demo that can be reviewed before integrating the Decision Console into the Factorio GUI.

**Architecture:** Use the selected 1672x941 image as the visual source, derive a deterministic cleaned background and atomic sprite crops, and register the asset contract without contaminating live controls with baked text or sample rows. Build an interactive offline HTML demo over the cleaned background so tabs, radio controls, checkboxes, steppers, and the Back to research action can be reviewed at the same scale as the game window. After feedback, reuse the same measured rectangles and sprite names in `data/sprites.lua`, `data/style.lua`, `view/gui/builder.lua`, and `view/gui/components.lua`.

**Tech Stack:** Factorio 2.0.77+ Lua data/control stages, existing PNG sprite assets, Pillow-based deterministic cleanup/crops, standalone HTML/CSS/JavaScript demo, existing Lua unit harness.

## Global Constraints

- Preserve all existing uncommitted user changes; do not touch `diagnostics/`.
- Use the selected generated reference at 1672x941 as the authoritative visual target.
- Static artwork may be baked only into cleaned background/sprite assets; dynamic labels, controls, rows, science icons, timers, and tabs must remain live in the future Factorio GUI.
- Register only existing PNG files; every registered sprite path must be checked after generation.
- Keep Factorio data-stage code free of runtime APIs and validate new style fields against Factorio 2.0.
- This pass ends with the standalone demo and asset review checkpoint; live GUI integration waits for user feedback.

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

- [ ] **Step 1: Register only approved clean background and atomic sprites.**
- [ ] **Step 2: Replace the policy panel structure with named live elements matching the approved demo geometry.**
- [ ] **Step 3: Preserve existing policy model/event behavior while routing tab selection and controls to current handlers.**
- [ ] **Step 4: Run unit, parser, locale, production lint, and disposable in-game checks, then perform an actual in-game visual smoke test.**
