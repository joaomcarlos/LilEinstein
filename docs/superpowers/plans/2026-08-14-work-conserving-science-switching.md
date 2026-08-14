# Work-Conserving Science Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep research capacity productive by temporarily selecting any safe supplied technology when the chosen queue is pack-bound, and do not restore the chosen target until its incoming supply can sustain a meaningful research window.

**Architecture:** Preserve the explicit queue as the normal source. The starvation path scans it first, then performs a scored all-technology emergency fallback only when the queue has no supplied substitute. Inactive candidates and stored targets are evaluated against their own physical pack demand over the configured forecast horizon, using existing bounded lab observations and force science-flow forecasts.

**Tech Stack:** Factorio 2.0.77 runtime API, modified Lua 5.2, existing `model.queue`, Lua public-seam tests, disposable headless Factorio harness.

## Global Constraints

- Do not permanently add emergency fallback technologies to the stored manual queue.
- Preserve pins, avoid policies, runtime-candidate exclusions, target restoration, and the minimum switch dwell.
- Calculate physical pack demand without research-productivity bonuses.
- Use the existing bounded lab registry/content; do not add world scans or heavyweight `on_tick` work.
- Verify the authoritative `LuaForce.current_research`, not only `storage.temp_tech`.

---

### Task 1: Starvation-only candidate fallback

**Files:**
- Modify: `model/queue.lua`
- Test: `tests/queue_core_spec.lua`

**Interfaces:**
- Consumes: `get_virtual_queue_source(force_index, tsx)`, `get_all_runtime_candidate_names(force_index, tsx)`, `find_runtime_candidate(...)`.
- Produces: an emergency source that searches scored eligible technologies only after the explicit source yields no supplied candidate.

- [x] **Step 1: Write the failing public-seam test**

  Model a current technology with a unique pack, 98% missing lab capacity and 2% working capacity, a stored queue containing only the current technology, and a supplied alternate outside that queue. Assert PACK-BOUND evidence, selected `temp_tech`, one reselection request, and the alternate first after forced runtime reorder.

- [x] **Step 2: Run the focused test and verify RED**

  Run: `lua52 .\tests\queue_core_spec.lua`

  Expected: FAIL because `temp_tech` is `nil` while the bottleneck is present.

- [ ] **Step 3: Implement the emergency fallback**

  Forward-declare a starvation fallback source near the existing queue helpers. Define it beside `get_virtual_queue_source` so it can reuse the scored all-runtime-candidate list. In `check_and_switch_temp_research`, preserve pinned/explicit order first; only after that source yields nothing, scan the emergency source, skip duplicates/current, require the candidate's own supply projection, and store the original target unchanged.

- [ ] **Step 4: Run the focused test and verify GREEN**

  Run: `lua52 .\tests\queue_core_spec.lua`

  Expected: the new alternate is selected and applied first.

### Task 2: Demand-aware restoration and fallback filtering

**Files:**
- Modify: `model/queue.lua`
- Test: `tests/queue_core_spec.lua`

**Interfaces:**
- Consumes: bounded `lab.get_runtime_lab_content(force_index)`, `get_lab_science_consumption_spm`, `queue.get_science_forecast`, and `forecast_seconds`.
- Produces: per-science physical demand for an inactive technology and a projected stock sufficiency decision over its own research horizon.

- [x] **Step 1: Write the failing timeout regression**

  Model a 100x-speed lab, a target needing 6,000 packs/minute, ten idle packs, no production, an active supplied alternate, and an expired timeout. Assert the target remains insufficient, the alternate remains active, and its timeout is extended without a redundant reselection request.

- [x] **Step 2: Run the focused test and verify RED**

  Run: `lua52 .\tests\queue_core_spec.lua`

  Expected: FAIL because the inactive target is currently considered sufficient from coarse inventory state.

- [ ] **Step 3: Add the target-demand projection**

  Sum required physical pack rates across valid compatible runtime labs. For inactive technology supply, require `stock + production_per_minute * horizon / 60` to cover `demand_per_minute * horizon / 60`, with the horizon capped by configured forecast time and estimated research completion. Keep the active technology on live missing-pack evidence.

- [ ] **Step 4: Apply the same strict predicate to emergency candidates**

  A nominally stocked alternate that cannot sustain its projected demand must be skipped so the switcher does not trade one starvation loop for another.

- [ ] **Step 5: Run focused tests and verify GREEN**

  Run: `lua52 .\tests\queue_core_spec.lua`

### Task 3: Live low-throughput acceptance

**Files:**
- Modify: `tests/factorio/lil-einstein-test_0.1.0/control.lua`
- Modify if needed: `tests/factorio/lil-einstein-test_0.1.0/data.lua`
- Modify: `model/AGENTS.md`
- Modify: `tests/AGENTS.md`
- Modify: `tests/factorio/AGENTS.md`

**Interfaces:**
- Consumes: the production cadence and public test-only snapshot bridge.
- Produces: an authoritative live switch from a singleton pack-bound queue at low-but-nonzero progress.

- [ ] **Step 1: Convert the disposable scenario to the reported transition**

  Queue only the starved technology. Keep its unique pack in 5 of 275 labs and keep the alternate pack in all labs, so current progress is nonzero but about 1.8% of capacity. Do not pre-queue the alternate.

- [ ] **Step 2: Assert the real scheduler result**

  Confirm the starved technology begins and makes nonzero progress, then assert `LuaForce.current_research.name` becomes the supplied alternate after the normal sampler, switch, and reselection cadences.

- [ ] **Step 3: Run all verification gates**

  Run:

  - `lua52 .\tests\run_all.lua`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame`
  - production and test-harness Factorio-aware lint
  - `luac52 -p` across Lua sources
  - `git diff --check`

- [ ] **Step 4: Complete the DOX and independent review pass**

  Record the starvation-only fallback and demand-aware recovery contracts, verify no new unbounded scheduler work, and review Factorio API use, function ordering, nil guards, and unrelated dirty files.
