After each edit:
- double check everything added against Factorio API
- double check function hoisting or ordering is correct
- double check visibility of functions and such
- double check there is no nulls that will happen during execution

Also check standard.md for coding standards



# DOX framework

- DOX is highly performant AGENTS.md hierarchy installed here
- Agent must follow DOX instructions across any edits

## Core Contract

- AGENTS.md files are binding work contracts for their subtrees
- Work products, source materials, instructions, records, assets, and durable docs must stay understandable from the nearest applicable AGENTS.md plus every parent AGENTS.md above it

## Read Before Editing

1. Read the root AGENTS.md
2. Identify every file or folder you expect to touch
3. Walk from the repository root to each target path
4. Read every AGENTS.md found along each route
5. If a parent AGENTS.md lists a child AGENTS.md whose scope contains the path, read that child and continue from there
6. Use the nearest AGENTS.md as the local contract and parent docs for repo-wide rules
7. If docs conflict, the closer doc controls local work details, but no child doc may weaken DOX

Do not rely on memory. Re-read the applicable DOX chain in the current session before editing.

## Update After Editing

Every meaningful change requires a DOX pass before the task is done.

Update the closest owning AGENTS.md when a change affects:

- purpose, scope, ownership, or responsibilities
- durable structure, contracts, workflows, or operating rules
- required inputs, outputs, permissions, constraints, side effects, or artifacts
- user preferences about behavior, communication, process, organization, or quality
- AGENTS.md creation, deletion, move, rename, or index contents

Update parent docs when parent-level structure, ownership, workflow, or child index changes. Update child docs when parent changes alter local rules. Remove stale or contradictory text immediately. Small edits that do not change behavior or contracts may leave docs unchanged, but the DOX pass still must happen.

## Hierarchy

- Root AGENTS.md is the DOX rail: project-wide instructions, global preferences, durable workflow rules, and the top-level Child DOX Index
- Child AGENTS.md files own domain-specific instructions and their own Child DOX Index
- Each parent explains what its direct children cover and what stays owned by the parent
- The closer a doc is to the work, the more specific and practical it must be

## Child Doc Shape

- Create a child AGENTS.md when a folder becomes a durable boundary with its own purpose, rules, responsibilities, workflow, materials, or quality standards
- Work Guidance must reflect the current standards of the project or user instructions; if there are no specific standards or instructions yet, leave it empty
- Verification must reflect an existing check; if no verification framework exists yet, leave it empty and update it when one exists

Default section order:
- Purpose
- Ownership
- Local Contracts
- Work Guidance
- Verification
- Child DOX Index

## Style

- Keep docs concise, current, and operational
- Document stable contracts, not diary entries
- Put broad rules in parent docs and concrete details in child docs
- Prefer direct bullets with explicit names
- Do not duplicate rules across many files unless each scope needs a local version
- Delete stale notes instead of explaining history
- Trim obvious statements, repeated rules, misplaced detail, and warnings for risks that no longer exist

## Closeout

1. Re-check changed paths against the DOX chain
2. Update nearest owning docs and any affected parents or children
3. Refresh every affected Child DOX Index
4. Remove stale or contradictory text
5. Run existing verification when relevant
6. Report any docs intentionally left unchanged and why

## User Preferences

When the user requests a durable behavior change, record it here or in the relevant child AGENTS.md

## Project Overview

LilEinstein is a Factorio 2.0 mod (base >= 2.0.77): a science-aware research autopilot with strategy profiles, supply forecasting, lab-cluster scheduling, queue budgets, repeat policies, plan presets, and multiplayer controls. Architecture is Control -> lib -> model -> view per `standard.md`.

Root-owned (no child doc):

- `control.lua` — runtime entry point: inits `storage`/`storage.forces`/`storage.players`, wires lifecycle and lab-membership events, and advances bounded per-open-force display jobs plus non-destructive Upcoming refreshes on staggered `on_nth_tick` schedules; it has no heavyweight `on_tick` work
- `data.lua`, `settings.lua`, `info.json`, `changelog.txt`, `locale/` (de, en, fr, pt-PT), `migrations/` (version migration scripts)
- `standard.md` — coding standard: naming, data model, module order; binding for all Lua edits
- `RESEARCH_AUTOPILOT_IMPLEMENTATION.md` — maintainer/tester notes for the research-autopilot branch
- `docs/_human/raw_request_log.md` — append-only verbatim record of user requests and project decisions
- `audit/` — GUI mockup reference assets; `scripts/import_ui_slices.ps1` regenerates `lib/ui_slices.lua` from them
- `graphics/` — mod icons and UI sprite assets
- `output/` — generated output folder (currently `output/imagegen/`)
- `website/` — mod landing-page assets (`index.html`, `styles.css`, `script.js`, `assets/`)

## Child DOX Index

- `model/AGENTS.md` — runtime data model and autopilot logic: env, state, tech, queue, lab, research_policy, research_weights, cmd
- `view/AGENTS.md` — GUI layer: gui entry, builder, analyzer, gutil, components
- `lib/AGENTS.md` — foundation utilities: const, util, log, ui_slices
- `data/AGENTS.md` — data-stage prototypes: style, shortcut, sprites, signals
- `tests/AGENTS.md` — Lua unit, data/migration, GUI, and disposable in-game test contracts
