local const = require("lib.const")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local policy = require("model.research_policy")
local lab = require("model.lab")
local logger = require("lib.log")
local analyzer = require("view.gui.analyzer")

local gutil = require("view.gui.gutil")

local gctech = {}
local populate_jobs = {}
local filtered_allowed_cache = {}

local get_tech_icon = function(techtbl, xcur, enbl, player_index)
    local icn = techtbl.add({
        type = "sprite-button",
        name = xcur.technology.name,
        style = "lil_einstein_tech_btn_available",
        sprite = "technology/" .. xcur.technology.name,
        tags = {
            lil_einstein_on_click = true,
            handler = "show_technology_screen"
        },
        enabled = enbl,
        tooltip = gutil.get_tooltip_text(xcur, player_index)
    })
    icn.style.width = 74
    icn.style.height = 74
    if xcur.technology.researched then
        icn.style = "lil_einstein_tech_btn_researched"
    elseif xcur.available and xcur.meta.has_trigger then
        icn.style = "lil_einstein_tech_btn_blocked"
    elseif not xcur.available then
        icn.style = "lil_einstein_tech_btn_unavailable"
    end
    -- icn.style.height = 85
end

local get_title = function(techtbl, xcur, enbl, player_index, force_index, score_comps)
    local TECH_ICON_SIZE = 22
    local ICON_SIZE = 14

    -- Make tooltip
    local tt = gutil.get_tooltip_text(xcur, player_index)

    local s = techtbl.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_nospacing",
        direction = "horizontal",
        enabled = enbl
    })
    s.style.width = 506
    s.style.height = 74

    local n = s.add({
        type = "flow",
        direction = "vertical",
        style = "lil_einstein_vertical_flow",
        enabled = enbl
    })

    -- The name with on/off checkbox
    local name = xcur.technology.localised_name
    local t = n.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_nospacing",
        direction = "horizontal",
        enabled = enbl
    })
    t.style.top_margin = 5
    t.style.left_margin = 2

    local is_enabled = queue.get_tech_enabled(force_index, xcur.technology.name)
    local sw = t.add({
        type = "sprite-button",
        style = "lil_einstein_enable_switch_button",
        sprite = is_enabled and "lil_einstein_mockup_enable_switch_on" or "lil_einstein_mockup_enable_switch_off",
        hovered_sprite = is_enabled and "lil_einstein_mockup_enable_switch_on" or
            "lil_einstein_mockup_enable_switch_off",
        clicked_sprite = is_enabled and "lil_einstein_mockup_enable_switch_on" or
            "lil_einstein_mockup_enable_switch_off",
        tags = {
            lil_einstein_on_click = true,
            handler = "toggle_tech_enabled",
            technology = xcur.technology.name
        },
        enabled = enbl
    })
    sw.style.right_margin = 4

    local l = t.add({
        type = "label",
        caption = name,
        style = "bold_label",
        tooltip = tt,
        enabled = enbl
    })
    -- Dim the label if disabled
    if not is_enabled then
        l.style.font_color = {r = 0.5, g = 0.5, b = 0.5}
    end

    l.style.left_margin = 5
    l.style.maximal_width = 360
    local f = n.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_nospacing",
        direction = "horizontal",
        enabled = enbl
    })
    f.style.height = TECH_ICON_SIZE
    -- The sciences
    local first = true
    for _, sci in pairs(xcur.meta.sciences or {}) do
        local ss = f.add({
            type = "sprite",
            sprite = "item/" .. sci,
            tooltip = {"item-name." .. sci}
        })
        -- If there are more than 8 sciences we need to add negative left margin to compensate for each science icon
        -- if not first and #t.research_unit_ingredients > 8 then
        if not first and #xcur.meta.sciences > 10 then
            ss.style.left_margin = (TECH_ICON_SIZE * (#xcur.meta.sciences - 10)) / -#xcur.meta.sciences
        end
        ss.style.size = TECH_ICON_SIZE
        ss.style.stretch_image_to_widget_size = true
        first = false
    end
    -- The unlock tech
    if xcur.meta.has_trigger then
        local rt = xcur.meta.prototype.research_trigger
        local pr = {
            type = "sprite",
            style = "lil_einstein_image_science"
        }
        if rt.type == "craft-item" and rt.item then
            local rtname = (rt.item.name or rt.item)
            local lname = prototypes.item[rtname].localised_name
            local itm = {"", "[item=" .. rtname .. "]", {"gui-text-tags.following-text-item", lname}}
            local cnt = rt.count or 1
            if cnt == 1 then
                pr.tooltip = {"technology-trigger.craft-item", itm}
            else
                pr.tooltip = {"technology-trigger.craft-items", cnt, itm}
            end
            pr.sprite = "item/" .. rtname
        elseif rt.type == "mine-entity" and rt.entity then
            local rtname = (rt.entity.name or rt.entity)
            local lname = prototypes.entity[rtname].localised_name
            local itm = {"", "[entity=" .. rtname .. "]", {"gui-text-tags.following-text-entity", lname}}
            pr.tooltip = {"technology-trigger.mine-entity", itm}
            pr.sprite = "entity/" .. rtname
        elseif rt.type == "craft-fluid" and rt.fluid then
            local rtname = (rt.fluid.name or rt.fluid)
            local lname = prototypes.fluid[rtname].localised_name
            local itm = {"", "[fluid=" .. rtname .. "]", {"gui-text-tags.following-text-fluid", lname}}
            pr.tooltip = {"lil_einstein-trigger-action.craft-fluid", rt.amount or 0, itm}
            pr.sprite = "fluid/" .. rtname
        elseif rt.type == "capture-spawner" then
            if rt.entity then
                local rtname = (rt.entity.name or rt.entity)
                local lname = prototypes.entity[rtname].localised_name
                local itm = {"", "[entity=" .. rtname .. "]", {"gui-text-tags.following-text-entity", lname}}
                pr.tooltip = {"technology-trigger.capture-spawner", itm}
                pr.sprite = "entity/" .. rtname
            else
                -- TODO: Add custom trigger unlock image
                pr.tooltip = {"technology-trigger.capture-any-spawner"}
                pr.sprite = "entity/biter-spawner"
            end
        elseif rt.type == "build-entity" and rt.entity then
            local rtname = (rt.entity.name or rt.entity)
            local lname = prototypes.entity[rtname].localised_name
            local itm = {"", "[entity=" .. rtname .. "]", {"gui-text-tags.following-text-entity", lname}}
            pr.tooltip = {"technology-trigger.build-entity", itm}
            pr.sprite = "entity/" .. rtname
        elseif rt.type == "create-space-platform" then
            local rtname = ("space-platform-starter-pack")
            local lname = prototypes.item[rtname].localised_name
            local itm = {"", "[item=" .. rtname .. "]", {"gui-text-tags.following-text-item", lname}}
            pr.tooltip = {"technology-trigger.create-space-platform-specific", itm}
            pr.sprite = "item/space-platform-starter-pack"
        elseif rt.type == "send-item-to-orbit" and rt.item then
            local rtname = (rt.item.name or rt.item)
            local lname = prototypes.item[rtname].localised_name
            local itm = {"", "[item=" .. rtname .. "]", {"gui-text-tags.following-text-item", lname}}
            pr.tooltip = {"technology-trigger.send-item-to-orbit", itm}
            pr.sprite = "item/" .. rtname
        elseif rt.type == "scripted" then
            pr.tooltip = rt.trigger_description
            pr.sprite = "utility/questionmark"
        else
            pr.tooltip = xcur.technology.name ..
                             " has unknown research trigger, please open a bug report in the mod portal"
            pr.sprite = "utility/danger_icon"
        end
        pr.enabled = enbl
        local ss = f.add(pr)
        ss.style.size = TECH_ICON_SIZE
        ss.style.width = TECH_ICON_SIZE
        ss.style.height = TECH_ICON_SIZE
        ss.style.stretch_image_to_widget_size = true

        local cu = f.add({
            type = "sprite",
            sprite = "virtual-signal/signal-unlock",
            tooltip = pr.tooltip
        })
        cu.style.size = ICON_SIZE
        cu.style.stretch_image_to_widget_size = true
        cu.style.left_margin = -8
        cu.style.top_margin = 9
    end

    -- Weight components display
    if score_comps then
        local wf = n.add({
            type = "flow",
            style = "lil_einstein_horizontal_flow_nospacing",
            direction = "horizontal",
            enabled = enbl
        })
        wf.style.top_margin = 0
        wf.style.left_margin = 2
        wf.add({
            type = "label",
            caption = string.format("IW:%d LB:%d UB:%d SP:%d ST:%d = %.1f", score_comps.importance,
                score_comps.level_boost, score_comps.user_boost, score_comps.science_priority or 0,
                score_comps.strategy_boost or 0, score_comps.total),
            style = "lil_einstein_queue_subinfo",
            enabled = enbl,
            tooltip = {"lil_einstein-policy.score-breakdown"}
        })

        if xcur.meta.is_infinite then
            local rule = policy.get_repeat_rule(force_index, xcur.technology.name)
            local repeat_button = wf.add({
                type = "button",
                style = "lil_einstein_button",
                caption = {"lil_einstein-repeat." .. rule.mode, rule.max_level or ""},
                tags = {
                    lil_einstein_on_click = true,
                    handler = "cycle_repeat_rule",
                    technology = xcur.technology.name
                },
                tooltip = {"lil_einstein-policy.repeat-cycle"},
                enabled = enbl
            })
            repeat_button.style.left_margin = 8
            if rule.mode == "to_level" then
                wf.add({
                    type = "button",
                    style = "lil_einstein_button",
                    caption = "-",
                    tags = {
                        lil_einstein_on_click = true,
                        handler = "adjust_repeat_level",
                        technology = xcur.technology.name,
                        delta = -1
                    },
                    enabled = enbl
                })
                wf.add({
                    type = "button",
                    style = "lil_einstein_button",
                    caption = "+",
                    tags = {
                        lil_einstein_on_click = true,
                        handler = "adjust_repeat_level",
                        technology = xcur.technology.name,
                        delta = 1
                    },
                    enabled = enbl
                })
            end
        end
    end

end

local get_buttons = function(techtbl, xcur, enbl)
    -- Flow for reorder buttons
    local fo = techtbl.add({
        type = "flow",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_padded",
        enabled = enbl
    })
    fo.style.width = 70
    fo.style.horizontal_align = "center"
    local f1 = fo.add({
        type = "flow",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing",
        enabled = enbl
    })
    f1.style.width = 35
    f1.style.height = 52
    local up_btn = f1.add({
        type = "sprite-button",
        style = "lil_einstein_row_arrow_button",
        sprite = "lil_einstein_mockup_row_arrow_up",
        hovered_sprite = "lil_einstein_mockup_row_arrow_up",
        clicked_sprite = "lil_einstein_mockup_row_arrow_up",
        tags = {
            lil_einstein_on_click = true,
            handler = "move_tech_up",
            technology = xcur.technology.name
        },
        enabled = enbl
    })
    up_btn.style.width = 35
    up_btn.style.height = 26
    local down_btn = f1.add({
        type = "sprite-button",
        style = "lil_einstein_row_arrow_button",
        sprite = "lil_einstein_mockup_row_arrow_down",
        hovered_sprite = "lil_einstein_mockup_row_arrow_down",
        clicked_sprite = "lil_einstein_mockup_row_arrow_down",
        tags = {
            lil_einstein_on_click = true,
            handler = "move_tech_down",
            technology = xcur.technology.name
        },
        enabled = enbl
    })
    down_btn.style.width = 33
    down_btn.style.height = 26

end

local render_technology_row = function(techtbl, entry, enabled, player_index, force_index)
    local row = techtbl.add({
        type = "frame",
        direction = "horizontal",
        style = "lil_einstein_available_row_frame",
        enabled = enabled
    })
    row.style.width = 650
    get_tech_icon(row, entry.xcur, enabled, player_index)
    get_title(row, entry.xcur, enabled, player_index, force_index, entry.score)
    get_buttons(row, entry.xcur, enabled)
end

gctech.populate = function(player_index, anchor)
    local p = game.get_player(player_index)
    local f = p.force
    local techtbl = gutil.get_child(anchor, "available_technology_table")
    if not techtbl then
        return
    end
    techtbl.clear()

    -- Get the state from storage or default settings
    local st = state.get_force_setting(f.index, "master_enable", const.default_settings.force.master_enable)
    local enbl = true
    if st == "left" then
        enbl = false
    end

    -- Build custom order if none exists
    local order = queue.get_tech_order(f.index)
    if not order then
        order = queue.build_tech_order(f.index)
    end

    local tsx = tech.get_all_tech_state_ext(f.index)
    if not tsx then
        return
    end

    -- Get filtered tech set from analyzer (respects Hide by characteristic, Filter by category, Allowed sciences)
    local filtered = analyzer.get_filtered_technologies_player(player_index)
    local allowed = {}
    for _, xcur in ipairs(filtered) do
        allowed[xcur.technology.name] = true
    end
    filtered_allowed_cache[player_index] = allowed

    -- Compute average cost of all unresearched enabled techs for level boost display
    local total_cost_sum = 0
    local cost_count = 0
    for _, tech_name in ipairs(order) do
        local xcur = tsx[tech_name]
        if xcur and not xcur.technology.researched and allowed[xcur.technology.name] then
            if xcur and xcur.technology.name ~= tech_name then
                logger.debug(nil, "key mismatch: order=" .. tostring(tech_name) .. " name=" .. tostring(xcur.technology.name))
            end
            local cost = xcur.technology.research_unit_count or 1
            total_cost_sum = total_cost_sum + cost
            cost_count = cost_count + 1
        end
    end
    local avg_cost = cost_count > 0 and (total_cost_sum / cost_count) or nil

    -- Collect all techs with their scores
    local scored_techs = {}
    for i, tech_name in ipairs(order) do
        local xcur = tsx[tech_name]
        if xcur and not xcur.technology.researched and allowed[xcur.technology.name] then
            if xcur.technology.name ~= tech_name then
                logger.debug(nil, "key mismatch: order=" .. tostring(tech_name) .. " name=" .. tostring(xcur.technology.name))
            end
            local ub = queue.get_tech_ub(f.index, xcur.technology.name)
            local sd = queue.score_tech_detailed(xcur, xcur.technology.level, ub, avg_cost, f.index)
            table.insert(scored_techs, {
                tech_name = tech_name,
                xcur = xcur,
                score = sd
            })
        end
    end

    -- Sort by total score descending (highest priority first)
    table.sort(scored_techs, function(a, b)
        return a.score.total > b.score.total
    end)

    -- Render sorted list with score breakdown
    for _, entry in ipairs(scored_techs) do
        render_technology_row(techtbl, entry, enbl, player_index, f.index)
    end
end

gctech.request_populate = function(player_index, anchor)
    local p = game.get_player(player_index)
    local techtbl = anchor and gutil.get_child(anchor, "available_technology_table")
    if not p or not techtbl then
        populate_jobs[player_index] = nil
        return true
    end

    local force_index = p.force.index
    local order = queue.get_tech_order(force_index)
    if not order then
        order = queue.build_tech_order(force_index)
    end
    local tsx = tech.get_all_tech_state_ext(force_index)
    if not tsx then
        populate_jobs[player_index] = nil
        return true
    end

    local allowed = filtered_allowed_cache[player_index]
    if not allowed then
        allowed = {}
        for _, xcur in ipairs(analyzer.get_filtered_technologies_player(player_index)) do
            allowed[xcur.technology.name] = true
        end
        filtered_allowed_cache[player_index] = allowed
    end
    local master_state = state.get_force_setting(
        force_index,
        "master_enable",
        const.default_settings.force.master_enable
    )
    techtbl.clear()
    populate_jobs[player_index] = {
        anchor = anchor,
        table = techtbl,
        force_index = force_index,
        order = order,
        tech_states = tsx,
        allowed = allowed,
        enabled = master_state ~= "left",
        phase = "average",
        next_index = 1,
        total_cost = 0,
        cost_count = 0,
        scored = {}
    }
    return false
end

gctech.tick_populate = function(player_index, anchor, budget)
    local job = populate_jobs[player_index]
    if not job then
        return true
    end
    if not anchor or not anchor.valid or job.anchor ~= anchor or not job.table.valid then
        populate_jobs[player_index] = nil
        return true
    end

    if job.phase == "average" then
        for _ = 1, 32 do
            local technology_name = job.order[job.next_index]
            if not technology_name then
                job.average_cost = job.cost_count > 0 and (job.total_cost / job.cost_count) or nil
                job.next_index = 1
                job.phase = "score"
                break
            end
            job.next_index = job.next_index + 1
            local xcur = job.tech_states[technology_name]
            if xcur and not xcur.technology.researched and job.allowed[xcur.technology.name] then
                if xcur.technology.name ~= technology_name then
                    logger.debug(
                        nil,
                        "key mismatch: order=" .. tostring(technology_name) ..
                            " name=" .. tostring(xcur.technology.name)
                    )
                end
                job.total_cost = job.total_cost + (xcur.technology.research_unit_count or 1)
                job.cost_count = job.cost_count + 1
            end
        end
        return false
    end

    if job.phase == "score" then
        for _ = 1, 8 do
            local technology_name = job.order[job.next_index]
            if not technology_name then
                job.phase = "sort"
                break
            end
            job.next_index = job.next_index + 1
            local xcur = job.tech_states[technology_name]
            if xcur and not xcur.technology.researched and job.allowed[xcur.technology.name] then
                if xcur.technology.name ~= technology_name then
                    logger.debug(
                        nil,
                        "key mismatch: order=" .. tostring(technology_name) ..
                            " name=" .. tostring(xcur.technology.name)
                    )
                end
                local user_boost = queue.get_tech_ub(job.force_index, xcur.technology.name)
                local score = queue.score_tech_detailed(
                    xcur,
                    xcur.technology.level,
                    user_boost,
                    job.average_cost,
                    job.force_index
                )
                table.insert(job.scored, {
                    tech_name = technology_name,
                    xcur = xcur,
                    score = score
                })
            end
        end
        return false
    end

    if job.phase == "sort" then
        table.sort(job.scored, function(a, b)
            return a.score.total > b.score.total
        end)
        job.next_index = 1
        job.phase = "render"
        return false
    end

    local remaining = math.max(1, math.floor(tonumber(budget) or 1))
    while remaining > 0 do
        local entry = job.scored[job.next_index]
        if not entry then
            populate_jobs[player_index] = nil
            return true
        end
        remaining = remaining - 1
        job.next_index = job.next_index + 1
        render_technology_row(
            job.table,
            entry,
            job.enabled,
            player_index,
            job.force_index
        )
    end
    return false
end

gctech.clear_runtime_cache = function()
    populate_jobs = {}
    filtered_allowed_cache = {}
end

return gctech
