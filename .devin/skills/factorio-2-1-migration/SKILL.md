---
name: factorio-2-1-migration
description: "Factorio 2.0 to 2.1 mod migration reference from the official 2.1 changelog and Lua API docs. Use when porting a mod to Factorio 2.1, fixing 2.1 load/desync errors, updating info.json factorio_version, renaming removed Lua API methods, migrating recipe categories, fixing defines.inventory renames, handling fluidbox removal, or any 2.0->2.1 compatibility question. Covers breaking Scripting and Modding changes, new circuit control behaviors, quality value rescaling, science-pack-as-plain-item, and migration file requirements."
version: "1.0.0"
user-invocable: true
compatibility: Pure knowledge reference — no runtime, network, or env vars required.
metadata: {"hermes":{"tags":["factorio","lileinstein","migration","2.1","2.0","lua-api","modding","changelog"],"category":"game-modding"}}
---

# Factorio 2.0 -> 2.1 Migration Guide

Reference distillation of the official Factorio 2.1 changelog (first
stable release 2.1.7, cumulative through 2.1.17) and the live Lua API
docs. Use this when porting any mod from 2.0 to 2.1, diagnosing a 2.1
load/runtime error, or auditing code for removed/renamed APIs.

## Sources

- **Official changelog**: https://wiki.factorio.com/Version_history/2.1.0
  (2.1.7 is the first stable 2.1 release; it bundles all experimental
  2.1.0-2.1.6 changes. The Modding and Scripting sections of 2.1.7 are
  the authoritative migration list.)
- **Raw changelog.txt**: https://raw.githubusercontent.com/wube/factorio-data/master/changelog.txt
- **Lua API docs (2.1.17)**: https://lua-api.factorio.com/latest/
- **Migrations auxiliary doc**: https://lua-api.factorio.com/latest/auxiliary/migrations.html
- **Real-world port example**: https://github.com/Telkine2018/compaktcircuit/pull/64

## Migration checklist (do these first)

1. **`info.json`**: set `"factorio_version": "2.1"`.
2. **`dependencies`**: bump `"base >= 2.0.0"` to `"base >= 2.1.7"`
   (2.1.7 is the first stable 2.1; earlier 2.1.x were experimental).
3. **New dependency modifier `+`**: optional-but-recommended — mod is
   enabled by default but can be turned off. Use instead of `(? )` when
   you want default-on optional.
4. **Run a full grep** for every removed/renamed API in the Breaking
   Changes tables below.
5. **Add a migration file** if you renamed/removed prototypes or need to
   fix up `storage` references (see Migration Files below).
6. **Quality values**: if you define quality prototypes or read quality
   effect values, they were divided by 10 (see Quality Rescaling).

## Breaking changes — Scripting (runtime / control stage)

These will crash at runtime or silently misbehave. Grep your codebase
for the left column and replace with the right.

### LuaEntity (high-impact)

| Removed / renamed (2.0) | Replacement (2.1) | Notes |
|-------------------------|-------------------|-------|
| `LuaEntity::fluidbox` + `LuaFluidBox` | Direct `LuaEntity` fluid methods | All fluid interaction is now on `LuaEntity` itself — see Fluid API below |
| `LuaEntity::remove_fluid()` | `LuaEntity::extract_fluid()` | Renamed |
| `LuaEntity::set_fluid()` 2nd arg | Now mandatory; returns `FluidAmount` not `Fluid` | Signature change |
| `LuaEntity::active` (write) | `LuaEntity::disabled_by_script` | Inverted semantics: `disabled_by_script = true` means off |
| `LuaEntity::minable` (write) | `LuaEntity::minable_flag` | Write path renamed |
| `LuaEntity::neighbors` (read) | `fluidbox_neighbours`, `underground_belt_neighbour`, `wall_neighbours`, `cliff_neighbours`, `neighbour_connectable_connections` (+ existing `belt_neighbours`, `heat_neighbours`) | Split into specific neighbour types |
| `LuaEntity::pump_rail_target` (read) | `pump_input_rail_targets`, `pump_output_rail_targets` | Split into input/output |
| `LuaEntity::mining_progress` | `LuaControl::mining_progress` (read/write) | Moved to `LuaControl` |
| `LuaEntity::display_panel_text` `LocalisedString` | `string` only | LocalisedString no longer accepted |

### Fluid API (complete replacement)

`LuaEntity::fluidbox` and the `LuaFluidBox` object are **gone**. All
fluid interaction is now direct methods on `LuaEntity`:

```lua
-- 2.0
local box = entity.fluidbox[1]
local fluid = box.get_fluid()
box.set_fluid(fluid)

-- 2.1 (signatures verified against lua-api.factorio.com 2.1.17)
local fluid  = entity:get_fluid(index)        -- Fluid? (index = fluidbox index)
local amount = entity:set_fluid(index, fluid) -- FluidAmount (2nd arg now mandatory)
local added  = entity:add_fluid(index, fluid) -- FluidAmount
local removed= entity:remove_fluid(index, amount) -- Fluid?
local cleared= entity:clear_fluid(index)      -- Fluid? (clears one box)
local all    = entity:clear_fluids()          -- array[Fluid] (clears all)
local extracted = entity:extract_fluid{       -- FluidAmount (table arg)
  name = "water", amount = 100, temperature = 15
}
entity:get_fluid_capacity(...)                 -- capacity queries
entity:get_fluid_box_prototype(index)          -- LuaFluidBoxPrototype
entity:get_fluid_box_neighbours(index)         -- replaces fluidbox neighbours
entity:get_fluid_segment_fluid(index)          -- pipeline segment queries
entity:set_fluid_segment_fluid(index, fluid)
entity:get_fluid_filter() / entity:set_fluid_filter()
entity:has_fluid_segment()
```

### defines.inventory (consolidated crafter inventories)

The per-machine inventory defines were merged into generic `crafter_*`:

| Removed (2.0) | Replacement (2.1) |
|---------------|-------------------|
| `defines.inventory.assembling_machine_input` | `defines.inventory.crafter_input` |
| `defines.inventory.furnace_source` | `defines.inventory.crafter_input` |
| `defines.inventory.rocket_silo_input` | `defines.inventory.crafter_input` |
| `defines.inventory.assembling_machine_output` | `defines.inventory.crafter_output` |
| `defines.inventory.furnace_result` | `defines.inventory.crafter_output` |
| `defines.inventory.rocket_silo_output` | `defines.inventory.crafter_output` |
| `defines.inventory.assembling_machine_modules` | `defines.inventory.crafter_modules` |
| `defines.inventory.furnace_modules` | `defines.inventory.crafter_modules` |
| `defines.inventory.rocket_silo_modules` | `defines.inventory.crafter_modules` |
| `defines.inventory.assembling_machine_trash` | `defines.inventory.crafter_trash` |
| `defines.inventory.furnace_trash` | `defines.inventory.crafter_trash` |

### Control behaviors

| Removed / renamed (2.0) | Replacement (2.1) |
|-------------------------|-------------------|
| `LuaLogisticContainerControlBehavior::circuit_exclusive_mode_of_operation` | `set_requests` and `read_contents` (read/write booleans) |
| `defines.control_behavior.logistic_container.exclusive_mode` | removed |
| `LuaCargoLandingPadControlBehavior::circuit_exclusive_mode_of_operation` | `read_contents`, `set_requests` |
| `defines.control_behavior.cargo_landing_pad.exclusive_mode` | removed |
| `LuaAssemblingMachineControlBehavior::include_fuel` | `read_fuel` |
| `LuaFurnaceControlBehavior::include_fuel` | `read_fuel` |
| `LuaDisplayPanelControlBehavior::get_message/set_message/messages` | `add_record/remove_record/move_record/get_record/set_record`; `records` read/write; `max_records_count`, `records_count` reads |
| `defines.control_behavior.type.storage_tank` | `defines.control_behavior.type.single_fluid_box` |

### Prototype reads (removed/renamed)

| Removed (2.0) | Replacement (2.1) |
|---------------|-------------------|
| `LuaEntityPrototype::fluid_usage_per_tick` | `get_fluid_usage_per_tick()` |
| `LuaEntityPrototype::max_power_output` | `get_max_power_output()` |
| `LuaEntityPrototype::pumping_speed` | `get_pumping_speed()` |
| `LuaEntityPrototype::build_base_evolution_requirement` | removed |
| `LuaRecipePrototype::category`, `additional_categories` | `categories` |
| `LuaRecipe::category`, `additional_categories` | `categories` |
| `LuaRecipePrototype::is_parameter` | `LuaPrototypeBase::parameter` |
| `LuaRecipePrototype::show_amount_in_title`, `result_is_always_fresh`, `reset_freshness_on_craft`, `always_show_products` | removed (moved to `ItemProductPrototype` or dropped) |
| `LuaItemPrototype::inventory_size` | `get_inventory_size()` |
| `LuaItemPrototype::tile_filter_slots`, `entity_filter_slots` | removed (dynamic filter counts) |
| `LuaFluidBoxPrototype::volume` | `get_volume()` |
| `LuaRecord::is_blueprint_preview` | `is_preview` |
| `LuaPlayer::pipette_entity()` | `pipette()` |

### Other scripting removals/changes

- `LuaGameScript::create_profiler()` removed -> use
  `LuaHelpers::create_profiler()`.
- `LuaPlayer::get_quick_bar_slot` / `set_quick_bar_slot` now take
  **page index + slot index** (was a single slot index).
- `LuaPlayer::teleport()` no longer implicitly exits remote view.
- `defines.default_icon_size` renamed to
  `defines.constant.default_icon_size`.

## Breaking changes — Modding (data stage / prototypes)

### Recipe categories (high-impact)

`RecipePrototype::category` and `additional_categories` are **removed**.
Use `RecipePrototype::categories` (an array):

```lua
-- 2.0
recipe.category = "crafting"
recipe.additional_categories = {"chemistry"}

-- 2.1
recipe.categories = {"crafting", "chemistry"}
```

Base mod reworked categories: added `hand-crafting`; removed
`basic-crafting`, `recycling-or-hand-crafting`, `chemistry-or-cryogenics`,
`pressing`, `crafting-with-fluid-or-metallurgy`, `metallurgy-or-assembling`,
`organic-or-hand-crafting`, `organic-or-assembling`, `organic-or-chemistry`,
`electronics-or-assembling`, `electronics`, `electronics-with-fluid`,
`cryogenics-or-assembling`. The `recycling` category moved from base to
the recycler mod. If you reference any removed category, switch to
multiple `categories` entries.

### Science packs are now plain items

`TechnologyPrototype` and `LabPrototype` now accept **any item type** as
research ingredients. All science packs were changed to plain items (no
longer a special tool-with-drain type). Implications:
- `data.raw.tool["automation-science-pack"]` may no longer exist as a
  `tool` — check the item type.
- Mods that filter research ingredients by `type == "tool"` will miss
  packs; filter by `used_by_labs` read / `"used-by-labs"` item prototype
  filter instead.
- `ItemPrototype::lab_ignores_spoil_percent` added to control spoil
  behavior in labs.

### Quality value rescaling (high-impact)

- Quality effect values in prototype definitions were **divided by 10**.
- Quality effect percentages shown in GUIs are no longer multiplied by
  `next_probability` — GUI and Lua API values now match.
- `next_probability` values were multiplied by 10 (so 1.0 = 100%
  guarantee).
- `QualityPrototype::beacon_power_usage_multiplier` must now be >= 0.01.
- New: `chain_probability` (affects steps after the first),
  `previous_probability`, `previous_chain_probability`.
- New quality multipliers: `cargo_wagon_inventory_size_multiplier`,
  `locomotive_power_multiplier`, `rolling_stock_max_speed_multiplier`,
  `module_consumption_multiplier`, `module_speed_multiplier`,
  `module_productivity_multiplier`, `module_pollution_multiplier`,
  `module_quality_multiplier`, `spoil_ticks_multiplier`.

### Other notable prototype removals/renames

| Removed / renamed (2.0) | Replacement (2.1) |
|-------------------------|-------------------|
| `AssemblingMachinePrototype::enable_logistic_control_behavior` | EntityPrototypeFlag `"no-logistic-connection"` |
| `AsteroidPrototype::mass` | `damage_per_hp` |
| `CraftingMachinePrototype::forced_symmetry` | `use_mirroring` |
| `RecipePrototype::always_show_products`, `show_amount_in_title` | removed |
| `RecipePrototype::result_is_always_fresh` | `ItemProductPrototype::always_fresh` |
| `RecipePrototype::reset_freshness_on_craft` | `ItemProductPrototype::reset_freshness_on_craft` |
| `VehiclePrototype::braking_power`, `friction` | `braking_force`, `friction_force` |
| `EntityPrototype::build_base_evolution_requirement` | removed |
| `MapSettings::steering` | `UnitPrototype::steering`, `SpiderUnitPrototype::steering` |
| `SpacePlatformHubPrototype::dump_container` | removed |
| `FluidBox::hide_connection_info` | `PipeConnectionDefinition::hide_connection_info` |
| `DeconstructionItemPrototype::tile_filter_count`, `entity_filter_count` | removed (dynamic filter counts) |
| `LoaderPrototype::circuit_connector_layer` | `CircuitConnectorSprites::render_layer` |
| `RailSignalPictureSet::circuit_connector_render_layer` | `CircuitConnectorSprites::render_layer` |
| `CraftingMachineGraphicsSet::circuit_connector_layer` + `circuit_connector_secondary_draw_order` | `CircuitConnectorSprites::render_layer` + `secondary_draw_order` |
| `MiningDrillGraphicsSet::circuit_connector_layer` + `circuit_connector_secondary_draw_order` | `CircuitConnectorSprites::render_layer` + `secondary_draw_order` |
| Renamed recipe `"molten-iron"` | `"iron-ore-melting"` |
| Renamed recipe `"molten-copper"` | `"copper-ore-melting"` |
| `UtilityConstants::rocket_lift_weight` | `default_rocket_lift_weight` |
| `UtilityConstants::minimap_slot_clicked_tint`, `minimap_slot_hovered_tint` | removed |
| `StateSteeringSettings::force_unit_fuzzy_goto_behavior` | removed |
| `SteeringSettings::moving`, `default` | removed |
| `CargoLandingPadPrototype::robot_animation`, `robot_landing_location_offset`, `robot_opened_duration`, `robot_animation_sound` | moved to `CargoLandingPadPrototype::robot_door` |
| `LogisticContainerPrototype::animation`, `landing_location_offset`, `opened_duration`, `animation_sound` | moved to `LogisticContainerPrototype::robot_door` |
| `GeneratorPrototype::horizontal_animation`, `vertical_animation`, `horizontal_frozen_patch`, `vertical_frozen_patch` | moved to `GeneratorPrototype::pictures` |
| `MiningDrillPrototype::base_picture`, `base_render_layer` | moved to `working_visualisations` |
| `platform_surface_render_parameters` (on SpacePlatformHubPrototype) | moved to `SpaceLocationPrototype` |
| `ProductPrototype` | `ProductPrototypeBase` (with `independent_probability` replacing `ItemProductPrototype::probability` / `FluidProductPrototype::probability`) |

### SelectionModeFlags behavior change

`"blueprint"`, `"deconstruct"`, `"cancel-deconstruct"`, `"upgrade"`,
`"cancel-upgrade"` and `"downgrade"` no longer imply `"any-entity"` nor
`"any-tile"`. If you relied on that implication, add the flags
explicitly.

### CustomInput changes

- Removed extra `CustomInputEvent` for inputs that collide with the
  map-drag control.
- Removed support for deprecated/undocumented key names from
  `CustomInputPrototype::key_sequence` and `alternative_key_sequence`.

## New features (additive, 2.1)

### Circuit network (headline 2.1 feature)

New circuit-connectable entities and control behaviors:

- **Labs**: `LuaLabControlBehavior` — read contents, read current
  research cost, read technology level, **set current research** based on
  conditions. `LabPrototype::circuit_connector` etc. added.
- **Boilers / heat exchangers**: `LuaBoilerControlBehavior` —
  circuit-controllable on/off. `BoilerPrototype::circuit_connector` etc.
- **Heat pipes**: `LuaHeatPipeControlBehavior` — circuit network reads.
  `HeatPipePrototype::circuit_connector` etc.
- **Land mines**: `LuaLandMineControlBehavior` — trip wires interrupt
  circuit network. `LandMinePrototype::circuit_connector` etc.
- **Pipes / pipes-to-ground / storage tanks**: circuit network reads for
  pipeline contents and fluid temperature.
  `PipePrototype::circuit_connector`, `default_fluid_temperature_signal`.
- **Red/green wire split**: `LuaControlBehavior::input_networks` and
  `output_networks` (read/write) — separate red/green filtered
  inputs/outputs. Requester/buffer chests can set requests and read
  contents simultaneously.
- **Selector combinator "Time" mode**: read game tick, time of day, day
  length. `SelectorCombinatorPrototype::time_symbol_sprites` etc.
- **Radar "universe" mode**: cross-surface signal transfer.
  `LuaRadarControlBehavior::mode`, `universe_channel`.
- **Space platform hub**: set requests from circuit network.
  `LuaSpacePlatformHubControlBehavior::set_requests`.
- **Agricultural tower**: separate circuit controls for disabling
  harvesting vs planting.

New `defines.control_behavior.type`: `lab`, `boiler`, `land_mine`,
`heat_pipe`. New `defines.control_behavior.radar.mode`: `surface`,
`universe`.

### New events

- `on_blueprint_settings_pasted`
- `on_player_color_changed`
- `on_player_music_changed`
- `on_gui_inventory_action` (new GUI element type `"inventory"`)
- `on_next_day_started` (2.1.15+)

### New LuaGuiElement type

`"inventory"` — with `inventory`, `slots_per_row`, `empty_slot_info`,
`handle_cursor_transfer`, `handle_cursor_split`, `handle_open_item`,
`handle_open_mod_item`, `handle_send_stack_to_trash`,
`hand_send_stacks_to_trash` read/writes.

### New choose-elem-button types

`airborne-pollutant`, `ammo-category`, `quality`, `shortcut`,
`space-connection`, `surface`, `virtual-signal`.

### Other additive highlights

- `LuaNotificationQueue` + `LuaBootstrap::new_notification_queue()`.
- `LuaElectricNetwork` + `LuaElectricSubNetwork`; `LuaEntity::electric_network`.
- `LuaEntity::flip`, `protected`, `script_reservations_count`.
- `LuaEntity::tooltip_fields` API (`get/set/clear_tooltip_field(s)`).
- `LuaForce::add_alert`, `add_custom_alert`, `remove_alert`,
  `is_visible`, `set_script_visible`.
- `LuaForce::unlock_logistic_network`,
  `unlock_travel_to_space_platforms`, `cargo_landing_pad_limit`,
  `max_cargo_bay_unloading_distance`.
- `LuaPlayer::play_music` / `LuaForce::play_music` /
  `LuaGameScript::play_music` / `LuaSurface::play_music`.
- `LuaPlayer::saved_logistic_filters`, `respawn_quality`,
  `disable_space_map`.
- `LuaEntityPrototype::get_max_speed()`, `get_duration()`,
  `get_inventory_size_bonus()`.
- `LuaRecipePrototype::get_ingredient_quality()`, `get_product_quality()`,
  `get_product_amount()`, `can_set_quality`.
- `LuaStyle::get_style()` (sub-styles), `LuaStyle::name` write (set
  parent style).
- `LuaDebugAdapter` for DAP-compatible tools.
- `LuaHelpers::stage` read, `is_valid_ambient_sound()`,
  `is_valid_animation_path()`.
- `defines.inventory_actions`, `defines.electric_interface_mode`.
- `"expansion"` feature flag.
- Storage tank / cargo wagon / locomotive stats now scale with quality.
- `LuaGroup` replaced by `LuaItemGroup` + `LuaItemSubGroup` (2.1.15+).

## Migration files

Migration files (`.lua` or `.json` in the mod's `migrations/` folder)
fix up saves from older versions. Key rules (from the official
[migrations doc](https://lua-api.factorio.com/latest/auxiliary/migrations.html)):

- Sorted by mod order first, file name second (lexicographic). All JSON
  migrations run before any Lua migrations.
- Each save remembers applied migrations by name and won't re-apply.
- When adding a mod to an existing save, all its migration scripts run.
- JSON migrations rename prototypes. Renaming an entity prototype
  **keeps** `unit_number` and `storage` references; changing its
  **type** gives a new `unit_number` and invalidates `storage` refs.
- Removing a prototype invalidates any `storage` references to it.
- Ghosts that can't be migrated are removed.
- The game auto-resets recipes and technologies when mods/prototypes/
  startup settings change — migration scripts do **not** need to do this.

For a 2.0 -> 2.1 port, add a migration file only if you renamed or
removed prototypes, or need to fix `storage` references. A pure API
rename (e.g. `active` -> `disabled_by_script`) does **not** need a
migration file — it only affects code, not save data.

## LilEinstein-specific impact

LilEinstein (already on `factorio_version: "2.1"`, `base >= 2.1.0`)
was audited against this changelog. Findings:

- **No direct use** of the removed APIs (`fluidbox`, `active` write,
  `minable` write, `neighbors`, per-machine `defines.inventory`, etc.).
  The codebase uses `.category` / `.active` only on internal mod
  structures and GUI elements, not on Factorio API objects.
- **Science packs as plain items**: `model/tech.lua` and supply
  forecasting should filter research ingredients via `used_by_labs` /
  the `"used-by-labs"` prototype filter, not by `type == "tool"`.
- **Lab circuit control**: 2.1 native set-research and read-research-cost
  overlap with LilEinstein's autopilot. See companion skill
  `factorio-fff443-research-control` for the strategic analysis.
- **Worker-robot-speed de-prioritization**: landing-pad throughput
  removes the bot bottleneck; update `research_weights` for 2.1. See
  `factorio-abucnasty-science` and `factorio-fff443-research-control`.
- **`base` dependency**: consider bumping `base >= 2.1.0` to
  `base >= 2.1.7` to target the first stable 2.1 release.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Setting `factorio_version: "2.1"` but keeping `base >= 2.0.0` | Bump to `base >= 2.1.7` (first stable 2.1) |
| Using `recipe.category = "..."` in data stage | Use `recipe.categories = {"..."}` |
| Reading `entity.fluidbox[1]` at runtime | Use `entity:get_fluid_box_prototype(...)` / `entity:add_fluid(...)` / `entity:extract_fluid(...)` |
| Writing `entity.active = false` | Use `entity.disabled_by_script = true` (inverted) |
| Writing `entity.minable = false` | Use `entity.minable_flag = false` |
| Using `defines.inventory.assembling_machine_input` | Use `defines.inventory.crafter_input` |
| Filtering science packs by `type == "tool"` | Use `used_by_labs` read or `"used-by-labs"` prototype filter |
| Using `include_fuel` on assembler/furnace control behavior | Use `read_fuel` |
| Referencing removed recipe categories (`basic-crafting`, etc.) | Use multiple `categories` entries |
| Adding a migration file for a pure code API rename | Only needed for prototype renames/removals or `storage` fixups |
| Assuming quality effect values are the same scale | Values divided by 10 in 2.1; `next_probability` multiplied by 10 |
| Using `LuaPlayer::pipette_entity()` | Use `LuaPlayer::pipette()` |
| Using `LuaGameScript::create_profiler()` | Use `LuaHelpers::create_profiler()` |

## Companion skills

- `factorio-fff443-research-control` — 2.1 lab circuit control, set-
  research, read-research-cost, landing pad throughput, red/green wire
  split (strategic analysis)
- `factorio-abucnasty-science` — ESPM, infinite-tech caps, 2.1 meta
  shifts, worker-robot-speed de-prioritization
- `factorio-abucnasty-lab-design` — lab clocking, inserter patterns
- `factorio-mod-lint` — lint Factorio mods for runtime, migrations,
  storage/global issues, require paths

## Attribution

All API changes are sourced from the official Factorio 2.1 changelog
(wiki.factorio.com/Version_history/2.1.0, 2.1.7 Modding/Scripting
sections) and the live Lua API docs (lua-api.factorio.com/latest,
version 2.1.17). Real-world migration patterns cross-referenced against
the compaktcircuit 2.1 port PR.
