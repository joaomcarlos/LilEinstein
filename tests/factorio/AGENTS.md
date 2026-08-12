# tests/factorio/

## Purpose

Disposable Factorio test mod used to exercise LilEinstein's production runtime in an isolated save.

## Ownership

- `lil-einstein-test_0.1.0/` — test-only Factorio mod and runtime assertions.

## Local Contracts

- This mod is never copied into a player's normal mod directory.
- Runtime output is written only through Factorio's `helpers.write_file` into the runner-owned `script-output` directory.
- Assertions must observe public LilEinstein module behavior or initialized storage.
- A read-only production bridge is permitted only when gated on the active test
  mod and must be absent from normal saves.

## Work Guidance

- Keep the test save disposable and bounded.
- Use Factorio 2.0.77+ runtime APIs and guard optional module-load paths with assertions that produce useful output.

## Verification

- Run `powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame` from the repository root.

## Child DOX Index

None.
