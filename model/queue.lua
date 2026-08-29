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
local auto_switch = require("model.auto_switch")

local queue = {}

local research_history_seconds = 10 * 60
local research_history_sample_seconds = 3
local research_history_samples = math.floor(research_history_seconds / research_history_sample_seconds)
local research_speed_average_samples = math.floor(60 / research_history_sample_seconds)
local science_flow_history_sample_seconds = 60
local science_flow_history_seconds = 2 * 60
local science_flow_history_samples = math.floor(science_flow_history_seconds / science_flow_history_sample_seconds) + 1
local diagnostic_healthy_utilization = 0.90
local diagnostic_meaningful_gap_fraction = 0.05
local diagnostic_minimum_lost_spm = 1
local diagnostic_minimum_samples = 2
local science_reserve_per_lab = 6
local emergency_raw_scan_budget = 256
local emergency_candidate_scan_budget = 64
local emergency_candidate_retry_ticks = 300
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
    local force_state = storage and storage.forces and storage.forces[force_index]
    if not force_state or not force_state.queue then
        return
    end
    force_state.queue[key] = val
end
local get = function(force_index, key)
    local force_state = storage and storage.forces and storage.forces[force_index]
    return force_state and force_state.queue and force_state.queue[key]
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

-- Removed: get_tech_weight was never referenced; score_tech_detailed uses
-- get_tech_weight_at_level, which is the only scoring path.
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
local get_virtual_queue_source
local get_bounded_emergency_candidate
local set_runtime_research_queue
local get_runtime_candidate_average_cost
local get_inactive_science_demand_spm
local get_in_transit_science_total
local science_demand_cache = {}
local research_capacity_cache = {}
local emergency_candidate_jobs = {}

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

local build_cluster_supply_scopes = function(availability)
    local scopes_by_science = {}
    if not availability.__cluster_mode then
        return scopes_by_science
    end
    for _, cluster in pairs(availability.__clusters or {}) do
        for science, lab_count in pairs(cluster.lab_input_counts or {}) do
            if lab_count > 0 then
                local key = cluster.key or tostring(cluster)
                local surface_index = key:match("^(.-):lab:")
                if surface_index then
                    key = surface_index .. ":direct"
                end
                local consuming_scopes = scopes_by_science[science]
                if not consuming_scopes then
                    consuming_scopes = {}
                    scopes_by_science[science] = consuming_scopes
                end
                local scope = consuming_scopes[key]
                if not scope then
                    scope = {stock = 0}
                    consuming_scopes[key] = scope
                end
                scope.stock = scope.stock + ((cluster.counts and cluster.counts[science]) or 0)
            end
        end
    end
    return scopes_by_science
end

local science_depletion_is_attributable = function(availability, science, cluster_supply_scopes)
    if not availability.__cluster_mode then
        return true, nil
    end
    -- Production statistics are force-wide across all loaded surfaces. In cluster mode
    -- they can only be attributed safely when exactly one consuming scope exists.
    local scopes = cluster_supply_scopes or build_cluster_supply_scopes(availability)
    local consuming_scopes = scopes[science] or {}
    local scope_count = 0
    local attributable_stock
    for _, scope in pairs(consuming_scopes) do
        scope_count = scope_count + 1
        attributable_stock = scope.stock
    end
    if scope_count == 1 then
        return true, attributable_stock or 0
    end
    return false, nil
end

local get_estimated_research_capacity_per_minute = function(xcur, force_index)
    if not xcur or not xcur.technology then
        return nil
    end

    local technology = xcur.technology
    local force_capacity = research_capacity_cache[force_index]
    local cached_capacity = force_capacity and force_capacity[technology.name]
    if cached_capacity and cached_capacity > 0 then
        return cached_capacity
    end

    local f = game.forces[force_index]
    local active = f and f.current_research
    local active_capacity = active and force_capacity and force_capacity[active.name]
    local target_energy = technology.research_unit_energy or 0
    if active_capacity and active_capacity > 0 then
        local active_energy = active.research_unit_energy or 0
        if active_energy > 0 and target_energy > 0 then
            return active_capacity * active_energy / target_energy
        end
    end

    local measured_speed = queue.get_research_speed(force_index)
    if not measured_speed or measured_speed <= 0 then
        return nil
    end
    if active then
        local active_energy = active.research_unit_energy or 0
        if active_energy > 0 and target_energy > 0 then
            measured_speed = measured_speed * active_energy / target_energy
        end
    end
    return measured_speed * 60
end

local get_depletion_horizon_seconds = function(xcur, force_index, forecast_seconds)
    -- Cap the depletion horizon at the estimated time to finish this tech: if the
    -- research completes before packs run out, the supply is sufficient.
    local horizon = forecast_seconds
    local f = game.forces[force_index]
    local capacity_per_minute = get_estimated_research_capacity_per_minute(xcur, force_index)
    local speed = capacity_per_minute and capacity_per_minute / 60 or nil
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

local science_supply_is_sufficient = function(
    xcur,
    force_index,
    supplied_availability,
    supplied_forecast,
    supplied_cluster_scopes
)
    if not xcur or not xcur.meta or not force_index then
        return false
    end

    local sciences = xcur.meta.sciences or {}
    if not next(sciences) then
        return true
    end

    local f = game.forces[force_index]
    if f and f.current_research and xcur.technology and
        f.current_research.name == xcur.technology.name then
        local live_bottleneck = queue.get_active_missing_science_bottleneck and
            queue.get_active_missing_science_bottleneck(force_index, xcur)
        if live_bottleneck and next(live_bottleneck) then
            return false
        end
        -- Emergency fallback: when the staggered sampler/display evidence is
        -- temporarily unavailable, use the direct registered-lab inventory scan
        -- to confirm a materially pack-bound current technology. Do not treat a
        -- stale or empty scan as starvation.
        local emergency_missing = auto_switch.get_missing_sciences(
            force_index, xcur.technology,
            lab.get_runtime_lab_content(force_index),
            env.get_all_sciences())
        if emergency_missing and next(emergency_missing) then
            return false
        end
        return true
    end

    local availability = supplied_availability or queue.get_science_availability(force_index)
    local forecast = supplied_forecast or
        (queue.get_science_forecast and queue.get_science_forecast(force_index)) or {}
    local cluster_supply_scopes = supplied_cluster_scopes or build_cluster_supply_scopes(availability)
    local forecast_seconds = policy.get_setting(force_index, "forecast_seconds") or 0
    if not queue.science_is_available(xcur, availability) then
        return false
    end
    if forecast_seconds > 0 then
        local horizon = get_depletion_horizon_seconds(xcur, force_index, forecast_seconds)
        local inactive_demand = get_inactive_science_demand_spm and
            get_inactive_science_demand_spm(xcur, force_index) or {}
        for _, science in pairs(sciences) do
            local science_forecast = forecast[science]
            local demand_per_minute = inactive_demand[science] or 0
            local attributable, attributable_stock = science_depletion_is_attributable(
                availability,
                science,
                cluster_supply_scopes
            )
            if attributable and science_forecast and demand_per_minute > 0 and horizon > 0 then
                local stock = availability.__cluster_mode and
                    math.max(0, attributable_stock or 0) or
                    math.max(0, science_forecast.stock or 0)
                local production_per_minute
                if availability.__cluster_mode then
                    -- Force production includes remote surfaces and packs that may still
                    -- be in transit. Require enough stock already reachable by these labs
                    -- for the recovery horizon instead of extrapolating a delivery burst.
                    production_per_minute = 0
                else
                    production_per_minute = math.max(0, science_forecast.production_per_minute or 0)
                end
                local projected_supply = stock + production_per_minute * horizon / 60
                local projected_demand = demand_per_minute * horizon / 60
                if projected_supply + 0.001 < projected_demand then
                    return false
                end
            elseif attributable and not availability.__cluster_mode and science_forecast and
                science_forecast.depletion_seconds and
                science_forecast.depletion_seconds < horizon then
                return false
            end
        end
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

-- Search outside the explicit queue only in a fixed-size slice. This path runs
-- from force maintenance while research is materially pack-bound, so it must
-- never score and sort the entire technology graph in one tick.
get_bounded_emergency_candidate = function(force_index, current_name, pinned, queued_names, tsx, lsci, sfsci)
    local job = emergency_candidate_jobs[force_index]
    if not job or job.current_name ~= current_name or job.tech_states ~= tsx or
        (job.retry_tick and game.tick >= job.retry_tick) then
        job = {
            current_name = current_name,
            tech_states = tsx,
            scan_key = nil,
            retry_tick = nil
        }
        emergency_candidate_jobs[force_index] = job
    elseif job.retry_tick then
        return nil
    end

    local best_candidate
    local best_score
    local seen_candidates = {}
    local raw_scanned = 0
    local candidates_scanned = 0
    local forecast
    local cluster_supply_scopes
    while raw_scanned < emergency_raw_scan_budget and
        candidates_scanned < emergency_candidate_scan_budget do
        local technology_name = next(tsx, job.scan_key)
        job.scan_key = technology_name
        if not technology_name then
            job.retry_tick = game.tick + emergency_candidate_retry_ticks
            break
        end
        raw_scanned = raw_scanned + 1
        if technology_name ~= current_name and technology_name ~= pinned and
            not queued_names[technology_name] then
            local xcur = tsx[technology_name]
            if not tech_can_be_runtime_candidate(force_index, xcur) then
                goto continue_emergency_candidate
            end
            candidates_scanned = candidates_scanned + 1
            local candidate = find_runtime_candidate(force_index, technology_name, tsx, lsci, sfsci)
            if candidate and candidate ~= current_name and candidate ~= pinned and
                not queued_names[candidate] and not seen_candidates[candidate] then
                seen_candidates[candidate] = true
                local xcandidate = tsx[candidate]
                if xcandidate and not cluster_supply_scopes then
                    forecast = queue.get_science_forecast and queue.get_science_forecast(force_index) or {}
                    cluster_supply_scopes = build_cluster_supply_scopes(lsci)
                end
                if xcandidate and science_supply_is_sufficient(
                    xcandidate,
                    force_index,
                    lsci,
                    forecast,
                    cluster_supply_scopes
                ) then
                    local stored_ub = queue.get_tech_ub(force_index, candidate)
                    local score = queue.score_tech_detailed(
                        xcandidate,
                        xcandidate.technology.level,
                        stored_ub,
                        nil,
                        force_index
                    ).total
                    if not best_candidate or score > best_score or
                        (score == best_score and candidate < best_candidate) then
                        best_candidate = candidate
                        best_score = score
                    end
                end
            end
        end
        ::continue_emergency_candidate::
    end

    if best_candidate then
        emergency_candidate_jobs[force_index] = nil
    end
    return best_candidate
end

local activate_temp_research = function(f, sq, target, current_name, candidate, tsx, lsci, minimum_switch_ticks)
    emergency_candidate_jobs[f.index] = nil
    -- The target is the tech we want to return to once science is available
    -- again. When the current tech is a regular queue tech that just went
    -- pack-bound, it becomes the new target. When the current tech is itself
    -- the temp tech from a previous switch (both target and temp are
    -- pack-bound), keep the original target so we still try to return to it
    -- after the replacement temp finishes.
    local existing_temp = sq[keys.temp_tech]
    local target_name = (existing_temp and current_name == existing_temp) and target or current_name
    sq[keys.target_tech] = target_name
    sq[keys.temp_tech] = candidate
    sq[keys.temp_tech_timeout] = game.tick + minimum_switch_ticks
    sq[keys.last_switch_tick] = game.tick
    notify_switch(f, current_name, candidate, tsx, lsci)
    state.request_next_research(f)
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
queue.get_research_control_state = function(force_index)
    local f = game.forces[force_index]
    local sq = storage and storage.forces and storage.forces[force_index] and
        storage.forces[force_index].queue
    local runtime_queue = {}
    for _, technology in ipairs((f and f.research_queue) or {}) do
        local technology_name = type(technology) == "string" and technology or
            (technology and technology.name)
        if technology_name then
            table.insert(runtime_queue, technology_name)
        end
    end
    return {
        live_current_tech = f and f.current_research and f.current_research.name or nil,
        cached_current_tech = sq and sq[keys.current_tech] or nil,
        cached_smart_tech = sq and sq[keys.current_tech_smart] or nil,
        target_tech = sq and sq[keys.target_tech] or nil,
        temp_tech = sq and sq[keys.temp_tech] or nil,
        temp_tech_timeout_tick = sq and sq[keys.temp_tech_timeout] or nil,
        last_switch_tick = sq and sq[keys.last_switch_tick] or nil,
        is_stuck = sq and sq[keys.is_stuck] == true or false,
        stored_queue = sq and sq[keys.queue] or {},
        runtime_queue = runtime_queue
    }
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
    local blocked_by_interval = last_switch_tick and game.tick - last_switch_tick < minimum_switch_ticks
    if blocked_by_interval then
        -- The normal minimum switch interval stays enforced unless an explicit
        -- plan-demand override was requested and is permitted by policy.
        local override_used, override_reason
        if policy.consume_instant_switch then
            override_used, override_reason = policy.consume_instant_switch(f.index)
        end
        if not override_used then
            return
        end
        if policy.record_action then
            policy.record_action(f.index, nil, "instant_switch", {
                category = "switch",
                reason = override_reason,
                trigger = "override"
            })
        end
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
        if queue.science_is_sufficient(xtemp, f.index) then
            -- Target still doesn't have packs, but the temporary research can run.
            sq[keys.temp_tech_timeout] = game.tick + (60 * temp_tech_timeout_extend_seconds)
            if not f.current_research or f.current_research.name ~= temp then
                state.request_next_research(f)
            end
            return
        end
        -- Both the target and temporary research are pack-bound. Fall through
        -- so the normal candidate scan can replace the temporary technology.
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

    -- If current tech has sufficient packs, only interrupt it for a higher-priority
    -- science policy, or for a same-priority candidate with a much better score.
    if current_is_sufficient then
        emergency_candidate_jobs[f.index] = nil
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
    -- Emergency fallback: when the staggered sampler/display evidence is
    -- temporarily unavailable (no bottleneck detected), use the direct
    -- registered-lab inventory scan to confirm a materially pack-bound current
    -- technology. Do not treat a stale or empty scan as starvation.
    if not next(live_bottleneck) then
        live_bottleneck = auto_switch.get_missing_sciences(
            f.index, xcur.technology,
            lab.get_runtime_lab_content(f.index),
            env.get_all_sciences())
    end
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
            activate_temp_research(f, sq, target, cur_name, candidate, tsx, lsci, minimum_switch_ticks)
            return
        end
    end

    -- Try queue order
    local queued_names = {}
    for _, q in ipairs(sfq or {}) do
        queued_names[q] = true
        if q ~= cur_name and q ~= pinned then
            local candidate, _ = find_runtime_candidate(f.index, q, tsx, lsci, sfsci)
            if candidate and candidate ~= cur_name then
                activate_temp_research(f, sq, target, cur_name, candidate, tsx, lsci, minimum_switch_ticks)
                return
            end
        end
    end

    -- The explicit queue remains authoritative during normal selection. When it
    -- has no runnable substitute for a materially pack-bound technology, widen
    -- only this temporary search so useful lab capacity does not sit idle.
    local candidate = get_bounded_emergency_candidate(
        f.index,
        cur_name,
        pinned,
        queued_names,
        tsx,
        lsci,
        sfsci
    )
    if candidate then
        activate_temp_research(f, sq, target, cur_name, candidate, tsx, lsci, minimum_switch_ticks)
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

---@param f LuaForce
---@param force_reselection? boolean
queue.start_next_research = function(f, force_reselection)
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
    -- While research is active, event-driven queue updates already keep the
    -- runtime queue current. Do not rescore the entire technology graph on the
    -- 30-second maintenance call.
    local stored_current_name = get(f.index, keys.current_tech)
    local live_current_name = f.current_research and f.current_research.name
    if stored_current_name and live_current_name and
        stored_current_name == live_current_name and not force_reselection then
        return
    end

    local sfq = get(f.index, keys.queue)
    local rebuilt_from_empty = false
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
        rebuilt_from_empty = true
        sfq = get(f.index, keys.queue)
        if not sfq or #sfq == 0 then
            f.research_queue = {}
            warn_force(f, {"lil_einstein-warn.empty-research-queue"})
            return
        end
    end

    queue.reorder_queue_by_score(f.index)
    -- A forced update may be applying a temporary switch or a queue/policy change
    -- while research is already active. Keep the newly written runtime queue; the
    -- idle-only cleanup below would otherwise cancel the live research.
    if f.current_research then
        return
    end
    if rebuilt_from_empty and get(f.index, keys.current_tech) then
        return
    end
    if auto_research and not f.current_research and not rebuilt_from_empty then
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

    local contiguous_start = 1
    if tech_name then
        contiguous_start = #samples + 1
        for i = #samples, 1, -1 do
            local sample = samples[i]
            if not sample or sample.tech_name ~= tech_name then
                break
            end
            contiguous_start = i
        end
        if contiguous_start > #samples then
            return nil, 0
        end
    end

    local end_index = #samples - (start_offset or 0)
    if end_index < contiguous_start then
        return nil, 0
    end
    local start_index = math.max(contiguous_start, end_index - sample_count + 1)
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

queue.record_science_flow = function(force_index)
    local sf = storage and storage.forces and storage.forces[force_index]
    local sq = sf and sf.queue
    if not sq then
        return
    end

    local history = sq.science_flow_history or {}
    local last = history[#history]
    if last and game.tick - (last.tick or 0) < science_flow_history_sample_seconds then
        return
    end

    local forecast = queue.get_science_forecast(force_index)
    local values = {}
    for science, item in pairs(forecast or {}) do
        values[science] = {
            stock = item.stock or 0,
            production_per_minute = item.production_per_minute or 0,
            consumption_per_minute = item.consumption_per_minute or 0,
            net_per_minute = item.net_per_minute or 0
        }
    end
    table.insert(history, {tick = game.tick, values = values})
    while #history > science_flow_history_samples do
        table.remove(history, 1)
    end
    sq.science_flow_history = history
end

queue.get_science_flow_history = function(force_index)
    local sf = storage and storage.forces and storage.forces[force_index]
    local sq = sf and sf.queue
    return sq and sq.science_flow_history or {}
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

-- Runtime-only caches per force. Lab membership comes from the event-driven
-- registry in model.lab; never rescan every surface during a GUI refresh.
local labs_cache = {}
local counts_cache = {}
local diagnostic_cache = {}
local forecast_cache = {}
local lab_observation_cache = {}
local lab_network_cache = {}
local lab_input_cache = {}
local active_bottleneck_cache = {}
local inactive_science_demand_cache = {}
local science_pack_insight_cache = {}
local in_transit_science_cache = {}
local research_health_snapshots = {}
local research_health_jobs = {}
local research_health_requests = {}
local upcoming_display_jobs = {}
local research_health_refresh_ticks = 300
local in_transit_refresh_ticks = 300
local research_health_lab_budget = 8
local research_health_cluster_budget = 8
local research_health_availability_budget = 32

local has_invalid_ref = function(refs)
    for _, ref in pairs(refs or {}) do
        if not ref or not ref.valid then
            return true
        end
    end
    return false
end

local get_lab_network = function(force_index, lab_entity)
    if not lab_entity or not lab_entity.valid then
        return nil
    end

    local now = game.tick
    local force_cache = lab_network_cache[force_index]
    if not force_cache then
        force_cache = {}
        lab_network_cache[force_index] = force_cache
    end
    local unit_number = lab_entity.unit_number or 0
    local cached = force_cache[unit_number]
    if cached and now < cached.refresh_tick then
        if cached.network == false then
            return nil
        end
        if cached.network and cached.network.valid then
            return cached.network
        end
    end

    local force = lab_entity.force
    local surface = lab_entity.surface
    local position = lab_entity.position
    local network
    if force and surface and position then
        network = force.find_logistic_network_by_position(position, surface)
    end

    if not network or not network.valid then
        network = false
    end
    -- Spread refreshes by unit number so hundreds of associations never all
    -- expire on the same tick. Uncovered labs refresh sooner than covered labs.
    local base_refresh = network == false and 600 or 3600
    force_cache[unit_number] = {
        network = network,
        refresh_tick = now + base_refresh + (unit_number % base_refresh)
    }
    return network ~= false and network or nil
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
    labs_cache[force_index] = {
        tick = game.tick,
        labs = lab.get_registered_labs(force_index)
    }
end

local get_cached_labs = function(force_index)
    local lc = labs_cache[force_index]
    if not lc or has_invalid_ref(lc.labs) then
        refresh_labs_cache(force_index)
        lc = labs_cache[force_index]
    end
    return (lc and lc.labs) or {}
end

local get_lab_input_set = function(lab_entity)
    local prototype = lab_entity and lab_entity.valid and lab_entity.prototype
    local prototype_name = prototype and prototype.name
    if not prototype_name then
        return {}
    end
    local cached = lab_input_cache[prototype_name]
    if cached then
        return cached
    end
    cached = {}
    for _, science in pairs(prototype.lab_inputs or {}) do
        cached[science] = true
    end
    lab_input_cache[prototype_name] = cached
    return cached
end

local get_lab_observations = function(force_index)
    local labs = get_cached_labs(force_index)
    local labs_tick = labs_cache[force_index] and labs_cache[force_index].tick
    local cached = lab_observation_cache[force_index]
    if cached and cached.labs_tick == labs_tick and not has_invalid_ref(cached.entities) then
        return cached.values
    end

    local runtime_content = lab.get_runtime_lab_content(force_index)
    local observations = {}
    local entities = {}
    for _, lab_entity in pairs(labs) do
        if lab_entity and lab_entity.valid then
            local lcur = runtime_content[lab_entity.unit_number or 0]
            table.insert(observations, {
                entity = lab_entity,
                runtime = lcur
            })
            table.insert(entities, lab_entity)
        end
    end
    lab_observation_cache[force_index] = {
        labs_tick = labs_tick,
        values = observations,
        entities = entities
    }
    return observations
end

local get_observation_contents = function(observation)
    local lcur = observation and observation.runtime
    if lcur and lcur.latest_contents and lcur.latest_tick and
        game.tick - lcur.latest_tick <= 900 then
        return lcur.latest_contents
    end

    local lab_entity = observation and observation.entity
    if not lab_entity or not lab_entity.valid then
        return {}
    end
    local inv = lab_entity.get_inventory(defines.inventory.lab_input)
    return inv and inv.get_contents() or {}
end

local get_observation_status = function(observation)
    local lcur = observation and observation.runtime
    if lcur and lcur.latest_status ~= nil then
        return lcur.latest_status
    end
    local lab_entity = observation and observation.entity
    return lab_entity and lab_entity.valid and lab_entity.status or nil
end

get_science_counts = function(force_index)
    local now = game.tick

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
    for _, observation in pairs(get_lab_observations(force_index)) do
        local lab_entity = observation.entity
        if lab_entity.valid then
            local network = get_lab_network(force_index, lab_entity)
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
            local lab_inputs = get_lab_input_set(lab_entity)
            for science in pairs(lab_inputs) do
                cluster.lab_input_counts[science] = (cluster.lab_input_counts[science] or 0) + 1
            end
            table.insert(cluster.lab_input_sets, lab_inputs)
            for _, item in pairs(get_observation_contents(observation)) do
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
    lab_observation_cache[force_index] = nil
    lab_network_cache[force_index] = nil
    active_bottleneck_cache[force_index] = nil
    in_transit_science_cache[force_index] = nil
    science_demand_cache[force_index] = nil
    research_capacity_cache[force_index] = nil
    emergency_candidate_jobs[force_index] = nil
    science_pack_insight_cache[force_index] = nil
    auto_switch.invalidate(force_index)
    -- Keep the last completed report visible while the replacement is measured.
    -- tick_research_health_snapshot swaps in the new complete snapshot atomically.
    research_health_jobs[force_index] = nil
    research_health_requests[force_index] = true
    upcoming_display_jobs[force_index] = nil
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

local lab_accepts_research = function(lab_entity, current, accepted)
    accepted = accepted or get_lab_input_set(lab_entity)
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        if not accepted[ingredient.name] then
            return false
        end
    end
    return true
end

local get_lab_research_unit_spm = function(lab_entity, current)
    local research_energy = current.research_unit_energy or 0
    if research_energy <= 0 then
        return 0
    end

    local base_speed = lab_entity.prototype.get_researching_speed(lab_entity.quality) or 0
    local speed_multiplier = math.max(0, 1 + (lab_entity.speed_bonus or 0))

    -- Runtime research energy is measured in ticks; 3600 converts units/tick to units/minute.
    return base_speed * speed_multiplier * 3600 / research_energy
end

local get_lab_capacity_spm = function(lab_entity, current)
    local productivity_multiplier = math.max(0, 1 + (lab_entity.productivity_bonus or 0))
    local f = lab_entity.force
    local force_productivity_multiplier = math.max(0, 1 + ((f and f.laboratory_productivity_bonus) or 0))
    return get_lab_research_unit_spm(lab_entity, current) * productivity_multiplier * force_productivity_multiplier
end

local get_lab_science_pack_drain_multiplier = function(lab_entity)
    local prototype = lab_entity.prototype
    local drain_rate = math.max(0, math.min(100, prototype.science_pack_drain_rate_percent or 100)) / 100
    if prototype.uses_quality_drain_modifier and lab_entity.quality then
        drain_rate = drain_rate * (lab_entity.quality.science_pack_drain_multiplier or 1)
    end
    return drain_rate
end

local get_lab_science_consumption_spm = function(lab_entity, current, amount)
    -- Productivity increases research progress without consuming extra packs. The
    -- prototype/quality drain is the separate factor that changes pack demand.
    return get_lab_research_unit_spm(lab_entity, current) *
        get_lab_science_pack_drain_multiplier(lab_entity) * math.max(0, amount or 1)
end

get_inactive_science_demand_spm = function(xcur, force_index)
    local current = xcur and xcur.technology
    if not current or not force_index then
        return {}
    end

    local cached = science_demand_cache[force_index] and
        science_demand_cache[force_index][current.name]
    if cached then
        return cached
    end

    -- A technology that was active immediately before a temporary switch has
    -- an exact physical-demand cache populated by the live bottleneck pass. For
    -- another inactive candidate, reuse the active technology's full compatible-
    -- lab capacity and scale it by unit energy. Falling back to measured speed
    -- would size the candidate for the few labs still working during starvation.
    local progress_units_per_minute = get_estimated_research_capacity_per_minute(xcur, force_index)
    if not progress_units_per_minute or progress_units_per_minute <= 0 then
        return {}
    end

    local f = game.forces[force_index]
    local productivity_multiplier = math.max(
        1,
        1 + ((f and f.laboratory_productivity_bonus) or 0)
    )
    local physical_units_per_minute = progress_units_per_minute / productivity_multiplier
    local res = {}
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        res[ingredient.name] = physical_units_per_minute * math.max(0, ingredient.amount or 1)
    end
    return res
end

local get_missing_lab_sciences = function(current, contents)
    local present = {}
    for _, item in pairs(contents or {}) do
        present[item.name] = (present[item.name] or 0) + (item.count or 0)
    end

    local res = {}
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        if (present[ingredient.name] or 0) < (ingredient.amount or 1) then
            table.insert(res, ingredient.name)
        end
    end
    return res
end

local get_lab_loss_kind = function(lab_entity, status)
    if status == defines.entity_status.missing_science_packs then
        return "missing_science"
    elseif status == defines.entity_status.no_power or status == defines.entity_status.low_power or
           status == defines.entity_status.no_fuel or
           status == defines.entity_status.not_plugged_in_electric_network then
        return "power"
    elseif status == defines.entity_status.frozen or lab_entity.frozen then
        return "frozen"
    elseif status == defines.entity_status.disabled_by_control_behavior or
           status == defines.entity_status.disabled_by_script or status == defines.entity_status.disabled or
           status == defines.entity_status.closed_by_circuit_network or
           status == defines.entity_status.marked_for_deconstruction then
        return "disabled"
    elseif status == defines.entity_status.no_research_in_progress then
        return "no_research"
    end
    return "other"
end

local add_loss_cause = function(cause_data, kind, capacity_spm)
    local cause = cause_data[kind]
    if not cause then
        cause = {kind = kind, labs = 0, lost_spm = 0}
        cause_data[kind] = cause
    end
    cause.labs = cause.labs + 1
    cause.lost_spm = cause.lost_spm + capacity_spm
end

local add_missing_science_evidence = function(missing_sciences, science, capacity_spm, missing_per_minute)
    local item = missing_sciences[science]
    if not item then
        item = {science = science, labs = 0, missing_per_minute = 0, lost_spm = 0}
        missing_sciences[science] = item
    end
    item.labs = item.labs + 1
    item.missing_per_minute = item.missing_per_minute + (missing_per_minute or 0)
    item.lost_spm = item.lost_spm + capacity_spm
end

local sort_loss_evidence = function(items, identity_key)
    table.sort(items, function(a, b)
        if a.lost_spm == b.lost_spm then
            return tostring(a[identity_key] or "") < tostring(b[identity_key] or "")
        end
        return a.lost_spm > b.lost_spm
    end)
end

local map_values = function(source)
    local res = {}
    for _, item in pairs(source or {}) do
        table.insert(res, item)
    end
    return res
end

local sort_science_pack_rates = function(items)
    table.sort(items, function(a, b)
        return tostring(a.science or "") < tostring(b.science or "")
    end)
end

local initialize_science_pack_rates = function(current)
    local res = {}
    for _, ingredient in pairs(current and current.research_unit_ingredients or {}) do
        res[ingredient.name] = {
            science = ingredient.name,
            amount = ingredient.amount or 1,
            maximum_per_minute = 0,
            working_per_minute = 0
        }
    end
    return res
end

local add_science_pack_rate = function(pack_rates, science, amount, rate, working)
    local item = pack_rates[science]
    if not item then
        item = {
            science = science,
            amount = amount or 1,
            maximum_per_minute = 0,
            working_per_minute = 0
        }
        pack_rates[science] = item
    end
    item.maximum_per_minute = item.maximum_per_minute + (rate or 0)
    if working then
        item.working_per_minute = item.working_per_minute + (rate or 0)
    end
end

local new_diagnostic_cluster = function(key, scope, surface_index, surface_name, network_id, lab_entity)
    local position
    if lab_entity and lab_entity.valid and lab_entity.position then
        position = {x = lab_entity.position.x, y = lab_entity.position.y}
    end
    return {
        key = key,
        scope = scope,
        surface_index = surface_index,
        surface_name = surface_name,
        network_id = network_id,
        representative_position = position,
        representative_unit_number = lab_entity and lab_entity.valid and lab_entity.unit_number or nil,
        total_labs = 0,
        compatible_labs = 0,
        working_labs = 0,
        incompatible_labs = 0,
        expected_spm = 0,
        working_spm = 0,
        lost_spm = 0,
        unavailable_spm = 0,
        causes = {},
        missing_sciences = {},
        science_pack_rates = {},
        local_stock = {},
        lab_descriptors = {},
        _cause_data = {},
        _missing_sciences = {},
        _science_pack_rates = {},
        _lab_stock = {},
        _network = nil
    }
end

local get_diagnostic_cluster = function(clusters, lab_entity, network)
    local surface = lab_entity.surface
    local surface_index = surface and surface.index or 0
    local surface_name = surface and surface.name or "unknown"
    local network_id
    local key
    local scope
    if network and network.valid then
        network_id = network.network_id
        key = tostring(surface_index) .. ":network:" .. tostring(network_id or "unknown")
        scope = "network"
    else
        key = tostring(surface_index) .. ":direct"
        scope = "direct"
    end

    local cluster = clusters[key]
    if not cluster then
        cluster = new_diagnostic_cluster(key, scope, surface_index, surface_name, network_id, lab_entity)
        clusters[key] = cluster
    end
    if network and network.valid then
        cluster._network = network
    end
    return cluster
end

local add_lab_stock = function(cluster, contents)
    for _, item in pairs(contents or {}) do
        cluster._lab_stock[item.name] = (cluster._lab_stock[item.name] or 0) + (item.count or 0)
    end
end

local finalize_diagnostic_cluster = function(cluster, required_sciences, required_pack_amounts)
    cluster.causes = map_values(cluster._cause_data)
    sort_loss_evidence(cluster.causes, "kind")
    cluster.missing_sciences = map_values(cluster._missing_sciences)
    sort_loss_evidence(cluster.missing_sciences, "science")
    for _, science in ipairs(required_sciences or {}) do
        if not cluster._science_pack_rates[science] then
            cluster._science_pack_rates[science] = {
                science = science,
                amount = (required_pack_amounts and required_pack_amounts[science]) or 1,
                maximum_per_minute = 0,
                working_per_minute = 0
            }
        end
    end
    cluster.science_pack_rates = map_values(cluster._science_pack_rates)
    sort_science_pack_rates(cluster.science_pack_rates)
    cluster.lost_spm = math.max(0, cluster.expected_spm - cluster.working_spm)
    cluster.unavailable_spm = cluster.lost_spm

    local network = cluster._network
    for _, science in ipairs(required_sciences) do
        local stock = cluster._lab_stock[science] or 0
        if network and network.valid then
            stock = stock + network.get_item_count(science)
        end
        cluster.local_stock[science] = stock
    end
    for _, item in ipairs(cluster.missing_sciences) do
        item.local_stock = cluster.local_stock[item.science] or 0
    end

    cluster.dominant_cause = cluster.causes[1]
    cluster.dominant_missing_science = cluster.missing_sciences[1]
    table.sort(cluster.lab_descriptors, function(a, b)
        local a_unit = a.unit_number or math.huge
        local b_unit = b.unit_number or math.huge
        if a_unit == b_unit then
            return tostring(a.prototype_name or "") < tostring(b.prototype_name or "")
        end
        return a_unit < b_unit
    end)
    cluster._cause_data = nil
    cluster._missing_sciences = nil
    cluster._science_pack_rates = nil
    cluster._lab_stock = nil
    cluster._network = nil
end

local get_dominant_cluster = function(clusters, cause_kind, science)
    local best
    local best_lost_spm = -1
    for _, cluster in ipairs(clusters or {}) do
        local lost_spm = 0
        local evidence = science and cluster.missing_sciences or cluster.causes
        local identity_key = science and "science" or "kind"
        local identity = science or cause_kind
        for _, item in ipairs(evidence or {}) do
            if item[identity_key] == identity then
                lost_spm = item.lost_spm or 0
                break
            end
        end
        if lost_spm > best_lost_spm or
           (lost_spm == best_lost_spm and best and cluster.key < best.key) then
            best = cluster
            best_lost_spm = lost_spm
        end
    end
    return best
end

queue.get_research_diagnostic = function(force_index)
    local cached = diagnostic_cache[force_index]
    if cached and cached.tick == game.tick then
        return cached.value
    end

    local f = game.forces[force_index]
    local current = f and f.current_research
    local res = {
        available = current ~= nil,
        state = current and "measuring" or "idle",
        current_technology = current and current.name or nil,
        actual_spm = 0,
        recent_spm = nil,
        previous_spm = nil,
        trend_percent = nil,
        sample_count = 0,
        sampling_ready = false,
        expected_spm = 0,
        working_spm = 0,
        utilization = 0,
        total_labs = 0,
        compatible_labs = 0,
        working_labs = 0,
        incompatible_labs = 0,
        causes = {},
        missing_sciences = {},
        science_pack_rates = {},
        clusters = {},
        material_loss_spm = 0,
        material_threshold_spm = diagnostic_minimum_lost_spm,
        dominant_cause = nil,
        dominant_missing_science = nil,
        dominant_cluster_key = nil
    }

    if not current then
        diagnostic_cache[force_index] = {tick = game.tick, value = res}
        return res
    end

    local sf = storage.forces[force_index]
    local samples = sf and sf.queue and sf.queue.speed_samples
    local measured_speed, measured_count =
        get_research_speed_window(samples, 0, research_speed_average_samples, current.name)
    res.actual_spm = measured_speed and (measured_speed * 60) or 0
    res.sample_count = measured_count
    res.sampling_ready = measured_count >= diagnostic_minimum_samples

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

    local cause_data = {}
    local missing_sciences = {}
    local clusters = {}
    local required_sciences = {}
    local required_pack_amounts = {}
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        table.insert(required_sciences, ingredient.name)
        required_pack_amounts[ingredient.name] = ingredient.amount or 1
    end
    table.sort(required_sciences)
    res.science_pack_rates = initialize_science_pack_rates(current)

    for _, observation in pairs(get_lab_observations(force_index)) do
        local lab_entity = observation.entity
        if lab_entity and lab_entity.valid then
            local network = get_lab_network(force_index, lab_entity)
            local cluster = get_diagnostic_cluster(clusters, lab_entity, network)
            res.total_labs = res.total_labs + 1
            cluster.total_labs = cluster.total_labs + 1
            local contents = get_observation_contents(observation)
            add_lab_stock(cluster, contents)
            local surface = lab_entity.surface
            local descriptor = {
                unit_number = lab_entity.unit_number,
                prototype_name = lab_entity.name or "lab",
                surface_index = surface and surface.index or 0,
                surface_name = surface and surface.name or "unknown",
                position = lab_entity.position and {
                    x = lab_entity.position.x,
                    y = lab_entity.position.y
                } or nil,
                compatible = false,
                working = false,
                status_key = "incompatible",
                missing_sciences = {}
            }
            table.insert(cluster.lab_descriptors, descriptor)
            if not lab_accepts_research(lab_entity, current, get_lab_input_set(lab_entity)) then
                res.incompatible_labs = res.incompatible_labs + 1
                cluster.incompatible_labs = cluster.incompatible_labs + 1
                goto continue
            end

            res.compatible_labs = res.compatible_labs + 1
            cluster.compatible_labs = cluster.compatible_labs + 1
            local capacity_spm = get_lab_capacity_spm(lab_entity, current)
            res.expected_spm = res.expected_spm + capacity_spm
            cluster.expected_spm = cluster.expected_spm + capacity_spm
            local status = get_observation_status(observation)
            local working = status == defines.entity_status.working
            descriptor.compatible = true
            descriptor.working = working
            descriptor.status_key = working and "working" or get_lab_loss_kind(lab_entity, status)
            local pack_rates = {}
            for _, ingredient in pairs(current.research_unit_ingredients or {}) do
                local pack_rate = get_lab_science_consumption_spm(lab_entity, current, ingredient.amount)
                pack_rates[ingredient.name] = (pack_rates[ingredient.name] or 0) + pack_rate
                add_science_pack_rate(res.science_pack_rates, ingredient.name, ingredient.amount,
                    pack_rate, working)
                add_science_pack_rate(cluster._science_pack_rates, ingredient.name, ingredient.amount,
                    pack_rate, working)
            end

            if working then
                res.working_labs = res.working_labs + 1
                res.working_spm = res.working_spm + capacity_spm
                cluster.working_labs = cluster.working_labs + 1
                cluster.working_spm = cluster.working_spm + capacity_spm
            else
                local cause_kind = get_lab_loss_kind(lab_entity, status)
                add_loss_cause(cause_data, cause_kind, capacity_spm)
                add_loss_cause(cluster._cause_data, cause_kind, capacity_spm)
            end

            if status == defines.entity_status.missing_science_packs then
                descriptor.missing_sciences = get_missing_lab_sciences(current, contents)
                for _, science in pairs(descriptor.missing_sciences) do
                    add_missing_science_evidence(missing_sciences, science, capacity_spm, pack_rates[science])
                    add_missing_science_evidence(cluster._missing_sciences, science, capacity_spm,
                                                 pack_rates[science])
                end
            end
        end
        ::continue::
    end

    if res.expected_spm > 0 then
        res.utilization = math.max(0, math.min(1, res.actual_spm / res.expected_spm))
    end

    res.causes = map_values(cause_data)
    res.missing_sciences = map_values(missing_sciences)
    res.science_pack_rates = map_values(res.science_pack_rates)
    sort_loss_evidence(res.causes, "kind")
    sort_loss_evidence(res.missing_sciences, "science")
    sort_science_pack_rates(res.science_pack_rates)
    res.material_threshold_spm =
        math.max(diagnostic_minimum_lost_spm, res.expected_spm * diagnostic_meaningful_gap_fraction)

    res.clusters = map_values(clusters)
    for _, cluster in ipairs(res.clusters) do
        finalize_diagnostic_cluster(cluster, required_sciences, required_pack_amounts)
    end
    table.sort(res.clusters, function(a, b)
        if a.lost_spm == b.lost_spm then
            if a.surface_name == b.surface_name then
                return a.key < b.key
            end
            return a.surface_name < b.surface_name
        end
        return a.lost_spm > b.lost_spm
    end)

    if res.total_labs == 0 then
        local cause = {kind = "no_labs", labs = 0, lost_spm = 0, material = true}
        table.insert(res.causes, 1, cause)
        res.state = "operational_fault"
        res.dominant_cause = cause
    elseif res.compatible_labs == 0 then
        local cause = {kind = "no_compatible_labs", labs = res.total_labs, lost_spm = 0, material = true}
        table.insert(res.causes, 1, cause)
        res.state = "operational_fault"
        res.dominant_cause = cause
    elseif res.expected_spm <= 0 then
        local cause = {kind = "no_capacity", labs = res.compatible_labs, lost_spm = 0, material = true}
        table.insert(res.causes, 1, cause)
        res.state = "operational_fault"
        res.dominant_cause = cause
    else
        for _, cause in ipairs(res.causes) do
            cause.material = cause.lost_spm >= res.material_threshold_spm
            if cause.material and not res.dominant_cause then
                res.dominant_cause = cause
                res.material_loss_spm = cause.lost_spm
            end
        end

        if res.dominant_cause then
            if res.dominant_cause.kind == "missing_science" then
                res.state = "pack_bound"
                res.dominant_missing_science = res.missing_sciences[1]
            else
                res.state = "operational_fault"
            end
        elseif not res.sampling_ready then
            res.state = "measuring"
        elseif res.utilization >= diagnostic_healthy_utilization then
            res.state = "at_capacity"
        else
            res.state = "degraded_unexplained"
        end
    end

    if res.dominant_cause then
        local dominant_science = res.dominant_missing_science and res.dominant_missing_science.science or nil
        local dominant_cluster = get_dominant_cluster(
            res.clusters,
            res.dominant_cause.kind,
            dominant_science
        )
        if dominant_cluster then
            res.dominant_cluster_key = dominant_cluster.key
        end
    end

    diagnostic_cache[force_index] = {tick = game.tick, value = res}
    return res
end

local new_display_diagnostic = function(force_index, current)
    local res = {
        available = current ~= nil,
        state = current and "measuring" or "idle",
        current_technology = current and current.name or nil,
        actual_spm = 0,
        recent_spm = nil,
        previous_spm = nil,
        trend_percent = nil,
        sample_count = 0,
        sampling_ready = false,
        expected_spm = 0,
        working_spm = 0,
        utilization = 0,
        total_labs = 0,
        compatible_labs = 0,
        working_labs = 0,
        incompatible_labs = 0,
        causes = {},
        missing_sciences = {},
        science_pack_rates = {},
        clusters = {},
        material_loss_spm = 0,
        material_threshold_spm = diagnostic_minimum_lost_spm,
        dominant_cause = nil,
        dominant_missing_science = nil,
        dominant_cluster_key = nil
    }
    local context = {
        result = res,
        cause_data = {},
        missing_sciences = {},
        clusters = {},
        required_sciences = {},
        required_pack_amounts = {}
    }
    if not current then
        return context
    end

    local sf = storage.forces[force_index]
    local samples = sf and sf.queue and sf.queue.speed_samples
    local measured_speed, measured_count =
        get_research_speed_window(samples, 0, research_speed_average_samples, current.name)
    res.actual_spm = measured_speed and (measured_speed * 60) or 0
    res.sample_count = measured_count
    res.sampling_ready = measured_count >= diagnostic_minimum_samples

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
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        table.insert(context.required_sciences, ingredient.name)
        context.required_pack_amounts[ingredient.name] = ingredient.amount or 1
    end
    table.sort(context.required_sciences)
    res.science_pack_rates = initialize_science_pack_rates(current)
    return context
end

local process_display_diagnostic_observation = function(context, current, observation, network)
    if not current then
        return
    end
    local lab_entity = observation.entity
    if not lab_entity or not lab_entity.valid then
        return
    end

    local res = context.result
    local cluster = get_diagnostic_cluster(context.clusters, lab_entity, network)
    res.total_labs = res.total_labs + 1
    cluster.total_labs = cluster.total_labs + 1
    local contents = get_observation_contents(observation)
    add_lab_stock(cluster, contents)
    local surface = lab_entity.surface
    local descriptor = {
        unit_number = lab_entity.unit_number,
        prototype_name = lab_entity.name or "lab",
        surface_index = surface and surface.index or 0,
        surface_name = surface and surface.name or "unknown",
        position = lab_entity.position and {
            x = lab_entity.position.x,
            y = lab_entity.position.y
        } or nil,
        compatible = false,
        working = false,
        status_key = "incompatible",
        missing_sciences = {}
    }
    table.insert(cluster.lab_descriptors, descriptor)
    if not lab_accepts_research(lab_entity, current, get_lab_input_set(lab_entity)) then
        res.incompatible_labs = res.incompatible_labs + 1
        cluster.incompatible_labs = cluster.incompatible_labs + 1
        return
    end

    res.compatible_labs = res.compatible_labs + 1
    cluster.compatible_labs = cluster.compatible_labs + 1
    local capacity_spm = get_lab_capacity_spm(lab_entity, current)
    res.expected_spm = res.expected_spm + capacity_spm
    cluster.expected_spm = cluster.expected_spm + capacity_spm
    local status = get_observation_status(observation)
    local working = status == defines.entity_status.working
    descriptor.compatible = true
    descriptor.working = working
    descriptor.status_key = working and "working" or get_lab_loss_kind(lab_entity, status)
    local pack_rates = {}
    for _, ingredient in pairs(current.research_unit_ingredients or {}) do
        local pack_rate = get_lab_science_consumption_spm(lab_entity, current, ingredient.amount)
        pack_rates[ingredient.name] = (pack_rates[ingredient.name] or 0) + pack_rate
        add_science_pack_rate(res.science_pack_rates, ingredient.name, ingredient.amount,
            pack_rate, working)
        add_science_pack_rate(cluster._science_pack_rates, ingredient.name, ingredient.amount,
            pack_rate, working)
    end
    if working then
        res.working_labs = res.working_labs + 1
        res.working_spm = res.working_spm + capacity_spm
        cluster.working_labs = cluster.working_labs + 1
        cluster.working_spm = cluster.working_spm + capacity_spm
    else
        local cause_kind = get_lab_loss_kind(lab_entity, status)
        add_loss_cause(context.cause_data, cause_kind, capacity_spm)
        add_loss_cause(cluster._cause_data, cause_kind, capacity_spm)
    end

    if status == defines.entity_status.missing_science_packs then
        descriptor.missing_sciences = get_missing_lab_sciences(current, contents)
        for _, science in pairs(descriptor.missing_sciences) do
            add_missing_science_evidence(context.missing_sciences, science, capacity_spm, pack_rates[science])
            add_missing_science_evidence(cluster._missing_sciences, science, capacity_spm, pack_rates[science])
        end
    end
end

local finish_display_diagnostic = function(context)
    local res = context.result
    if not res.available then
        return res
    end
    if res.expected_spm > 0 then
        res.utilization = math.max(0, math.min(1, res.actual_spm / res.expected_spm))
    end

    res.causes = map_values(context.cause_data)
    res.missing_sciences = map_values(context.missing_sciences)
    res.science_pack_rates = map_values(res.science_pack_rates)
    sort_loss_evidence(res.causes, "kind")
    sort_loss_evidence(res.missing_sciences, "science")
    sort_science_pack_rates(res.science_pack_rates)
    res.material_threshold_spm =
        math.max(diagnostic_minimum_lost_spm, res.expected_spm * diagnostic_meaningful_gap_fraction)

    res.clusters = map_values(context.clusters)
    table.sort(res.clusters, function(a, b)
        if a.lost_spm == b.lost_spm then
            if a.surface_name == b.surface_name then
                return a.key < b.key
            end
            return a.surface_name < b.surface_name
        end
        return a.lost_spm > b.lost_spm
    end)

    if res.total_labs == 0 then
        local cause = {kind = "no_labs", labs = 0, lost_spm = 0, material = true}
        table.insert(res.causes, 1, cause)
        res.state = "operational_fault"
        res.dominant_cause = cause
    elseif res.compatible_labs == 0 then
        local cause = {kind = "no_compatible_labs", labs = res.total_labs, lost_spm = 0, material = true}
        table.insert(res.causes, 1, cause)
        res.state = "operational_fault"
        res.dominant_cause = cause
    elseif res.expected_spm <= 0 then
        local cause = {kind = "no_capacity", labs = res.compatible_labs, lost_spm = 0, material = true}
        table.insert(res.causes, 1, cause)
        res.state = "operational_fault"
        res.dominant_cause = cause
    else
        for _, cause in ipairs(res.causes) do
            cause.material = cause.lost_spm >= res.material_threshold_spm
            if cause.material and not res.dominant_cause then
                res.dominant_cause = cause
                res.material_loss_spm = cause.lost_spm
            end
        end
        if res.dominant_cause then
            if res.dominant_cause.kind == "missing_science" then
                res.state = "pack_bound"
                res.dominant_missing_science = res.missing_sciences[1]
            else
                res.state = "operational_fault"
            end
        elseif not res.sampling_ready then
            res.state = "measuring"
        elseif res.utilization >= diagnostic_healthy_utilization then
            res.state = "at_capacity"
        else
            res.state = "degraded_unexplained"
        end
    end

    if res.dominant_cause then
        local science = res.dominant_missing_science and res.dominant_missing_science.science or nil
        local cluster = get_dominant_cluster(res.clusters, res.dominant_cause.kind, science)
        if cluster then
            res.dominant_cluster_key = cluster.key
        end
    end
    return res
end

local new_research_health_job = function(force_index)
    local f = game.forces[force_index]
    local current = f and f.current_research
    local all_sciences = env.get_all_sciences()
    local breakdown = {}
    for _, science in pairs(all_sciences) do
        breakdown[science] = {
            lab_count = 0,
            lab_entity_count = 0,
            network_total = 0,
            networks = {}
        }
    end
    return {
        force_index = force_index,
        technology_name = current and current.name or nil,
        current = current,
        phase = "labs",
        observations = get_lab_observations(force_index),
        observation_index = 1,
        all_sciences = all_sciences,
        counts = {},
        breakdown = breakdown,
        detected_networks = {},
        science_clusters = {},
        lab_input_counts = {},
        networks = nil,
        network_index = 1,
        availability = {},
        availability_index = 1,
        availability_cluster_index = 1,
        availability_current = false,
        science_cluster_list = nil,
        active_science_cluster_keys = nil,
        cluster_mode = policy.get_setting(force_index, "cluster_mode") == true,
        forecast = {},
        forecast_index = 1,
        diagnostic = new_display_diagnostic(force_index, current),
        diagnostic_clusters = nil,
        diagnostic_cluster_index = 1
    }
end

local process_research_health_lab = function(job, observation)
    local lab_entity = observation and observation.entity
    if not lab_entity or not lab_entity.valid then
        return
    end
    local force_index = job.force_index
    local network = get_lab_network(force_index, lab_entity)
    local surface_index = lab_entity.surface and lab_entity.surface.index or 0
    local cluster_key
    if network and network.valid then
        cluster_key = tostring(surface_index) .. ":network:" .. tostring(network.network_id or "unknown")
        local meta = job.detected_networks[cluster_key]
        if not meta then
            meta = {
                key = cluster_key,
                network = network,
                lab_count = 0,
                sample_lab = lab_entity,
                sample_unit_number = lab_entity.unit_number or 0
            }
            job.detected_networks[cluster_key] = meta
        end
        meta.lab_count = meta.lab_count + 1
    else
        cluster_key = tostring(surface_index) .. ":lab:" .. tostring(lab_entity.unit_number or 0)
    end

    local cluster = job.science_clusters[cluster_key]
    if not cluster then
        cluster = {
            key = cluster_key,
            lab_count = 0,
            counts = {},
            lab_input_counts = {},
            lab_input_sets = {}
        }
        job.science_clusters[cluster_key] = cluster
    end

    cluster.lab_count = cluster.lab_count + 1
    local lab_inputs = get_lab_input_set(lab_entity)
    for science in pairs(lab_inputs) do
        job.lab_input_counts[science] = (job.lab_input_counts[science] or 0) + 1
        cluster.lab_input_counts[science] = (cluster.lab_input_counts[science] or 0) + 1
    end
    table.insert(cluster.lab_input_sets, lab_inputs)
    local contents = get_observation_contents(observation)
    for _, item in pairs(contents) do
        job.counts[item.name] = (job.counts[item.name] or 0) + (item.count or 0)
        cluster.counts[item.name] = (cluster.counts[item.name] or 0) + (item.count or 0)
        local detail = job.breakdown[item.name]
        if detail then
            detail.lab_count = detail.lab_count + (item.count or 0)
            detail.lab_entity_count = detail.lab_entity_count + 1
        end
    end
    process_display_diagnostic_observation(job.diagnostic, job.current, observation, network)
end

local prepare_research_health_networks = function(job)
    local networks = {}
    for _, meta in pairs(job.detected_networks) do
        table.insert(networks, meta)
    end
    table.sort(networks, function(a, b)
        local a_surface = (a.sample_lab and a.sample_lab.valid and a.sample_lab.surface.name) or ""
        local b_surface = (b.sample_lab and b.sample_lab.valid and b.sample_lab.surface.name) or ""
        if a_surface == b_surface then
            return (a.sample_unit_number or 0) < (b.sample_unit_number or 0)
        end
        return a_surface < b_surface
    end)
    job.networks = networks
end

local process_research_health_network = function(job, meta)
    local network = meta and meta.network
    if not network or not network.valid then
        return
    end
    local label = get_network_label(network, meta.sample_lab)
    for _, science in pairs(job.all_sciences) do
        local count = network.get_item_count(science)
        job.counts[science] = (job.counts[science] or 0) + count
        local cluster = job.science_clusters[meta.key]
        if cluster then
            cluster.counts[science] = (cluster.counts[science] or 0) + count
        end
        local detail = job.breakdown[science]
        detail.network_total = detail.network_total + count
        table.insert(detail.networks, {
            label = label,
            count = count,
            lab_count = meta.lab_count
        })
    end
end

local process_research_health_availability = function(job)
    local science = job.all_sciences[job.availability_index]
    if not science then
        if job.cluster_mode then
            policy.prune_cluster_science_states(job.force_index, job.active_science_cluster_keys or {})
        end
        return true
    end

    local science_policy = policy.get_science_policy(job.force_index, science)
    if job.cluster_mode then
        local last = math.min(
            #job.science_cluster_list,
            job.availability_cluster_index + research_health_availability_budget - 1
        )
        for index = job.availability_cluster_index, last do
            local cluster = job.science_cluster_list[index]
            cluster.available_sciences = cluster.available_sciences or {}
            local previous =
                policy.get_cluster_science_available_state(job.force_index, cluster.key, science, false)
            local threshold = previous and science_policy.lower_threshold or science_policy.upper_threshold
            local lab_count = cluster.lab_input_counts[science] or 0
            local required_count = math.max(1, lab_count * science_reserve_per_lab * threshold)
            local cluster_available = lab_count > 0 and (cluster.counts[science] or 0) >= required_count
            policy.set_cluster_science_available_state(
                job.force_index,
                cluster.key,
                science,
                cluster_available
            )
            cluster.available_sciences[science] = cluster_available
            job.availability_current = job.availability_current or cluster_available
        end
        job.availability_cluster_index = last + 1
        if job.availability_cluster_index <= #job.science_cluster_list then
            return false
        end
        job.availability[science] = job.availability_current
        job.availability_index = job.availability_index + 1
        job.availability_cluster_index = 1
        job.availability_current = false
    else
        local previous = policy.get_science_available_state(job.force_index, science, false)
        local threshold = previous and science_policy.lower_threshold or science_policy.upper_threshold
        local lab_count = job.lab_input_counts[science] or 0
        local required_count = math.max(1, lab_count * science_reserve_per_lab * threshold)
        local available = lab_count > 0 and (job.counts[science] or 0) >= required_count
        policy.set_science_available_state(job.force_index, science, available)
        job.availability[science] = available
        job.availability_index = job.availability_index + 1
    end
    return false
end

-- Transit stock is not part of lab/network counts yet, but it is already
-- committed science. Include it in the player-facing runtime forecast so an
-- incoming delivery extends the depletion runtime instead of showing a false
-- imminent starvation.
get_in_transit_science_total = function(force_index, science)
    local cached = in_transit_science_cache[force_index]
    if cached and cached.expires_tick > game.tick then
        return cached.by_science[science] or 0
    end

    local force = game.forces[force_index]
    local by_science = {}
    local all_sciences = env.get_all_sciences()
    local known_sciences = {}
    for _, science_name in pairs(all_sciences) do
        known_sciences[science_name] = true
        by_science[science_name] = 0
    end

    for _, platform in pairs(force and force.platforms or {}) do
        local ok_platform, connection, hub = pcall(function()
            return platform and platform.valid and platform.space_connection, platform and platform.hub
        end)
        if ok_platform and connection and hub then
            for _, science_name in pairs(all_sciences) do
                local ok_count, count = pcall(function() return hub.get_item_count(science_name) end)
                if ok_count and type(count) == "number" then
                    by_science[science_name] = by_science[science_name] + math.max(0, count)
                end
            end
        end
    end

    -- One surface query per refresh, then read all science packs from each pod's
    -- cargo inventory. The old per-science filter multiplied surface scans by the
    -- number of installed science packs and allocated a result table for each scan.
    for _, surface in pairs(game.surfaces or {}) do
        local ok_pods, pods = pcall(function()
            return surface.find_entities_filtered({force = force_index, type = "cargo-pod"})
        end)
        if ok_pods and type(pods) == "table" then
            for _, pod in pairs(pods) do
                if pod and pod.valid then
                    local ok_inventory, inventory = pcall(function()
                        return pod.get_inventory(defines.inventory.cargo_unit)
                    end)
                    local ok_contents, contents = false, nil
                    if ok_inventory and inventory then
                        ok_contents, contents = pcall(function() return inventory.get_contents() end)
                    end
                    if ok_contents and type(contents) == "table" then
                        for _, item in pairs(contents) do
                            if item and known_sciences[item.name] and type(item.count) == "number" then
                                by_science[item.name] = by_science[item.name] + math.max(0, item.count)
                            end
                        end
                    elseif pod.get_item_count then
                        -- Defensive fallback for compatible cargo-pod implementations
                        -- that do not expose cargo_unit through get_inventory.
                        for _, science_name in pairs(all_sciences) do
                            local ok_count, count = pcall(function()
                                return pod.get_item_count(science_name)
                            end)
                            if ok_count and type(count) == "number" then
                                by_science[science_name] = by_science[science_name] + math.max(0, count)
                            end
                        end
                    end
                end
            end
        end
    end

    in_transit_science_cache[force_index] = {
        expires_tick = game.tick + in_transit_refresh_ticks,
        by_science = by_science
    }
    return by_science[science] or 0
end

local process_research_health_forecast = function(job, science)
    local f = game.forces[job.force_index]
    if not f then
        job.forecast[science] = {}
        return
    end
    local production = 0
    local consumption = 0
    local precision = defines.flow_precision_index.one_minute
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

    local science_policy = policy.get_science_policy(job.force_index, science)
    local target = (job.lab_input_counts[science] or 0) * science_reserve_per_lab *
        science_policy.upper_threshold
    local in_transit = get_in_transit_science_total(job.force_index, science)
    local stock = (job.counts[science] or 0) + in_transit
    local net = production - consumption
    local depletion_seconds
    local recovery_seconds
    if net < -0.001 then
        depletion_seconds = stock > 0 and (stock / -net) * 60 or 0
    elseif net > 0.001 and stock < target then
        recovery_seconds = ((target - stock) / net) * 60
        depletion_seconds = math.huge
    else
        depletion_seconds = math.huge
    end
    job.forecast[science] = {
        stock = stock,
        target = target,
        production_per_minute = production,
        consumption_per_minute = consumption,
        net_per_minute = net,
        in_transit = in_transit,
        depletion_seconds = depletion_seconds,
        recovery_seconds = recovery_seconds
    }
end

queue.request_research_health_snapshot = function(force_index)
    local f = game.forces[force_index]
    local technology_name = f and f.current_research and f.current_research.name or nil
    local snapshot = research_health_snapshots[force_index]
    if not snapshot or game.tick - snapshot.tick >= research_health_refresh_ticks or
        snapshot.technology_name ~= technology_name then
        research_health_requests[force_index] = true
    end
end

queue.tick_research_health_snapshot = function(force_index)
    local f = game.forces[force_index]
    if not f then
        research_health_jobs[force_index] = nil
        research_health_snapshots[force_index] = nil
        research_health_requests[force_index] = nil
        return false
    end

    local technology_name = f.current_research and f.current_research.name or nil
    local snapshot = research_health_snapshots[force_index]
    local job = research_health_jobs[force_index]
    -- Complete a snapshot against the technology it captured. Cancelling a
    -- large staged job whenever research rotates can starve the snapshot
    -- forever; display consumers retain the last complete report until this
    -- job publishes its replacement.
    local expired = not snapshot or game.tick - snapshot.tick >= research_health_refresh_ticks or
        snapshot.technology_name ~= technology_name
    if not job and (research_health_requests[force_index] or expired) then
        job = new_research_health_job(force_index)
        research_health_jobs[force_index] = job
    end
    if not job then
        return false
    end

    if job.phase == "labs" then
        local last = math.min(#job.observations, job.observation_index + research_health_lab_budget - 1)
        for index = job.observation_index, last do
            process_research_health_lab(job, job.observations[index])
        end
        job.observation_index = last + 1
        if job.observation_index > #job.observations then
            prepare_research_health_networks(job)
            job.phase = "networks"
        end
        return false
    end

    if job.phase == "networks" then
        local meta = job.networks[job.network_index]
        if meta then
            process_research_health_network(job, meta)
            job.network_index = job.network_index + 1
            return false
        end
        job.science_cluster_list = map_values(job.science_clusters)
        job.active_science_cluster_keys = {}
        for _, cluster in ipairs(job.science_cluster_list) do
            job.active_science_cluster_keys[cluster.key] = true
        end
        job.availability.__cluster_mode = job.cluster_mode
        job.availability.__clusters = job.science_clusters
        job.availability.__force_index = job.force_index
        job.phase = "availability"
    end

    if job.phase == "availability" then
        if not process_research_health_availability(job) then
            return false
        end
        job.phase = "forecast"
    end

    if job.phase == "forecast" then
        local science = job.all_sciences[job.forecast_index]
        if science then
            process_research_health_forecast(job, science)
            job.forecast_index = job.forecast_index + 1
            return false
        end
        job.diagnostic_clusters = map_values(job.diagnostic.clusters)
        job.phase = "diagnostic_clusters"
    end

    if job.phase == "diagnostic_clusters" then
        local last = math.min(
            #job.diagnostic_clusters,
            job.diagnostic_cluster_index + research_health_cluster_budget - 1
        )
        for index = job.diagnostic_cluster_index, last do
            finalize_diagnostic_cluster(
                job.diagnostic_clusters[index],
                job.diagnostic.required_sciences,
                job.diagnostic.required_pack_amounts
            )
        end
        job.diagnostic_cluster_index = last + 1
        if job.diagnostic_cluster_index <= #job.diagnostic_clusters then
            return false
        end
        job.phase = "finish"
    end

    local diagnostic = finish_display_diagnostic(job.diagnostic)
    research_health_snapshots[force_index] = {
        tick = game.tick,
        technology_name = job.technology_name,
        counts = job.counts,
        breakdown = job.breakdown,
        availability = job.availability,
        forecast = job.forecast,
        diagnostic = diagnostic
    }
    research_health_jobs[force_index] = nil
    research_health_requests[force_index] = nil
    return true
end

local get_display_research_health_snapshot = function(force_index)
    queue.request_research_health_snapshot(force_index)
    return research_health_snapshots[force_index]
end

queue.get_science_display_counts = function(force_index)
    local snapshot = get_display_research_health_snapshot(force_index)
    return snapshot and snapshot.counts or {}
end

queue.get_science_display_breakdown = function(force_index, science)
    local snapshot = get_display_research_health_snapshot(force_index)
    local breakdown = snapshot and snapshot.breakdown
    return (breakdown and breakdown[science]) or {
        lab_count = 0,
        lab_entity_count = 0,
        network_total = 0,
        networks = {}
    }
end

queue.get_science_display_forecast = function(force_index)
    local snapshot = get_display_research_health_snapshot(force_index)
    return snapshot and snapshot.forecast or {}
end

queue.get_research_health_snapshot_tick = function(force_index)
    local snapshot = research_health_snapshots[force_index]
    return snapshot and snapshot.tick or -1
end

queue.get_research_display_diagnostic = function(force_index)
    local f = game.forces[force_index]
    local snapshot = get_display_research_health_snapshot(force_index)
    if snapshot then
        return snapshot.diagnostic
    end
    return new_display_diagnostic(force_index, f and f.current_research).result
end

local is_valid_runtime_object = function(object)
    return object and object.valid ~= false
end

local get_runtime_name = function(object, fallback)
    if type(object) == "string" then
        return object
    end
    if object then
        local ok_name, name = pcall(function() return object.name end)
        if ok_name and name then
            return tostring(name)
        end
    end
    return fallback
end

local get_runtime_unit_number = function(object)
    if not object then
        return nil
    end
    local ok_unit, unit_number = pcall(function() return object.unit_number end)
    return ok_unit and type(unit_number) == "number" and unit_number or nil
end

local get_surface_planet_name = function(surface)
    if not is_valid_runtime_object(surface) then
        return nil
    end
    local planet = surface.planet
    if not is_valid_runtime_object(planet) then
        return nil
    end
    return get_runtime_name(planet, nil)
end

local count_surface_science = function(surface, force_index, science)
    if not is_valid_runtime_object(surface) or not surface.find_entities_filtered then
        return 0
    end
    local ok_entities, entities = pcall(function()
        return surface.find_entities_filtered({force = force_index, has_item_inside = science})
    end)
    if not ok_entities or type(entities) ~= "table" then
        return 0
    end

    local total = 0
    for _, entity in pairs(entities) do
        if is_valid_runtime_object(entity) and entity.type ~= "cargo-pod" and entity.get_item_count then
            local ok_count, count = pcall(function()
                return entity.get_item_count(science)
            end)
            if ok_count and type(count) == "number" then
                total = total + math.max(0, count)
            end
        end
    end
    return total
end

local is_excluded_planet_name = function(name)
    if type(name) ~= "string" or name == "" then
        return true
    end
    local lower = name:lower()
    if lower == "drawing-board_player" or lower == "space-platform-graveyard" or
        lower == "unknown" then
        return true
    end
    if lower:sub(1, 11) == "cargo-flow-" then
        return true
    end
    return false
end

local get_planet_stock = function(force_index, science)
    local rows_by_name = {}
    local surfaces = game.surfaces or {}

    for key, planet in pairs(game.planets or {}) do
        local name = get_runtime_name(planet, key)
        if not is_excluded_planet_name(name) then
            local ok_surface, surface = pcall(function() return planet and planet.surface end)
            if not ok_surface then
                surface = nil
            end
            rows_by_name[name] = {
                name = name,
                surface = is_valid_runtime_object(surface) and surface or nil,
                stock = 0
            }
        end
    end

    for _, surface in pairs(surfaces) do
        if is_valid_runtime_object(surface) and not surface.platform then
            local name = get_surface_planet_name(surface)
            if name and not is_excluded_planet_name(name) then
                local row = rows_by_name[name]
                if row and not row.surface then
                    row.surface = surface
                end
            end
        end
    end

    local rows = {}
    local stock_by_name = {}
    for name, row in pairs(rows_by_name) do
        row.stock = count_surface_science(row.surface, force_index, science)
        stock_by_name[name] = row.stock
        if row.stock > 0 then
            table.insert(rows, {name = row.name, stock = row.stock})
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows, stock_by_name
end

local get_transit_item_count = function(object, science)
    if not is_valid_runtime_object(object) or not object.get_item_count then
        return 0
    end
    local ok_count, count = pcall(function()
        return object.get_item_count(science)
    end)
    return ok_count and type(count) == "number" and math.max(0, count) or 0
end

local get_transit_routes = function(force_index, science)
    local f = game.forces[force_index]
    local routes = {}
    local total = 0
    for key, platform in pairs(f and f.platforms or {}) do
        if is_valid_runtime_object(platform) then
            local ok_connection, connection = pcall(function() return platform.space_connection end)
            if ok_connection and connection then
                local count = get_transit_item_count(platform.hub, science)
                if count > 0 then
                    local from = get_runtime_name(connection.from, nil)
                    local to = get_runtime_name(connection.to, nil)
                    if not is_excluded_planet_name(from) and not is_excluded_planet_name(to) then
                        table.insert(routes, {
                            platform = get_runtime_name(platform, key),
                            from = from,
                            to = to,
                            stock = count,
                            progress = type(platform.distance) == "number" and platform.distance or nil
                        })
                        total = total + count
                    end
                end
            end
        end
    end

    for _, surface in pairs(game.surfaces or {}) do
        if is_valid_runtime_object(surface) and surface.find_entities_filtered then
            local ok_pods, pods = pcall(function()
                return surface.find_entities_filtered({force = force_index, type = "cargo-pod",
                                                       has_item_inside = science})
            end)
            if ok_pods and type(pods) == "table" then
                for _, pod in pairs(pods) do
                    local count = get_transit_item_count(pod, science)
                    if count > 0 then
                        local from = get_runtime_name(pod.cargo_pod_origin, nil)
                        local to = get_runtime_name(pod.cargo_pod_destination, nil)
                        if not is_excluded_planet_name(from) and not is_excluded_planet_name(to) then
                            local pod_unit_number = get_runtime_unit_number(pod)
                            table.insert(routes, {
                                platform = pod_unit_number and ("Cargo pod #" .. tostring(pod_unit_number)) or
                                    "Cargo pod",
                                from = from,
                                to = to,
                                stock = count,
                                progress = nil
                            })
                            total = total + count
                        end
                    end
                end
            end
        end
    end

    table.sort(routes, function(a, b)
        if a.stock == b.stock then
            if a.platform == b.platform then
                return a.to < b.to
            end
            return a.platform < b.platform
        end
        return a.stock > b.stock
    end)
    return {total = total, routes = routes}
end

local is_nauvis_cluster = function(cluster)
    return tostring(cluster and cluster.surface_name or ""):lower() == "nauvis"
end

local get_cluster_pack_rate = function(cluster, science)
    for _, item in pairs(cluster and cluster.science_pack_rates or {}) do
        if item.science == science then
            return item
        end
    end
    return {maximum_per_minute = 0, working_per_minute = 0}
end

local get_cluster_missing_labs = function(cluster, science)
    for _, item in pairs(cluster and cluster.missing_sciences or {}) do
        if item.science == science then
            return item.labs or 0
        end
    end
    return 0
end

queue.get_science_pack_insight = function(force_index, science)
    if type(science) ~= "string" then
        return nil
    end
    local force_cache = science_pack_insight_cache[force_index]
    if not force_cache then
        force_cache = {}
        science_pack_insight_cache[force_index] = force_cache
    end
    local cached = force_cache[science]
    local refresh_ticks = (const.runtime_intervals and const.runtime_intervals.science_pack_panel_ticks) or 300
    if cached and game.tick < cached.next_refresh_tick then
        return cached.value
    end

    local forecast = queue.get_science_display_forecast(force_index)[science] or {}
    local diagnostic = queue.get_research_display_diagnostic(force_index) or {}
    local planet_rows, planet_stock = get_planet_stock(force_index, science)
    local transit = get_transit_routes(force_index, science)
    local labs = {
        surface_name = "nauvis",
        stock = queue.get_science_display_breakdown(force_index, science).lab_count or 0,
        compatible_labs = 0,
        supplied_labs = 0,
        starved_labs = 0,
        maximum_per_minute = 0,
        working_per_minute = 0,
        clusters = {}
    }
    for _, cluster in pairs(diagnostic.clusters or {}) do
        if is_nauvis_cluster(cluster) then
            local rate = get_cluster_pack_rate(cluster, science)
            local cluster_row = {
                key = cluster.key,
                label = cluster.label or cluster.surface_name or "Nauvis",
                surface_name = cluster.surface_name,
                total_labs = cluster.total_labs or 0,
                compatible_labs = cluster.compatible_labs or 0,
                supplied_labs = cluster.working_labs or 0,
                starved_labs = get_cluster_missing_labs(cluster, science),
                maximum_per_minute = rate.maximum_per_minute or 0,
                working_per_minute = rate.working_per_minute or 0
            }
            table.insert(labs.clusters, cluster_row)
            labs.compatible_labs = labs.compatible_labs + cluster_row.compatible_labs
            labs.supplied_labs = labs.supplied_labs + cluster_row.supplied_labs
            labs.starved_labs = labs.starved_labs + cluster_row.starved_labs
            labs.maximum_per_minute = labs.maximum_per_minute + cluster_row.maximum_per_minute
            labs.working_per_minute = labs.working_per_minute + cluster_row.working_per_minute
        end
    end
    table.sort(labs.clusters, function(a, b) return a.label < b.label end)

    local value = {
        science = science,
        current_stock = forecast.stock or 0,
        production_per_minute = forecast.production_per_minute or 0,
        consumption_per_minute = forecast.consumption_per_minute or 0,
        net_per_minute = forecast.net_per_minute or 0,
        depletion_seconds = forecast.depletion_seconds,
        recovery_seconds = forecast.recovery_seconds,
        labs = labs,
        planet_stock = planet_stock,
        planet_stock_rows = planet_rows,
        in_transit = transit,
        generated_tick = game.tick
    }
    force_cache[science] = {
        value = value,
        next_refresh_tick = game.tick + refresh_ticks
    }
    value.next_refresh_tick = game.tick + refresh_ticks
    return value
end

-- Background tick for research health snapshots. Only processes an existing
-- job or an explicit request; never auto-starts from snapshot expiry. This
-- lets control.lua run it every force_maintenance tick for all forces without
-- triggering a new 5-second-expiry rebuild on forces that have no pending
-- 2-minute background request.
queue.tick_background_research_health = function(force_index)
    if not research_health_jobs[force_index] and not research_health_requests[force_index] then
        return false
    end
    return queue.tick_research_health_snapshot(force_index)
end

-- Use the staggered lab snapshots for the background switcher. This preserves
-- the diagnostic's missing-pack thresholds without rebuilding its full cluster
-- model in one scheduler tick.
local get_display_pack_bound_bottleneck = function(force_index, current)
    if not current or not current.name or
        not queue.get_research_health_snapshot_tick or
        not queue.get_research_display_diagnostic then
        return {}
    end

    local snapshot_tick = queue.get_research_health_snapshot_tick(force_index)
    if type(snapshot_tick) ~= "number" or snapshot_tick < 0 or
        snapshot_tick > game.tick then
        return {}
    end

    local diagnostic = queue.get_research_display_diagnostic(force_index)
    if not diagnostic or diagnostic.current_technology ~= current.name or
        diagnostic.state ~= "pack_bound" then
        return {}
    end

    -- For massive factories the bounded health-snapshot job can take longer
    -- than the 900-tick (15 s) freshness window to rebuild. A PACK-BOUND
    -- diagnostic for the same live technology is still authoritative while
    -- the replacement snapshot is building: the supply situation for an
    -- actively starving technology does not recover without intervention,
    -- and the next completed snapshot will atomically replace this one. The
    -- technology and state checks above already gate this path, so a stale
    -- same-technology pack_bound snapshot is honored without an age check.

    -- Only include sciences whose individual lost SPM exceeds the diagnostic's
    -- material threshold. A science missing from a trivial number of labs
    -- must not block switching to candidates that also use it.
    local threshold = diagnostic.material_threshold_spm or diagnostic_minimum_lost_spm
    local result = {}
    for _, item in pairs(diagnostic.missing_sciences or {}) do
        local science = type(item) == "string" and item or item and item.science
        if science then
            local lost_spm = type(item) == "table" and item.lost_spm or threshold
            if lost_spm >= threshold then
                result[science] = true
            end
        end
    end
    local dominant = diagnostic.dominant_missing_science
    local dominant_science = type(dominant) == "string" and dominant or dominant and dominant.science
    if dominant_science then
        local dominant_lost = type(dominant) == "table" and dominant.lost_spm or threshold
        if dominant_lost >= threshold then
            result[dominant_science] = true
        end
    end
    return result
end

queue.get_active_missing_science_bottleneck = function(force_index, xcur)
    local f = game.forces[force_index]
    if not f or not f.current_research or not xcur or not xcur.technology or
        f.current_research.name ~= xcur.technology.name then
        return {}
    end

    local current = f.current_research
    local cached = active_bottleneck_cache[force_index]
    if cached and cached.tick == game.tick and cached.technology_name == current.name then
        return cached.value
    end
    local cache_result = function(value)
        active_bottleneck_cache[force_index] = {
            tick = game.tick,
            technology_name = current.name,
            value = value
        }
        return value
    end

    local expected_spm = 0
    local sampled_spm = 0
    local missing_spm = 0
    local physical_demand = {}
    local per_science_lost_spm = {}
    local now = game.tick
    for _, lcur in pairs(lab.get_runtime_lab_content(force_index)) do
        local lab_entity = lcur and lcur.lab
        if lab_entity and lab_entity.valid and lab_accepts_research(lab_entity, current) then
            local capacity_spm = get_lab_capacity_spm(lab_entity, current)
            expected_spm = expected_spm + capacity_spm
            for _, ingredient in pairs(current.research_unit_ingredients or {}) do
                physical_demand[ingredient.name] = (physical_demand[ingredient.name] or 0) +
                    get_lab_science_consumption_spm(lab_entity, current, ingredient.amount)
            end
            if lcur.latest_tick and now - lcur.latest_tick <= 900 then
                sampled_spm = sampled_spm + capacity_spm
                if lcur.latest_status == defines.entity_status.missing_science_packs then
                    missing_spm = missing_spm + capacity_spm
                    for _, science in pairs(get_missing_lab_sciences(current, lcur.latest_contents)) do
                        per_science_lost_spm[science] = (per_science_lost_spm[science] or 0) + capacity_spm
                    end
                end
            end
        end
    end

    science_demand_cache[force_index] = science_demand_cache[force_index] or {}
    science_demand_cache[force_index][current.name] = physical_demand
    research_capacity_cache[force_index] = research_capacity_cache[force_index] or {}
    research_capacity_cache[force_index][current.name] = expected_spm

    -- Wait for one near-complete staggered pass after load or large lab changes.
    -- The completed health diagnostic uses the same lab observations but can
    -- finish before this bounded sampler has 80% fresh coverage. Keep the
    -- switcher aligned with that player-visible PACK-BOUND result during this
    -- short gap instead of leaving the force on a starving technology.
    local display_bottleneck = get_display_pack_bound_bottleneck(force_index, current)
    if expected_spm <= 0 or sampled_spm < expected_spm * 0.80 then
        return cache_result(display_bottleneck)
    end
    -- Use the same material-loss threshold as the player-facing diagnostic. The
    -- switcher must react to a visible PACK-BOUND state even when the remaining
    -- labs keep total utilization above the old 60%/40% emergency thresholds.
    local material_threshold_spm = math.max(
        diagnostic_minimum_lost_spm,
        expected_spm * diagnostic_meaningful_gap_fraction
    )
    if missing_spm < material_threshold_spm then
        return cache_result(display_bottleneck)
    end
    -- Only include sciences whose individual lost SPM exceeds the material
    -- threshold. A science missing from a trivial number of labs (e.g. 1 of
    -- 500) must not be flagged as a bottleneck, because it would block
    -- switching to any candidate that also uses that science — even when the
    -- science is being produced in surplus and the loss is negligible.
    local res = {}
    for science, lost_spm in pairs(per_science_lost_spm) do
        if lost_spm >= material_threshold_spm then
            res[science] = true
        end
    end
    return cache_result(res)
end

queue.science_is_sufficient = function(xcur, force_index)
    return science_supply_is_sufficient(xcur, force_index)
end

-- Read-only explanation seam for diagnostics. Keep the boolean sufficiency
-- decision authoritative in science_supply_is_sufficient, while identifying
-- the first observable pack-level reason for a failed decision.
queue.get_science_sufficiency_details = function(xcur, force_index)
    local sufficient = science_supply_is_sufficient(xcur, force_index)
    if sufficient then
        return {sufficient = true, reason = nil, failed_sciences = {}}
    end

    local availability = queue.get_science_availability(force_index) or {}
    local missing = {}
    for _, science in pairs((xcur and xcur.meta and xcur.meta.sciences) or {}) do
        if availability[science] ~= true then
            table.insert(missing, science)
        end
    end
    table.sort(missing)
    if #missing > 0 then
        return {sufficient = false, reason = "missing_science", failed_sciences = missing}
    end

    local f = game.forces[force_index]
    if f and f.current_research and xcur and xcur.technology and
        f.current_research.name == xcur.technology.name then
        local bottleneck = queue.get_active_missing_science_bottleneck and
            queue.get_active_missing_science_bottleneck(force_index, xcur) or {}
        local failed = {}
        for science in pairs(bottleneck) do
            table.insert(failed, science)
        end
        table.sort(failed)
        if #failed > 0 then
            return {sufficient = false, reason = "pack_bound", failed_sciences = failed}
        end
        local emergency_missing = auto_switch.get_missing_sciences(
            force_index, xcur.technology, lab.get_runtime_lab_content(force_index), env.get_all_sciences())
        for science in pairs(emergency_missing or {}) do
            table.insert(failed, science)
        end
        table.sort(failed)
        if #failed > 0 then
            return {sufficient = false, reason = "pack_bound", failed_sciences = failed}
        end
    end

    return {sufficient = false, reason = "forecast_insufficient", failed_sciences = {}}
end

queue.get_research_recovery_evidence = function(force_index, technology_name)
    local xcur = tech.get_single_tech_state_ext(force_index, technology_name)
    if not xcur or not xcur.technology then
        return {}
    end
    local forecast_seconds = policy.get_setting(force_index, "forecast_seconds") or 0
    return {
        horizon_seconds = get_depletion_horizon_seconds(xcur, force_index, forecast_seconds),
        physical_demand_per_minute = get_inactive_science_demand_spm(xcur, force_index),
        cached_capacity_per_minute = research_capacity_cache[force_index] and
            research_capacity_cache[force_index][technology_name] or nil
    }
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
        local in_transit = get_in_transit_science_total(force_index, science)
        local stock = (counts[science] or 0) + in_transit
        local net = production - consumption
        local depletion_seconds
        local recovery_seconds
        if net < -0.001 then
            depletion_seconds = stock > 0 and (stock / -net) * 60 or 0
        elseif net > 0.001 and stock < target then
            recovery_seconds = ((target - stock) / net) * 60
            depletion_seconds = math.huge
        else
            depletion_seconds = math.huge
        end

        res[science] = {
            stock = stock,
            target = target,
            production_per_minute = production,
            consumption_per_minute = consumption,
            net_per_minute = net,
            in_transit = in_transit,
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

local compare_scored_queue_entries = function(a, b)
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
end

local get_scored_queue_source = function(force_index, tsx, source)
    local scored = {}
    local seen = {}
    local total_cost = 0
    local candidate_count = 0
    for _, tech_name in ipairs(source or {}) do
        local xcur = tsx and tsx[tech_name]
        if tech_can_be_runtime_candidate(force_index, xcur) then
            total_cost = total_cost + get_research_unit_count(xcur)
            candidate_count = candidate_count + 1
        end
    end
    local avg_cost = candidate_count > 0 and (total_cost / candidate_count) or nil
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

    table.sort(scored, compare_scored_queue_entries)

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

local get_virtual_research_entries = function(force_index, count, science_availability)
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

    local lsci = science_availability or queue.get_science_availability(force_index)
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

        local queue_index = 1
        while sfq[queue_index] ~= nil and not selected_name do
            local candidate_name, candidate_xcur = get_ready_candidate(sfq[queue_index])
            if candidate_name then
                if science_is_available(candidate_xcur, lsci) then
                    selected_name = candidate_name
                    selected_xcur = candidate_xcur
                elseif not blocked_name then
                    blocked_name = candidate_name
                    blocked_xcur = candidate_xcur
                end
            end
            queue_index = queue_index + 1
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
        return true
    end
    mark_internal_research_queue_update(f.index, names)
    f.research_queue = names
    return research_queue_matches(f, names)
end

queue.reorder_queue_by_score = function(force_index)
    local f = game.forces[force_index]
    if not f then return end

    local active_name = get_first_next_tech(f)
    local names, fallback_active = build_runtime_queue_names(force_index, active_name)
    if fallback_active and not active_name then
        set(force_index, keys.current_tech, fallback_active)
    end

    local applied = set_runtime_research_queue(f, names)
    if not applied then
        -- LuaForce silently drops invalid or unavailable technologies. Do not
        -- leave bookkeeping claiming a technology that Factorio rejected.
        local live_name = f.current_research and f.current_research.name
        local first_runtime_tech = f.research_queue and f.research_queue[1]
        local runtime_name = first_runtime_tech and first_runtime_tech.name or first_runtime_tech
        set(force_index, keys.current_tech, runtime_name or live_name)
    end
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
    if selected then
        local rotated_names = {selected}
        for index, tech_name in ipairs(names) do
            if index ~= sq.parallel_rotation_index then
                table.insert(rotated_names, tech_name)
            end
        end
        set(f.index, keys.current_tech, selected)
        set_runtime_research_queue(f, rotated_names)
    end
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

queue.get_upcoming_research_display = function(force_index, count)
    local snapshot = research_health_snapshots[force_index]
    local availability = snapshot and snapshot.availability
    return get_virtual_research_entries(force_index, count, availability)
end

local add_upcoming_display_entry = function(job, tech_name, xcur)
    local cost = get_research_unit_count(xcur)
    local duration
    if job.speed then
        duration = cost / job.speed
        if job.force.current_research and job.force.current_research.name == tech_name then
            duration = duration * math.max(0, 1 - (job.force.research_progress or 0))
        end
    end
    local availability_reason, missing_sciences = get_science_block_details(xcur, job.science_availability)
    table.insert(job.results, {
        tech_name = tech_name,
        level = xcur.technology.level,
        cost = cost,
        duration = duration,
        wait_time = job.speed and job.cumulative_time or nil,
        xcur = xcur,
        has_science = availability_reason == nil,
        availability_reason = availability_reason,
        missing_sciences = missing_sciences
    })
    job.virtually_researched[tech_name] = true
    if duration then
        job.cumulative_time = job.cumulative_time + duration
    end
end

local get_upcoming_display_candidate = function(job, requested_name)
    if job.virtually_researched[requested_name] then
        return nil, nil
    end
    local xcur = job.tech_states[requested_name]
    if not tech_can_be_runtime_candidate(job.force_index, xcur) then
        return nil, nil
    end

    local all_pre_met = true
    local prerequisite_names = {}
    for prerequisite_name in pairs(xcur.meta.all_prerequisites or {}) do
        table.insert(prerequisite_names, prerequisite_name)
        if not job.virtually_researched[prerequisite_name] then
            all_pre_met = false
        end
    end
    if all_pre_met then
        return requested_name, xcur
    end

    table.sort(prerequisite_names)
    for _, prerequisite_name in ipairs(prerequisite_names) do
        local prerequisite = job.tech_states[prerequisite_name]
        if prerequisite and not job.virtually_researched[prerequisite_name] and
            tech_can_be_runtime_candidate(job.force_index, prerequisite) then
            local prerequisite_ready = true
            for second_name in pairs(prerequisite.meta.all_prerequisites or {}) do
                if not job.virtually_researched[second_name] then
                    prerequisite_ready = false
                    break
                end
            end
            if prerequisite_ready then
                return prerequisite_name, prerequisite
            end
        end
    end
    return nil, nil
end

queue.request_upcoming_research_display = function(force_index, count)
    upcoming_display_jobs[force_index] = {
        force_index = force_index,
        phase = "initialize",
        results = {},
        maximum = count or math.huge,
        requested_count = count,
        complete = false
    }
end

queue.tick_upcoming_research_display = function(force_index, budget)
    local job = upcoming_display_jobs[force_index]
    if not job then
        return true, {}
    end
    if job.complete then
        return true, job.results
    end

    if job.phase == "initialize" then
        local f = game.forces[force_index]
        local tsx = tech.get_all_tech_state_ext(force_index)
        if not f or not tsx then
            job.complete = true
            return true, job.results
        end

        local stored_queue = get(force_index, keys.queue)
        local collect_source = not stored_queue or #stored_queue == 0
        if collect_source and (policy.get_setting(force_index, "strategy") == "focused" or
            not state.get_force_setting(force_index, "auto_research",
                const.default_settings.force.settings.auto_research)) then
            collect_source = false
        end

        local source = {}
        if stored_queue and #stored_queue > 0 then
            for _, technology_name in ipairs(stored_queue) do
                table.insert(source, technology_name)
            end
        end

        local speed = queue.get_research_speed(force_index)
        if not speed or speed <= 0 then
            speed = nil
        end
        job.force = f
        job.tech_states = tsx
        job.source = source
        job.collect_source = collect_source
        job.speed = speed
        job.virtually_researched = {}
        job.total_candidate_cost = 0
        job.candidate_count = 0
        job.scan_key = nil
        job.scored = {}
        job.scored_seen = {}
        job.score_index = 1
        job.pinned = queue.get_pinned_tech(force_index)
        job.cumulative_time = 0
        job.phase = "scan"
        queue.request_research_health_snapshot(force_index)
        return false, job.results
    end

    if job.phase == "scan" then
        for _ = 1, 16 do
            local technology_name, xcur = next(job.tech_states, job.scan_key)
            job.scan_key = technology_name
            if not technology_name then
                if job.collect_source then
                    table.sort(job.source)
                end
                if job.candidate_count > 0 then
                    job.average_cost = job.total_candidate_cost / job.candidate_count
                end
                job.phase = "score"
                break
            end
            if xcur.technology.researched then
                job.virtually_researched[technology_name] = true
            end
            if tech_can_be_runtime_candidate(force_index, xcur) then
                job.total_candidate_cost = job.total_candidate_cost + get_research_unit_count(xcur)
                job.candidate_count = job.candidate_count + 1
                if job.collect_source then
                    table.insert(job.source, technology_name)
                end
            end
        end
        return false, job.results
    end

    if job.phase == "score" then
        for _ = 1, 8 do
            local source_index = job.score_index
            local technology_name = job.source[source_index]
            if not technology_name then
                table.sort(job.scored, compare_scored_queue_entries)
                job.source = {}
                for _, entry in ipairs(job.scored) do
                    table.insert(job.source, entry.tech_name)
                end
                job.phase = "finalize"
                break
            end
            job.score_index = source_index + 1
            if not job.scored_seen[technology_name] then
                job.scored_seen[technology_name] = true
                local xcur = job.tech_states[technology_name]
                if tech_can_be_runtime_candidate(force_index, xcur) then
                    local stored_ub = queue.get_tech_ub(force_index, technology_name)
                    local score = queue.score_tech_detailed(
                        xcur,
                        xcur.technology.level,
                        stored_ub,
                        job.average_cost,
                        force_index
                    )
                    table.insert(job.scored, {
                        tech_name = technology_name,
                        score = score.total,
                        source_index = source_index,
                        pinned = job.pinned == technology_name
                    })
                end
            end
        end
        return false, job.results
    end

    if job.phase == "finalize" then
        local snapshot = research_health_snapshots[force_index]
        if not snapshot or not snapshot.availability then
            queue.request_research_health_snapshot(force_index)
            return false, job.results
        end
        local speed = queue.get_research_speed(force_index)
        if speed and speed > 0 then
            job.speed = speed
        end
        job.science_availability = snapshot.availability
        local current_name = job.force.current_research and job.force.current_research.name
        job.remaining_iterations = math.max(
            #job.source * 10,
            (job.requested_count or #job.source) * 10,
            10
        )
        local current = current_name and job.tech_states[current_name]
        if current and current.technology and current.meta then
            add_upcoming_display_entry(job, current_name, current)
        end
        job.phase = "entries"
        if #job.results >= job.maximum or (#job.source == 0 and not current_name) then
            job.complete = true
        end
        if job.complete then
            return true, job.results
        end
        return false, job.results
    end

    local remaining = math.max(1, math.floor(tonumber(budget) or 1))
    while remaining > 0 and #job.results < job.maximum and job.remaining_iterations > 0 do
        remaining = remaining - 1
        job.remaining_iterations = job.remaining_iterations - 1
        local selected_name
        local selected_xcur
        local blocked_name
        local blocked_xcur
        local source_index = 1
        while job.source[source_index] ~= nil and not selected_name do
            local candidate_name, candidate_xcur = get_upcoming_display_candidate(job, job.source[source_index])
            if candidate_name then
                if science_is_available(candidate_xcur, job.science_availability) then
                    selected_name = candidate_name
                    selected_xcur = candidate_xcur
                elseif not blocked_name then
                    blocked_name = candidate_name
                    blocked_xcur = candidate_xcur
                end
            end
            source_index = source_index + 1
        end
        selected_name = selected_name or blocked_name
        selected_xcur = selected_xcur or blocked_xcur
        if not selected_name then
            job.complete = true
            break
        end
        add_upcoming_display_entry(job, selected_name, selected_xcur)
    end

    if #job.results >= job.maximum or job.remaining_iterations <= 0 then
        job.complete = true
    end
    return job.complete, job.results
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

-- Public plan snapshot with stable revision/tick metadata. The inner `plan`
-- retains version = 1 so existing import/export compatibility is preserved;
-- the wrapper only adds non-breaking metadata for the Research Control Center.
queue.get_plan_snapshot = function(force_index)
    local plan = build_plan_snapshot(force_index)
    if not plan then
        return nil
    end
    return {
        revision = 1,
        tick = game and game.tick or 0,
        plan = plan
    }
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
    queue.invalidate_science_cache(force_index)
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
