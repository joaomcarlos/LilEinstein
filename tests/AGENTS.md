# tests/

## Purpose

Focused Lua 5.2 unit tests and disposable Factorio smoke tests for LilEinstein's
runtime, data-stage, migration, queue, policy, lab, and GUI contracts.

## Ownership

- `testlib.lua` — shared assertions, module isolation, and suite runner.
- `run_all.lua` — canonical local suite entry point.
- `*_spec.lua` — focused public-seam tests; queue, policy, lab, auto_switch, model,
  view, data, migration, translation, and GUI guard contracts are kept in separate suites.
- `coverage.lua` — line-hit instrumentation used by `scripts/measure_coverage.ps1`.
- `factorio/` — disposable test-only mod and its local DOX contract.

## Local Contracts

- Tests exercise public interfaces with explicit, narrow Factorio stubs; private
  implementation details are not imported solely to make assertions possible.
- Tests must save and restore every `queue.` function they stub; a missing restore corrupts all subsequent tests in the same suite by leaving a stub in place of the real function.
- Tests must distinguish an idle force from an actively researching force.
- Active science-switch regressions exercise `queue.check_and_switch_temp_research` with a live current technology, lab starvation evidence, and a supplied alternate candidate; do not test only the lower-level science predicate. Per-science material threshold regressions prove that a science missing from a trivial number of labs (below the per-pack lost-SPM threshold) does not block switching to a candidate that also uses that science. Partial-supply fallback regressions prove that when all candidates use at least one bottleneck science, the candidate with the fewest bottleneck sciences is selected, and a candidate with the same bottleneck count as the current technology is not selected. Score-margin regressions prove a clearly higher-scored candidate can interrupt a sufficient current research with the 1.15× margin. Tests that exercise the live bottleneck sampler must call `queue.invalidate_science_cache(1)` after `reset_runtime` when reusing the same `game.tick` and current technology name as a prior test, to avoid stale bottleneck cache hits.
- Stale-sampler regressions also keep a completed PACK-BOUND display snapshot and assert that the full switch path selects the supplied alternate when the bounded live sampler has not reached 80% fresh coverage. A stale same-technology PACK-BOUND snapshot (older than the 900-tick freshness window) is still honored while its replacement is building; a stale snapshot for a different technology or a non-pack-bound state is ignored.
- Starvation fallback regressions keep the explicit queue at one pack-bound technology and place the supplied alternate outside it; recovery regressions prove a small idle buffer cannot satisfy a high-demand target.
- Emergency fallback regressions cap per-check technology and availability work, reject a long available-but-forecast-insufficient alternate, accept a finite alternate stocked to completion, preserve compatible-scope cluster attribution, and prove that incompatible remote stock, force-wide production, and a one-time partial delivery cannot restore a target before enough local stock is reachable.
- AutoSwitch emergency detector regressions exercise `auto_switch.get_availability`, `auto_switch.get_missing_sciences`, and `auto_switch.invalidate` with valid, empty-inventory, frozen, unpowered, disabled, invalid, and mixed-pack labs; assert exact `with`/`allowing`/`fraction` counts, cache reuse within the bounded interval, explicit invalidation, force-refresh, and that a no-lab snapshot is not treated as starvation. A lab with an empty inventory still counts in the `allowing` denominator for every pack it accepts, so completely starved labs lower the availability fraction and flag the pack missing. Queue integration regressions exercise `queue.check_and_switch_temp_research` with the staggered sampler/display bottleneck stubbed empty so the direct-inventory fallback confirms a singleton queued pack-bound technology and switches to a supplied unqueued alternate, while an alternate that fails existing sufficiency is rejected.
- Throughput GUI/model regressions cover fixed-width cluster rows, capacity-versus-active semantics, depletion-horizon status classification, infinite runtime, stock/transit evidence, deterministic lab descriptors, and the affected-lab inspection transition. Utilization regressions prove `min(actual_spm, working_spm) / expected_spm` avoids false 100% when labs are idle, and `measured_utilization` retains the raw clamp. Upcoming wait_time regressions prove blocked technologies do not inflate the cumulative wait time of technologies behind them in the plan.
- Science-pack inspector regressions cover lazy world scans, Nauvis-only lab rows, positive stock per verified planet, pseudo-surface and unresolved-route filtering, in-transit platform stock, stable row refreshes, and the open-panel countdown seam.
- Transit forecast regressions preserve per-pack cargo-pod totals while asserting that a bounded refresh scans cargo pods once per surface rather than once per science pack.
- Debug-report tests cover deterministic report sections, the live GUI-details snapshot seam, and the copy-ready, selected text-box modal seam.
- GUI crash regressions cover invalid report-text lifecycle access and label-only style writes on button elements.
- GUI construction stubs require checkbox/radiobutton `state` to be a boolean in `add` property trees and may separately verify live-state synchronization.
- Data-stage and migration tests execute against isolated `data`/`game` doubles.
- In-game checks must use the disposable runner and must not open or mutate a
  player save.
- The disposable runner advances its isolated save on a loopback-only ephemeral server with auto-pause disabled and asserts `LuaForce.current_research` switches from a singleton-queued pack-bound technology to an unqueued supplied alternate after bounded sampling of 275 labs, while 5 supplied labs prove the original research still made low but nonzero progress; it then continues through the target-recovery timeout and proves the undersupplied target is not restored.
- A regression test may remain red while it documents an unfixed player-visible bug; report that state explicitly.

## Work Guidance

- Run the canonical local suite from the repository root with Lua 5.2:
  `lua52 .\tests\run_all.lua`.
- Run the measured unit coverage report with:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\measure_coverage.ps1`.
- Run the disposable Factorio suite with:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame`.
- The coverage report prints diagnostic Lua line-hook mappings and executable-line
  coverage; the executable metric excludes only compiler-mapped syntax-only
  lines such as closing `end`/table/call markers.
- Keep stubs narrow and independent of the implementation formula under test.

## Verification

- `lua52 .\tests\run_all.lua`
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame`

## Child DOX Index

None.
