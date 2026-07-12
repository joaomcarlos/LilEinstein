# LilEinstein Research Autopilot - Implementation Notes

This document summarizes what was implemented on the `codex/research-autopilot` branch.
It is for maintainers and testers only. Factorio does not load this file.

## Scope

The branch turns LilEinstein from a basic queue helper into a research autopilot that can reason about the queue, science supply, future tech ordering, and player policy settings at the same time.

The implementation was built around four goals:

- Make research decisions based on actual availability instead of a shallow next-tech picker.
- Give players a control center for policy, budgets, presets, and manual objectives.
- Keep the mod safe when imports, migrations, or queue snapshots contain bad data.
- Preserve Factorio runtime safety so GUI refreshes and research events do not crash the game.

## Research Selection

The queue engine now scores technologies instead of treating the queue as a simple list.

Strategy profiles were added so the player can steer the queue toward different goals:

- Cheapest-first progression.
- Unlock-focused progression for recipes and core milestones.
- Logistics, combat, and space progression.
- Spoilable-science and productivity-oriented progression.
- Focused targets when the player wants a narrow set of technologies.

The score also includes science priorities, repeat rules, user overrides, and tech-specific availability state. That means the branch can prefer efficient techs without losing the ability to respect manual priorities.

## Science Supply and Forecasting

The mod now tracks science as a supply problem, not just a count on hand.

It calculates:

- Science present in labs.
- Science moving through logistic networks.
- Science available by cluster when multiple labs share the same usable input network.
- Forecasts for production, consumption, and depletion.

Cluster mode is important here. A technology is only treated as supplied when the required science packs exist together in the same usable cluster and at least one lab in that cluster can accept all required packs. That avoids overestimating supply when packs are spread across unrelated inputs.

The implementation also keeps a separate limitation in mind: Factorio does not expose belt or chest connectivity as a real lab supply graph. Direct-fed labs are therefore evaluated individually until packs are actually in the lab input inventories. Production and consumption data is aggregated across all loaded force surfaces, which means science produced on other planets and shipped back in is counted. Projected-starvation switching only uses those rates when cluster enforcement is disabled.

## Queue Budgets and Repeat Rules

The branch adds a queue budget view that estimates how much research is planned and where the queue is likely to stop.

It now understands:

- Finite repeat plans, including once and to-level behavior.
- Continuous or global infinite-tech plans that should be treated as unbounded.
- Truncated views for large trees so the budget display stays readable.
- The limiting science that is most likely to block the current plan.

Planning pause is also enforced immediately. When the user enables it, the queue is trimmed back to the research that is already running instead of allowing additional technologies to start.

## Parallel Research

The branch adds a dedicated parallel-research toggle.

When enabled, Little Einstein can time-slice the top planned technologies so several research targets make progress together without changing the total science cost logic. If the external Parallel Research mod is installed, Little Einstein switches into a support role: it supplies and orders the queue while that mod owns the actual lab distribution.

This was implemented with two safeguards:

- Only technologies that are actually queueable and currently researchable are sent forward.
- The integration respects the configured parallel slot limit instead of pushing speculative future descendants.

## Presets, Import, and Multiplayer

The control center now supports named plan presets and compact import/export strings.

That part of the branch does three things:

- Saves and loads research plans by name.
- Exports and imports plan snapshots in a compact text form.
- Rejects malformed or incompatible data instead of accepting a half-valid plan.

Multiplayer governance was tightened at the same time. Non-admin players cannot mutate force-wide research settings, queue order, or plan state when the multiplayer lock is active. The shared change history is preserved so the team can see who changed the plan and when.

## GUI and Presentation

The branch includes the new control center and the updated research screens:

- Strategy, budget, science policy, trigger objectives, preset management, and history are separated into dedicated sections.
- The main research window keeps the science summary, upcoming queue, available technologies, and graph view together.
- The research graph was rebuilt around stable children and explicit sizing so refreshes can redraw without depending on stale widget indexes.
- The upcoming list and science buttons use live tooltips and per-item progress state instead of static placeholder text.

There was also a layout correction for the top master-enable area. The action button was being squeezed beside the toggle label, which caused visual clipping in the main window. The row was split so the button has its own line and no longer overlaps the graph area.

## Safety Hardening

Several parts of the branch were hardened specifically to avoid runtime crashes:

- Queue imports now validate structure, size, and item types before they touch live state.
- Migrations check table shape before reading queue fields.
- `on_load` no longer writes to storage.
- GUI helpers check that the player, anchor, and child element exist before mutating them.
- Multiplayer event handlers reject forbidden queue changes before they can desync the game state.
- Technology-trigger handling checks the relevant prototype type before building tooltips or sprites.

That hardening is deliberate. The mod should fail cleanly on bad input rather than partially mutating game state and leaving the save in a broken state.

## Validation

The branch was checked with:

- `luac52 -p` on the edited Lua files.
- The Factorio mod linter from the local Factorio skill set.
- A runtime smoke test against a live save.

The mod targets Factorio 2.0.77 and later 2.0 releases. A separate 2.1-validated package should be treated as a distinct artifact because the manifest and API assumptions are not automatically interchangeable.

## Notes for Future Work

The branch is now in a good place for testing and iteration, but the following assumptions still matter:

- Cluster mode depends on the limits of the Factorio API for lab supply visibility.
- Force-wide flow data is not enough to attribute production to a specific lab cluster.
- Large overhaul trees may still need performance mode enabled if the player wants slower but lighter policy scans.

If you need the exact implementation history, the git branch and commit log are still the source of truth. This document is the human-readable summary.
