--- The queue module is the model in which the mod queue is stored
local util = require("lib.util")
local const = require("lib.const")
local state = require("model.state")
local tech = require("model.tech")
local lab = require("model.lab")
local env = require("model.env")
local rw = require("model.research_weights")

local queue = {}

-- Data model
-- storage.forces[force_index].queue.queue = {"tech-1", ...}

local keys = {
    queue = "queue",
    current_tech = "current_tech",
    current_tech_smart = "current_tech_smart",
    misses_science = "misses_science",
    announced_blocked = "announced_blocked",
    is_stuck = "is_stuck",
    pinned_tech = "pinned_tech"
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
local get_first_next_tech = function(f)
    -- This function returns the first next available technology as required to progress in the queue
    local sfq = get(f.index, keys.queue)
    local lsci = lab.get_labs_fill_rate(f.index)

    -- Reset current researching tech
    set(f.index, keys.current_tech, nil)

    -- Reset & get missing science array
    set(f.index, keys.misses_science, {})
    local sfsci = get(f.index, keys.misses_science)

    for _, q in ipairs(sfq or {}) do
        local xcur = tech.get_single_tech_state_ext(f.index, q)
        if not xcur then goto skip_next end
        if xcur.technology.researched then goto skip_next end
        if not xcur.technology.enabled or xcur.meta.hidden then goto skip_next end

        if xcur.available then
            if science_is_available(xcur, lsci) then
                set(f.index, keys.current_tech, q)
                set(f.index, keys.current_tech_smart, nil)
                return q
            else
                sfsci[q] = true
            end
        else
            local misses_science = false
            for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
                local xpre = tech.get_single_tech_state_ext(f.index, pre_req_tech)
                if xpre and not xpre.technology.researched and tech_is_available(xpre) then
                    if science_is_available(xpre, lsci) then
                        set(f.index, keys.current_tech, q)
                        set(f.index, keys.current_tech_smart, nil)
                        return pre_req_tech
                    else
                        misses_science = true
                    end
                end
            end
            if misses_science then
                sfsci[q] = true
            end
        end
        ::skip_next::
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
        f.print("[LilEinstein] Error: Unexpected technology " .. (t.name or "(no technology passed)"))
        return
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

local set_ingame_research = function(f, tech_name)
    local target = f.technologies[tech_name]
    if not target then return end
    -- Already researching this tech
    if f.current_research and f.current_research.name == tech_name then
        return
    end
    -- If idle, start the tech
    if not f.current_research then
        f.add_research(target)
        return
    end
    -- Already researching something else: do nothing, let reorder_queue_by_score handle queue ordering
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

    if not f.current_research then
        -- Idle: ensure sorted then pick best scored available tech and start it
        queue.reorder_queue_by_score(f.index)
        local next = get_first_next_tech(f)
        if next then
            set_ingame_research(f, next)
            set(f.index, keys.current_tech_smart, nil)
            return
        end
        if auto_research then
            queue.build_queue_from_available(f.index)
            queue.reorder_queue_by_score(f.index)
            next = get_first_next_tech(f)
            if next then
                set_ingame_research(f, next)
                set(f.index, keys.current_tech_smart, nil)
                return
            end
        end
        f.research_queue = {}
    else
        -- Researching: keep display in sync and switch away if starved
        set(f.index, keys.current_tech, f.current_research.name)
        if auto_research then
            -- Refresh queue with newly available techs so prerequisites that
            -- just completed are picked up instead of letting the queue go stale
            queue.build_queue_from_available(f.index)
        end
        queue.reorder_queue_by_score(f.index)
        if queue.research_is_stuck(f) then
            local sfq = get(f.index, keys.queue)
            local tsx = tech.get_all_tech_state_ext(f.index)
            local lsci = lab.get_labs_fill_rate(f.index)
            -- Scan the whole queue for the first available tech and switch to it
            for _, q in ipairs(sfq or {}) do
                if q ~= f.current_research.name then
                    local x = tsx and tsx[q]
                    if x and x.available and science_is_available(x, lsci) then
                        f.cancel_current_research()
                        f.research_queue = sfq
                        set(f.index, keys.current_tech, q)
                        break
                    end
                end
            end
        end
    end
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
        if t.name and (t.name ~= nil or t.name ~= "") then
            f.print("[LilEinstein] ERROR: Trying to queue technology: '" .. t.name ..
                        "' but it is not valid, please open a bug report on the mod portal")
        else
            f.print("[LilEinstein] ERROR: Trying to queue technology: '" .. serpent.line(t) ..
                        "' but it is not valid, please open a bug report on the mod portal")
        end
        return
    end

    -- Check if this research is actually available or early exit
    if not t.enabled then
        if not silent then
            f.print({"lil_einstein-msg.warn-queue-disabled", t.localised_name})
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
                f.print({"lil_einstein-msg.already-queued", t.localised_name})
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
        f.print({"lil_einstein-msg.added-to-queue", t.localised_name})
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
                f.print({"lil_einstein-msg.removed-from-queue", t.localised_name})
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

queue.record_research_progress = function(force_index)
    -- Sample actual research progress every 60 ticks to measure real speed.
    local f = game.forces[force_index]
    if not f then return end
    local current = f.current_research
    if not current then return end

    local sf = storage.forces[force_index]
    if not sf.queue then sf.queue = {} end
    if not sf.queue.speed_samples then
        sf.queue.speed_samples = {}
    end
    local samples = sf.queue.speed_samples

    local now = game.tick
    local progress = f.research_progress or 0
    local tech_name = current.name
    local unit_count = current.research_unit_count or 1

    -- Compute speed if same research as previous sample
    if #samples > 0 then
        local last = samples[#samples]
        if last.tech_name == tech_name and progress > last.progress then
            local delta_progress = progress - last.progress
            local delta_ticks = now - last.tick
            -- units per second = (fraction_complete * total_units) / seconds
            local ups = (delta_progress * unit_count * 60) / delta_ticks
            last.speed = ups
        end
    end

    table.insert(samples, {
        tick = now,
        progress = progress,
        tech_name = tech_name,
        unit_count = unit_count
    })

    -- Keep only last 60 samples (1 minute at 1 sample/sec)
    while #samples > 60 do
        table.remove(samples, 1)
    end
end

queue.get_research_speed = function(force_index)
    -- Return average measured research speed in units/second, and a flag.
    local sf = storage.forces[force_index]
    if not sf or not sf.queue or not sf.queue.speed_samples then
        return nil, false
    end
    local samples = sf.queue.speed_samples

    local total = 0
    local count = 0
    for _, s in ipairs(samples) do
        if s.speed and s.speed > 0 then
            total = total + s.speed
            count = count + 1
        end
    end

    if count > 0 then
        return total / count, true
    end
    return nil, false
end

-- Cooldown tracker for reorder_queue_by_score [force_index] = last_tick
-- Two-tier cache per force:
--   labs_cache:  labs + best_network, refreshed every 10 min (36000 ticks)
--   counts_cache: counts refreshed every tick
local labs_cache = {}
local counts_cache = {}

local refresh_labs_cache = function(force_index)
    local all_labs = {}
    local network_lab_counts = {}

    for _, surface in pairs(game.surfaces) do
        local surface_labs = surface.find_entities_filtered({type = "lab", force = force_index})
        for _, lab_entity in pairs(surface_labs) do
            if lab_entity.valid then
                table.insert(all_labs, lab_entity)
                local network = lab_entity.logistic_network
                if network and network.valid then
                    network_lab_counts[network] = (network_lab_counts[network] or 0) + 1
                end
            end
        end
    end

    local best_network = nil
    local best_count = 0
    for network, count in pairs(network_lab_counts) do
        if count > best_count then
            best_count = count
            best_network = network
        end
    end

    labs_cache[force_index] = {
        tick = game.tick,
        labs = all_labs,
        network = best_network
    }
end

get_science_counts = function(force_index)
    local now = game.tick

    -- Refresh labs/network cache every 10 minutes, or immediately if refs went invalid (save/load)
    local lc = labs_cache[force_index]
    if not lc or (now - lc.tick) >= 36000
        or (lc.network and not lc.network.valid)
        or (#lc.labs > 0 and not lc.labs[1].valid) then
        refresh_labs_cache(force_index)
        lc = labs_cache[force_index]
    end

    -- Count cache is per-tick
    local cc = counts_cache[force_index]
    if cc and cc.tick == now then
        return cc.counts
    end

    local counts = {}

    -- Packs on the chosen network
    if lc.network and lc.network.valid then
        for _, science in pairs(env.get_all_sciences()) do
            counts[science] = (counts[science] or 0) + lc.network.get_item_count(science)
        end
    end

    -- Packs in labs
    for _, lab_entity in pairs(lc.labs) do
        if lab_entity.valid then
            local inv = lab_entity.get_inventory(defines.inventory.lab_input)
            if inv then
                for _, item in pairs(inv.get_contents()) do
                    counts[item.name] = (counts[item.name] or 0) + (item.count or 0)
                end
            end
        end
    end

    counts_cache[force_index] = {tick = now, counts = counts}
    return counts
end

queue.get_science_counts = get_science_counts

local reorder_cooldown = {}

queue.reorder_queue_by_score = function(force_index)
    local f = game.forces[force_index]
    if not f then return end
    local sfq = get(force_index, keys.queue)
    if not sfq or #sfq == 0 then return end

    -- Enforce 60-tick cooldown to avoid thrashing / constant research switching
    local last = reorder_cooldown[force_index] or 0
    if game.tick - last < 60 then
        return
    end
    reorder_cooldown[force_index] = game.tick

    local tsx = tech.get_all_tech_state_ext(force_index)
    if not tsx then return end

    local lsci = lab.get_labs_fill_rate(force_index)

    -- Compute avg_cost from ALL unresearched enabled techs (same as right panel)
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
    for orig_idx, tech_name in ipairs(sfq) do
        local xcur = tsx[tech_name]
        if xcur then
            local include = true
            if xcur.technology.researched then include = false end
            if not xcur.technology.enabled or xcur.meta.hidden then include = false end
            if not queue.get_tech_enabled(force_index, tech_name) then include = false end
            if xcur.meta.is_infinite then
                local cap = rw.research_caps[tech_name]
                if cap and xcur.technology.level >= cap then include = false end
            end

            if include then
                local stored_ub = queue.get_tech_ub(force_index, tech_name)
                local sd = queue.score_tech_detailed(xcur, xcur.technology.level, stored_ub, avg_cost, force_index)
                local entry = {
                    tech_name = tech_name,
                    score = sd.total,
                    orig_idx = orig_idx,
                    is_available = xcur.available and science_is_available(xcur, lsci),
                    importance = sd.importance,
                    level_boost = sd.level_boost,
                    user_boost = sd.user_boost
                }
                if entry.is_available then
                    table.insert(available, entry)
                else
                    table.insert(blocked, entry)
                end
            end
        end
    end

    -- Sort available by score descending; blocked keep original order
    table.sort(available, function(a, b)
        return a.score > b.score
    end)

    -- Promote pinned tech to the absolute front of available entries
    local pinned = queue.get_pinned_tech(force_index)
    if pinned then
        for i, entry in ipairs(available) do
            if entry.tech_name == pinned then
                table.remove(available, i)
                table.insert(available, 1, entry)
                break
            end
        end
    end

    -- Rebuild sfq and game queue: available techs sorted purely by score,
    -- then blocked. This lets a previously-starved tech resume at the front
    -- when its packs return and it has the highest score.
    local sorted_names = {}
    for _, entry in ipairs(available) do
        table.insert(sorted_names, entry.tech_name)
    end
    for _, entry in ipairs(blocked) do
        table.insert(sorted_names, entry.tech_name)
    end

    -- Print reason for each moved research
    for new_idx, tech_name in ipairs(sorted_names) do
        for _, entry in ipairs(available) do
            if entry.tech_name == tech_name then
                local delta = entry.orig_idx - new_idx
                if delta ~= 0 then
                    local reason
                    if delta > 0 then
                        reason = "moved UP " .. delta .. " spots"
                    else
                        reason = "moved DOWN " .. math.abs(delta) .. " spots"
                    end
                    local pinned_note = ""
                    if tech_name == pinned then
                        pinned_note = " [PINNED]"
                    end
                    local avail_note = entry.is_available and "" or " [BLOCKED]"
                    game.print("LilEinstein: " .. tech_name .. pinned_note .. avail_note .. " " .. reason ..
                        " | importance=" .. entry.importance ..
                        " level_boost=" .. entry.level_boost ..
                        " user_boost=" .. entry.user_boost ..
                        " total=" .. string.format("%.2f", entry.score))
                end
                break
            end
        end
    end

    -- Update sfq in place
    for i, name in ipairs(sorted_names) do
        sfq[i] = name
    end
    for i = #sfq, #sorted_names + 1, -1 do
        sfq[i] = nil
    end

    -- Assign directly to game queue
    f.research_queue = sorted_names
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
    -- Simulate upcoming research from the mod's master queue (sfq).
    -- This is the mod's execution plan, NOT a read of f.research_queue.
    local f = game.forces[force_index]
    if not f then
        return {}
    end

    local sfq = get(force_index, keys.queue)
    if not sfq or #sfq == 0 then
        sfq = {}
        local tsx = tech.get_all_tech_state_ext(force_index)
        if not tsx then
            return {}
        end

        local scored = {}
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
            total_cost_sum = total_cost_sum + (xcur.technology.research_unit_count or 1)
            cost_count = cost_count + 1
            ::skip_avg::
        end
        local avg_cost = cost_count > 0 and (total_cost_sum / cost_count) or nil

        for tech_name, xcur in pairs(tsx) do
            if xcur.technology.researched then goto skip_score end
            if not xcur.technology.enabled or xcur.meta.hidden then goto skip_score end
            if not queue.get_tech_enabled(force_index, tech_name) then goto skip_score end
            if xcur.meta.is_infinite then
                local cap = rw.research_caps[tech_name]
                if cap and xcur.technology.level >= cap then goto skip_score end
            end

            local stored_ub = queue.get_tech_ub(force_index, tech_name)
            local sd = queue.score_tech_detailed(xcur, xcur.technology.level, stored_ub, avg_cost, force_index)
            table.insert(scored, {
                tech_name = tech_name,
                score = sd.total
            })
            ::skip_score::
        end

        table.sort(scored, function(a, b) return a.score > b.score end)
        for _, entry in ipairs(scored) do
            table.insert(sfq, entry.tech_name)
        end
        if #sfq == 0 then
            return {}
        end
    end

    local speed, _ = queue.get_research_speed(force_index)
    if not speed or speed <= 0 then
        speed = nil
    end

    local tsx = tech.get_all_tech_state_ext(force_index)
    if not tsx then
        return {}
    end

    local lsci = lab.get_labs_fill_rate(force_index)

    -- Set of techs already researched or consumed in the simulation
    local virtually_researched = {}
    for name, xcur in pairs(tsx) do
        if xcur.technology.researched then
            virtually_researched[name] = true
        end
    end

    local results = {}
    local cumulative_time = 0
    local max_iter = count * 5  -- safety guard

    while #results < count and max_iter > 0 do
        max_iter = max_iter - 1
        local found = false

        for _, q in ipairs(sfq) do
            if virtually_researched[q] then goto skip end

            local xcur = tsx[q]
            if not xcur then goto skip end
            if not xcur.technology.enabled or xcur.meta.hidden then goto skip end
            if not queue.get_tech_enabled(force_index, q) then goto skip end

            -- Check if all prerequisites are virtually researched
            local all_pre_met = true
            for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
                if not virtually_researched[pre_req_tech] then
                    all_pre_met = false
                    break
                end
            end

            if all_pre_met then
                -- Available: add to projected sequence
                if science_is_available(xcur, lsci) then
                    local cost = xcur.technology.research_unit_count or 1
                    local duration
                    if speed then
                        duration = cost / speed
                    end
                    table.insert(results, {
                        tech_name = q,
                        level = xcur.technology.level,
                        cost = cost,
                        duration = duration,
                        wait_time = cumulative_time,
                        xcur = xcur
                    })
                    virtually_researched[q] = true
                    if duration then
                        cumulative_time = cumulative_time + duration
                    end
                    found = true
                    break
                end
            else
                -- Blocked: inject the first available prerequisite
                for pre_req_tech, _ in pairs(xcur.meta.all_prerequisites or {}) do
                    local xpre = tsx[pre_req_tech]
                    if xpre and not virtually_researched[pre_req_tech] then
                        local pre_all_met = true
                        for pre_req_tech_2, _ in pairs(xpre.meta.all_prerequisites or {}) do
                            if not virtually_researched[pre_req_tech_2] then
                                pre_all_met = false
                                break
                            end
                        end
                        if pre_all_met and science_is_available(xpre, lsci) then
                            local cost = xpre.technology.research_unit_count or 1
                            local duration
                            if speed then
                                duration = cost / speed
                            end
                            table.insert(results, {
                                tech_name = pre_req_tech,
                                level = xpre.technology.level,
                                cost = cost,
                                duration = duration,
                                wait_time = cumulative_time,
                                xcur = xpre
                            })
                            virtually_researched[pre_req_tech] = true
                            if duration then
                                cumulative_time = cumulative_time + duration
                            end
                            found = true
                            break
                        end
                    end
                end
                if found then break end
            end

            ::skip::
        end

        if not found then break end
    end

    return results
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
