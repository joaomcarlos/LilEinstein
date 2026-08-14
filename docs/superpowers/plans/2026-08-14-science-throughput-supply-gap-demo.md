# Science Throughput Supply Gap Demo Implementation Plan

> **For agentic workers:** This plan is executed inline in the current shared checkout. The standalone demo is the approval gate; live Factorio GUI wiring is intentionally deferred until the user approves the demo.

**Goal:** Build an offline, sprite-backed demo of selected direction 2 (“Supply Gap Meter”) at the intended compact panel size, with deterministic asset crops and a visible sprite map so the user can approve the visual and asset treatment before any live GUI integration.

**Architecture:** Use the selected generated image as the authoritative visual reference, but keep it as reference-only artwork. Prepare a cleaned panel background and atomic sprite assets with a deterministic Pillow script. Render the live sample rows, status states, exact rates, gap meters, bottleneck action, heuristic result, and sprite inspector in a standalone HTML/CSS/JavaScript demo. After approval, reuse the measured asset contract in `data/sprites.lua`, `data/style.lua`, `view/gui/builder.lua`, and `view/gui/components.lua`; do not wire production Lua in this pass.

**Tech Stack:** Python 3 + Pillow for deterministic PNG crops/validation, standalone offline HTML/CSS/JavaScript, Factorio 2.0.77+ source PNGs, existing LilEinstein status/UI PNGs.

## Global Constraints

- Preserve all existing uncommitted user changes; do not touch `diagnostics/` or unrelated files.
- Use the corrected selected reference path `C:\Users\silent\.codex\generated_images\019fff9b-3fe8-7961-aaec-20ebdd484c8a\exec-7d98ae5f-a78a-47a6-97be-8bc33630875c.png` as the visual target.
- Use a compact `1120 × 680` design canvas; the prototype may scale down responsively but must not introduce horizontal scrolling at the target size.
- Treat the Factorio science-pack files as packed sprites: each source is `120 × 64`, and only `[0, 0, 64, 64]` is the primary icon crop for this prototype.
- Use real source art for science packs and status indicators. Do not replace sprites with emoji, inline SVG, handcrafted SVG, CSS drawings, or placeholder glyphs.
- Keep the demo clearly marked as a prototype and offline. It must not require npm, a backend, persistence, or a Factorio process.
- The demo's “Analyze bottleneck” interaction is a visual heuristic simulation only; it must not claim to calculate live production or delivery data.
- This pass ends with the standalone demo, the sprite map, and a verification note for user approval. Production Lua/data-stage changes wait for approval.

---

### Task 1: Freeze the sprite and layout contract

**Files:**
- Modify: `docs/_human/raw_request_log.md`
- Modify: `AGENTS.md`
- Create: `output/science-throughput-demo/asset-plan.json`
- Create: `output/science-throughput-demo/README.md`
- Reference: `C:\Users\silent\.codex\generated_images\019fff9b-3fe8-7961-aaec-20ebdd484c8a\exec-7d98ae5f-a78a-47a6-97be-8bc33630875c.png`

**Interfaces:**
- `asset-plan.json` records source paths, target dimensions, clear regions, crop rectangles, output names, display dimensions, and future Factorio consumers.
- `README.md` explains how to run the demo, the packed-icon crop rule, the sprite atlas contract, and the boundary between prototype and live mod work.

- [x] **Step 1: Append the user's request verbatim to the append-only request log.** Keep prior entries unchanged.
- [x] **Step 2: Record the `1120 × 680` canvas and the selected reference dimensions.** Treat the reference's current 1610 × 977 ratio as visual guidance, not the runtime canvas.
- [x] **Step 3: Record every sprite source and crop.** Pack icons use the first 64 × 64 cell from the 120 × 64 Factorio source; status icons retain their native 26/32-pixel dimensions and are displayed at 24/26 pixels.
- [x] **Step 4: Record dynamic regions.** Header, warning strip, table rows, meters, status labels, diagnostic drawer, sprite inspector, and footer legend remain live HTML in the demo and live Lua elements later.

### Task 2: Prepare and validate deterministic sprite assets

**Files:**
- Create: `scripts/prepare_science_throughput_demo_assets.py`
- Create: `output/science-throughput-demo/assets/supply-gap-background-clean.png`
- Create: `output/science-throughput-demo/assets/science-automation.png`
- Create: `output/science-throughput-demo/assets/science-logistic.png`
- Create: `output/science-throughput-demo/assets/science-military.png`
- Create: `output/science-throughput-demo/assets/science-chemical.png`
- Create: `output/science-throughput-demo/assets/science-production.png`
- Create: `output/science-throughput-demo/assets/science-utility.png`
- Create: `output/science-throughput-demo/assets/science-space.png`
- Create: `output/science-throughput-demo/assets/status-bottleneck.png`
- Create: `output/science-throughput-demo/assets/status-starved.png`
- Create: `output/science-throughput-demo/assets/status-balanced.png`
- Create: `output/science-throughput-demo/assets/status-overproducing.png`
- Create: `output/science-throughput-demo/assets/sprite-atlas-preview.png`
- Create: `output/science-throughput-demo/assets/sprite-manifest.json`

**Interfaces:**
- `prepare_science_throughput_demo_assets.py --plan output/science-throughput-demo/asset-plan.json` reads only declared source files and writes only declared outputs.
- The script fails when a source is missing, a packed icon is not at least 120 × 64, a crop is outside the source, or an output has an unexpected size.
- `sprite-manifest.json` exposes each sprite's source, crop box, atlas cell, output file, display size, and future Factorio sprite name.

- [ ] **Step 1: Copy the selected reference into the plan as a read-only source and clean only the live-content rectangles.** Preserve the industrial frame and warning-strip surface while removing baked title, sample rows, meters, labels, and footer note from the prototype background.
- [ ] **Step 2: Crop the first 64 × 64 cell from each Factorio science-pack source.** Never use the trailing packed variants in the 120 × 64 file.
- [ ] **Step 3: Copy existing LilEinstein status sprites without resampling.** Map `no_science_medium.png` to bottleneck, `blocked_medium.png` to starved, `progress_medium.png` to balanced, and `progress_smart_medium.png` to overproducing for prototype review.
- [ ] **Step 4: Build a transparent 4 × 3, 64-pixel-cell atlas preview from those real crops.** Center the 32-pixel status sprites in their cells and record all slots in `sprite-manifest.json`.
- [ ] **Step 5: Inspect the crop output at 100% and verify there are no trailing miniature icons, clipped alpha edges, or incorrect status mappings.**

### Task 3: Build the standalone interactive demo

**Files:**
- Create: `output/science-throughput-demo/index.html`
- Create: `output/science-throughput-demo/demo.css`
- Create: `output/science-throughput-demo/demo.js`
- Use: `output/science-throughput-demo/assets/*`

**Interfaces:**
- The page renders one compact `1120 × 680` Supply Gap Meter panel with the selected visual hierarchy.
- `demo.js` owns in-memory row data and exposes three UI actions: `Analyze bottleneck`, `Close analysis`, and `Show sprite map`/`Close sprite map`.
- No action mutates persistent state or contacts a service.

- [ ] **Step 1: Build the panel shell and fixed column grid.** Use the cleaned industrial background asset, a warning strip, one header row, and one scroll-free body at the target canvas size.
- [ ] **Step 2: Render real cropped science icons and status icons.** Keep the data columns exact: Science pack, Need / min, Used / min, Produced / min, Supply gap meter, Status.
- [ ] **Step 3: Render realistic states.** Put automation first as the dominant bottleneck, logistic second as starving, military as balanced, and the remaining packs as overproducing with the required asterisk in the status copy.
- [ ] **Step 4: Wire the opt-in heuristic simulation.** Clicking `Analyze bottleneck` opens a compact inline diagnostic strip stating that the sample factory output is sufficient but the delivery path is lagging; clicking again closes it. Do not imply live calculation.
- [ ] **Step 5: Wire the sprite-map inspector.** The inspector shows the atlas preview and a compact source/crop table so the user can approve the cut strategy without changing the production-facing panel.
- [ ] **Step 6: Add responsive scaling only as a wrapper.** At `1120 × 680`, the design must be 1:1; smaller viewports may scale the whole panel but must not reflow columns into a different design.

### Task 4: Run and verify the approval demo

**Files:**
- Create: `output/science-throughput-demo/verification.md`

- [ ] **Step 1: Run the asset-preparation script and verify every declared output exists.** Check PNG dimensions and the manifest's crop/atlas coordinates.
- [ ] **Step 2: Start the offline demo with one command from `output/science-throughput-demo/`.** Keep the local preview available for the user in Codex Desktop.
- [ ] **Step 3: Verify the main panel at the target canvas.** Confirm no clipping, no horizontal scroll, readable values, correct row ordering, visible shortage/overproduction states, and correctly placed source icons.
- [ ] **Step 4: Verify both interactions.** Confirm the bottleneck drawer opens/closes and the sprite inspector opens/closes without changing the table layout.
- [ ] **Step 5: Record the verification boundary.** State explicitly that this proves visual layout and sprite crops only; the actual Factorio Lua/data-stage integration and live heuristic remain deferred.
- [ ] **Step 6: Present the demo for approval before touching `data/sprites.lua`, `data/style.lua`, `view/gui/builder.lua`, `view/gui/components.lua`, locales, or tests.**

### Task 5: After approval, integrate into the Factorio mod

**Files:**
- Modify: `data/sprites.lua`
- Modify: `data/style.lua`
- Modify: `view/gui/builder.lua`
- Modify: `view/gui/components.lua`
- Modify: relevant locale files
- Modify: focused GUI/model tests under `tests/`

- [ ] **Step 1: Register only approved atomic sprite crops and preserve Factorio's existing sprite naming conventions.**
- [ ] **Step 2: Replace the oversized nested throughput layout with the approved compact live table while keeping model reads separate from view construction.**
- [ ] **Step 3: Use physical consumption data for `Used / min`, not sampled working demand.**
- [ ] **Step 4: Add the per-pack status classifier and opt-in heuristic action behind bounded runtime work.**
- [ ] **Step 5: Add locale coverage and public-seam tests for width, status, interaction, and sprite-backed controls.**
- [ ] **Step 6: Run Lua tests, parse/lint, disposable Factorio checks, and a real in-game visual smoke test before claiming integration complete.**
