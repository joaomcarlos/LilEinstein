# Work-Conserving Science Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep research capacity productive by temporarily selecting any safe supplied technology when the chosen queue is pack-bound, and do not restore the chosen target until its incoming supply can sustain a meaningful research window.

**Architecture:** Preserve the explicit queue as the normal source. The starvation path scans it first, then advances through fixed-size scored slices of eligible technologies only when the queue has no supplied substitute. Inactive candidates and stored targets share a cached full-capacity estimate for physical demand and completion horizon. Cluster-mode recovery uses stock only from the sole compatible consuming scope, while one availability/forecast/scope snapshot is reused across each bounded slice.

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

- [x] **Step 3: Implement the emergency fallback**

  Forward-declare a starvation fallback helper near the existing queue helpers. In `check_and_switch_temp_research`, preserve pinned/explicit order first; only after that source yields nothing, advance a persistent fixed-size technology cursor, score the runnable candidates in that slice, and store the original target unchanged.

- [x] **Step 4: Run the focused test and verify GREEN**

  Run: `lua52 .\tests\queue_core_spec.lua`

  Expected: the new alternate is selected and applied first.

### Task 2: Demand-aware restoration

**Files:**
- Modify: `model/queue.lua`
- Test: `tests/queue_core_spec.lua`

**Interfaces:**
- Consumes: bounded `lab.get_runtime_lab_content(force_index)`, `get_lab_science_consumption_spm`, `queue.get_science_forecast`, and `forecast_seconds`.
- Produces: cached per-science physical demand and research capacity for the active target, plus a projected recovery decision over that target's own horizon.

- [x] **Step 1: Write the failing timeout regression**

  Model a 100x-speed lab, a target needing 6,000 packs/minute, ten idle packs, no production, an active supplied alternate, and an expired timeout. Assert the target remains insufficient, the alternate remains active, and its timeout is extended without a redundant reselection request.

- [x] **Step 2: Run the focused test and verify RED**

  Run: `lua52 .\tests\queue_core_spec.lua`

  Expected: FAIL because the inactive target is currently considered sufficient from coarse inventory state.

- [x] **Step 3: Add the target-demand projection**

  Cache required physical pack rates and expected capacity from valid compatible runtime labs. For inactive technology supply, require `stock + production_per_minute * horizon / 60` to cover `demand_per_minute * horizon / 60`, using the same full-capacity estimate to cap the horizon at research completion. Keep the active technology on live missing-pack evidence.

- [x] **Step 4: Keep emergency candidate work bounded**

  Inspect a fixed-size scored technology slice per starvation check. Reuse one cluster-aware availability snapshot, forecast, and precomputed compatible-scope stock map while requiring each candidate's forecast sufficiency; once active, normal live PACK-BOUND evidence can replace an unsuitable temporary technology.

- [x] **Step 5: Require reachable stock in cluster mode**

  During recovery, require current stock in the sole compatible consuming scope to cover the target's forecast window. Do not count incompatible remote stock, force-wide production, packs still in transit, or one partial delivery as sustained ready lab supply.

- [x] **Step 6: Run focused tests and verify GREEN**

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

- [x] **Step 1: Convert the disposable scenario to the reported transition**

  Seed both LilEinstein's stored queue and Factorio's live queue with only the starved technology. Keep its unique pack in 5 of 275 labs and keep the alternate pack in all labs, so current progress is nonzero but about 1.8% of capacity. Do not pre-queue the alternate.

- [x] **Step 2: Assert the real scheduler result**

  Confirm the starved technology begins and makes nonzero progress, assert `LuaForce.current_research.name` becomes the supplied alternate after the normal sampler, switch, and reselection cadences, then continue beyond the minimum dwell and prove the low-stock target is not restored.

- [x] **Step 3: Run all verification gates**

  Run:

  - `lua52 .\tests\run_all.lua`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame`
  - production and test-harness Factorio-aware lint
  - `luac52 -p` across Lua sources
  - `git diff --check`

- [x] **Step 4: Complete the DOX and independent review pass**

  Record the starvation-only fallback and demand-aware recovery contracts, verify no new unbounded scheduler work, and review Factorio API use, function ordering, nil guards, and unrelated dirty files.
