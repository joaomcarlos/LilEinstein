local const = require("lib.const")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local gutil = require("view.gui.gutil")

local gcupcoming = {}

-- Cache for lightweight per-second countdown refresh
local upcoming_ui_cache = {}
local upcoming_row_width = 525
local upcoming_row_height = 60
local upcoming_rank_width = 37
local upcoming_icon_gap = 8
local upcoming_icon_size = 60
local upcoming_icon_progress_left_margin = 4
local upcoming_icon_progress_top_margin = -16
local upcoming_icon_progress_width = 52
local upcoming_icon_progress_height = 14
local upcoming_name_width = 300
local upcoming_science_icon_size = 14
local upcoming_time_width = 68

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

local get_current_progress = function(player, tech_name)
    if not player or not player.force or not player.force.current_research then
        return 0
    end
    if player.force.current_research.name ~= tech_name then
        return 0
    end
    return math.max(0, math.min(1, player.force.research_progress or 0))
end

local set_icon_progress = function(progress_bar, progress)
    if not progress_bar or not progress_bar.valid then
        return
    end

    progress = math.max(0, math.min(1, progress or 0))
    local width = math.floor((upcoming_icon_progress_width * progress) + 0.5)
    if width <= 0 then
        progress_bar.visible = false
        progress_bar.style.width = 1
        return
    end

    progress_bar.value = 1
    progress_bar.visible = true
    progress_bar.style.width = width
    progress_bar.style.height = upcoming_icon_progress_height
    progress_bar.style.bar_width = upcoming_icon_progress_height
end

local add_upcoming_row = function(parent, rank, entry, player_index)
    local xcur = entry.xcur
    if not xcur then
        return
    end

    local player = game.get_player(player_index)
    if not player then
        return
    end

    local is_pinned = queue.get_pinned_tech(player.force.index) == entry.tech_name
    local tech_tooltip = gutil.get_tooltip_text(xcur, player_index, entry.level, entry.cost)

    local row = parent.add({
        type = "frame",
        direction = "horizontal",
        style = "lil_einstein_upcoming_row_frame"
    })
    row.style.vertically_stretchable = false
    row.style.horizontally_stretchable = true
    row.style.width = upcoming_row_width
    row.style.height = upcoming_row_height
    row.tags = {
        duration = entry.duration or 0,
        wait_time = entry.wait_time or 0,
        rank = rank,
        technology = entry.tech_name
    }

    local rank_lbl = row.add({
        type = "label",
        style = "lil_einstein_queue_index_label",
        caption = (is_pinned and ">" or "") .. rank .. "."
    })
    rank_lbl.style.width = upcoming_rank_width
    rank_lbl.style.vertical_align = "center"
    rank_lbl.style.horizontal_align = "right"
    rank_lbl.style.font = "heading-2"

    local icon_gap = row.add({
        type = "empty-widget"
    })
    icon_gap.style.width = upcoming_icon_gap
    icon_gap.style.height = upcoming_row_height

    local icon_stack = row.add({
        type = "flow",
        name = "upcoming_icon_stack",
        direction = "vertical",
        style = "lil_einstein_upcoming_icon_stack"
    })
    icon_stack.style.width = upcoming_icon_size
    icon_stack.style.height = upcoming_icon_size

    local tech_btn = icon_stack.add({
        type = "sprite-button",
        name = entry.tech_name,
        style = "lil_einstein_tech_btn_available",
        sprite = "technology/" .. entry.tech_name,
        tags = {
            lil_einstein_on_click = true,
            handler = "pin_upcoming_tech",
            technology = entry.tech_name
        },
        tooltip = (is_pinned and "Pinned - click to unpin" or "Click to pin to top priority")
    })
    tech_btn.style.width = upcoming_icon_size
    tech_btn.style.height = upcoming_icon_size

    local progress_bar = icon_stack.add({
        type = "progressbar",
        name = "upcoming_icon_progress",
        value = 1,
        style = "lil_einstein_upcoming_icon_progress_bar",
        ignored_by_interaction = true
    })
    progress_bar.style.left_margin = upcoming_icon_progress_left_margin
    progress_bar.style.top_margin = upcoming_icon_progress_top_margin
    set_icon_progress(progress_bar, get_current_progress(player, entry.tech_name))

    local level_suffix = entry.level > 1 and (" " .. entry.level) or ""
    local infinite_suffix = xcur.meta.is_infinite and " (infinite)" or ""
    local col = row.add({
        type = "flow",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing"
    })
    col.style.left_margin = 4
    col.style.horizontally_stretchable = true
    col.style.width = upcoming_name_width

    local title_lbl = col.add({
        type = "label",
        caption = {"", xcur.technology.localised_name, level_suffix .. infinite_suffix},
        tooltip = tech_tooltip,
        tags = {
            lil_einstein_on_click = true,
            handler = "show_technology_screen"
        },
        name = entry.tech_name
    })
    title_lbl.style.maximal_width = upcoming_name_width - 8
    title_lbl.style.top_margin = 3

    local sci_flow = col.add({
        type = "flow",
        style = "lil_einstein_horizontal_flow_nospacing",
        direction = "horizontal"
    })
    sci_flow.style.height = upcoming_science_icon_size
    local first = true
    for _, sci in pairs(xcur.meta.sciences or {}) do
        local sci_icon = sci_flow.add({
            type = "sprite",
            sprite = "item/" .. sci,
            tooltip = {"item-name." .. sci}
        })
        sci_icon.style.size = upcoming_science_icon_size
        if not first then
            sci_icon.style.left_margin = -2
        end
        first = false
    end

    local time_col = row.add({
        type = "flow",
        name = "upcoming_time_col",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing"
    })
    time_col.style.left_margin = 6
    time_col.style.width = upcoming_time_width
    time_col.style.top_margin = 8

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

    local drag_handle = row.add({
        type = "sprite",
        style = "lil_einstein_drag_handle",
        sprite = "lil_einstein_mockup_drag_handle",
        ignored_by_interaction = true
    })
end

local add_separator = function(parent)
    local separator = parent.add({
        type = "sprite",
        sprite = "lil_einstein_mockup_upcoming_row_separator",
        ignored_by_interaction = true
    })
    separator.style.width = upcoming_row_width
    separator.style.height = 4
    separator.style.stretch_image_to_widget_size = true
end

gcupcoming.refresh_progress = function(player_index, anchor)
    local player = game.get_player(player_index)
    if not player then
        return
    end

    local flow = gutil.get_child(anchor, "flow_upcoming")
    if not flow then
        return
    end

    for _, row in ipairs(flow.children) do
        if row.valid and row.tags and row.tags.technology then
            local progress_bar = gutil.get_child(row, "upcoming_icon_progress")
            set_icon_progress(progress_bar, get_current_progress(player, row.tags.technology))
        end
    end
end

gcupcoming.populate = function(player_index, anchor)
    local player = game.get_player(player_index)
    if not player then
        return
    end

    local flow = gutil.get_child(anchor, "flow_upcoming")
    if not flow then
        return
    end
    flow.clear()

    local upcoming = queue.get_upcoming_research(player.force.index, 15)
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

    for i, entry in ipairs(upcoming) do
        add_upcoming_row(flow, i, entry, player_index)
        if i < #upcoming then
            add_separator(flow)
        end
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

    for _, row in ipairs(flow.children) do
        if row.valid and row.tags and row.tags.rank then
            local dur = math.max(0, (row.tags.duration or 0) - elapsed)
            local wait = math.max(0, (row.tags.wait_time or 0) - elapsed)
            if row.tags.rank ~= 1 then
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
