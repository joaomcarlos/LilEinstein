# tests/

## Purpose

Focused Lua 5.2 unit tests and disposable Factorio smoke tests for LilEinstein's
runtime, data-stage, migration, queue, policy, lab, and GUI contracts.

## Ownership

- `testlib.lua` — shared assertions, module isolation, and suite runner.
- `run_all.lua` — canonical local suite entry point.
- `*_spec.lua` — focused public-seam tests; queue, policy, lab, model, view, data,
  migration, translation, and GUI guard contracts are kept in separate suites.
- `coverage.lua` — line-hit instrumentation used by `scripts/measure_coverage.ps1`.
- `factorio/` — disposable test-only mod and its local DOX contract.

## Local Contracts

- Tests exercise public interfaces with explicit, narrow Factorio stubs; private
  implementation details are not imported solely to make assertions possible.
- Tests must distinguish an idle force from an actively researching force.
- Active science-switch regressions exercise `queue.check_and_switch_temp_research` with a live current technology, lab starvation evidence, and a supplied alternate candidate; do not test only the lower-level science predicate.
- Starvation fallback regressions keep the explicit queue at one pack-bound technology and place the supplied alternate outside it; recovery regressions prove a small idle buffer cannot satisfy a high-demand target.
- Emergency fallback regressions cap per-check technology and availability work, reject a long available-but-forecast-insufficient alternate, accept a finite alternate stocked to completion, preserve compatible-scope cluster attribution, and prove that incompatible remote stock, force-wide production, and a one-time partial delivery cannot restore a target before enough local stock is reachable.
- Throughput GUI/model regressions cover fixed-width cluster rows, deterministic lab descriptors, and the affected-lab inspection transition.
- Science-pack inspector regressions cover lazy world scans, Nauvis-only lab rows, per-planet stock including zero values, in-transit platform stock, stable row refreshes, and the open-panel countdown seam.
- Transit forecast regressions preserve per-pack cargo-pod totals while asserting that a bounded refresh scans cargo pods once per surface rather than once per science pack.
- Debug-report tests cover deterministic report sections, the live GUI-details snapshot seam, and the copy-ready, selected text-box modal seam.
- GUI crash regressions cover invalid report-text lifecycle access and label-only style writes on button elements.
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
