--- AutoSwitch-style emergency science detector.
-- Owns the direct registered-lab inventory availability scan. Provides a fast,
-- bounded, cached emergency signal for the queue's active starvation decision
-- without replacing LilEinstein's forecast-aware candidate selection, explicit
-- queue authority, temporary target recovery, or UPS protections.
-- Callers pass lab_content and all_sciences as parameters; env is a top-level
-- fallback only, used when callers omit them.

local env = require("model.env")

local auto_switch = {}

-- Cache interval in ticks (1 second at 60 UPS). A queue maintenance pass reuses
-- one cached scan instead of scanning every lab repeatedly or once per candidate.
local cache_interval_ticks = 60

-- A science pack present in no more than this fraction of accepting labs is
-- materially pack-bound. Matches the AutoSwitchTechs emergency threshold: a
-- low but nonzero supply fraction still signals starvation.
local availability_threshold = 0.80

-- Module-local runtime cache: [force_index] = {tick = n, value = {...}}
-- Not persisted to storage; rebuilt on load. Save-safe by construction.
local availability_cache = {}

local get_runtime_lab_content = function(force_index)
    local forces = storage and storage.forces
    local force_store = forces and forces[force_index]
    local lab_store = force_store and force_store.lab
    return (lab_store and lab_store.lab_content) or {}
end

--- Invalidate the cached availability scan for a force.
-- Safe to call when storage/force entries are absent.
---@param force_index integer|nil
auto_switch.invalidate = function(force_index)
    if force_index == nil then
        availability_cache = {}
        return
    end
    availability_cache[force_index] = nil
end

--- Scan registered labs and return per-pack availability.
-- Uses LilEinstein's already-registered lab runtime data; never performs a
-- world-wide find_entities_filtered search.
-- Returns { [pack_name] = {with = n, allowing = n, fraction = n}, __tick = n, __lab_count = n }
-- Returns safe empty data for missing/invalid force, lab, prototype, or inventory.
---@param force_index integer
---@param force_refresh boolean|nil
---@param lab_content table  -- from lab.get_runtime_lab_content(force_index)
---@param all_sciences table  -- from env.get_all_sciences()
---@return table
auto_switch.get_availability = function(force_index, force_refresh, lab_content, all_sciences)
    if force_index == nil then
        return {__tick = 0, __lab_count = 0}
    end

    local now = game and game.tick or 0
    local cached = availability_cache[force_index]
    if not force_refresh and cached and (now - cached.tick) < cache_interval_ticks then
        return cached.value
    end

    local resolved_lab_content = lab_content or get_runtime_lab_content(force_index)
    local resolved_sciences = all_sciences or env.get_all_sciences() or {}
    local sci_data = {}
    for _, sci in pairs(resolved_sciences) do
        sci_data[sci] = {with = 0, allowing = 0}
    end

    local lab_count = 0
    for _, lcur in pairs(resolved_lab_content or {}) do
        local lab_entity = lcur and lcur.lab
        if lab_entity and lab_entity.valid then
            -- Skip frozen labs
            if not lab_entity.frozen then
                -- Skip unpowered labs (only when they have an electric buffer)
                local powered = true
                if lab_entity.electric_buffer_size ~= nil
                    and lab_entity.electric_buffer_size > 0
                    and lab_entity.energy == 0 then
                    powered = false
                end
                if powered
                    and not lab_entity.disabled_by_script
                    and not lab_entity.disabled_by_control_behavior then
                    -- Validate inventory immediately before use
                    local get_inventory = lab_entity.get_inventory
                    if get_inventory then
                        local inv = lab_entity.get_inventory(defines.inventory.lab_input)
                        if inv and inv.is_empty and not inv.is_empty() then
                            -- Record which packs this lab currently holds
                            local has_packs = {}
                            local contents = inv.get_contents and inv.get_contents() or {}
                            for _, item in pairs(contents) do
                                if sci_data[item.name] ~= nil then
                                    has_packs[item.name] = true
                                end
                            end
                            if next(has_packs) ~= nil then
                                -- Count allowing vs having for each pack the lab accepts
                                local proto = lab_entity.prototype
                                local lab_inputs = proto and proto.lab_inputs
                                for _, pack_name in pairs(lab_inputs or {}) do
                                    if sci_data[pack_name] then
                                        sci_data[pack_name].allowing =
                                            sci_data[pack_name].allowing + 1
                                        if has_packs[pack_name] then
                                            sci_data[pack_name].with =
                                                sci_data[pack_name].with + 1
                                        end
                                    end
                                end
                                lab_count = lab_count + 1
                            end
                        end
                    end
                end
            end
        end
    end

    local res = {}
    for pack_name, data in pairs(sci_data) do
        if data.allowing > 0 then
            data.fraction = data.with / data.allowing
        else
            data.fraction = 0
        end
        res[pack_name] = data
    end
    res.__tick = now
    res.__lab_count = lab_count

    availability_cache[force_index] = {tick = now, value = res}
    return res
end

--- Return only missing required science packs for a technology.
-- Uses the cached direct-inventory scan. Returns {[pack_name] = true, ...} or
-- {} when no labs, invalid technology, no ingredients, or no missing packs.
-- Does not treat an empty or no-lab snapshot as starvation.
---@param force_index integer
---@param technology LuaTechnology|table
---@param lab_content table  -- from lab.get_runtime_lab_content(force_index)
---@param all_sciences table  -- from env.get_all_sciences()
---@return table
auto_switch.get_missing_sciences = function(force_index, technology, lab_content, all_sciences)
    if not technology or not technology.valid then
        return {}
    end
    local ingredients = technology.research_unit_ingredients
    if not ingredients or next(ingredients) == nil then
        return {}
    end

    local availability = auto_switch.get_availability(force_index, false, lab_content, all_sciences)
    -- Do not treat an empty or no-lab snapshot as starvation.
    if availability.__lab_count == 0 then
        return {}
    end

    local res = {}
    for _, ingredient in pairs(ingredients) do
        local pack_name = ingredient.name
        if pack_name then
            local pack_data = availability[pack_name]
            -- AutoSwitchTechs treats a pack as unavailable when no more than
            -- its configured 80% of accepting labs currently hold it. Keep the
            -- threshold explicit so low-but-nonzero factories are recognized
            -- as materially pack-bound.
            if pack_data and pack_data.allowing > 0 and
                pack_data.fraction <= availability_threshold then
                res[pack_name] = true
            end
        end
    end
    return res
end

return auto_switch
