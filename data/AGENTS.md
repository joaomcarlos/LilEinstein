# data/

## Purpose

Data-stage prototype definitions, loaded via root `data.lua` in this order: `style`, `shortcut`, `sprites`, `signals`.

## Ownership

- `style.lua` — GUI style prototypes (largest file); referenced by name from `view/`
- `shortcut.lua` — toolbar shortcut prototype
- `sprites.lua` — sprite prototypes, including UI slices sourced from `lib/ui_slices.lua` and `graphics/`
- `signals.lua` — virtual signal prototypes

## Local Contracts

- Data stage only: no runtime API (`game`, `storage`) usage
- Style names defined here are contracts consumed by `view/gui/*`; renaming requires updating all view references

## Work Guidance

- Validate prototype fields against the Factorio 2.0 prototype API

## Verification

- No automated tests; verify the mod loads without data-stage errors

## Child DOX Index

None.
