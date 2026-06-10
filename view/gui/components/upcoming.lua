local const = require("lib.const")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local gutil = require("view.gui.gutil")

local gcupcoming = {}

-- Cache for lightweight per-second countdown refresh
local upcoming_ui_cache = {}

local format_time = function(seconds)
    if not seconds then
        return "calculating..."
    end
    if seconds <= 0 then
        return "0s"
    end
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, mins)
    elseif mins > 0 then
        return string.format("%dm %02ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

local add_upcoming_row = function(parent, rank, entry, player_index)
    local xcur = entry.xcur
    if not xcur then
        return
    end

    local f = game.get_player(player_index).force
    local is_pinned = queue.get_pinned_tech(f.index) == entry.tech_name

    local row = parent.add({
        type = "frame",
        direction = "horizontal",
        style = "lil_einstein_upcoming_row_frame"
    })
    row.style.vertically_stretchable = false
    row.style.horizontally_stretchable = true
    row.style.width = 525
    row.style.height = 52
    -- Store original timing data for per-second refresh
    row.tags = {
        duration = entry.duration or 0,
        wait_time = entry.wait_time or 0,
        rank = rank
    }

    -- Rank label (shows pin indicator when pinned)
    local rank_lbl = row.add({
        type = "label",
        style = "lil_einstein_queue_index_label",
        caption = (is_pinned and "▸" or "") .. rank .. "."
    })
    rank_lbl.style.width = 34
    rank_lbl.style.vertical_align = "center"
    rank_lbl.style.font = "heading-2"

    -- Tech icon: click to pin/unpin
    local tech_btn = row.add({
        type = "sprite-button",
        name = entry.tech_name,
        style = "lil_einstein_tech_btn_available",
        sprite = "technology/" .. entry.tech_name,
        tags = {
            lil_einstein_on_click = true,
            handler = "pin_upcoming_tech",
            technology = entry.tech_name
        },
        tooltip = (is_pinned and "Pinned — click to unpin" or "Click to pin to top priority")
    })

    tech_btn.style.width = 52
    tech_btn.style.height = 52

    -- Name + sciences column (use localised_name directly for proper translation)
    local level_suffix = entry.level > 1 and (" " .. entry.level) or ""
    local infinite_suffix = xcur.meta.is_infinite and " (infinite)" or ""
    local col = row.add({
        type = "flow",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing"
    })
    col.style.vertical_align = "center"
    col.style.left_margin = 4
    col.style.horizontally_stretchable = true
    col.style.width = 326

    local nl = col.add({
        type = "label",
        caption = {"", xcur.technology.localised_name, level_suffix .. infinite_suffix},
        tooltip = gutil.get_tooltip_text(xcur, player_index, entry.level, entry.cost),
        tags = {
            lil_einstein_on_click = true,
            handler = "show_technology_screen"
        },
        name = entry.tech_name
    })
    nl.style.maximal_width = 318

    local sci_flow = col.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_nospacing",
        direction = "horizontal"
    })
    for _, sci in pairs(xcur.meta.sciences or {}) do
        sci_flow.add({
            type = "sprite",
            sprite = "item/" .. sci,
            tooltip = {"item-name." .. sci}
        }).style.size = 16
    end

    -- Time estimates (right side)
    local time_col = row.add({
        type = "flow",
        name = "upcoming_time_col",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing"
    })
    time_col.style.vertical_align = "center"
    time_col.style.left_margin = 6
    time_col.style.width = 68

    time_col.add({
        type = "label",
        style = "lil_einstein_queue_subinfo",
        caption = format_time(entry.duration)
    })
    if rank > 1 then
        time_col.add({
            type = "label",
            style = "lil_einstein_queue_subinfo",
            caption = "in " .. format_time(entry.wait_time)
        })
    end

    row.add({
        type = "sprite",
        style = "lil_einstein_drag_handle",
        sprite = "lil_einstein_mockup_drag_handle",
        ignored_by_interaction = true
    })
end

gcupcoming.populate = function(player_index, anchor)
    local player = game.get_player(player_index)
    if not player then
        return
    end
    local f = player.force

    local flow = gutil.get_child(anchor, "flow_upcoming")
    if not flow then
        return
    end
    flow.clear()

    local upcoming = queue.get_upcoming_research(f.index, 15)
    if not upcoming or #upcoming == 0 then
        flow.add({
            type = "label",
            caption = "No upcoming research available"
        })
        return
    end

    upcoming_ui_cache[player_index] = {
        tick = game.tick,
        data = upcoming
    }

    for i, entry in pairs(upcoming) do
        add_upcoming_row(flow, i, entry, player_index)
    end
end

-- Lightweight refresh: only updates countdown labels, does not re-fetch queue
gcupcoming.refresh_times = function(player_index, anchor)
    local cache = upcoming_ui_cache[player_index]
    if not cache or not cache.data then
        return
    end

    local flow = gutil.get_child(anchor, "flow_upcoming")
    if not flow then
        return
    end

    local elapsed = (game.tick - cache.tick) / 60

    for _, row in pairs(flow.children) do
        if row.valid and row.tags and row.tags.rank then
            local dur = math.max(0, (row.tags.duration or 0) - elapsed)
            local wait = math.max(0, (row.tags.wait_time or 0) - elapsed)
            -- For rows after rank 1, wait_time decreases but duration stays the same
            -- since those researches haven't started yet
            if row.tags.rank == 1 then
                dur = math.max(0, (row.tags.duration or 0) - elapsed)
            else
                dur = row.tags.duration or 0
            end

            local time_col = row["upcoming_time_col"] or row.children[#row.children - 1]
            if time_col and time_col.valid then
                local dur_lbl = time_col.children[1]
                local wait_lbl = time_col.children[2]
                if dur_lbl and dur_lbl.valid then
                    dur_lbl.caption = format_time(dur)
                end
                if wait_lbl and wait_lbl.valid then
                    wait_lbl.caption = "in " .. format_time(wait)
                end
            end
        end
    end
end

return gcupcoming
