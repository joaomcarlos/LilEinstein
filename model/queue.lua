--- The queue module is the model in which the mod queue is stored
local util = require("lib.util")
local const = require("lib.const")
local state = require("model.state")
local tech = require("model.tech")
local lab = require("model.lab")
local env = require("model.env")
local logger = require("lib.log")
local rw = require("model.research_weights")

local queue = {}

local research_history_seconds = 10 * 60
local research_history_sample_seconds = 3
local research_history_samples = math.floor(research_history_seconds / research_history_sample_seconds)
local research_speed_average_samples = math.floor(60 / research_history_sample_seconds)

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
    internal_cancelled_techs = "internal_cancelled_techs"
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

local score_tech_custom = function(xcur, weight, cost, num_ingredients)
    if weight <= -100 then
        return weight
    end
    if num_ingredients == 0 then
        num_ingredients = 1
    end
    local total_cost = cost * num_ingredients
    local score = weight / (total_cost ^ 0.15)
    if xcur.available then
        score = score * 1.5
    end
    if xcur.meta.has_spoilable_science then
        score = score * 1.2
    end
    return score
end

local score_tech = function(xcur)
    local weight = get_tech_weight_at_level(xcur, xcur.technology.level)
    local cost = xcur.technology.research_unit_count or 1
    local num_ingredients = 0
    for _ in pairs(xcur.technology.research_unit_ingredients or {}) do
        num_ingredients = num_ingredients + 1
    end
    return score_tech_custom(xcur, weight, cost, num_ingredients)
end

local score_tech_at_level = function(xcur, level)
    local weight = get_tech_weight_at_level(xcur, level)
    local cost = xcur.technology.research_unit_count or 1
    if xcur.meta.is_infinite and xcur.meta.prototype.research_unit_count_formula then
        local est = eval_formula(xcur.meta.prototype.research_unit_count_formula, level)
        if est then
            cost = est
        elseif xcur.technology.level > 0 then
            cost = cost * (level / xcur.technology.level)
        end
    end
    local num_ingredients = 0
    for _ in pairs(xcur.technology.research_unit_ingredients or {}) do
        num_ingredients = num_ingredients + 1
    end
    return score_tech_custom(xcur, weight, cost, num_ingredients)
end

local get_science_counts

-- Return detailed score components: {importance, level_boost, user_boost, total}
-- importance = base AI weight from rw.research_weights + effect inference
-- level_boost = bonus for cheap techs relative to current candidate pool average
-- user_boost = direct user override (can be negative)
-- total = (importance + level_boost) / (total_cost ^ 0.15) + user_boost
queue.score_tech_detailed = function(xcur, level, user_boost, avg_cost, force_index)
    local importance = get_tech_weight_at_level(xcur, level)
    if importance <= -100 then
        return {importance = importance, level_boost = 0, user_boost = user_boost, total = importance}
    end

    if not xcur.available then
        return {importance = -10000, level_boost = 0, user_boost = user_boost, total = -10000}
    end

    if xcur.technology.name == "research-productivity" and force_index then
        local logistic_counts = get_science_counts(force_index)
        local required = (xcur.technology.research_unit_count or 1) * 0.2
        local has_all = true
        for _, s in pairs(xcur.meta.sciences or {}) do
            if (logistic_counts[s] or 0) < required then
                has_all = false
                break
            end
        end
        if has_all then
            return {importance = 999999, level_boost = 0, user_boost = user_boost, total = 999999}
        end
    end

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

    local base = (importance + level_boost) / (total_cost ^ 0.15)
    local total = base + user_boost

    return {
        importance = importance,
        level_boost = level_boost,
        user_boost = user_boost,
        total = total
    }
end

local tech_is_available = function(xcur)
    return xcur and not xcur.technology.researched and xcur.available and xcur.technology.enabled and
               not xcur.meta.has_trigger
end
queue.science_is_available = function(xcur, lsci)
    for _, s in pairs(xcur.meta.sciences or {}) do
        if not lsci or not lsci[s] or lsci[s] <= 0 then
            return false
        end
    end
    return true
end
local science_is_available = queue.science_is_available

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
    if xcur.meta.is_infinite then
        local cap = rw.research_caps[xcur.technology.name]
        if cap and xcur.technology.level >= cap then
            return false
        end
    end
    return true
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
    -- This function returns the next runtime technology without changing the virtual queue order.
    local sfq = get(f.index, keys.queue)
    local tsx = tech.get_all_tech_state_ext(f.index)
    local lsci = lab.get_labs_fill_rate(f.index)

    -- Reset current researching tech
    set(f.index, keys.current_tech, nil)
    set(f.index, keys.current_tech_smart, nil)

    -- Reset & get missing science array
    set(f.index, keys.misses_science, {})
    local sfsci = get(f.index, keys.misses_science)

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

local get_single_next_science = function(candidates, lsci, tsx)
    local best_score = -math.huge
    local best_tech = nil

    for tech_name, xcur in pairs(candidates) do
        local candidate = nil
        if xcur.available then
            if science_is_available(xcur, lsci) then
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
            local score = score_tech(candidate)
            if score > best_score then
                best_score = score
                best_tech = candidate.technology.name
            end
        end
    end

    return best_tech
end
local get_first_next_tech_smart = function(f)
    -- AI weighted scoring + custom order bonus. Skips disabled techs.
    local tsx = tech.get_all_tech_state_ext(f.index)
    local lsci = lab.get_labs_fill_rate(f.index)

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
    local lsci = lab.get_labs_fill_rate(f.index)
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

    -- For finite tech levels that are not fully researched yet we only need to request the next stage
    if xcur.technology.level and not xcur.meta.is_infinite and not xcur.technology.researched then
        return
    end

    -- For all other cases we have to remove the tech from the queue
    queue.remove(f, t.name, true)

    -- If it is an infinite tech and requeueing is enabled we have to add it to the end of the queue again
    if xcur.meta.is_infinite and
        state.get_force_setting(f.index, "requeue_infinite_tech",
            const.default_settings.force.settings.requeue_infinite_tech) then
        queue.add(f, t.name)
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
        f.research_queue = {}
        return
    end

    local sfq = get(f.index, keys.queue)
    local auto_research = state.get_force_setting(f.index, "auto_research",
        const.default_settings.force.settings.auto_research)

    -- If no queue and auto-research is off, clear game queue and idle
    if not sfq or #sfq == 0 then
        if not auto_research then
            f.research_queue = {}
            return
        end
        queue.build_queue_from_available(f.index)
        sfq = get(f.index, keys.queue)
        if not sfq or #sfq == 0 then
            f.research_queue = {}
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
    for i, q in pairs(sfq or {}) do
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
        i = i + 1
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

    -- Get the current position or early exit if already first
    local i = get_queue_position(f, tech_name)
    if i == 1 then
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

    -- Get the current index and length or early exit if already last
    local i = get_queue_position(f, tech_name)
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

local get_average_research_speed = function(samples, sample_count)
    if not samples or #samples == 0 then
        return nil, false
    end

    local total = 0
    local count = 0
    local start_index = math.max(1, #samples - (sample_count or research_speed_average_samples) + 1)
    for i = start_index, #samples do
        local s = samples[i]
        if s and s.speed and s.speed > 0 then
            total = total + s.speed
            count = count + 1
        end
    end

    if count > 0 then
        return total / count, true
    end
    return nil, false
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

    -- Compute speed if same research as previous sample
    if #samples > 0 then
        local last = samples[#samples]
        if current and last.tech_name == tech_name and progress >= last.progress then
            local delta_progress = progress - last.progress
            local delta_ticks = now - last.tick
            -- units per second = (fraction_complete * total_units) / seconds
            if delta_ticks > 0 then
                speed = (delta_progress * unit_count * 60) / delta_ticks
            end
        end
    end

    table.insert(samples, {
        tick = now,
        progress = progress,
        tech_name = tech_name,
        unit_count = unit_count,
        speed = speed
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

get_science_counts = function(force_index)
    local now = game.tick

    -- Refresh labs/network cache every 10 minutes, or immediately if refs went invalid (save/load)
    local lc = labs_cache[force_index]
    if not lc or (now - lc.tick) >= 36000
        or has_invalid_ref(lc.labs) then
        refresh_labs_cache(force_index)
        lc = labs_cache[force_index]
    end

    -- Count cache is per-tick
    local cc = counts_cache[force_index]
    if cc and cc.tick == now then
        return cc.counts
    end

    local counts = {}
    local detected_networks = {}
    local breakdown = {}

    -- Packs in labs
    for _, lab_entity in pairs(lc.labs) do
        if lab_entity.valid then
            local inv = lab_entity.get_inventory(defines.inventory.lab_input)
            local network = get_lab_network(lab_entity)
            if network and network.valid then
                local network_id = network.network_id
                local cur = network_id and detected_networks[network_id] or nil
                if not cur then
                    cur = {
                        network_id = network_id,
                        network = network,
                        lab_count = 0,
                        sample_lab = lab_entity,
                        sample_unit_number = lab_entity.unit_number or 0
                    }
                    if network_id then
                        detected_networks[network_id] = cur
                    end
                end
                if cur then
                    cur.lab_count = cur.lab_count + 1
                end
            end
            if inv then
                for _, item in pairs(inv.get_contents()) do
                    counts[item.name] = (counts[item.name] or 0) + (item.count or 0)
                    if not breakdown[item.name] then
                        breakdown[item.name] = {
                            lab_count = 0,
                            lab_entity_count = 0,
                            network_total = 0,
                            networks = {}
                        }
                    end
                    breakdown[item.name].lab_count = breakdown[item.name].lab_count + (item.count or 0)
                    breakdown[item.name].lab_entity_count = breakdown[item.name].lab_entity_count + 1
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
            for _, science in pairs(env.get_all_sciences()) do
                local network_count = network.get_item_count(science)
                counts[science] = (counts[science] or 0) + network_count
                if network_count > 0 then
                    if not breakdown[science] then
                        breakdown[science] = {
                            lab_count = 0,
                            lab_entity_count = 0,
                            network_total = 0,
                            networks = {}
                        }
                    end
                    breakdown[science].network_total = breakdown[science].network_total + network_count
                    table.insert(breakdown[science].networks, {
                        label = network_label,
                        count = network_count,
                        lab_count = network_meta.lab_count
                    })
                end
            end
        end
    end

    counts_cache[force_index] = {tick = now, counts = counts, breakdown = breakdown}
    return counts
end

queue.get_science_counts = get_science_counts
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

local get_research_unit_count = function(xcur)
    local cost = xcur.technology.research_unit_count or 1
    if xcur.meta.is_infinite and xcur.meta.prototype.research_unit_count_formula then
        local est = eval_formula(xcur.meta.prototype.research_unit_count_formula, xcur.technology.level)
        if est then
            cost = est
        end
    end
    return cost
end

local get_virtual_queue_source = function(force_index, tsx)
    local sfq = get(force_index, keys.queue)
    if sfq and #sfq > 0 then
        return sfq
    end

    local scored = {}
    local total_cost_sum = 0
    local cost_count = 0
    for tech_name, xcur in pairs(tsx or {}) do
        if tech_can_be_runtime_candidate(force_index, xcur) then
            total_cost_sum = total_cost_sum + get_research_unit_count(xcur)
            cost_count = cost_count + 1
        end
    end
    local avg_cost = cost_count > 0 and (total_cost_sum / cost_count) or nil

    for tech_name, xcur in pairs(tsx or {}) do
        if tech_can_be_runtime_candidate(force_index, xcur) then
            local stored_ub = queue.get_tech_ub(force_index, tech_name)
            local sd = queue.score_tech_detailed(xcur, xcur.technology.level, stored_ub, avg_cost, force_index)
            table.insert(scored, {
                tech_name = tech_name,
                score = sd.total
            })
        end
    end

    table.sort(scored, function(a, b)
        return a.score > b.score
    end)

    local res = {}
    for _, entry in ipairs(scored) do
        table.insert(res, entry.tech_name)
    end
    return res
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

    local sfq = get_virtual_queue_source(force_index, tsx)
    if not sfq or #sfq == 0 then
        return {}
    end

    local speed, _ = queue.get_research_speed(force_index)
    if not speed or speed <= 0 then
        speed = nil
    end

    local lsci = lab.get_labs_fill_rate(force_index)
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
        end
        table.insert(results, {
            tech_name = tech_name,
            level = xcur.technology.level,
            cost = cost,
            duration = duration,
            wait_time = cumulative_time,
            xcur = xcur,
            has_science = science_is_available(xcur, lsci)
        })
        virtually_researched[tech_name] = true
        if duration then
            cumulative_time = cumulative_time + duration
        end
    end

    while #results < max_results and max_iter > 0 do
        max_iter = max_iter - 1
        local found = false

        for _, q in ipairs(sfq) do
            if not virtually_researched[q] then
                local xcur = tsx[q]
                if tech_can_be_runtime_candidate(force_index, xcur) then
                    local all_pre_met = true
                    for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
                        if not virtually_researched[pre_req_tech] then
                            all_pre_met = false
                            break
                        end
                    end

                    if all_pre_met then
                        add_entry(q, xcur)
                        found = true
                        break
                    end

                    for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
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
                                add_entry(pre_req_tech, xpre)
                                found = true
                                break
                            end
                        end
                    end
                    if found then break end
                end
            end
        end

        if not found then
            break
        end
    end

    return results
end

local build_runtime_queue_names = function(force_index, active_name)
    local entries = get_virtual_research_entries(force_index)
    local names = {}
    local seen = {}

    if active_name then
        table.insert(names, active_name)
        seen[active_name] = true
    elseif entries[1] then
        active_name = entries[1].tech_name
        table.insert(names, active_name)
        seen[active_name] = true
    end

    for _, entry in ipairs(entries) do
        if not seen[entry.tech_name] then
            table.insert(names, entry.tech_name)
            seen[entry.tech_name] = true
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

local set_runtime_research_queue = function(f, names)
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

    if #names == 0 then
        return
    end

    set_runtime_research_queue(f, names)
end

queue.build_queue_from_available = function(force_index)
    -- Build a fresh queue from all available techs sorted by score (same as right panel)
    local f = game.forces[force_index]
    if not f then return end
    local tsx = tech.get_all_tech_state_ext(force_index)
    if not tsx then return end

    local lsci = lab.get_labs_fill_rate(force_index)

    -- Compute avg_cost from all unresearched enabled techs
    local total_cost_sum = 0
    local cost_count = 0
    for tech_name, xcur in pairs(tsx) do
        if xcur.technology.researched then goto skip_avg end
        if not xcur.technology.enabled or xcur.meta.hidden then goto skip_avg end
        if not queue.get_tech_enabled(force_index, tech_name) then goto skip_avg end
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

queue.promote = function(f, tech_name, steps)
    local sfq = get(f.index, keys.queue)
    if not sfq then
        return
    end
    steps = steps or 1
    for i = 2, #sfq do
        if sfq[i] == tech_name then
            local new_pos = math.max(1, i - steps)
            table.remove(sfq, i)
            table.insert(sfq, new_pos, tech_name)
            break
        end
    end
end

queue.demote = function(f, tech_name, steps)
    local sfq = get(f.index, keys.queue)
    if not sfq then
        return
    end
    steps = steps or 1
    for i = 1, #sfq - 1 do
        if sfq[i] == tech_name then
            local new_pos = math.min(#sfq, i + steps)
            table.remove(sfq, i)
            table.insert(sfq, new_pos, tech_name)
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

    -- Register each queued tech
    local sfq = get(force_index, keys.queue)
    for _, q in pairs(sfq or {}) do
        tech.update_queued(force_index, q, true)
    end
end

return queue
