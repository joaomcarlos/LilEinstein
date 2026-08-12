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
- Data-stage and migration tests execute against isolated `data`/`game` doubles.
- In-game checks must use the disposable runner and must not open or mutate a
  player save.
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
