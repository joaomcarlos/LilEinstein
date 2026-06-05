local const = require("lib.const")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local analyzer = require("view.gui.analyzer")

local gutil = require("view.gui.gutil")

local gcqueue = {}

-- Prio listbox
local add_prio = function(tblq, meta, i)
    local fl = tblq.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_padded"
    })
    fl.add({
        type = "label",
        style = "lil_einstein_queue_index_label",
        caption = i,
        name = meta.tech_name .. "_textfield",
        lose_focus_on_confirm = true
    })
    fl.style.width = 45
end

-- Move up/down buttons
local add_buttons = function(tblq, meta, i, queue)
    local fl = tblq.add({
        type = "flow",
        direction = "vertical"
    })
    local enbl, ign
    if i == 1 then
        enbl = false
        ign = true
    else
        enbl = nil
        ign = nil
    end
    fl.add({
        type = "sprite-button",
        style = "lil_einstein_icon_button",
        sprite = "lil_einstein_arrow_up_small",
        hovered_sprite = "lil_einstein_arrow_up_small_black",
        clicked_sprite = "lil_einstein_arrow_up_small_black",
        enabled = enbl,
        tags = {
            lil_einstein_on_click = true,
            handler = "promote_research",
            tech_name = meta.tech_name,
            ignore_force_enable = ign
        },
        tooltip = {"lil_einstein-gui.promote_tooltip"}
    })
    if i == #queue then
        enbl = false
        ign = true
    else
        enbl = nil
        ign = nil
    end
    fl.add({
        type = "sprite-button",
        style = "lil_einstein_icon_button",
        sprite = "lil_einstein_arrow_down_small",
        hovered_sprite = "lil_einstein_arrow_down_small_black",
        clicked_sprite = "lil_einstein_arrow_down_small_black",
        enabled = enbl,
        tags = {
            lil_einstein_on_click = true,
            handler = "demote_research",
            tech_name = meta.tech_name,
            ignore_force_enable = ign
        },
        tooltip = {"lil_einstein-gui.demote_tooltip"}
    })
end

-- The status symbol
local add_status_symbol = function(tblq, meta, player_index, qns)
    -- Tech can have one of following statuses:
    -- in_(smart_)research, is_blocked/is_disabled, no_science, pending, is_inherited
    -- If a tech is inherited, we will always research it earlier in the queue despite any status
    -- If a tech is in research, it should never have status no_science/pending/is_inherited
    -- If a tech is blocked/disabled, it should never have status pending
    -- A tech can both be blocked and have it's prerequisites either in_research or no_science
    -- (for now) in this case the in_research or no_science takes priority over blocked
    -- If a tech is auto researching it means that any queued tech can't be researched anyways
    -- Thus the priority order for status symbols is as following:
    -- in_smart_research/is_inherited > in_research/no_science > is_blocked/is_disabled > pending
    local fl = tblq.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_queue_status"
    })
    fl.style.width = 60
    local spr, tt

    if meta.is_smart_researching then
        spr = "lil_einstein_progress_smart_medium"
        tt = {"lil_einstein-tt.auto_researching"}
    elseif meta.is_inherited then
        spr = "lil_einstein_inherit_medium"

        -- Find the technology that makes this tech inherited
        local inh = ""
        for _, ib in pairs(meta.inherit_by) do
            inh = inh .. (state.get_translation(player_index, "technology", ib, "localised_name") or ib) .. ", "
        end
        -- Remove the trailing comma
        if #inh > 2 then
            inh = string.sub(inh, 1, -3)
        end
        tt = {"lil_einstein-tt.inherited-by", inh}
    elseif meta.is_researching then
        spr = "lil_einstein_progress_medium"
        tt = {"lil_einstein-tt.researching"}
    elseif meta.misses_science then
        spr = "lil_einstein_no_science_medium"
        local ms = ""
        for s, _ in pairs(meta.missing_science) do
            ms = ms .. "[item=" .. s .. "] " .. (state.get_translation(player_index, "item", s, "localised_name") or s)
            if next(meta.missing_science, s) ~= nil then
                ms = ms .. "\n"
            end
        end
        tt = {"lil_einstein-tt.missing_science", ms}
    elseif meta.is_blocked then
        spr = "lil_einstein_blocked_medium"
        local bt = {""}
        for r, b in pairs(meta.blocking_reasons or {}) do
            local ttr = ""
            for k, t in pairs(b) do
                ttr = ttr .. (state.get_translation(player_index, "technology", t, "localised_name") or t)
                if next(b, k) ~= nil then
                    ttr = ttr .. ", "
                end
            end
            if next(meta.blocking_reasons, r) ~= nil then
                ttr = ttr .. "\n"
            end
            table.insert(bt, {"lil_einstein-tt.blocked_" .. r, ttr})
        end
        tt = {"lil_einstein-tt.blocked", bt}
    else
        spr = "lil_einstein_queue_medium"
    end
    fl.add({
        type = "sprite",
        sprite = spr,
        tooltip = tt
    })

end

local add_tech_badge = function(tblq, meta, player_index)

    -- TODO: Move this to separate function & re-use the logic from available tech
    -- Tech icon
    local p = game.get_player(player_index)
    local f = p.force
    local t = f.technologies[meta.tech_name]
    local xcur = tech.get_single_tech_state_ext(f.index, meta.tech_name)

    -- Container for icon + progress bar
    local container = tblq.add({
        type = "flow",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing"
    })

    container.add({
        type = "sprite-button",
        name = meta.tech_name,
        style = "lil_einstein_tech_btn_available",
        sprite = "technology/" .. meta.tech_name,
        tags = {
            lil_einstein_on_click = true,
            handler = "show_technology_screen"
        },
        tooltip = gutil.get_tooltip_text(xcur, player_index)
    })

    -- Progress bar on the queue item the mod is actively researching (includes prerequisites)
    local mod_current = queue.get_current_researching(f.index)
    if mod_current and mod_current == meta.tech_name then
        local pb = container.add({
            type = "progressbar",
            value = f.research_progress or 0,
            style = "lil_einstein_research_progress"
        })
        pb.style.width = 54
        pb.style.height = 8
        pb.style.top_margin = 2
    end

end

local add_tech_name_info = function(tblq, meta, player_index, enbl)

    -- Tech name, info & sciences (possibly)
    local p = game.get_player(player_index)
    local f = p.force
    local t = f.technologies[meta.tech_name]
    local xcur = tech.get_single_tech_state_ext(f.index, meta.tech_name)
    local name = gutil.get_tech_name(player_index, xcur)
    local n = tblq.add({
        type = "flow",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing"
    })
    n.add({
        type = "label",
        caption = name,
        tooltip = gutil.get_tooltip_text(xcur, player_index)
    })

    -- Additional info on how many (un)blocked predecessors
    local un = (#meta.new_unblocked + #meta.inherit_unblocked)
    local bl = (#meta.new_blocked + #meta.inherit_blocked)
    if un > 0 then
        local ttp = ""
        for _, u in pairs({meta.new_unblocked, meta.inherit_unblocked}) do
            for k, t in pairs(u) do
                ttp = ttp .. (state.get_translation(player_index, "technology", t, "localised_name") or t)
                if next(u, k) ~= nil then
                    ttp = ttp .. ", "
                end
            end
        end

        local tt = {"lil_einstein-tt.inherited-tech", ttp}
        local ifl = n.add({
            type = "flow",
            direction = "horizontal",
            tooltip = tt
        })
        ifl.add({
            type = "label",
            style = "lil_einstein_queue_subinfo",
            caption = {"lil_einstein-lbl.prerequisite-tech", (un)},
            tooltip = tt
        })
        ifl.add({
            type = "sprite",
            sprite = "info",
            tooltip = tt
        })
    end
    if bl > 0 then
        local ttp = ""
        for _, u in pairs({meta.new_blocked, meta.inherit_blocked}) do
            for k, t in pairs(u) do
                ttp = ttp .. (state.get_translation(player_index, "technology", t, "localised_name") or t)
                if next(u, k) ~= nil then
                    ttp = ttp .. ", "
                end
            end
        end

        local tt = {"lil_einstein-tt.blocked-tech", ttp}
        local ifl = n.add({
            type = "flow",
            direction = "horizontal",
            tooltip = tt
        })
        local lbl = {"lil_einstein-lbl.blocked-tech-only", bl}
        ifl.add({
            type = "label",
            style = "lil_einstein_queue_subinfo",
            caption = lbl,
            tooltip = tt
        })
        ifl.add({
            type = "sprite",
            sprite = "info",
            tooltip = tt
        })
    end

    if not (un > 0 and bl > 0) then
        -- Add the sciences if there is max 1 line of (un)blocked info
        local ifl = n.add({
            type = "flow",
            style = "lil_einstein_horizontal_flow_nospacing",
            direction = "horizontal",
            enabled = enbl
        })
        local first = true
        for _, sci in pairs(xcur.meta.sciences or {}) do
            local ss = ifl.add({
                type = "sprite",
                sprite = "item/" .. sci,
                tooltip = {"item-name." .. sci}
            })
            -- If there are more than 8 sciences we need to add negative left margin to compensate for each science icon
            -- if not first and #t.research_unit_ingredients > 8 then
            if not first and #xcur.meta.sciences > 8 then
                ss.style.left_margin = (28 * (#xcur.meta.sciences - 8)) / -#xcur.meta.sciences
            end
            ss.style.size = 21
            -- ss.style.vertically_stretchable = false
            -- ss.style.vertically_squashable = false
            ss.style.stretch_image_to_widget_size = true
            first = false
        end
    end

end

local add_trash_bin = function(tblq, meta)
    local fl = tblq.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_padded"
    })
    fl.add({
        type = "sprite-button",
        style = "lil_einstein_icon_button",
        sprite = "lil_einstein_bin_small",
        tags = {
            lil_einstein_on_click = true,
            handler = "remove_from_queue",
            technology = meta.tech_name
        }
    })
end
gcqueue.populate = function(player_index, anchor)
    -- Get the player
    local player = game.get_player(player_index)
    if not player then
        return
    end
    local f = player.force

    -- Get the table
    local tblq = gutil.get_child(anchor, "table_queue")
    if not tblq then
        return
    end
    tblq.clear()

    -- Get the queue
    local queue = analyzer.get_queue_meta(f.index)
    if not queue or #queue == 0 then
        tblq.add({
            type = "label",
            caption = {"lil_einstein-lbl.empty-queue"}
        })
        return
    end

    -- Iterate over the queued_count tech
    local i = 1
    for _, meta in pairs(queue) do
        add_prio(tblq, meta, i)
        add_buttons(tblq, meta, i, queue)
        add_status_symbol(tblq, meta, player_index)
        add_tech_badge(tblq, meta, player_index)
        add_tech_name_info(tblq, meta, player_index, true)
        add_trash_bin(tblq, meta)
        i = i + 1
    end
end

return gcqueue
