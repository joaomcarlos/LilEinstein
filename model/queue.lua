--- The queue module is the model in which the mod queue is stored
local util = require("lib.util")
local const = require("lib.const")
local state = require("model.state")
local tech = require("model.tech")
local lab = require("model.lab")
local env = require("model.env")
local logger = require("lib.log")
local rw = require("model.research_weights")
local policy = require("model.research_policy")

local queue = {}

local research_history_seconds = 10 * 60
local research_history_sample_seconds = 3
local research_history_samples = math.floor(research_history_seconds / research_history_sample_seconds)
local research_speed_average_samples = math.floor(60 / research_history_sample_seconds)
local science_reserve_per_lab = 6
-- score factor applied to techs only reachable through prerequisites
local unavailable_score_factor = 0.5
-- a candidate must out-score the current research by this relative margin to interrupt it
local score_interrupt_margin = 1.5

-- interrupt comparison: margin scales with |current| so negative scores don't get an easier threshold
local score_would_interrupt = function(candidate_total, current_total)
    local margin = math.abs(current_total) * (score_interrupt_margin - 1)
    return candidate_total > current_total + margin
end
local max_plan_exchange_length = 250000
local max_plan_json_length = 2000000

-- seconds to stay on temp tech before checking to switch back
local temp_tech_timeout_seconds = 5 
-- seconds to extend temp tech timeout when target still lacks packs
local temp_tech_timeout_extend_seconds = 5  

-- Data model
-- storage.forces[force_index].queue.queue = {"tech-1", ...}

local keys = {
    queue = "queue",
    current_tech = "current_tech",
    current_tech_smart = "current_tech_smart",
    misses_science = "misses_science",
    announced_blocked = "announced_blocked",
    is_stuck = "is_stuck",
    pinned_tech = "pinned_tech",
    internal_queue_update_until = "internal_queue_update_until",
    internal_cancelled_techs = "internal_cancelled_techs",
    target_tech = "target_tech",
    temp_tech = "temp_tech",
    temp_tech_timeout = "temp_tech_timeout",
    last_switch_tick = "last_switch_tick",
    last_warn_tick = "last_warn_tick"
}

---------------------------------------------------------------------------
-- Internal queue helpers
---------------------------------------------------------------------------

local set = function(force_index, key, val)
    if not storage.forces[force_index] then
        return
    end
    storage.forces[force_index].queue[key] = val
end
local get = function(force_index, key)
    return storage.forces[force_index].queue[key]
end

---------------------------------------------------------------------------
-- Warning helpers (ported from AutoSwitchTechs)
---------------------------------------------------------------------------

local make_science_icon_string = function(sciences)
    if not sciences or next(sciences) == nil then return "(none)" end
    local r = ""
    for sci_pack, _ in pairs(sciences) do
        r = r .. "[img=item/" .. sci_pack .. "] "
    end
    return r
end

local can_warn_now = function(force_index)
    if not storage.settings or not storage.settings.showWarnings then return false end
    local last = get(force_index, keys.last_warn_tick)
    local interval = storage.settings.warnEveryNTicks or 3600
    return (last == nil) or (last + interval < game.tick)
end

local update_warn_time = function(force_index)
    set(force_index, keys.last_warn_tick, game.tick)
end

local warning_alert_icon = {type = "virtual", name = "lil_einstein-science-alert"}
local switch_alert_icon = {type = "virtual", name = "lil_einstein-tech-switch-alert"}

local get_any_lab = function(force_index)
    if not force_index then
        return nil
    end
    local sf = storage.forces and storage.forces[force_index]
    local sfl = sf and sf.lab
    local all_labs = sfl and sfl.all_labs
    if all_labs and sfl.lab_content then
        for _, unit_number in ipairs(all_labs) do
            local content = sfl.lab_content[unit_number]
            if content and content.lab and content.lab.valid then
                return content.lab
            end
        end
    end

    for _, surface in pairs(game.surfaces) do
        local surface_labs = surface.find_entities_filtered({type = "lab", force = force_index})
        for _, lab_entity in pairs(surface_labs) do
            if lab_entity.valid then
                if sfl and sfl.all_labs and sfl.lab_content then
                    lab.register(lab_entity)
                end
                return lab_entity
            end
        end
    end
    return nil
end

local alert_force = function(force, icon, message, show_on_map)
    local lab_entity = get_any_lab(force.index)
    if not lab_entity then return end
    for _, player in pairs(force.connected_players) do
        if player and player.valid then
            player.add_custom_alert(lab_entity, icon, message, show_on_map)
        end
    end
end

local warn_force = function(force, message)
    if not can_warn_now(force.index) then return end
    update_warn_time(force.index)
    alert_force(force, warning_alert_icon, message, false)
end

local notify_switch = function(force, cur_tech, candidate, tsx, lsci)
    if not storage.settings or not storage.settings.notifySwitches then return end
    local xcur = tsx[cur_tech]
    local xcan = tsx[candidate]
    if not xcur or not xcan then return end

    local switch_reason
    if xcan.meta.has_spoilable_science then
        local spoilable = {}
        for _, s in pairs(xcan.meta.sciences or {}) do
            local item = prototypes.item[s]
            if item and item.get_spoil_ticks() > 0 then
                spoilable[s] = true
            end
        end
        switch_reason = {"lil_einstein-warn.switched-bc-prioritized", make_science_icon_string(spoilable)}
    else
        local missing = {}
        for _, s in pairs(xcur.meta.sciences or {}) do
            if not lsci or not lsci[s] then
                missing[s] = true
            end
        end
        if next(missing) ~= nil then
            switch_reason = {"lil_einstein-warn.switched-bc-first-tech-missing-science", make_science_icon_string(missing)}
        else
            switch_reason = {"lil_einstein-warn.switched-bc-keep-research-running"}
        end
    end

    local new_tech_name
    if xcan.meta.is_infinite and xcan.technology.level then
        new_tech_name = {"", xcan.technology.localised_name, " ", xcan.technology.level}
    else
        new_tech_name = xcan.technology.localised_name
    end

    local msg = {"lil_einstein-warn.switched-to-tech", new_tech_name, switch_reason}
    alert_force(force, switch_alert_icon, msg, true)
end

---------------------------------------------------------------------------
-- Weighted research scoring (LilEinstein)
---------------------------------------------------------------------------

-- Research weights and caps are maintained in model/research_weights.lua for easy editing.

local get_tech_weight = function(xcur)
    local name = xcur.technology.name

    -- Hard-cap check: deprioritize techs that have reached their practical limit
    local cap = rw.research_caps[name]
    if cap and xcur.technology.level >= cap then
        return -1000
    end

    local w = rw.research_weights[name]
    if w then
        return w
    end

    -- Default weight inference from research effects
    local effects = xcur.meta.research_effects or {}
    if effects["unlock-space-location"] then
        return 5
    end
    if effects["unlock-recipe"] then
        return 3
    end
    if effects["change-recipe-productivity"] or effects["laboratory-productivity"] or effects["laboratory-speed"] then
        return 4
    end
    if effects["mining-drill-productivity-bonus"] then
        return 6
    end
    if effects["turret-attack"] or effects["ammo-damage"] or effects["gun-speed"] or effects["artillery-range"] then
        return 2
    end
    if effects["character-health-bonus"] or effects["character-inventory-slots-bonus"] then
        return 1
    end

    return 2
end

local eval_formula = function(formula, level)
    if not formula then return nil end
    -- Factorio formulas may use implicit multiplication e.g. "100(L-6)+1000"
    -- Lua requires explicit "*", so fix "word(" or "number(" → "word*(" / "number*("
    local fixed = formula:gsub("(%w)(%()", "%1*%2")
    local env = {L = level, math = math}
    local chunk, err = load("return " .. fixed, "formula", "t", env)
    if chunk then
        local ok, val = pcall(chunk)
        if ok and type(val) == "number" then
            return val
        end
    end
    return nil
end

local get_tech_weight_at_level = function(xcur, level)
    local name = xcur.technology.name
    local cap = rw.research_caps[name]
    if cap and level >= cap then
        return -1000
    end
    local w = rw.research_weights[name]
    if w then
        return w
    end
    local effects = xcur.meta.research_effects or {}
    if effects["unlock-space-location"] then return 5 end
    if effects["unlock-recipe"] then return 3 end
    if effects["change-recipe-productivity"] or effects["laboratory-productivity"] or effects["laboratory-speed"] then return 4 end
    if effects["mining-drill-productivity-bonus"] then return 6 end
    if effects["turret-attack"] or effects["ammo-damage"] or effects["gun-speed"] or effects["artillery-range"] then return 2 end
    if effects["character-health-bonus"] or effects["character-inventory-slots-bonus"] then return 1 end
    return 2
end

local get_science_counts
local get_lab_science_counts
local get_virtual_queue_source
local set_runtime_research_queue
local get_runtime_candidate_average_cost

queue.apply_planning_pause = function(f)
    if not f then
        return
    end
    local paused_queue = {}
    if f.current_research then
        table.insert(paused_queue, f.current_research.name)
    end
    set_runtime_research_queue(f, paused_queue)
end

local science_depletion_is_attributable = function(availability, science)
    if not availability.__cluster_mode then
        return true
    end
    -- Production statistics are force-wide across all loaded surfaces. In cluster mode
    -- they can only be attributed safely when exactly one cluster consumes this science.
    local consuming_clusters = 0
    for _, cluster in pairs(availability.__clusters or {}) do
        if ((cluster.lab_input_counts and cluster.lab_input_counts[science]) or 0) > 0 then
            consuming_clusters = consuming_clusters + 1
        end
    end
    return consuming_clusters == 1
end

local get_depletion_horizon_seconds = function(xcur, force_index, forecast_seconds)
    -- Cap the depletion horizon at the estimated time to finish this tech: if the
    -- research completes before packs run out, the supply is sufficient.
    local horizon = forecast_seconds
    local f = game.forces[force_index]
    local speed = queue.get_research_speed(force_index)
    if f and xcur.technology and speed and speed > 0 then
        local unit_count = xcur.technology.research_unit_count or 1
        local remaining_units = unit_count
        if f.current_research and f.current_research.name == xcur.technology.name then
            remaining_units = math.max(0, unit_count * (1 - (f.research_progress or 0)))
        end
        local remaining_seconds = remaining_units / speed
        if remaining_seconds < horizon then
            horizon = remaining_seconds
        end
    end
    return horizon
end

local science_supply_is_sufficient = function(xcur, force_index)
    if not xcur or not xcur.meta or not force_index then
        return false
    end

    local sciences = xcur.meta.sciences or {}
    if not next(sciences) then
        return true
    end

    local availability = queue.get_science_availability(force_index)
    local forecast = queue.get_science_forecast and queue.get_science_forecast(force_index) or {}
    local forecast_seconds = policy.get_setting(force_index, "forecast_seconds") or 0
    if not queue.science_is_available(xcur, availability) then
        return false
    end
    if forecast_seconds > 0 then
        local horizon = get_depletion_horizon_seconds(xcur, force_index, forecast_seconds)
        for _, science in pairs(sciences) do
            local science_forecast = forecast[science]
            if science_forecast and science_forecast.depletion_seconds and
                science_forecast.depletion_seconds < horizon and
                science_depletion_is_attributable(availability, science) then
                return false
            end
        end
    end

    -- Only pay for the live lab diagnostic when the cheaper aggregate and
    -- depletion checks both claim the active technology is supplied.
    local live_bottleneck = queue.get_active_missing_science_bottleneck and
        queue.get_active_missing_science_bottleneck(force_index, xcur)
    if live_bottleneck and next(live_bottleneck) then
        return false
    end
    return true
end

-- Return detailed score components: {importance, level_boost, user_boost, total}
-- importance = base AI weight from rw.research_weights + effect inference
-- level_boost = bonus for cheap techs relative to current candidate pool average
-- user_boost = direct user override (can be negative)
-- total = ((importance + level_boost) / (total_cost ^ 0.15)) * available_factor + user_boost + science_priority + strategy_boost
queue.score_tech_detailed = function(xcur, level, user_boost, avg_cost, force_index)
    local importance = get_tech_weight_at_level(xcur, level)
    if importance <= -100 then
        local total = xcur.available and importance or -10000
        return {importance = importance, level_boost = 0, user_boost = user_boost, total = total}
    end

    -- Techs not yet available (prerequisites pending) are still scored so the
    -- virtual queue keeps them in sensible order. Their base score is discounted
    -- because the player cannot start them immediately.
    local available_factor = xcur.available and 1 or unavailable_score_factor

    local cost = xcur.technology.research_unit_count or 1
    if xcur.meta.is_infinite and xcur.meta.prototype.research_unit_count_formula then
        local est = eval_formula(xcur.meta.prototype.research_unit_count_formula, level)
        if est then
            cost = est
        elseif xcur.technology.level > 0 then
            cost = cost * (level / xcur.technology.level)
        end
    end

    -- Level boost: based on how many doubling-steps below the average
    local level_boost = 0
    if avg_cost and avg_cost > 0 and cost < avg_cost then
        local steps = math.log(avg_cost / cost, 2)
        level_boost = math.min(50, math.floor(steps * 15))
    end

    local num_ingredients = 0
    for _ in pairs(xcur.technology.research_unit_ingredients or {}) do
        num_ingredients = num_ingredients + 1
    end
    if num_ingredients == 0 then
        num_ingredients = 1
    end
    local total_cost = cost * num_ingredients

    local science_priority = force_index and policy.get_tech_science_priority(force_index, xcur) or 0
    if science_priority <= -1000 then
        return {
            importance = importance,
            level_boost = level_boost,
            user_boost = user_boost,
            science_priority = science_priority,
            strategy_boost = 0,
            total = -10000
        }
    end

    local strategy_boost = force_index and policy.get_strategy_adjustment(force_index, xcur, cost) or 0
    local base = (importance + level_boost) / (total_cost ^ 0.15)
    local total = base * available_factor + user_boost + science_priority + strategy_boost

    return {
        importance = importance,
        level_boost = level_boost,
        user_boost = user_boost,
        science_priority = science_priority,
        strategy_boost = strategy_boost,
        total = total
    }
end

local tech_is_available = function(xcur)
    return xcur and not xcur.technology.researched and xcur.available and xcur.technology.enabled and
               not xcur.meta.has_trigger
end
queue.science_is_available = function(xcur, lsci)
    if not xcur or not xcur.meta then
        return false
    end
    for _, s in pairs(xcur.meta.sciences or {}) do
        if not lsci or not lsci[s] then
            return false
        end
    end

    if lsci and lsci.__cluster_mode and next(xcur.meta.sciences or {}) ~= nil then
        for _, cluster in pairs(lsci.__clusters or {}) do
            local supplied = true
            for _, science in pairs(xcur.meta.sciences or {}) do
                if not cluster.available_sciences or not cluster.available_sciences[science] then
                    supplied = false
                    break
                end
            end
            if supplied then
                for _, lab_inputs in pairs(cluster.lab_input_sets or {}) do
                    local compatible = true
                    for _, science in pairs(xcur.meta.sciences or {}) do
                        if not lab_inputs[science] then
                            compatible = false
                            break
                        end
                    end
                    if compatible then
                        return true
                    end
                end
            end
        end
        return false
    end
    return true
end
local science_is_available = queue.science_is_available

local get_science_block_details = function(xcur, lsci)
    if science_is_available(xcur, lsci) then
        return nil, {}
    end

    local missing_sciences = {}
    for _, science in pairs((xcur and xcur.meta and xcur.meta.sciences) or {}) do
        if not lsci or not lsci[science] then
            table.insert(missing_sciences, science)
        end
    end
    table.sort(missing_sciences)

    if #missing_sciences > 0 then
        return "missing_science", missing_sciences
    end
    if lsci and lsci.__cluster_mode then
        return "science_not_together", {}
    end
    return "missing_science", {}
end


local tech_can_be_runtime_candidate = function(force_index, xcur)
    if not xcur or not xcur.technology or not xcur.meta then
        return false
    end
    if xcur.technology.researched then
        return false
    end
    if not xcur.technology.enabled or xcur.meta.hidden or xcur.meta.has_trigger then
        return false
    end
    if not queue.get_tech_enabled(force_index, xcur.technology.name) then
        return false
    end
    if policy.get_tech_science_priority(force_index, xcur) <= -1000 then
        return false
    end
    local cap = rw.research_caps[xcur.technology.name]
    if cap and xcur.technology.level >= cap then
        return false
    end
    return true
end

local clear_temp_research_state = function(force_index)
    set(force_index, keys.target_tech, nil)
    set(force_index, keys.temp_tech, nil)
    set(force_index, keys.temp_tech_timeout, nil)
end

local tech_is_queue_relevant = function(xcur)
    return xcur and (xcur.queued or next(xcur.inherited_by or {}) ~= nil)
end

local tech_can_be_restored = function(force_index, xcur)
    return tech_is_queue_relevant(xcur) and xcur.available and tech_can_be_runtime_candidate(force_index, xcur) and
               queue.science_is_sufficient(xcur, force_index)
end

local mark_missing_science = function(sfsci, tech_name)
    if sfsci and tech_name then
        sfsci[tech_name] = true
    end
end

local find_runtime_candidate = function(force_index, tech_name, tsx, lsci, sfsci)
    local xcur = tsx and tsx[tech_name]
    if not tech_can_be_runtime_candidate(force_index, xcur) then
        return nil, nil
    end

    if xcur.available then
        if science_is_available(xcur, lsci) then
            return tech_name, nil
        end
        mark_missing_science(sfsci, tech_name)
        return nil, tech_name
    end

    local fallback
    local misses_science = false
    for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
        local xpre = tsx[pre_req_tech]
        if tech_can_be_runtime_candidate(force_index, xpre) and xpre.available then
            if science_is_available(xpre, lsci) then
                return pre_req_tech, nil
            end
            misses_science = true
            fallback = fallback or pre_req_tech
        end
    end
    if misses_science then
        mark_missing_science(sfsci, tech_name)
    end
    return nil, fallback
end

local get_first_next_tech = function(f)
    -- This function returns the next runtime technology from the scored virtual queue.
    local tsx = tech.get_all_tech_state_ext(f.index)
    local sfq = get_virtual_queue_source(f.index, tsx)
    local lsci = queue.get_science_availability(f.index)

    -- Reset current researching tech
    set(f.index, keys.current_tech, nil)
    set(f.index, keys.current_tech_smart, nil)

    -- Reset & get missing science array
    set(f.index, keys.misses_science, {})
    local sfsci = get(f.index, keys.misses_science)

    -- If a temp tech is designated and still valid, honor it
    local temp = get(f.index, keys.temp_tech)
    if temp then
        local xtemp = tsx[temp]
        if xtemp and xtemp.available and tech_can_be_runtime_candidate(f.index, xtemp) and science_is_available(xtemp, lsci) then
            set(f.index, keys.current_tech, temp)
            return temp
        end
        -- Temp tech no longer valid, clear it
        set(f.index, keys.temp_tech, nil)
        set(f.index, keys.temp_tech_timeout, nil)
    end

    local target = get(f.index, keys.target_tech)
    if target then
        local xtarget = tsx[target]
        if tech_can_be_restored(f.index, xtarget) then
            set(f.index, keys.current_tech, target)
            return target
        end
        if not tech_can_be_runtime_candidate(f.index, xtarget) then
            clear_temp_research_state(f.index)
        end
    end

    local fallback
    local pinned = queue.get_pinned_tech(f.index)
    if pinned then
        local candidate, pinned_fallback = find_runtime_candidate(f.index, pinned, tsx, lsci, sfsci)
        if candidate then
            set(f.index, keys.current_tech, candidate)
            return candidate
        end
        fallback = fallback or pinned_fallback
    end

    for _, q in ipairs(sfq or {}) do
        if q ~= pinned then
            local candidate, queue_fallback = find_runtime_candidate(f.index, q, tsx, lsci, sfsci)
            if candidate then
                set(f.index, keys.current_tech, candidate)
                return candidate
            end
            fallback = fallback or queue_fallback
        end
    end

    if fallback then
        set(f.index, keys.current_tech, fallback)
        return fallback
    end
end

local get_first_next_tech_smart = function(f)
    -- AI weighted scoring + custom order bonus. Skips disabled techs.
    local tsx = tech.get_all_tech_state_ext(f.index)
    local lsci = queue.get_science_availability(f.index)

    local all_candidates = {}
    for tech_name, xcur in pairs(tsx) do
        if xcur.technology.researched then goto skip end
        if not xcur.technology.enabled or xcur.meta.hidden then goto skip end
        if not queue.get_tech_enabled(f.index, tech_name) then goto skip end
        if xcur.meta.is_infinite then
            local cap = rw.research_caps[tech_name]
            if cap and xcur.technology.level >= cap then goto skip end
        end

        -- Find actual researchable candidate (prerequisite if not directly available)
        local candidate
        if xcur.available then
            if xcur.available and science_is_available(xcur, lsci) then
                candidate = xcur
            end
        else
            for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
                local xpre = tsx[pre_req_tech]
                if xpre and xpre.available and science_is_available(xpre, lsci) then
                    candidate = xpre
                    break
                end
            end
        end

        if candidate then
            all_candidates[candidate.technology.name] = candidate
        end
        ::skip::
    end

    local order = queue.get_tech_order(f.index)

    -- Compute average cost of all candidates for level boost
    local total_cost_sum = 0
    local cost_count = 0
    for tech_name, xcur in pairs(all_candidates) do
        local cost = xcur.technology.research_unit_count or 1
        total_cost_sum = total_cost_sum + cost
        cost_count = cost_count + 1
    end
    local avg_cost = cost_count > 0 and (total_cost_sum / cost_count) or nil

    local best_score = -math.huge
    local nexttech

    for tech_name, xcur in pairs(all_candidates) do
        local stored_ub = queue.get_tech_ub(f.index, tech_name)
        local sd = queue.score_tech_detailed(xcur, xcur.technology.level, stored_ub, avg_cost, f.index)
        if sd.total > best_score then
            best_score = sd.total
            nexttech = tech_name
        end
    end

    if nexttech then
        set(f.index, keys.current_tech, nil)
        set(f.index, keys.current_tech_smart, nexttech)
        return nexttech
    end
    set(f.index, keys.current_tech_smart, nil)
end

local get_queue_position = function(f, tech_name)
    -- Check if technology is valid or early exit
    local t = f.technologies[tech_name] or nil
    if not t or not t.valid then
        return
    end

    -- Get the queued tech index
    local sfq = get(f.index, keys.queue)
    for i, q in pairs(sfq or {}) do
        if q == tech_name then
            return i
        end
    end
end

local get_queue_length = function(f)
    -- Init the queue and get the global force
    local sfq = get(f.index, keys.queue)

    -- Return the queue length, or 0 if the queue array does not exist
    return #sfq or 0
end

queue.get_tech_missing_science = function(force_index)
    return get(force_index, keys.misses_science)
end
queue.get_current_researching = function(force_index)
    return get(force_index, keys.current_tech)
end
queue.get_current_smart_researching = function(force_index)
    return get(force_index, keys.current_tech_smart)
end
queue.get_pinned_tech = function(force_index)
    return get(force_index, keys.pinned_tech)
end
queue.set_pinned_tech = function(force_index, tech_name)
    set(force_index, keys.pinned_tech, tech_name)
end

local mark_internal_research_queue_update = function(force_index, queue_names)
    local sf = storage.forces[force_index]
    if not sf or not sf.queue then
        return
    end

    sf.queue[keys.internal_queue_update_until] = game.tick + 2
    local cancelled = {}
    local f = game.forces[force_index]
    if f and f.current_research then
        cancelled[f.current_research.name] = game.tick + 2
    end
    for _, tech_name in ipairs(queue_names or {}) do
        cancelled[tech_name] = game.tick + 2
    end
    sf.queue[keys.internal_cancelled_techs] = cancelled
end

queue.is_internal_research_queue_update = function(f)
    if not f or not storage.forces[f.index] or not storage.forces[f.index].queue then
        return false
    end

    local sq = storage.forces[f.index].queue
    local expires = sq[keys.internal_queue_update_until]
    if expires and expires >= game.tick then
        return true
    end
    sq[keys.internal_queue_update_until] = nil
    return false
end

queue.consume_internal_research_cancel = function(f, tech_name)
    if not f or not tech_name or not storage.forces[f.index] or not storage.forces[f.index].queue then
        return false
    end

    local sq = storage.forces[f.index].queue
    local cancelled = sq[keys.internal_cancelled_techs]
    local expires = cancelled and cancelled[tech_name]
    if expires and expires >= game.tick then
        cancelled[tech_name] = nil
        return true
    end
    return false
end

queue.research_is_stuck = function(f)
    -- Get some variables to work with
    local sfq = get(f.index, keys.queue)
    local tsx = tech.get_all_tech_state_ext(f.index)
    local lsci = queue.get_science_availability(f.index)
    local cur_tech = f.current_research and f.current_research.name or get(f.index, keys.current_tech)
    local auto_research = state.get_force_setting(f.index, "auto_research",
        const.default_settings.force.settings.auto_research)

    -- Check if the current tech matches the queue
    if sfq and #sfq > 0 and not cur_tech then
        return true
    end

    -- Get the auto research tech if we are auto researching
    if auto_research and not cur_tech then
        cur_tech = get(f.index, keys.current_tech_smart)
    end
    -- Check if we are stuck now and if we were stuck in the last tick check
    if not cur_tech then
        return false
    end

    -- Get the current tech and return if we have the sciences for it
    local xcur = tsx[cur_tech]
    if not xcur then
        return false
    end

    -- Check if we are stuck now and if we were stuck in the last tick check
    local was_stuck = get(f.index, keys.is_stuck)
    local is_stuck = not science_is_available(xcur, lsci) or false

    -- Only trigger a reorder when entering the stuck state.
    -- When leaving stuck (packs returned), just update the flag silently.
    if was_stuck ~= is_stuck then
        set(f.index, keys.is_stuck, is_stuck)
        if is_stuck then
            return true
        end
    end
    return is_stuck
end

-- Decide whether an active temporary research should continue instead of restoring
-- the target. Pins always win. Otherwise prefer higher science priority, then a
-- large enough score margin over the target.
local temp_should_persist = function(force_index, xtemp, xtarget, avg_cost)
    if not xtemp or not xtarget then
        return false
    end
    local pinned = queue.get_pinned_tech(force_index)
    if xtarget.technology.name == pinned then
        return false
    end
    if xtemp.technology.name == pinned then
        return true
    end
    if not queue.science_is_sufficient(xtemp, force_index) then
        return false
    end
    local temp_priority = policy.get_tech_science_priority(force_index, xtemp)
    local target_priority = policy.get_tech_science_priority(force_index, xtarget)
    if temp_priority > target_priority then
        return true
    end
    if temp_priority < target_priority then
        return false
    end
    local temp_ub = queue.get_tech_ub(force_index, xtemp.technology.name)
    local target_ub = queue.get_tech_ub(force_index, xtarget.technology.name)
    local temp_sd = queue.score_tech_detailed(xtemp, xtemp.technology.level, temp_ub, avg_cost, force_index)
    local target_sd = queue.score_tech_detailed(xtarget, xtarget.technology.level, target_ub, avg_cost, force_index)
    return score_would_interrupt(temp_sd.total, target_sd.total)
end

queue.check_and_switch_temp_research = function(f)
    if not f then
        return
    end
    local st = state.get_force_setting(f.index, "master_enable")
    if st == "left" then
        return
    end
    if policy.get_setting(f.index, "planning_paused") then
        queue.apply_planning_pause(f)
        return
    end
    if policy.get_setting(f.index, "parallel_research") then
        return
    end
    local sf = storage.forces[f.index]
    if not sf or not sf.queue then
        return
    end
    local sq = sf.queue
    local minimum_switch_ticks = 60 * (policy.get_setting(f.index, "min_switch_seconds") or 20)
    local last_switch_tick = sq[keys.last_switch_tick]
    if last_switch_tick and game.tick - last_switch_tick < minimum_switch_ticks then
        return
    end

    -- If temp tech is active and timeout hasn't expired, don't disturb it
    local temp = sq[keys.temp_tech]
    local timeout = sq[keys.temp_tech_timeout]
    if temp and timeout and game.tick < timeout then
        return
    end

    local tsx = tech.get_all_tech_state_ext(f.index)
    if not tsx then
        return
    end

    -- If timeout expired, check if target tech now has enough packs
    if temp and timeout and game.tick >= timeout then
        local target = sq[keys.target_tech]
        if target then
            local xtarget = tsx[target]
            if tech_can_be_restored(f.index, xtarget) then
                local xtemp = tsx[temp]
                local avg_cost = get_runtime_candidate_average_cost(f.index, tsx)
                if xtemp and temp_should_persist(f.index, xtemp, xtarget, avg_cost) then
                    -- Temp is still higher priority / much better scored; keep it.
                    sq[keys.temp_tech_timeout] = game.tick + (60 * temp_tech_timeout_extend_seconds)
                    if not f.current_research or f.current_research.name ~= temp then
                        state.request_next_research(f)
                    end
                    return
                end
                -- Switch back to target
                sq[keys.temp_tech] = nil
                sq[keys.temp_tech_timeout] = nil
                sq[keys.last_switch_tick] = game.tick
                state.request_next_research(f)
                return
            end
            if not tech_can_be_runtime_candidate(f.index, xtarget) then
                clear_temp_research_state(f.index)
                state.request_next_research(f)
                return
            end
        else
            clear_temp_research_state(f.index)
            state.request_next_research(f)
            return
        end

        local xtemp = tsx[temp]
        if not xtemp or not xtemp.available or not tech_can_be_runtime_candidate(f.index, xtemp) then
            sq[keys.temp_tech] = nil
            sq[keys.temp_tech_timeout] = nil
            state.request_next_research(f)
            return
        end
        -- Target still doesn't have packs; extend timeout so temp gets more air time
        sq[keys.temp_tech_timeout] = game.tick + (60 * temp_tech_timeout_extend_seconds)
        if not f.current_research or f.current_research.name ~= temp then
            state.request_next_research(f)
        end
        return
    end

    -- Normal check: is current tech low on packs?
    local cur_name = f.current_research and f.current_research.name
    if not cur_name then
        return
    end

    local xcur = tsx[cur_name]
    if not xcur then
        return
    end

    -- Validate stored target/temp state against the live research.
    local target = sq[keys.target_tech]
    if target then
        local xtarget = tsx[target]
        if not tech_can_be_runtime_candidate(f.index, xtarget) then
            clear_temp_research_state(f.index)
            target = nil
        elseif not temp and cur_name ~= target and tech_can_be_restored(f.index, xtarget) then
            state.request_next_research(f)
            return
        end
    end

    local current_is_sufficient = queue.science_is_sufficient(xcur, f.index)

    -- Avoid switching away from a tech that is almost finished and still has packs.
    local finish_threshold = policy.get_setting(f.index, "finish_current_threshold") or 0.90
    if current_is_sufficient and (f.research_progress or 0) >= finish_threshold then
        return
    end

    -- If current tech has sufficient packs, only interrupt it for a higher-priority
    -- science policy, or for a same-priority candidate with a much better score.
    if current_is_sufficient then
        local temp_name = sq[keys.temp_tech]
        -- Temp finished and we're back on target; clean up
        if target and not temp_name and cur_name == target then
            sq[keys.target_tech] = nil
            sq[keys.temp_tech_timeout] = nil
            return
        end
        -- Current research changed to something unexpected; clear stale temp state
        if target and cur_name ~= target and cur_name ~= temp_name then
            sq[keys.target_tech] = nil
            sq[keys.temp_tech] = nil
            sq[keys.temp_tech_timeout] = nil
        end
        local current_priority = policy.get_tech_science_priority(f.index, xcur)
        local avg_cost = get_runtime_candidate_average_cost(f.index, tsx)
        local current_ub = queue.get_tech_ub(f.index, cur_name)
        local current_sd = queue.score_tech_detailed(xcur, xcur.technology.level, current_ub, avg_cost, f.index)
        local lsci = queue.get_science_availability(f.index)
        local sfq = get_virtual_queue_source(f.index, tsx)
        for _, q in ipairs(sfq or {}) do
            if q ~= cur_name then
                local candidate, _ = find_runtime_candidate(f.index, q, tsx, lsci, {})
                local xcandidate = candidate and tsx[candidate] or nil
                if not xcandidate then
                    goto continue_sufficient
                end
                local candidate_priority = policy.get_tech_science_priority(f.index, xcandidate)
                local switch_reason
                if candidate_priority > current_priority then
                    switch_reason = "priority"
                elseif candidate_priority == current_priority then
                    local candidate_ub = queue.get_tech_ub(f.index, candidate)
                    local candidate_sd = queue.score_tech_detailed(xcandidate, xcandidate.technology.level, candidate_ub, avg_cost, f.index)
                    if score_would_interrupt(candidate_sd.total, current_sd.total) then
                        switch_reason = "score"
                    end
                end
                if switch_reason then
                    sq[keys.target_tech] = cur_name
                    sq[keys.temp_tech] = candidate
                    sq[keys.temp_tech_timeout] = game.tick + minimum_switch_ticks
                    sq[keys.last_switch_tick] = game.tick
                    notify_switch(f, cur_name, candidate, tsx, lsci)
                    state.request_next_research(f)
                    return
                end
                ::continue_sufficient::
            end
        end
        return
    end

    -- Current tech is low on packs. Find next suitable tech in order.
    local lsci = queue.get_science_availability(f.index)
    local live_bottleneck = queue.get_active_missing_science_bottleneck(f.index, xcur)
    if next(live_bottleneck) then
        local effective_availability = {}
        for science, available in pairs(lsci or {}) do
            effective_availability[science] = available
        end
        for science, _ in pairs(live_bottleneck) do
            effective_availability[science] = false
        end
        lsci = effective_availability
    end
    local sfq = get_virtual_queue_source(f.index, tsx)
    local sfsci = {}

    -- Try pinned first
    local pinned = queue.get_pinned_tech(f.index)
    if pinned and pinned ~= cur_name then
        local candidate, _ = find_runtime_candidate(f.index, pinned, tsx, lsci, sfsci)
        if candidate and candidate ~= cur_name then
            sq[keys.target_tech] = cur_name
            sq[keys.temp_tech] = candidate
            sq[keys.temp_tech_timeout] = game.tick + minimum_switch_ticks
            sq[keys.last_switch_tick] = game.tick
            notify_switch(f, cur_name, candidate, tsx, lsci)
            state.request_next_research(f)
            return
        end
    end

    -- Try queue order
    for _, q in ipairs(sfq or {}) do
        if q ~= cur_name and q ~= pinned then
            local candidate, _ = find_runtime_candidate(f.index, q, tsx, lsci, sfsci)
            if candidate and candidate ~= cur_name then
                sq[keys.target_tech] = cur_name
                sq[keys.temp_tech] = candidate
                sq[keys.temp_tech_timeout] = game.tick + minimum_switch_ticks
                sq[keys.last_switch_tick] = game.tick
                notify_switch(f, cur_name, candidate, tsx, lsci)
                state.request_next_research(f)
                return
            end
        end
    end
end
---------------------------------------------------------------------------
-- Ingame queue interactions
---------------------------------------------------------------------------

queue.sync_ingame_queue = function(f)
    local sfq = get(f.index, keys.queue)
    if not sfq then
        return
    end
    if not f.research_queue or next(f.research_queue) == nil or #f.research_queue == 0 then
        return
    end

    -- If there is only one item in the research queue check if it is our first next tech
    if #f.research_queue == 1 then
        local next = get_first_next_tech(f)
        if f.research_queue[1].name == next then
            return
        end
    end

    -- Remove all tech from our queue (if applicable) and add it again
    for _, t in pairs(f.research_queue) do
        queue.remove(f, t.name, true)
    end
    for i = #f.research_queue, 1, -1 do
        queue.add(f, f.research_queue[i].name, 1, true)
    end

    -- If we don't have anything in our queue but there is an in-game queue, add all tech
    if #sfq == 0 and f.research_queue and next(f.research_queue) ~= nil then
        for _, t in pairs(f.research_queue) do
            queue.add(f, t.name)
        end
        return
    end
end

-- This function requeues finished technology when applicable
---@param f LuaForce
---@param t LuaTechnology
queue.requeue_finished = function(f, t)
    local xcur = tech.get_single_tech_state_ext(f.index, t.name)
    if not xcur then
        logger.error(f, "Unexpected technology " .. (t.name or "(no technology passed)"))
        return
    end

    if queue.get_pinned_tech(f.index) == t.name then
        queue.set_pinned_tech(f.index, nil)
    end

    -- If the finished tech was a temporary switch, clear the temp state
    if get(f.index, keys.temp_tech) == t.name then
        set(f.index, keys.temp_tech, nil)
        set(f.index, keys.temp_tech_timeout, nil)
        -- Keep target_tech so we can try to return to it
    end

    -- For finite tech levels that are not fully researched yet we only need to request the next stage
    if xcur.technology.level and not xcur.meta.is_infinite and not xcur.technology.researched then
        return
    end

    -- For all other cases we have to remove the tech from the queue
    queue.remove(f, t.name, true)

    -- If it is an infinite tech and requeueing is enabled we have to add it to the end of the queue again
    local global_repeat = state.get_force_setting(f.index, "requeue_infinite_tech",
        const.default_settings.force.settings.requeue_infinite_tech)
    local next_level = xcur.technology.level
    if xcur.meta.is_infinite and policy.should_requeue(f.index, t.name, next_level, global_repeat) then
        queue.add(f, t.name)
        policy.consume_repeat(f.index, t.name)
    end
end

queue.start_next_research = function(f)
    -- Early exit if no force
    if not f then
        return
    end

    -- Early exit if LilEinstein is disabled
    local st = state.get_force_setting(f.index, "master_enable")
    if st == "left" then
        return
    end
    if policy.get_setting(f.index, "planning_paused") then
        queue.apply_planning_pause(f)
        return
    end

    local sfq = get(f.index, keys.queue)
    local auto_research = state.get_force_setting(f.index, "auto_research",
        const.default_settings.force.settings.auto_research)

    -- If no queue and auto-research is off, clear game queue and idle
    if not sfq or #sfq == 0 then
        if policy.get_setting(f.index, "strategy") == "focused" then
            f.research_queue = {}
            return
        end
        if not auto_research then
            f.research_queue = {}
            warn_force(f, {"lil_einstein-warn.empty-research-queue"})
            return
        end
        queue.build_queue_from_available(f.index)
        sfq = get(f.index, keys.queue)
        if not sfq or #sfq == 0 then
            f.research_queue = {}
            warn_force(f, {"lil_einstein-warn.empty-research-queue"})
            return
        end
    end

    queue.reorder_queue_by_score(f.index)
    if get(f.index, keys.current_tech) then
        return
    end

    if auto_research and not f.current_research then
        queue.build_queue_from_available(f.index)
        queue.reorder_queue_by_score(f.index)
        if get(f.index, keys.current_tech) then
            return
        end
    end

    -- Nothing in the queue can be started (all blocked or missing science)
    if sfq and #sfq > 0 then
        local missing = get(f.index, keys.misses_science)
        warn_force(f, {"lil_einstein-warn.no-techs-available", make_science_icon_string(missing)})
    end
    f.research_queue = {}
end

---------------------------------------------------------------------------
-- Queue manipulation
---------------------------------------------------------------------------

---@param f LuaForce
---@param tech_name string technology name
---@param pos? int position
---@param silent? bool announce or not
queue.add = function(f, tech_name, pos, silent)
    if not tech_name then
        return
    end
    -- This function adds a new technology to the modqueue
    -- If no position is given assume append at the end
    -- Check if technology is valid or early exit
    local t = f.technologies[tech_name]
    if not t or not t.valid then
        if t and t.name and t.name ~= "" then
            logger.error(f, "Trying to queue technology '" .. t.name .. "' but it is not valid, please open a bug report on the mod portal")
        else
            logger.error(f, "Trying to queue technology '" .. serpent.line(t) .. "' but it is not valid, please open a bug report on the mod portal")
        end
        return
    end

    -- Check if this research is actually available or early exit
    if not t.enabled then
        if not silent then
            logger.warn(f, {"lil_einstein-msg.warn-queue-disabled", t.localised_name})
        end
        return
    end

    local sfq = get(f.index, keys.queue)

    -- Eary exit if this technology is already scheduled
    for _, q in pairs(sfq or {}) do
        if q == t.name then
            -- TODO: If the user adds an infinite tech multiple times to the in-game queue we need to trigger the auto clean-up
            local t = f.technologies[q]
            if not silent then
                logger.log(f, {"lil_einstein-msg.already-queued", t.localised_name})
            end
            return
        end
    end

    -- Add the tech to our queue
    if pos then
        table.insert(sfq, pos, tech_name)
    else
        table.insert(sfq, tech_name)
    end

    -- Register queued
    tech.update_queued(f.index, tech_name, true)

    if not silent then
        -- Request next research
        state.request_next_research(f)

        -- Announce
        logger.log(f, {"lil_einstein-msg.added-to-queue", t.localised_name})
    end
end

---@param f LuaForce
---@param tech_name string technology name
---@param silent? bool position
queue.remove = function(f, tech_name, silent)
    -- This function removes a technology from the modqueue

    -- Go through our queue and drop the target tech
    local sfq = get(f.index, keys.queue)
    for i, q in ipairs(sfq or {}) do
        if q == tech_name then
            -- We found our target tech, remove it from our queue
            table.remove(sfq, i)

            -- Deregister queued
            tech.update_queued(f.index, tech_name, false)

            if not silent then
                -- Request next research
                state.request_next_research(f)

                -- Announce
                local t = f.technologies[q]
                logger.log(f, {"lil_einstein-msg.removed-from-queue", t.localised_name})
            end

            -- Exit because there is nothing more to do
            return
        end
    end

end

local move_research = function(f, tech_name, old_position, new_position)
    -- Early exit if same position
    if old_position == new_position then
        return
    end

    -- Get the queue
    local gfq = get(f.index, keys.queue)
    if not gfq then
        return
    end

    -- Remove the old position
    table.remove(gfq, old_position)

    -- Insert the item on the new position
    table.insert(gfq, new_position, tech_name)

    -- Request next research
    state.request_next_research(f)

end

queue.promote = function(f, tech_name, steps)
    -- Check if technology is valid or early exit
    local t = f.technologies[tech_name] or nil
    if not t or not t.valid then
        return
    end
    steps = steps or 1

    -- Get the current position or early exit if already first
    local i = get_queue_position(f, tech_name)
    if not i or i == 1 then
        return
    end

    -- Calculate new position
    local new_position
    if i - steps < 1 then
        new_position = 1
    else
        new_position = i - steps
    end

    move_research(f, tech_name, i, new_position)
end

queue.demote = function(f, tech_name, steps)
    -- Check if technology is valid or early exit
    local t = f.technologies[tech_name] or nil
    if not t or not t.valid then
        return
    end
    steps = steps or 1

    -- Get the current index and length or early exit if already last
    local i = get_queue_position(f, tech_name)
    if not i then
        return
    end
    local l = get_queue_length(f)
    if i == l then
        return
    end

    -- Calculate new position
    local new_position
    if i + steps > l then
        new_position = l
    else
        new_position = i + steps
    end

    -- Do the move
    move_research(f, tech_name, i, new_position or i + 1)
end

queue.clean_ingame_queue_timeout = function(f)
    -- This function is to be called after a timeout when the user changes the ingame queue
    -- At the point this function is called we don't know what caused it
    -- To check wether cleanup is actually needed we can check the following;
    -- if the length is 0 or 1 and the tech matches one of the entry tech from our modqueue,
    -- then we don't have to clean up the ingame queue
    -- Note: We might have a ingame queue length of 0 and a modqueue length of >0
    -- when all modqueued tech are blocked
    -- if the length is >1 then a clean up is needed
    local sfq = get(f.index, keys.queue)
    if not sfq then
        return
    end
    if not f.research_queue or next(f.research_queue) == nil or #f.research_queue <= 1 then
        return
    end

    -- -- Remove all tech from our queue (if applicable) and add it again
    -- for _, t in pairs(f.research_queue) do
    --     queue.remove(f, t.name, true)
    -- end
    -- for i = #f.research_queue, 1, -1 do
    --     queue.add(f, f.research_queue[i].name, 1, true)
    -- end
    queue.start_next_research(f)
end

queue.clear = function(f)
    -- This function clears the ingame queue
    local sfq = get(f.index, keys.queue)
    if not sfq then
        return
    end
    for i = #sfq, 1, -1 do
        queue.remove(f, sfq[i])
    end

    -- Clear force ingame queue and request GUI update
    f.research_queue = {}
    state.request_gui_update(f)
end

---------------------------------------------------------------------------
-- Interfaces
---------------------------------------------------------------------------
queue.get_queue = function(force_index)
    return get(force_index, keys.queue)
end

local research_sample_is_valid = function(sample)
    return sample and (sample.valid_speed == true or
               (sample.valid_speed == nil and sample.speed and sample.speed > 0))
end

local get_average_research_speed = function(samples, sample_count)
    if not samples or #samples == 0 then
        return nil, false
    end

    local total = 0
    local count = 0
    local start_index = math.max(1, #samples - (sample_count or research_speed_average_samples) + 1)
    for i = start_index, #samples do
        local s = samples[i]
        if research_sample_is_valid(s) then
            total = total + (s.speed or 0)
            count = count + 1
        end
    end

    if count > 0 then
        return total / count, true
    end
    return nil, false
end


local get_research_speed_window = function(samples, start_offset, sample_count, tech_name)
    if not samples or #samples == 0 or sample_count <= 0 then
        return nil, 0
    end

    local end_index = #samples - (start_offset or 0)
    local start_index = math.max(1, end_index - sample_count + 1)
    local total = 0
    local count = 0
    for i = start_index, end_index do
        local sample = samples[i]
        if research_sample_is_valid(sample) and (not tech_name or sample.tech_name == tech_name) then
            total = total + (sample.speed or 0)
            count = count + 1
        end
    end
    if count == 0 then
        return nil, 0
    end
    return total / count, count
end

local new_research_spm_history = function()
    local values = {}
    for i = 1, research_history_samples do
        values[i] = 0
    end

    return {
        values = values,
        head = 0,
        count = 0,
        size = research_history_samples,
        last_tick = nil
    }
end

local write_research_spm_history = function(history, spm, tick)
    if not history then
        return
    end

    history.head = ((history.head or 0) % research_history_samples) + 1
    history.values[history.head] = spm or 0
    history.count = math.min((history.count or 0) + 1, research_history_samples)
    history.last_tick = tick
end

local ensure_research_spm_history = function(sq)
    if not sq then
        return nil
    end

    local history = sq.research_spm_history
    if history and history.size == research_history_samples and type(history.values) == "table" then
        for i = 1, research_history_samples do
            history.values[i] = history.values[i] or 0
        end

        history.count = math.min(math.max(math.floor(history.count or 0), 0), research_history_samples)
        if history.count > 0 then
            history.head = ((math.floor(history.head or history.count) - 1) % research_history_samples) + 1
        else
            history.head = 0
        end
        return history
    end

    history = new_research_spm_history()

    -- Backfill once from the old sampled deltas so existing saves do not lose all visible history.
    local samples = sq.speed_samples
    if samples and #samples > 0 then
        local first_index = math.max(1, #samples - research_history_samples + 1)
        local rolling_samples = {}
        for i = first_index, #samples do
            local item = samples[i]
            if item then
                table.insert(rolling_samples, item)
                while #rolling_samples > research_speed_average_samples do
                    table.remove(rolling_samples, 1)
                end

                local average_speed = get_average_research_speed(rolling_samples, research_speed_average_samples)
                write_research_spm_history(history, average_speed and (average_speed * 60) or 0, item.tick)
            end
        end
    end

    sq.research_spm_history = history
    return history
end

queue.record_research_progress = function(force_index)
    -- Sample actual research progress every 3 seconds to match the 10-minute graph window.
    local f = game.forces[force_index]
    if not f then return end

    local sf = storage.forces[force_index]
    if not sf then return end
    if not sf.queue then sf.queue = {} end
    local history = ensure_research_spm_history(sf.queue)
    if not sf.queue.speed_samples then
        sf.queue.speed_samples = {}
    end
    local samples = sf.queue.speed_samples

    local now = game.tick
    local current = f.current_research
    local progress = current and (f.research_progress or 0) or 0
    local tech_name = current and current.name or nil
    local unit_count = current and (current.research_unit_count or 1) or 0
    local speed = 0
    local valid_speed = false

    -- Compute speed if same research as previous sample
    if #samples > 0 then
        local last = samples[#samples]
        if current and last.tech_name == tech_name and progress >= last.progress then
            local delta_progress = progress - last.progress
            local delta_ticks = now - last.tick
            -- units per second = (fraction_complete * total_units) / seconds
            if delta_ticks > 0 then
                speed = (delta_progress * unit_count * 60) / delta_ticks
                valid_speed = true
            end
        end
    end

    table.insert(samples, {
        tick = now,
        progress = progress,
        tech_name = tech_name,
        unit_count = unit_count,
        speed = speed,
        valid_speed = valid_speed
    })

    -- Keep only the last 10 minutes at one sample every 3 seconds.
    while #samples > research_history_samples do
        table.remove(samples, 1)
    end

    local average_speed = get_average_research_speed(samples, research_speed_average_samples)
    write_research_spm_history(history, average_speed and (average_speed * 60) or 0, now)
end

queue.get_research_speed = function(force_index)
    -- Return average measured research speed in units/second, and a flag.
    local sf = storage.forces[force_index]
    if not sf or not sf.queue or not sf.queue.speed_samples then
        return nil, false
    end
    return get_average_research_speed(sf.queue.speed_samples, research_speed_average_samples)
end

queue.get_research_history = function(force_index, bucket_count)
    local res = {}
    bucket_count = bucket_count or 64
    for i = 1, bucket_count do
        res[i] = 0
    end

    local sf = storage.forces[force_index]
    if not sf or not sf.queue then
        return res, false
    end

    local history = ensure_research_spm_history(sf.queue)
    if not history or not history.values then
        return res, false
    end

    local output_count = math.min(research_history_samples, bucket_count)
    local output_start = bucket_count - output_count + 1
    local head = history.head or 0
    if head < 1 then
        return res, true
    end

    for i = 1, output_count do
        local offset = output_count - i
        local slot = ((head - offset - 1) % research_history_samples) + 1
        res[output_start + i - 1] = history.values[slot] or 0
    end
    return res, true
end

queue.get_research_summary = function(force_index)
    local f = game.forces[force_index]
    local speed = queue.get_research_speed(force_index)
    local spm = speed and (speed * 60) or 0
    local res = {
        progress = 0,
        done = 0,
        total = 0,
        spm = spm,
        remaining_seconds = nil,
        is_researching = false
    }

    if not f or not f.current_research then
        return res
    end

    local current = f.current_research
    local progress = f.research_progress or 0
    local total = current.research_unit_count or 1
    local done = math.floor((progress * total) + 0.5)
    local remaining = math.max(0, total - (progress * total))

    res.progress = progress
    res.done = done
    res.total = total
    res.is_researching = true
    if speed and speed > 0 then
        res.remaining_seconds = math.ceil(remaining / speed)
    end

    return res
end

-- Two-tier cache per force:
--   labs_cache: labs, refreshed every 10 min (36000 ticks)
--   counts_cache: counts refreshed every tick
local labs_cache = {}
local counts_cache = {}
local diagnostic_cache = {}
local forecast_cache = {}

local has_invalid_ref = function(refs)
    for _, ref in pairs(refs or {}) do
        if not ref or not ref.valid then
            return true
        end
    end
    return false
end

local get_lab_network = function(lab_entity)
    if not lab_entity or not lab_entity.valid then
        return nil
    end

    local force = lab_entity.force
    local surface = lab_entity.surface
    local position = lab_entity.position
    if force and surface and position then
        local network = force.find_logistic_network_by_position(position, surface)
        if network and network.valid then
            return network
        end
    end

    return nil
end

local get_network_label = function(network, sample_lab)
    local surface_name = "unknown"
    if sample_lab and sample_lab.valid and sample_lab.surface and sample_lab.surface.valid then
        surface_name = sample_lab.surface.name or "unknown"
    end
    local network_id = "?"
    if network and network.valid and network.network_id then
        network_id = tostring(network.network_id)
    end
    return "Network #" .. network_id .. " (" .. tostring(surface_name) .. ")"
end

local refresh_labs_cache = function(force_index)
    local all_labs = {}

    for _, surface in pairs(game.surfaces) do
        local surface_labs = surface.find_entities_filtered({type = "lab", force = force_index})
        for _, lab_entity in pairs(surface_labs) do
            if lab_entity.valid then
                table.insert(all_labs, lab_entity)
            end
        end
    end

    labs_cache[force_index] = {
        tick = game.tick,
        labs = all_labs
    }
end

local get_cached_labs = function(force_index)
    local now = game.tick
    local lc = labs_cache[force_index]
    if not lc or (now - lc.tick) >= 36000 or has_invalid_ref(lc.labs) then
        refresh_labs_cache(force_index)
        lc = labs_cache[force_index]
    end
    return (lc and lc.labs) or {}
end

get_science_counts = function(force_index)
    local now = game.tick

    -- Refresh labs/network cache every 10 minutes, or immediately if refs went invalid (save/load)
    local all_labs = get_cached_labs(force_index)

    -- Count cache is per-tick
    local cc = counts_cache[force_index]
    if cc and cc.tick == now then
        return cc.counts
    end

    local counts = {}
    local detected_networks = {}
    local clusters = {}
    local breakdown = {}
    local all_sciences = env.get_all_sciences()
    for _, science in pairs(all_sciences) do
        breakdown[science] = {
            lab_count = 0,
            lab_entity_count = 0,
            network_total = 0,
            networks = {}
        }
    end

    -- Packs in labs
    for _, lab_entity in pairs(all_labs) do
        if lab_entity.valid then
            local inv = lab_entity.get_inventory(defines.inventory.lab_input)
            local network = get_lab_network(lab_entity)
            local surface_index = lab_entity.surface and lab_entity.surface.index or 0
            local cluster_key
            local cluster
            if network and network.valid then
                local network_id = network.network_id
                cluster_key = tostring(surface_index) .. ":network:" .. tostring(network_id or "unknown")
                local cur = detected_networks[cluster_key]
                if not cur then
                    cur = {
                        key = cluster_key,
                        network_id = network_id,
                        network = network,
                        lab_count = 0,
                        sample_lab = lab_entity,
                        sample_unit_number = lab_entity.unit_number or 0
                    }
                    detected_networks[cluster_key] = cur
                end
                if cur then
                    cur.lab_count = cur.lab_count + 1
                end
                cluster = clusters[cluster_key]
                if not cluster then
                    cluster = {
                        key = cluster_key,
                        label = get_network_label(network, lab_entity),
                        surface_index = surface_index,
                        surface_name = lab_entity.surface and lab_entity.surface.name or "unknown",
                        network_id = network_id,
                        lab_count = 0,
                        counts = {},
                        lab_input_counts = {},
                        lab_input_sets = {}
                    }
                    clusters[cluster_key] = cluster
                end
            else
                cluster_key = tostring(surface_index) .. ":lab:" .. tostring(lab_entity.unit_number or 0)
                cluster = clusters[cluster_key]
                if not cluster then
                    cluster = {
                        key = cluster_key,
                        label = "Direct-fed lab (" .. tostring(lab_entity.surface and lab_entity.surface.name or "unknown") .. ")",
                        surface_index = surface_index,
                        surface_name = lab_entity.surface and lab_entity.surface.name or "unknown",
                        lab_count = 0,
                        counts = {},
                        lab_input_counts = {},
                        lab_input_sets = {}
                    }
                    clusters[cluster_key] = cluster
                end
            end
            cluster.lab_count = cluster.lab_count + 1
            local lab_inputs = {}
            for _, science in pairs((lab_entity.prototype and lab_entity.prototype.lab_inputs) or {}) do
                lab_inputs[science] = true
                cluster.lab_input_counts[science] = (cluster.lab_input_counts[science] or 0) + 1
            end
            table.insert(cluster.lab_input_sets, lab_inputs)
            if inv then
                for _, item in pairs(inv.get_contents()) do
                    counts[item.name] = (counts[item.name] or 0) + (item.count or 0)
                    cluster.counts[item.name] = (cluster.counts[item.name] or 0) + (item.count or 0)
                    local item_breakdown = breakdown[item.name]
                    if item_breakdown then
                        item_breakdown.lab_count = item_breakdown.lab_count + (item.count or 0)
                        item_breakdown.lab_entity_count = item_breakdown.lab_entity_count + 1
                    end
                end
            end
        end
    end

    -- Add robot network stock for every network attached to the detected labs
    local sorted_networks = {}
    for _, network_meta in pairs(detected_networks) do
        table.insert(sorted_networks, network_meta)
    end
    table.sort(sorted_networks, function(a, b)
        local a_surface = (a.sample_lab and a.sample_lab.valid and a.sample_lab.surface and a.sample_lab.surface.name) or ""
        local b_surface = (b.sample_lab and b.sample_lab.valid and b.sample_lab.surface and b.sample_lab.surface.name) or ""
        if a_surface == b_surface then
            return (a.sample_unit_number or 0) < (b.sample_unit_number or 0)
        end
        return a_surface < b_surface
    end)
    for _, network_meta in pairs(sorted_networks) do
        local network = network_meta.network
        if network and network.valid then
            local network_label = get_network_label(network, network_meta.sample_lab)
            local cluster = clusters[network_meta.key]
            for _, science in pairs(all_sciences) do
                local network_count = network.get_item_count(science)
                counts[science] = (counts[science] or 0) + network_count
                if cluster then
                    cluster.counts[science] = (cluster.counts[science] or 0) + network_count
                end
                local science_breakdown = breakdown[science]
                science_breakdown.network_total = science_breakdown.network_total + network_count
                table.insert(science_breakdown.networks, {
                    label = network_label,
                    count = network_count,
                    lab_count = network_meta.lab_count
                })
            end
        end
    end

    counts_cache[force_index] = {tick = now, counts = counts, breakdown = breakdown, clusters = clusters}
    return counts
end

queue.get_science_counts = get_science_counts
queue.get_science_clusters = function(force_index)
    local cc = counts_cache[force_index]
    if not cc or cc.tick ~= game.tick then
        get_science_counts(force_index)
        cc = counts_cache[force_index]
    end
    return (cc and cc.clusters) or {}
end
queue.invalidate_science_cache = function(force_index)
    labs_cache[force_index] = nil
    counts_cache[force_index] = nil
    diagnostic_cache[force_index] = nil
    forecast_cache[force_index] = nil
end

queue.get_science_count_breakdown = function(force_index, science)
    local cc = counts_cache[force_index]
    if not cc or cc.tick ~= game.tick then
        get_science_counts(force_index)
        cc = counts_cache[force_index]
    end
    if not cc or not cc.breakdown then
        return {
            lab_count = 0,
            lab_entity_count = 0,
            network_total = 0,
            networks = {}
        }
    end
    return cc.breakdown[science] or {
        lab_count = 0,
        lab_entity_count = 0,
        network_total = 0,
        networks = {}
    }
end

get_lab_science_counts = function(force_index)
    local counts = {}
    local valid_lab_count = 0
    local sfl = storage.forces[force_index] and storage.forces[force_index].lab

    if sfl and sfl.all_labs and sfl.lab_content then
        for _, unit_number in ipairs(sfl.all_labs) do
            local lcur = sfl.lab_content[unit_number]
            local lab_entity = lcur and lcur.lab
            if lab_entity and lab_entity.valid then
                valid_lab_count = valid_lab_count + 1
                local inv = lab_entity.get_inventory(defines.inventory.lab_input)
                if inv then
                    for _, item in pairs(inv.get_contents()) do
                        counts[item.name] = (counts[item.name] or 0) + (item.count or 0)
                    end
                end
            end
        end
        return counts, valid_lab_count
    end

    refresh_labs_cache(force_index)
    local lc = labs_cache[force_index]
    for _, lab_entity in pairs((lc and lc.labs) or {}) do
        if lab_entity.valid then
            valid_lab_count = valid_lab_count + 1
            local inv = lab_entity.get_inventory(defines.inventory.lab_input)
            if inv then
                for _, item in pairs(inv.get_contents()) do
                    counts[item.name] = (counts[item.name] or 0) + (item.count or 0)
                end
            end
        end
    end

    return counts, valid_lab_count
end

local lab_accepts_research = function(lab_entity, current)
    local accepted = {}
    for _, science in pairs(lab_entity.prototype.lab_inputs or {}) do
        accepted[science] = true
    end
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        if not accepted[ingredient.name] then
            return false
        end
    end
    return true
end

local get_lab_capacity_spm = function(lab_entity, current)
    local research_energy = current.research_unit_energy or 0
    if research_energy <= 0 then
        return 0
    end

    local base_speed = lab_entity.prototype.get_researching_speed(lab_entity.quality) or 0
    local speed_multiplier = math.max(0, 1 + (lab_entity.speed_bonus or 0))
    local productivity_multiplier = math.max(0, 1 + (lab_entity.productivity_bonus or 0))

    -- Runtime research energy is measured in ticks; 3600 converts units/tick to units/minute.
    return base_speed * speed_multiplier * productivity_multiplier * 3600 / research_energy
end

local get_missing_lab_sciences = function(lab_entity, current)
    local present = {}
    local inv = lab_entity.get_inventory(defines.inventory.lab_input)
    if inv then
        for _, item in pairs(inv.get_contents()) do
            present[item.name] = (present[item.name] or 0) + (item.count or 0)
        end
    end

    local res = {}
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        if (present[ingredient.name] or 0) < (ingredient.amount or 1) then
            table.insert(res, ingredient.name)
        end
    end
    return res
end

queue.get_research_diagnostic = function(force_index)
    local cached = diagnostic_cache[force_index]
    if cached and cached.tick == game.tick then
        return cached.value
    end

    local f = game.forces[force_index]
    local current = f and f.current_research
    local speed = queue.get_research_speed(force_index)
    local res = {
        available = current ~= nil,
        actual_spm = speed and (speed * 60) or 0,
        recent_spm = nil,
        previous_spm = nil,
        trend_percent = nil,
        expected_spm = 0,
        working_spm = 0,
        utilization = 0,
        total_labs = 0,
        compatible_labs = 0,
        working_labs = 0,
        incompatible_labs = 0,
        causes = {},
        missing_sciences = {}
    }

    if not current then
        diagnostic_cache[force_index] = {tick = game.tick, value = res}
        return res
    end

    local sf = storage.forces[force_index]
    local samples = sf and sf.queue and sf.queue.speed_samples
    local recent_speed, recent_count = get_research_speed_window(samples, 0, 5, current.name)
    local previous_speed, previous_count = get_research_speed_window(samples, 5, 15, current.name)
    if recent_count >= 2 then
        res.recent_spm = recent_speed * 60
    end
    if previous_count >= 2 then
        res.previous_spm = previous_speed * 60
    end
    if res.recent_spm and res.previous_spm and res.previous_spm > 0 then
        res.trend_percent = ((res.recent_spm - res.previous_spm) * 100) / res.previous_spm
    end

    local cause_data = {
        missing_science = {kind = "missing_science", labs = 0, lost_spm = 0},
        power = {kind = "power", labs = 0, lost_spm = 0},
        disabled = {kind = "disabled", labs = 0, lost_spm = 0},
        frozen = {kind = "frozen", labs = 0, lost_spm = 0},
        no_research = {kind = "no_research", labs = 0, lost_spm = 0},
        other = {kind = "other", labs = 0, lost_spm = 0}
    }
    local missing_sciences = {}

    for _, lab_entity in pairs(get_cached_labs(force_index)) do
        if lab_entity and lab_entity.valid then
            res.total_labs = res.total_labs + 1
            if not lab_accepts_research(lab_entity, current) then
                res.incompatible_labs = res.incompatible_labs + 1
                goto continue
            end

            res.compatible_labs = res.compatible_labs + 1
            local capacity_spm = get_lab_capacity_spm(lab_entity, current)
            res.expected_spm = res.expected_spm + capacity_spm
            local status = lab_entity.status

            if status == defines.entity_status.working then
                res.working_labs = res.working_labs + 1
                res.working_spm = res.working_spm + capacity_spm
            elseif status == defines.entity_status.missing_science_packs then
                local cause = cause_data.missing_science
                cause.labs = cause.labs + 1
                cause.lost_spm = cause.lost_spm + capacity_spm
                local missing = get_missing_lab_sciences(lab_entity, current)
                for _, science in pairs(missing) do
                    local item = missing_sciences[science]
                    if not item then
                        item = {science = science, labs = 0, lost_spm = 0}
                        missing_sciences[science] = item
                    end
                    item.labs = item.labs + 1
                    item.lost_spm = item.lost_spm + capacity_spm
                end
            elseif status == defines.entity_status.no_power or status == defines.entity_status.low_power or
                   status == defines.entity_status.no_fuel or
                   status == defines.entity_status.not_plugged_in_electric_network then
                local cause = cause_data.power
                cause.labs = cause.labs + 1
                cause.lost_spm = cause.lost_spm + capacity_spm
            elseif status == defines.entity_status.disabled_by_control_behavior or
                   status == defines.entity_status.disabled_by_script or status == defines.entity_status.disabled or
                   status == defines.entity_status.closed_by_circuit_network or
                   status == defines.entity_status.marked_for_deconstruction then
                local cause = cause_data.disabled
                cause.labs = cause.labs + 1
                cause.lost_spm = cause.lost_spm + capacity_spm
            elseif status == defines.entity_status.frozen or lab_entity.frozen then
                local cause = cause_data.frozen
                cause.labs = cause.labs + 1
                cause.lost_spm = cause.lost_spm + capacity_spm
            elseif status == defines.entity_status.no_research_in_progress then
                local cause = cause_data.no_research
                cause.labs = cause.labs + 1
                cause.lost_spm = cause.lost_spm + capacity_spm
            else
                local cause = cause_data.other
                cause.labs = cause.labs + 1
                cause.lost_spm = cause.lost_spm + capacity_spm
            end
        end
        ::continue::
    end

    if res.expected_spm > 0 then
        res.utilization = math.max(0, math.min(1, res.actual_spm / res.expected_spm))
    end

    for _, cause in pairs(cause_data) do
        if cause.labs > 0 then
            table.insert(res.causes, cause)
        end
    end
    table.sort(res.causes, function(a, b)
        if a.lost_spm == b.lost_spm then
            return a.kind < b.kind
        end
        return a.lost_spm > b.lost_spm
    end)

    for _, item in pairs(missing_sciences) do
        table.insert(res.missing_sciences, item)
    end
    table.sort(res.missing_sciences, function(a, b)
        if a.lost_spm == b.lost_spm then
            return a.science < b.science
        end
        return a.lost_spm > b.lost_spm
    end)

    diagnostic_cache[force_index] = {tick = game.tick, value = res}
    return res
end

-- The throughput panel observes live lab starvation, while aggregate availability
-- includes packs elsewhere in the supply network. Treat a dominant live missing-pack
-- loss as a real bottleneck for the active technology so the switcher uses the same
-- player-visible truth as the diagnostic.
queue.get_active_missing_science_bottleneck = function(force_index, xcur)
    local f = game.forces[force_index]
    if not f or not f.current_research or not xcur or not xcur.technology or
        f.current_research.name ~= xcur.technology.name then
        return {}
    end

    local diagnostic = queue.get_research_diagnostic(force_index)
    local expected_spm = diagnostic and diagnostic.expected_spm or 0
    if not diagnostic or not diagnostic.available or expected_spm <= 0 or
        (diagnostic.utilization or 0) >= 0.60 then
        return {}
    end

    local missing_cause
    for _, cause in ipairs(diagnostic.causes or {}) do
        if cause.kind == "missing_science" then
            missing_cause = cause
            break
        end
    end
    if not missing_cause or (missing_cause.lost_spm or 0) < expected_spm * 0.40 then
        return {}
    end

    local res = {}
    for _, item in ipairs(diagnostic.missing_sciences or {}) do
        if item.science and (item.labs or 0) > 0 then
            res[item.science] = true
        end
    end
    return res
end

queue.science_is_sufficient = function(xcur, force_index)
    return science_supply_is_sufficient(xcur, force_index)
end

queue.get_science_availability = function(force_index)
    local counts = get_science_counts(force_index)
    local clusters = queue.get_science_clusters(force_index)
    local cluster_mode = policy.get_setting(force_index, "cluster_mode")
    local res = {}
    local active_cluster_keys = {}
    if cluster_mode then
        for _, cluster in pairs(clusters) do
            active_cluster_keys[cluster.key] = true
            cluster.available_sciences = {}
        end
    end
    for _, science in pairs(env.get_all_sciences()) do
        local science_policy = policy.get_science_policy(force_index, science)
        local available = false

        if cluster_mode then
            for _, cluster in pairs(clusters) do
                local previous = policy.get_cluster_science_available_state(force_index, cluster.key, science, false)
                local threshold = previous and science_policy.lower_threshold or science_policy.upper_threshold
                local lab_count = (cluster.lab_input_counts and cluster.lab_input_counts[science]) or 0
                local required_count = math.max(1, lab_count * science_reserve_per_lab * threshold)
                local cluster_available = lab_count > 0 and (cluster.counts[science] or 0) >= required_count
                policy.set_cluster_science_available_state(force_index, cluster.key, science, cluster_available)
                cluster.available_sciences[science] = cluster_available
                available = available or cluster_available
            end
        else
            local previous = policy.get_science_available_state(force_index, science, false)
            local threshold = previous and science_policy.lower_threshold or science_policy.upper_threshold
            local relevant_lab_count = 0
            for _, cluster in pairs(clusters) do
                relevant_lab_count = relevant_lab_count +
                    ((cluster.lab_input_counts and cluster.lab_input_counts[science]) or 0)
            end
            local required_count = math.max(1, relevant_lab_count * science_reserve_per_lab * threshold)
            available = relevant_lab_count > 0 and (counts[science] or 0) >= required_count
        end

        policy.set_science_available_state(force_index, science, available)
        res[science] = available
    end
    if cluster_mode then
        policy.prune_cluster_science_states(force_index, active_cluster_keys)
    end
    res.__cluster_mode = cluster_mode == true
    res.__clusters = clusters
    res.__force_index = force_index
    return res
end

queue.get_science_forecast = function(force_index)
    local cached = forecast_cache[force_index]
    if cached and cached.tick == game.tick then
        return cached.value
    end
    local f = game.forces[force_index]
    if not f then
        return {}
    end

    local counts = get_science_counts(force_index)
    local res = {}
    local precision = defines.flow_precision_index.one_minute

    for _, science in pairs(env.get_all_sciences()) do
        local production = 0
        local consumption = 0
        for _, surface in pairs(game.surfaces) do
            local ok_stats, stats = pcall(function()
                return f.get_item_production_statistics(surface)
            end)
            if ok_stats and stats and stats.valid then
                local ok_input, input = pcall(function()
                    return stats.get_flow_count({
                        name = science,
                        category = "input",
                        precision_index = precision
                    })
                end)
                local ok_output, output = pcall(function()
                    return stats.get_flow_count({
                        name = science,
                        category = "output",
                        precision_index = precision
                    })
                end)
                if ok_input then
                    production = production + math.max(0, input or 0)
                end
                if ok_output then
                    consumption = consumption + math.max(0, output or 0)
                end
            end
        end

        local science_policy = policy.get_science_policy(force_index, science)
        local relevant_lab_count = 0
        for _, cluster in pairs(queue.get_science_clusters(force_index)) do
            relevant_lab_count = relevant_lab_count +
                ((cluster.lab_input_counts and cluster.lab_input_counts[science]) or 0)
        end
        local target = relevant_lab_count * science_reserve_per_lab * science_policy.upper_threshold
        local stock = counts[science] or 0
        local net = production - consumption
        local depletion_seconds
        local recovery_seconds
        if net < -0.001 and stock > 0 then
            depletion_seconds = (stock / -net) * 60
        elseif net > 0.001 and stock < target then
            recovery_seconds = ((target - stock) / net) * 60
        end

        res[science] = {
            stock = stock,
            target = target,
            production_per_minute = production,
            consumption_per_minute = consumption,
            net_per_minute = net,
            depletion_seconds = depletion_seconds,
            recovery_seconds = recovery_seconds
        }
    end
    forecast_cache[force_index] = {tick = game.tick, value = res}
    return res
end

local get_research_unit_count_at_level = function(xcur, level)
    local cost = xcur.technology.research_unit_count or 1
    if xcur.meta.is_infinite and xcur.meta.prototype.research_unit_count_formula then
        local est = eval_formula(xcur.meta.prototype.research_unit_count_formula, level or xcur.technology.level)
        if est then
            cost = est
        end
    end
    return cost
end

local get_research_unit_count = function(xcur)
    return get_research_unit_count_at_level(xcur, xcur.technology.level)
end

local runtime_avg_cost_cache = {}
get_runtime_candidate_average_cost = function(force_index, tsx)
    local cached = runtime_avg_cost_cache[force_index]
    if cached and cached.tick == game.tick then
        return cached.value
    end
    local total_cost_sum = 0
    local cost_count = 0
    for _, xcur in pairs(tsx or {}) do
        if tech_can_be_runtime_candidate(force_index, xcur) then
            total_cost_sum = total_cost_sum + get_research_unit_count(xcur)
            cost_count = cost_count + 1
        end
    end
    local value = nil
    if cost_count > 0 then
        value = total_cost_sum / cost_count
    end
    runtime_avg_cost_cache[force_index] = {tick = game.tick, value = value}
    return value
end

local get_all_runtime_candidate_names = function(force_index, tsx)
    local res = {}
    for tech_name, xcur in pairs(tsx or {}) do
        if tech_can_be_runtime_candidate(force_index, xcur) then
            table.insert(res, tech_name)
        end
    end
    table.sort(res)
    return res
end

local get_scored_queue_source = function(force_index, tsx, source)
    local scored = {}
    local seen = {}
    local avg_cost = get_runtime_candidate_average_cost(force_index, tsx)
    local pinned = queue.get_pinned_tech(force_index)

    for i, tech_name in ipairs(source or {}) do
        if not seen[tech_name] then
            seen[tech_name] = true

            local xcur = tsx and tsx[tech_name]
            if tech_can_be_runtime_candidate(force_index, xcur) then
                local stored_ub = queue.get_tech_ub(force_index, tech_name)
                local sd = queue.score_tech_detailed(xcur, xcur.technology.level, stored_ub, avg_cost, force_index)
                table.insert(scored, {
                    tech_name = tech_name,
                    score = sd.total,
                    source_index = i,
                    pinned = pinned == tech_name
                })
            end
        end
    end

    table.sort(scored, function(a, b)
        if a.pinned ~= b.pinned then
            return a.pinned
        end
        if a.score == b.score then
            if a.source_index == b.source_index then
                return a.tech_name < b.tech_name
            end
            return a.source_index < b.source_index
        end
        return a.score > b.score
    end)

    local res = {}
    for _, entry in ipairs(scored) do
        table.insert(res, entry.tech_name)
    end
    return res
end

get_virtual_queue_source = function(force_index, tsx)
    local sfq = get(force_index, keys.queue)
    if sfq and #sfq > 0 then
        return get_scored_queue_source(force_index, tsx, sfq)
    end

    if policy.get_setting(force_index, "strategy") == "focused" then
        return {}
    end
    local auto_research = state.get_force_setting(force_index, "auto_research",
        const.default_settings.force.settings.auto_research)
    if not auto_research then
        return {}
    end

    return get_scored_queue_source(force_index, tsx, get_all_runtime_candidate_names(force_index, tsx))
end

local get_virtual_research_entries = function(force_index, count)
    local f = game.forces[force_index]
    if not f then
        return {}
    end

    local tsx = tech.get_all_tech_state_ext(force_index)
    if not tsx then
        return {}
    end

    local sfq = get_virtual_queue_source(force_index, tsx) or {}
    local current_name = f.current_research and f.current_research.name
    if #sfq == 0 and not current_name then
        return {}
    end

    local speed, _ = queue.get_research_speed(force_index)
    if not speed or speed <= 0 then
        speed = nil
    end

    local lsci = queue.get_science_availability(force_index)
    local virtually_researched = {}
    for name, xcur in pairs(tsx) do
        if xcur.technology.researched then
            virtually_researched[name] = true
        end
    end

    local results = {}
    local cumulative_time = 0
    local max_results = count or math.huge
    local max_iter = math.max(#sfq * 10, (count or #sfq) * 10, 10)

    local add_entry = function(tech_name, xcur)
        local cost = get_research_unit_count(xcur)
        local duration
        if speed then
            duration = cost / speed
            if f.current_research and f.current_research.name == tech_name then
                duration = duration * math.max(0, 1 - (f.research_progress or 0))
            end
        end
        local availability_reason, missing_sciences = get_science_block_details(xcur, lsci)
        table.insert(results, {
            tech_name = tech_name,
            level = xcur.technology.level,
            cost = cost,
            duration = duration,
            wait_time = speed and cumulative_time or nil,
            xcur = xcur,
            has_science = availability_reason == nil,
            availability_reason = availability_reason,
            missing_sciences = missing_sciences
        })
        virtually_researched[tech_name] = true
        if duration then
            cumulative_time = cumulative_time + duration
        end
    end

    -- The preview is an execution plan, so the technology Factorio is actually
    -- researching must be first even when higher-scored entries are waiting for science.
    local current_xcur = current_name and tsx[current_name]
    if current_xcur and current_xcur.technology and current_xcur.meta then
        add_entry(current_name, current_xcur)
    end

    local get_ready_candidate = function(requested_name)
        if virtually_researched[requested_name] then
            return nil, nil
        end

        local xcur = tsx[requested_name]
        if not tech_can_be_runtime_candidate(force_index, xcur) then
            return nil, nil
        end

        local all_pre_met = true
        local prerequisite_names = {}
        for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
            table.insert(prerequisite_names, pre_req_tech)
            if not virtually_researched[pre_req_tech] then
                all_pre_met = false
            end
        end
        if all_pre_met then
            return requested_name, xcur
        end

        table.sort(prerequisite_names)
        for _, pre_req_tech in ipairs(prerequisite_names) do
            local xpre = tsx[pre_req_tech]
            if xpre and not virtually_researched[pre_req_tech] and
                tech_can_be_runtime_candidate(force_index, xpre) then
                local pre_all_met = true
                for pre_req_tech_2, _ in pairs(xpre.meta.all_prerequisites or {}) do
                    if not virtually_researched[pre_req_tech_2] then
                        pre_all_met = false
                        break
                    end
                end
                if pre_all_met then
                    return pre_req_tech, xpre
                end
            end
        end
        return nil, nil
    end

    while #results < max_results and max_iter > 0 do
        max_iter = max_iter - 1
        local selected_name
        local selected_xcur
        local blocked_name
        local blocked_xcur

        for _, q in ipairs(sfq) do
            local candidate_name, candidate_xcur = get_ready_candidate(q)
            if candidate_name then
                if science_is_available(candidate_xcur, lsci) then
                    selected_name = candidate_name
                    selected_xcur = candidate_xcur
                    break
                elseif not blocked_name then
                    blocked_name = candidate_name
                    blocked_xcur = candidate_xcur
                end
            end
        end

        selected_name = selected_name or blocked_name
        selected_xcur = selected_xcur or blocked_xcur
        if not selected_name then
            break
        end
        add_entry(selected_name, selected_xcur)
    end

    return results
end

local get_current_research_candidate_names = function(force_index, count)
    local tsx = tech.get_all_tech_state_ext(force_index)
    if not tsx then
        return {}
    end
    local source = get_virtual_queue_source(force_index, tsx)
    local lsci = queue.get_science_availability(force_index)
    local names = {}
    local seen = {}
    local maximum = count or math.huge

    local add_candidate = function(requested_name)
        local candidate = find_runtime_candidate(force_index, requested_name, tsx, lsci, {})
        if candidate and not seen[candidate] then
            seen[candidate] = true
            table.insert(names, candidate)
        end
    end

    local pinned = queue.get_pinned_tech(force_index)
    if pinned then
        add_candidate(pinned)
    end
    for _, tech_name in ipairs(source or {}) do
        if #names >= maximum then
            break
        end
        add_candidate(tech_name)
    end
    return names
end

local build_runtime_queue_names = function(force_index, active_name, count)
    local candidates = get_current_research_candidate_names(force_index, count)
    local names = {}
    local seen = {}

    if active_name then
        local tsx = tech.get_all_tech_state_ext(force_index)
        local xcur = tsx and tsx[active_name]
        if tech_can_be_runtime_candidate(force_index, xcur) and xcur.available then
            table.insert(names, active_name)
            seen[active_name] = true
        else
            active_name = nil
        end
    end
    if not active_name and candidates[1] then
        active_name = candidates[1]
        table.insert(names, active_name)
        seen[active_name] = true
    end

    for _, tech_name in ipairs(candidates) do
        if not seen[tech_name] then
            table.insert(names, tech_name)
            seen[tech_name] = true
        end
    end

    return names, active_name
end

local research_queue_matches = function(f, names)
    local current = f.research_queue
    if not current or #current ~= #names then
        return false
    end
    for i, tech_name in ipairs(names) do
        local queued_tech = current[i]
        local queued_name = queued_tech and queued_tech.name or queued_tech
        if queued_name ~= tech_name then
            return false
        end
    end
    return true
end

set_runtime_research_queue = function(f, names)
    if research_queue_matches(f, names) then
        return
    end
    mark_internal_research_queue_update(f.index, names)
    f.research_queue = names
end

queue.reorder_queue_by_score = function(force_index)
    local f = game.forces[force_index]
    if not f then return end

    local active_name = get_first_next_tech(f)
    local names, fallback_active = build_runtime_queue_names(force_index, active_name)
    if fallback_active and not active_name then
        set(force_index, keys.current_tech, fallback_active)
    end

    set_runtime_research_queue(f, names)
end

queue.rotate_parallel_research = function(f)
    if not f or not policy.get_setting(f.index, "parallel_research") or
        policy.get_setting(f.index, "planning_paused") then
        return
    end
    if state.get_force_setting(f.index, "master_enable") == "left" then
        return
    end

    local sfq = get(f.index, keys.queue)
    local auto_research = state.get_force_setting(f.index, "auto_research",
        const.default_settings.force.settings.auto_research)
    if (not sfq or #sfq == 0) and
        (not auto_research or policy.get_setting(f.index, "strategy") == "focused") then
        return
    end

    local slots = policy.get_setting(f.index, "parallel_slots") or 5
    local names = get_current_research_candidate_names(f.index, slots)
    if #names < 2 then
        return
    end

    -- When the dedicated Parallel Research mod is installed, Little Einstein supplies and orders
    -- the queue while that mod owns lab distribution. Native rotation is only used without it.
    if policy.parallel_mod_available() then
        set_runtime_research_queue(f, names)
        return
    end

    local sf = storage.forces[f.index]
    local sq = sf and sf.queue
    if not sq then
        return
    end
    sq.parallel_rotation_index = ((sq.parallel_rotation_index or 0) % #names) + 1
    local selected = names[sq.parallel_rotation_index]
    if not selected then
        return
    end

    local rotated_names = {selected}
    for index, tech_name in ipairs(names) do
        if index ~= sq.parallel_rotation_index then
            table.insert(rotated_names, tech_name)
        end
    end
    set(f.index, keys.current_tech, selected)
    set_runtime_research_queue(f, rotated_names)
end

queue.build_queue_from_available = function(force_index)
    -- Build a fresh queue from all available techs sorted by score (same as right panel)
    local f = game.forces[force_index]
    if not f then return end
    if policy.get_setting(force_index, "strategy") == "focused" then return end
    local tsx = tech.get_all_tech_state_ext(force_index)
    if not tsx then return end

    local lsci = queue.get_science_availability(force_index)

    -- Compute avg_cost from all unresearched enabled techs
    local total_cost_sum = 0
    local cost_count = 0
    for tech_name, xcur in pairs(tsx) do
        if xcur.technology.researched then goto skip_avg end
        if not xcur.technology.enabled or xcur.meta.hidden then goto skip_avg end
        if not queue.get_tech_enabled(force_index, tech_name) then goto skip_avg end
        if policy.get_tech_science_priority(force_index, xcur) <= -1000 then goto skip_avg end
        if xcur.meta.is_infinite then
            local cap = rw.research_caps[tech_name]
            if cap and xcur.technology.level >= cap then goto skip_avg end
        end
        local cost = xcur.technology.research_unit_count or 1
        if xcur.meta.is_infinite and xcur.meta.prototype.research_unit_count_formula then
            local est = eval_formula(xcur.meta.prototype.research_unit_count_formula, xcur.technology.level)
            if est then cost = est end
        end
        total_cost_sum = total_cost_sum + cost
        cost_count = cost_count + 1
        ::skip_avg::
    end
    local avg_cost = cost_count > 0 and (total_cost_sum / cost_count) or nil

    local available = {}
    local blocked = {}
    for tech_name, xcur in pairs(tsx) do
        if xcur.technology.researched then goto skip end
        if not xcur.technology.enabled or xcur.meta.hidden then goto skip end
        if not queue.get_tech_enabled(force_index, tech_name) then goto skip end
        if policy.get_tech_science_priority(force_index, xcur) <= -1000 then goto skip end
        if xcur.meta.is_infinite then
            local cap = rw.research_caps[tech_name]
            if cap and xcur.technology.level >= cap then goto skip end
        end
        local stored_ub = queue.get_tech_ub(force_index, tech_name)
        local sd = queue.score_tech_detailed(xcur, xcur.technology.level, stored_ub, avg_cost, force_index)
        local entry = {tech_name = tech_name, score = sd.total}
        if xcur.available and science_is_available(xcur, lsci) then
            table.insert(available, entry)
        else
            table.insert(blocked, entry)
        end
        ::skip::
    end

    table.sort(available, function(a, b) return a.score > b.score end)

    local sfq = {}
    for _, entry in ipairs(available) do
        table.insert(sfq, entry.tech_name)
    end
    for _, entry in ipairs(blocked) do
        table.insert(sfq, entry.tech_name)
    end
    set(force_index, keys.queue, sfq)

    -- Mark all as queued
    for _, tech_name in ipairs(sfq) do
        tech.update_queued(force_index, tech_name, true)
    end
end

queue.get_upcoming_research = function(force_index, count)
    return get_virtual_research_entries(force_index, count)
end

local get_ingredient_name_and_amount = function(ingredient)
    if type(ingredient) ~= "table" then
        return nil, 0
    end
    return ingredient.name or ingredient[1], ingredient.amount or ingredient[2] or 1
end

queue.get_queue_budget = function(force_index, count)
    local maximum_entries = math.max(1, math.min(1000, math.floor(tonumber(count) or 250)))
    local entries = get_virtual_research_entries(force_index, maximum_entries)
    local totals = {}
    local total_seconds = 0
    local has_time_estimate = false
    local unlock_count = 0
    local technology_count = #entries
    local repeat_unbounded = false
    local repeat_truncated = false
    local f = game.forces[force_index]

    local add_science_cost = function(entry, multiplier)
        for _, ingredient in pairs(entry.xcur.technology.research_unit_ingredients or {}) do
            local name, amount = get_ingredient_name_and_amount(ingredient)
            if name then
                totals[name] = (totals[name] or 0) + multiplier * amount
            end
        end
    end

    for index, entry in ipairs(entries) do
        local multiplier = entry.cost or 0
        local remaining_factor = 1
        if index == 1 and f and f.current_research and f.current_research.name == entry.tech_name then
            remaining_factor = math.max(0, 1 - (f.research_progress or 0))
            multiplier = multiplier * remaining_factor
        end
        add_science_cost(entry, multiplier)
        if entry.duration then
            total_seconds = total_seconds + entry.duration * remaining_factor
            has_time_estimate = true
        end
        for _, effect in pairs(entry.xcur.meta.prototype.effects or {}) do
            if effect.type == "unlock-recipe" or effect.type == "unlock-space-location" or
                effect.type == "unlock-quality" then
                unlock_count = unlock_count + 1
            end
        end
    end

    local global_repeat = state.get_force_setting(force_index, "requeue_infinite_tech",
        const.default_settings.force.settings.requeue_infinite_tech)
    for _, entry in ipairs(entries) do
        if entry.xcur.meta.is_infinite then
            local rule = policy.get_repeat_rule(force_index, entry.tech_name)
            local extra_levels = 0
            if rule.mode == "continuous" or (rule.mode == "default" and global_repeat) then
                repeat_unbounded = true
            elseif rule.mode == "once" then
                extra_levels = math.max(0, rule.remaining or 0)
            elseif rule.mode == "to_level" then
                extra_levels = math.max(0, (rule.max_level or entry.level) - entry.level)
            end

            local speed = entry.duration and entry.duration > 0 and (entry.cost / entry.duration) or nil
            for offset = 1, extra_levels do
                if technology_count >= maximum_entries then
                    repeat_truncated = true
                    break
                end
                local cost = get_research_unit_count_at_level(entry.xcur, entry.level + offset)
                add_science_cost(entry, cost)
                if speed and speed > 0 then
                    total_seconds = total_seconds + cost / speed
                    has_time_estimate = true
                end
                technology_count = technology_count + 1
            end
        end
    end

    local counts = get_science_counts(force_index)
    local forecast = queue.get_science_forecast(force_index)
    local sciences = {}
    local limiting_science
    local limiting_minutes = -1
    for science, total in pairs(totals) do
        local available = counts[science] or 0
        local deficit = math.max(0, total - available)
        local production = forecast[science] and forecast[science].production_per_minute or 0
        local recovery_minutes = production > 0 and deficit / production or (deficit > 0 and math.huge or 0)
        if deficit > 0 and recovery_minutes > limiting_minutes then
            limiting_minutes = recovery_minutes
            limiting_science = science
        end
        sciences[science] = {
            required = total,
            available = available,
            deficit = deficit,
            production_per_minute = production,
            consumption_per_minute = forecast[science] and forecast[science].consumption_per_minute or 0
        }
    end

    return {
        technology_count = technology_count,
        total_seconds = has_time_estimate and total_seconds or nil,
        unlock_count = unlock_count,
        sciences = sciences,
        limiting_science = limiting_science,
        repeat_unbounded = repeat_unbounded,
        repeat_truncated = repeat_truncated
    }
end

queue.get_trigger_objectives = function(force_index)
    local tsx = tech.get_all_tech_state_ext(force_index)
    local res = {}
    for tech_name, xcur in pairs(tsx or {}) do
        if not xcur.technology.researched and xcur.meta.has_trigger then
            local trigger = xcur.meta.prototype.research_trigger
            table.insert(res, {
                tech_name = tech_name,
                xcur = xcur,
                trigger_type = trigger and trigger.type or "unknown",
                ready = next(xcur.blocked_by or {}) == nil and next(xcur.disabled_by or {}) == nil
            })
        end
    end
    table.sort(res, function(a, b)
        if a.ready ~= b.ready then
            return a.ready
        end
        return a.tech_name < b.tech_name
    end)
    return res
end

local build_plan_snapshot = function(force_index)
    local sq = storage.forces[force_index] and storage.forces[force_index].queue
    if not sq then
        return nil
    end
    return {
        version = 1,
        queue = policy.copy_table(sq[keys.queue] or {}),
        tech_enabled = policy.copy_table(sq.tech_enabled or {}),
        tech_ub = policy.copy_table(sq.tech_ub or {}),
        policy = policy.export_settings(force_index)
    }
end

local is_finite_number = function(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local validate_plan_snapshot = function(force_index, snapshot)
    if type(snapshot) ~= "table" or snapshot.version ~= 1 or type(snapshot.queue) ~= "table" then
        return false, "invalid-plan"
    end
    local f = game.forces[force_index]
    if not f then
        return false, "invalid-force"
    end

    local queue_entry_count = 0
    for index, tech_name in pairs(snapshot.queue) do
        if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(tech_name) ~= "string" then
            return false, "invalid-queue"
        end
        queue_entry_count = queue_entry_count + 1
    end
    if queue_entry_count ~= #snapshot.queue then
        return false, "invalid-queue"
    end

    local queue_names = {}
    local seen = {}
    for _, tech_name in ipairs(snapshot.queue) do
        local technology = f.technologies[tech_name]
        if technology and technology.valid and not technology.researched and not seen[tech_name] then
            table.insert(queue_names, tech_name)
            seen[tech_name] = true
        end
    end

    local tech_enabled = {}
    if type(snapshot.tech_enabled) == "table" then
        for tech_name, enabled in pairs(snapshot.tech_enabled) do
            if type(tech_name) ~= "string" or type(enabled) ~= "boolean" then
                return false, "invalid-tech-enabled"
            end
            if f.technologies[tech_name] then
                tech_enabled[tech_name] = enabled
            end
        end
    elseif snapshot.tech_enabled ~= nil then
        return false, "invalid-tech-enabled"
    end

    local tech_ub = {}
    if type(snapshot.tech_ub) == "table" then
        for tech_name, boost in pairs(snapshot.tech_ub) do
            if type(tech_name) ~= "string" or not is_finite_number(boost) then
                return false, "invalid-tech-priority"
            end
            if f.technologies[tech_name] then
                tech_ub[tech_name] = math.max(-100000, math.min(100000, boost))
            end
        end
    elseif snapshot.tech_ub ~= nil then
        return false, "invalid-tech-priority"
    end

    local sanitized_policy = policy.sanitize_settings(snapshot.policy)
    if not sanitized_policy then
        return false, "invalid-policy"
    end

    return {
        version = 1,
        queue = queue_names,
        tech_enabled = tech_enabled,
        tech_ub = tech_ub,
        policy = sanitized_policy
    }
end

local apply_plan_snapshot = function(force_index, snapshot)
    local sanitized, reason = validate_plan_snapshot(force_index, snapshot)
    if not sanitized then
        return false, reason
    end
    local f = game.forces[force_index]
    local sf = storage.forces[force_index]
    if not f or not sf or not sf.queue then
        return false, "invalid-force"
    end

    for _, tech_name in ipairs(sf.queue[keys.queue] or {}) do
        if type(tech_name) == "string" and f.technologies[tech_name] then
            tech.update_queued(force_index, tech_name, false)
        end
    end

    sf.queue[keys.queue] = sanitized.queue
    sf.queue.tech_enabled = sanitized.tech_enabled
    sf.queue.tech_ub = sanitized.tech_ub
    policy.import_settings(force_index, sanitized.policy)
    for _, tech_name in ipairs(sanitized.queue) do
        tech.update_queued(force_index, tech_name, true)
    end
    state.request_next_research(f)
    state.request_gui_update(f)
    return true
end

queue.save_preset = function(force_index, name)
    local snapshot = build_plan_snapshot(force_index)
    if not snapshot then
        return false
    end
    return policy.set_preset(force_index, name, snapshot)
end

queue.load_preset = function(force_index, name)
    local snapshot = policy.get_presets(force_index)[name]
    if not snapshot then
        return false, "missing-preset"
    end
    return apply_plan_snapshot(force_index, snapshot)
end

queue.delete_preset = function(force_index, name)
    policy.delete_preset(force_index, name)
end

queue.get_preset_names = function(force_index)
    local res = {}
    for name, _ in pairs(policy.get_presets(force_index)) do
        table.insert(res, name)
    end
    table.sort(res)
    return res
end

queue.export_plan = function(force_index)
    local snapshot = build_plan_snapshot(force_index)
    if not snapshot then
        return nil
    end
    local encoded = helpers.encode_string(helpers.table_to_json(snapshot))
    return encoded and ("LE1:" .. encoded) or nil
end

queue.import_plan = function(force_index, exchange_string)
    if type(exchange_string) ~= "string" or #exchange_string > max_plan_exchange_length or
        exchange_string:sub(1, 4) ~= "LE1:" then
        return false, "invalid-prefix"
    end
    local decoded_ok, decoded = pcall(helpers.decode_string, exchange_string:sub(5))
    if not decoded_ok or type(decoded) ~= "string" or #decoded > max_plan_json_length then
        return false, "invalid-encoding"
    end
    local json_ok, snapshot = pcall(helpers.json_to_table, decoded)
    if not json_ok then
        return false, "invalid-json"
    end
    return apply_plan_snapshot(force_index, snapshot)
end

------------------------------------------------------------------------------
-- Tech order / enabled helpers
---------------------------------------------------------------------------

queue.get_tech_order = function(force_index)
    local sq = storage.forces[force_index].queue
    if not sq or not sq.tech_custom_order or #sq.tech_custom_order == 0 then
        return nil
    end
    return sq.tech_custom_order
end

queue.get_tech_enabled = function(force_index, tech_name)
    local sq = storage.forces[force_index].queue
    if not sq or not sq.tech_enabled then
        return true
    end
    if sq.tech_enabled[tech_name] == nil then
        return true
    end
    return sq.tech_enabled[tech_name]
end

queue.set_tech_enabled = function(force_index, tech_name, enabled)
    local sq = storage.forces[force_index].queue
    if not sq then
        return
    end
    if not sq.tech_enabled then
        sq.tech_enabled = {}
    end
    sq.tech_enabled[tech_name] = enabled
end

queue.get_tech_ub = function(force_index, tech_name)
    local sq = storage.forces[force_index].queue
    if not sq or not sq.tech_ub then
        return 0
    end
    local val = sq.tech_ub[tech_name] or 0
    return val
end

queue.adjust_tech_ub = function(force_index, tech_name, delta)
    local sq = storage.forces[force_index].queue
    if not sq then
        return
    end
    if not sq.tech_ub then
        sq.tech_ub = {}
    end
    sq.tech_ub[tech_name] = (sq.tech_ub[tech_name] or 0) + delta
end

queue.move_tech_up = function(force_index, tech_name)
    local order = queue.get_tech_order(force_index)
    if not order then
        return
    end
    for i = 2, #order do
        if order[i] == tech_name then
            order[i], order[i - 1] = order[i - 1], order[i]
            break
        end
    end
end

queue.move_tech_down = function(force_index, tech_name)
    local order = queue.get_tech_order(force_index)
    if not order then
        return
    end
    for i = 1, #order - 1 do
        if order[i] == tech_name then
            order[i], order[i + 1] = order[i + 1], order[i]
            break
        end
    end
end

queue.build_tech_order = function(force_index)
    -- Build order from ALL unresearched enabled techs so up/down buttons work for everything
    local tsx = tech.get_all_tech_state_ext(force_index)
    local order = {}

    for tech_name, xcur in pairs(tsx) do
        if not xcur.technology.researched and xcur.technology.enabled and not xcur.meta.hidden then
            table.insert(order, tech_name)
        end
    end

    storage.forces[force_index].queue.tech_custom_order = order
    return order
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

queue.init_force = function(force_index)
    local sf = storage.forces[force_index]
    if not sf.queue then
        sf.queue = {}
    end
    local sq = sf.queue

    -- Init the queue
    if not sq[keys.queue] then
        sq[keys.queue] = {}
    end

    -- Init tech custom order, enabled states, and user boost overrides
    if not sq.tech_custom_order then
        sq.tech_custom_order = {}
    end
    if not sq.tech_enabled then
        sq.tech_enabled = {}
    end
    if not sq.tech_ub then
        sq.tech_ub = {}
    end
    if not sq[keys.target_tech] then
        sq[keys.target_tech] = nil
    end
    if not sq[keys.temp_tech] then
        sq[keys.temp_tech] = nil
    end
    if not sq[keys.temp_tech_timeout] then
        sq[keys.temp_tech_timeout] = nil
    end
    if not sq[keys.last_warn_tick] then
        sq[keys.last_warn_tick] = nil
    end
    if not sq[keys.last_switch_tick] then
        sq[keys.last_switch_tick] = nil
    end

    -- Register each queued tech
    local sfq = get(force_index, keys.queue)
    for _, q in pairs(sfq or {}) do
        tech.update_queued(force_index, q, true)
    end
end

return queue
