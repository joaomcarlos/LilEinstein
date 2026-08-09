# tests/

## Purpose

Focused Lua unit tests for the runtime queue and research-autopilot contracts.

## Ownership

- `queue_spec.lua` — lightweight Factorio-free regression coverage for queue recovery and current-research state.

## Local Contracts

- Tests exercise public model interfaces with explicit Factorio stubs.
- Tests must distinguish an idle force from an actively researching force.
- A regression test may remain red while it documents an unfixed player-visible bug; report that state explicitly.

## Work Guidance

- Run from the repository root with Lua 5.2: `lua52 .\tests\queue_spec.lua`.
- Keep stubs narrow and independent of the implementation formula under test.

## Verification

- `lua52 .\tests\queue_spec.lua`

## Child DOX Index

None.
