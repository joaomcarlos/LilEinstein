local env = require("model.env")

local policy = {}

policy.strategy_order = {
    "balanced",
    "cheapest",
    "unlocks",
    "logistics",
    "combat",
    "space",
    "spoilable",
    "productivity",
    "focused",
    "megabase"
}

policy.science_priority_order = {"avoid", "normal", "preferred", "urgent"}
policy.repeat_mode_order = {"default", "never", "once", "continuous", "to_level"}
policy.reserve_for_type_order = {"off", "safety_first", "balanced"}

-- bounded action history retention (entries per force)
local history_retention_limit = 40
-- bounded replan interval (seconds); the planner re-runs at most this often
local replan_interval_min_seconds = 30
local replan_interval_max_seconds = 3600

local default_settings = {
    strategy = "balanced",
    planning_paused = false,
    parallel_research = false,
    min_switch_seconds = 20,
    forecast_seconds = 120,
    plan_horizon_minutes = 30,
    science_lower_threshold = 0.25,
    science_upper_threshold = 0.80,
    cluster_mode = true,
    multiplayer_lock = false,
    performance_mode = false,
    parallel_slots = 5,
    replan_interval_seconds = 120,
    reserve_for_type = "safety_first",
    instant_switch_override = true
}

local science_priority_weights = {
    avoid = -1000,
    normal = 0,
    preferred = 15,
    urgent = 45
}

local valid_science_priorities = {}
for _, name in ipairs(policy.science_priority_order) do
    valid_science_priorities[name] = true
end

local valid_repeat_modes = {}
for _, name in ipairs(policy.repeat_mode_order) do
    valid_repeat_modes[name] = true
end

local valid_strategies = {}
for _, name in ipairs(policy.strategy_order) do
    valid_strategies[name] = true
end

local valid_reserve_for_types = {}
for _, name in ipairs(policy.reserve_for_type_order) do
    valid_reserve_for_types[name] = true
end

local copy_table
copy_table = function(value)
    if type(value) ~= "table" then
        return value
    end
    local res = {}
    for key, item in pairs(value) do
        res[copy_table(key)] = copy_table(item)
    end
    return res
end

local get_store = function(force_index)
    local sf = storage and storage.forces and storage.forces[force_index]
    return sf and sf.research_policy or nil
end

local clamp = function(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value ~= value or value == math.huge or value == -math.huge then
        value = minimum
    end
    return math.max(minimum, math.min(maximum, value))
end

local sanitize_setting = function(key, value)
    if default_settings[key] == nil then
        return nil, false
    end

    if key == "strategy" then
        return value, type(value) == "string" and valid_strategies[value] == true
    elseif key == "reserve_for_type" then
        return value, type(value) == "string" and valid_reserve_for_types[value] == true
    elseif key == "min_switch_seconds" then
        return math.floor(clamp(value, 5, 30)), true
    elseif key == "forecast_seconds" then
        return math.floor(clamp(value, 0, 300)), true
    elseif key == "plan_horizon_minutes" then
        return math.floor(clamp(value, 1, 300)), true
    elseif key == "replan_interval_seconds" then
        return math.floor(clamp(value, replan_interval_min_seconds, replan_interval_max_seconds)), true
    elseif key == "parallel_slots" then
        return math.floor(clamp(value, 2, 20)), true
    elseif key == "science_lower_threshold" or key == "science_upper_threshold" then
        return clamp(value, 0, 2), true
    elseif type(default_settings[key]) == "boolean" then
        return value == true, type(value) == "boolean"
    end
    return nil, false
end

policy.init_force = function(force_index)
    local sf = storage.forces[force_index]
    sf.research_policy = sf.research_policy or {}
    local store = sf.research_policy
    store.settings = store.settings or {}
    store.sciences = store.sciences or {}
    store.repeat_rules = store.repeat_rules or {}
    store.history = store.history or {}
    store.presets = store.presets or {}
    store.science_available = store.science_available or {}
    store.cluster_science_available = store.cluster_science_available or {}
    -- pending plan-demand instant switch override; save-safe (strings/numbers only)
    store.pending_instant_switch = store.pending_instant_switch or nil

    for key, value in pairs(default_settings) do
        if store.settings[key] == nil then
            store.settings[key] = value
        end
    end

    for _, science in pairs(env.get_all_sciences() or {}) do
        store.sciences[science] = store.sciences[science] or {
            priority = "normal",
            lower_threshold = store.settings.science_lower_threshold,
            upper_threshold = store.settings.science_upper_threshold
        }
    end
end

policy.get_setting = function(force_index, key)
    local store = get_store(force_index)
    if store and store.settings[key] ~= nil then
        return store.settings[key]
    end
    return default_settings[key]
end

policy.set_setting = function(force_index, key, value)
    local store = get_store(force_index)
    if not store then
        return false
    end

    local sanitized, valid = sanitize_setting(key, value)
    if not valid then
        return false
    end

    store.settings[key] = sanitized
    return true
end

policy.get_science_policy = function(force_index, science)
    local store = get_store(force_index)
    if not store then
        return {
            priority = "normal",
            lower_threshold = default_settings.science_lower_threshold,
            upper_threshold = default_settings.science_upper_threshold
        }
    end
    if not store.sciences[science] then
        store.sciences[science] = {
            priority = "normal",
            lower_threshold = policy.get_setting(force_index, "science_lower_threshold"),
            upper_threshold = policy.get_setting(force_index, "science_upper_threshold")
        }
    end
    return store.sciences[science]
end

policy.cycle_science_priority = function(force_index, science)
    local item = policy.get_science_policy(force_index, science)
    local next_index = 1
    for index, name in ipairs(policy.science_priority_order) do
        if item.priority == name then
            next_index = (index % #policy.science_priority_order) + 1
            break
        end
    end
    item.priority = policy.science_priority_order[next_index]
    return item.priority
end

policy.adjust_science_threshold = function(force_index, science, threshold_name, delta)
    local item = policy.get_science_policy(force_index, science)
    local key = threshold_name == "upper" and "upper_threshold" or "lower_threshold"
    item[key] = clamp((item[key] or 0) + (delta or 0), 0, 2)
    if item.lower_threshold > item.upper_threshold then
        if key == "lower_threshold" then
            item.upper_threshold = item.lower_threshold
        else
            item.lower_threshold = item.upper_threshold
        end
    end
    return item[key]
end

policy.get_science_priority_weight = function(force_index, science)
    local item = policy.get_science_policy(force_index, science)
    return science_priority_weights[item.priority] or 0
end

policy.get_tech_science_priority = function(force_index, xcur)
    local best = 0
    local avoided = false
    for _, science in pairs((xcur and xcur.meta and xcur.meta.sciences) or {}) do
        local weight = policy.get_science_priority_weight(force_index, science)
        if weight <= -1000 then
            avoided = true
        elseif weight > best then
            best = weight
        end
    end
    if avoided then
        return -1000
    end
    return best
end

local has_effect = function(xcur, names)
    local effects = (xcur and xcur.meta and xcur.meta.research_effects) or {}
    for _, name in ipairs(names) do
        if effects[name] then
            return true
        end
    end
    return false
end

policy.get_strategy_adjustment = function(force_index, xcur, cost)
    local strategy = policy.get_setting(force_index, "strategy")
    if strategy == "cheapest" then
        return 50 / math.max(1, math.log((cost or 1) + 2, 2))
    elseif strategy == "unlocks" then
        if has_effect(xcur, {"unlock-recipe", "unlock-space-location", "unlock-quality", "unlock-space-platforms"}) then
            return 35
        end
    elseif strategy == "logistics" then
        if has_effect(xcur, {"worker-robot-speed", "worker-robot-storage", "belt-stack-size-bonus",
                             "inserter-stack-size-bonus", "bulk-inserter-capacity-bonus", "vehicle-logistics"}) then
            return 35
        end
    elseif strategy == "combat" then
        if has_effect(xcur, {"ammo-damage", "gun-speed", "turret-attack", "artillery-range",
                             "character-health-bonus", "maximum-following-robots-count"}) then
            return 35
        end
    elseif strategy == "space" then
        if has_effect(xcur, {"unlock-space-location", "unlock-space-platforms", "create-space-platform"}) then
            return 60
        end
    elseif strategy == "spoilable" then
        if xcur and xcur.meta and xcur.meta.has_spoilable_science then
            return 60
        end
    elseif strategy == "productivity" then
        if has_effect(xcur, {"change-recipe-productivity", "laboratory-productivity",
                             "mining-drill-productivity-bonus"}) then
            return 60
        end
    elseif strategy == "megabase" then
        -- Infinite focused research, accounted for logistics. Bounded bonus
        -- for infinite (high-yield) targets plus a smaller logistics-aware bump.
        if xcur and xcur.meta and xcur.meta.is_infinite then
            local bonus = 40
            if has_effect(xcur, {"worker-robot-speed", "worker-robot-storage", "belt-stack-size-bonus",
                                 "inserter-stack-size-bonus", "bulk-inserter-capacity-bonus", "vehicle-logistics"}) then
                bonus = bonus + 20
            end
            return bonus
        end
    end
    return 0
end

policy.get_repeat_rule = function(force_index, tech_name)
    local store = get_store(force_index)
    if not store then
        return {mode = "default"}
    end
    store.repeat_rules[tech_name] = store.repeat_rules[tech_name] or {mode = "default"}
    return store.repeat_rules[tech_name]
end

policy.cycle_repeat_rule = function(force_index, tech_name, current_level)
    local rule = policy.get_repeat_rule(force_index, tech_name)
    local next_index = 1
    for index, mode in ipairs(policy.repeat_mode_order) do
        if rule.mode == mode then
            next_index = (index % #policy.repeat_mode_order) + 1
            break
        end
    end
    rule.mode = policy.repeat_mode_order[next_index]
    if rule.mode == "to_level" then
        rule.max_level = math.max((current_level or 1) + 5, rule.max_level or 0)
    elseif rule.mode ~= "once" then
        rule.remaining = nil
    end
    if rule.mode == "once" then
        rule.remaining = 1
    end
    return rule
end

policy.adjust_repeat_max_level = function(force_index, tech_name, delta, current_level)
    local rule = policy.get_repeat_rule(force_index, tech_name)
    rule.mode = "to_level"
    rule.max_level = math.max((current_level or 1) + 1, (rule.max_level or (current_level or 1) + 5) + delta)
    return rule.max_level
end

policy.should_requeue = function(force_index, tech_name, next_level, global_default)
    local rule = policy.get_repeat_rule(force_index, tech_name)
    if rule.mode == "never" then
        return false
    elseif rule.mode == "continuous" then
        return true
    elseif rule.mode == "once" then
        return (rule.remaining or 0) > 0
    elseif rule.mode == "to_level" then
        return next_level ~= nil and next_level <= (rule.max_level or 0)
    end
    return global_default == true
end

policy.consume_repeat = function(force_index, tech_name)
    local rule = policy.get_repeat_rule(force_index, tech_name)
    if rule.mode == "once" then
        rule.remaining = math.max(0, (rule.remaining or 1) - 1)
        if rule.remaining == 0 then
            rule.mode = "never"
        end
    end
end

policy.can_edit = function(player)
    if not player or not player.valid then
        return false
    end
    if not policy.get_setting(player.force.index, "multiplayer_lock") then
        return true
    end
    return player.admin == true
end

local normalize_history_category = function(action)
    local value = tostring(action or "update")
    if string.find(value, "switch", 1, true) then
        return "switch"
    elseif value == "strategy" or string.find(value, "strategy", 1, true) then
        return "strategy"
    elseif string.find(value, "queue", 1, true) or value == "move_tech_up" or
        value == "move_tech_down" or value == "promote_research" or value == "demote_research" then
        return "queue"
    elseif string.find(value, "policy", 1, true) or string.find(value, "priority", 1, true) or
        string.find(value, "threshold", 1, true) or string.find(value, "repeat", 1, true) or
        value == "master_enable" then
        return "policy"
    elseif string.find(value, "setting", 1, true) then
        return "setting"
    end
    return value
end

-- Structured action history. `detail` may be a plain string (legacy callers,
-- stored verbatim in `detail`) or a table carrying any of:
--   category, reason, trigger, before, after, reserved, release_reason, detail
-- All structured fields are optional; `category` defaults to `action`.
-- `before`/`after`/`reserved` are copied save-safe (strings/numbers/tables).
policy.record_action = function(force_index, player_index, action, detail)
    local store = get_store(force_index)
    if not store then
        return
    end
    local player = player_index and game.get_player(player_index) or nil
    local entry = {
        tick = game and game.tick or 0,
        player = player and player.name or "system",
        action = tostring(action or "update")
    }
    if type(detail) == "table" then
        entry.category = tostring(detail.category or entry.action)
        entry.reason = detail.reason ~= nil and tostring(detail.reason) or nil
        entry.trigger = detail.trigger ~= nil and tostring(detail.trigger) or nil
        entry.before = detail.before ~= nil and copy_table(detail.before) or nil
        entry.after = detail.after ~= nil and copy_table(detail.after) or nil
        entry.reserved = detail.reserved ~= nil and copy_table(detail.reserved) or nil
        entry.release_reason = detail.release_reason ~= nil and tostring(detail.release_reason) or nil
        entry.detail = detail.detail ~= nil and tostring(detail.detail) or nil
    else
        entry.category = normalize_history_category(entry.action)
        entry.detail = tostring(detail or "")
    end
    table.insert(store.history, 1, entry)
    while #store.history > history_retention_limit do
        table.remove(store.history)
    end
end

-- Returns filtered history. `filters` is an optional table of equality
-- predicates matched against entry fields (e.g. {category = "switch"}).
-- Omitting `filters` (or passing a non-table) returns the full bounded history.
policy.get_history = function(force_index, filters)
    local store = get_store(force_index)
    local history = (store and store.history) or {}
    if type(filters) ~= "table" then
        return history
    end
    local res = {}
    for _, entry in ipairs(history) do
        local match = true
        for key, expected in pairs(filters) do
            if entry[key] ~= expected then
                match = false
                break
            end
        end
        if match then
            table.insert(res, entry)
        end
    end
    return res
end

------------------------------------------------------------------------------
-- Plan-demand instant switch override seam
--
-- The normal minimum switch interval stays enforced unless an explicit
-- override is requested. `instant_switch_override` (default true) gates
-- whether a pending request may be consumed. The pending request and its
-- reason persist in save-safe state until consumed or cleared.
------------------------------------------------------------------------------

policy.request_instant_switch = function(force_index, reason)
    local store = get_store(force_index)
    if not store then
        return false
    end
    store.pending_instant_switch = {
        reason = reason ~= nil and tostring(reason) or "",
        tick = game and game.tick or 0
    }
    return true
end

policy.has_instant_switch_request = function(force_index)
    local store = get_store(force_index)
    return (store and store.pending_instant_switch ~= nil) or false
end

policy.get_instant_switch_reason = function(force_index)
    local store = get_store(force_index)
    if not store or not store.pending_instant_switch then
        return nil
    end
    return store.pending_instant_switch.reason
end

-- Consumes a pending override. Returns true, reason when an override is
-- granted (pending request exists and the setting allows it); otherwise
-- false, nil. The pending request is cleared only when actually granted.
policy.consume_instant_switch = function(force_index)
    local store = get_store(force_index)
    if not store or not store.pending_instant_switch then
        return false, nil
    end
    if not policy.get_setting(force_index, "instant_switch_override") then
        return false, nil
    end
    local reason = store.pending_instant_switch.reason
    store.pending_instant_switch = nil
    return true, reason
end

policy.clear_instant_switch = function(force_index)
    local store = get_store(force_index)
    if store then
        store.pending_instant_switch = nil
    end
end

policy.get_presets = function(force_index)
    local store = get_store(force_index)
    return (store and store.presets) or {}
end

policy.set_preset = function(force_index, name, value)
    local store = get_store(force_index)
    if not store then
        return false
    end
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" or #name > 40 then
        return false
    end
    store.presets[name] = copy_table(value)
    return true
end

policy.delete_preset = function(force_index, name)
    local store = get_store(force_index)
    if store then
        store.presets[name] = nil
    end
end

policy.export_settings = function(force_index)
    local store = get_store(force_index)
    if not store then
        return {}
    end
    return {
        settings = copy_table(store.settings),
        sciences = copy_table(store.sciences),
        repeat_rules = copy_table(store.repeat_rules)
    }
end

policy.sanitize_settings = function(value)
    if type(value) ~= "table" then
        return false
    end

    local res = {settings = {}}
    if type(value.settings) == "table" then
        for key, item in pairs(value.settings) do
            if type(key) == "string" then
                local sanitized, valid = sanitize_setting(key, item)
                if valid then
                    res.settings[key] = sanitized
                end
            end
        end
    end
    if type(value.sciences) == "table" then
        res.sciences = {}
        for science, item in pairs(value.sciences) do
            if type(science) == "string" and prototypes.item[science] and type(item) == "table" then
                local priority = valid_science_priorities[item.priority] and item.priority or "normal"
                local lower = clamp(item.lower_threshold or default_settings.science_lower_threshold, 0, 2)
                local upper = clamp(item.upper_threshold or default_settings.science_upper_threshold, 0, 2)
                if lower > upper then
                    lower = upper
                end
                res.sciences[science] = {
                    priority = priority,
                    lower_threshold = lower,
                    upper_threshold = upper
                }
            end
        end
    end
    if type(value.repeat_rules) == "table" then
        res.repeat_rules = {}
        for tech_name, item in pairs(value.repeat_rules) do
            if type(tech_name) == "string" and prototypes.technology[tech_name] and type(item) == "table" then
                local mode = valid_repeat_modes[item.mode] and item.mode or "default"
                local rule = {mode = mode}
                if mode == "to_level" then
                    rule.max_level = math.max(1, math.floor(clamp(item.max_level, 1, 4294967295)))
                elseif mode == "once" then
                    rule.remaining = item.remaining == 0 and 0 or 1
                end
                res.repeat_rules[tech_name] = rule
            end
        end
    end
    return res
end

policy.import_settings = function(force_index, value)
    local store = get_store(force_index)
    local sanitized = policy.sanitize_settings(value)
    if not store or not sanitized then
        return false
    end
    for key, item in pairs(sanitized.settings) do
        store.settings[key] = item
    end
    for science, item in pairs(sanitized.sciences or {}) do
        store.sciences[science] = item
    end
    if sanitized.repeat_rules then
        store.repeat_rules = sanitized.repeat_rules
    end
    return true
end

policy.get_science_available_state = function(force_index, science, default_value)
    local store = get_store(force_index)
    if not store then
        return default_value
    end
    if store.science_available[science] == nil then
        store.science_available[science] = default_value
    end
    return store.science_available[science]
end

policy.set_science_available_state = function(force_index, science, value)
    local store = get_store(force_index)
    if store then
        store.science_available[science] = value == true
    end
end

policy.get_cluster_science_available_state = function(force_index, cluster_key, science, default_value)
    local store = get_store(force_index)
    if not store then
        return default_value
    end
    store.cluster_science_available[cluster_key] = store.cluster_science_available[cluster_key] or {}
    local states = store.cluster_science_available[cluster_key]
    if states[science] == nil then
        states[science] = default_value
    end
    return states[science]
end

policy.set_cluster_science_available_state = function(force_index, cluster_key, science, value)
    local store = get_store(force_index)
    if not store then
        return
    end
    store.cluster_science_available[cluster_key] = store.cluster_science_available[cluster_key] or {}
    store.cluster_science_available[cluster_key][science] = value == true
end

policy.prune_cluster_science_states = function(force_index, active_keys)
    local store = get_store(force_index)
    if not store then
        return
    end
    for cluster_key, _ in pairs(store.cluster_science_available) do
        if not active_keys[cluster_key] then
            store.cluster_science_available[cluster_key] = nil
        end
    end
end

policy.parallel_mod_available = function()
    return script and script.active_mods and script.active_mods["simultaneous-research"] ~= nil
end

policy.copy_table = copy_table

return policy
