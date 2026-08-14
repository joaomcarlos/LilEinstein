# Starved Temporary Research Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure a pack-bound temporary technology cannot indefinitely retain the research slot when both its original target and itself are starved but another runtime candidate is supplied.

**Architecture:** Keep live lab starvation as the authority for the active technology. When an expired temporary slot is itself insufficient, fall through to the existing supplied-candidate scan instead of extending the timeout; preserve the original target while replacing only the temporary technology.

**Tech Stack:** Factorio 2.0 control-stage Lua 5.2, the public `queue.check_and_switch_temp_research` seam, and the disposable Factorio 2.0.77+ test runner.

## Global Constraints

- Preserve all unrelated dirty-worktree changes.
- Use only Factorio 2.0 runtime APIs and save-safe values.
- Follow `standard.md` names and Control -> lib -> model -> view dependency order.
- Do not weaken pinned, focused-mode, explicit-queue, or minimum-switch protections.
- Verify the player-visible switch, not only the PACK-BOUND diagnostic.

---

### Task 1: Replace a starved temporary technology

**Files:**
- Modify: `tests/queue_core_spec.lua`
- Modify: `model/queue.lua`

**Interfaces:**
- Consumes: `queue.check_and_switch_temp_research(f)` and staggered `lab.get_runtime_lab_content(force_index)` observations.
- Produces: existing `target_tech` remains the original target; `temp_tech` becomes a supplied third candidate; `state.request_next_research(f)` is requested once.

- [x] **Step 1: Write the failing public-seam regression**

Create an active `research-productivity-62` fixture whose one sampled compatible lab reports `missing_science_packs` for `agricultural-science-pack`. Keep its original target dependent on another unavailable pack, and place a third technology requiring only `available-pack` in the virtual queue. Call `queue.check_and_switch_temp_research(force)` after the temporary timeout and assert literal state:

```lua
t.assert_equal(storage.forces[1].queue.target_tech, "original-target")
t.assert_equal(storage.forces[1].queue.temp_tech, "supplied-alternate")
t.assert_equal(requests, 1)
```

- [x] **Step 2: Run the canonical unit suite and verify RED**

Run: `lua52 .\tests\run_all.lua`

Expected: the new queue-core case fails because `temp_tech` remains `research-productivity-62` and the expired timeout is extended.

- [x] **Step 3: Implement the minimal expired-temporary transition**

In `queue.check_and_switch_temp_research`, extend an expired temporary timeout only while the temporary technology remains science-sufficient. If it is pack-bound, fall through to the existing candidate scan. When that scan selects a replacement, retain an existing valid `target_tech` rather than overwriting it with the starved temporary name.

- [x] **Step 4: Verify GREEN and the complete runtime contract**

Run:

```powershell
lua52 .\tests\run_all.lua
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame
```

Expected: all unit tests pass; the disposable Factorio suite reports every in-game assertion passing and exits without LilEinstein runtime errors.

- [x] **Step 5: Review DOX and production safety**

Re-read the root, model, and tests contracts; confirm the existing model contract already describes supplied-alternate switching, so no AGENTS.md update is required. Inspect the final diff for Lua 5.2 syntax, function ordering/visibility, nil guards, and unrelated edits.

### Task 2: Persist bounded lab-sampler progress

**Files:**
- Modify: `tests/lab_spec.lua`
- Modify: `model/lab.lua`

**Interfaces:**
- Consumes: `storage.lab.current_force_idx`, `storage.lab.current_lab_idx`, and `lab.tick_update()`'s existing per-call budget.
- Produces: each scheduler call resumes after the last sampled lab, so a factory larger than one batch receives fresh observations across successive calls.

- [x] **Step 1: Write the minimal cross-call progress regression**

Register 75 labs while seven science types cap one update at 74 labs. Assert lab 1 is unsampled after the first update and has `latest_tick == 84` after the second update.

- [x] **Step 2: Run the focused lab suite and verify RED**

Run: `lua52 .\tests\lab_spec.lua`

Expected: lab 1 remains unsampled because both calls restart at lab 75.

- [x] **Step 3: Persist the advanced cursors**

After each bounded iteration advances the local lab/force indexes, store both indexes back into `storage.lab` before either the early full-pass return or the rate-limit exit.

- [x] **Step 4: Verify GREEN without increasing work per tick**

Run `lua52 .\tests\lab_spec.lua` and `lua52 .\tests\run_all.lua`. Confirm the first call still samples exactly 74 of 75 labs and the second call resumes at lab 1.

### Task 3: Prove the switch in disposable Factorio

**Files:**
- Create: `tests/factorio/lil-einstein-test_0.1.0/data.lua`
- Modify: `tests/factorio/lil-einstein-test_0.1.0/control.lua`
- Modify: `scripts/run_tests.ps1`
- Modify: `tests/factorio/AGENTS.md`

**Interfaces:**
- Consumes: Factorio's `script_raised_built`, writable `LuaForce.research_queue`, and read-only `LuaForce.current_research` APIs.
- Produces: a disposable 275-lab runtime scenario whose result file is written only after bounded sampling and research reselection have advanced.

- [x] **Step 1: Add the delayed in-game switch assertion**

Define a void-powered test lab plus starved/supplied technologies. Create 275 labs through `raise_built`, put only the alternate pack in them, queue the starved technology first, and assert after the scheduler window that `force.current_research.name` is the supplied alternate.

- [x] **Step 2: Verify the existing runner is RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame -TimeoutSeconds 15` before adding the server launch. Expected: timeout waiting for the delayed result because `--create` does not advance ticks.

- [x] **Step 3: Start only the runner-owned save headlessly**

Launch Factorio with `--start-server` against the disposable save using `Start-Process -WindowStyle Hidden`, retain its process handle, and keep all config, mods, save, log, and output paths under the runner's temporary stage.

- [x] **Step 4: Verify the authoritative current research changed**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame`. Expected: all unit checks plus the live 275-lab switch assertion pass.
