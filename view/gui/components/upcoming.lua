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
local upcoming_rank_width = 49
local upcoming_rank_arrow_width = 9
local upcoming_rank_number_width = 31
local upcoming_icon_gap = 8
local upcoming_icon_size = 60
local upcoming_icon_progress_height = 4
local upcoming_name_width = 288
local upcoming_science_icon_size = 14
local upcoming_time_width = 68
local upcoming_content_bottom_margin = 8

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

local get_research_progress = function(player, tech_name)
    if not player or not player.valid or not player.force then
        return 0
    end

    local f = player.force
    if f.current_research and f.current_research.name == tech_name then
        return math.max(0, math.min(1, f.research_progress or 0))
    end

    local t = f.technologies[tech_name]
    if not t or not t.valid then
        return 0
    end
    return math.max(0, math.min(1, t.saved_progress or 0))
end

local set_icon_progress = function(progress_bar, progress)
    if not progress_bar or not progress_bar.valid then
        return
    end

    progress = math.max(0, math.min(1, progress or 0))
    progress_bar.visible = true
    progress_bar.value = progress
    progress_bar.style.width = upcoming_icon_size
    progress_bar.style.height = upcoming_icon_progress_height
    progress_bar.style.bar_width = upcoming_icon_progress_height
end

local set_progress_text = function(progress_label, progress, is_current)
    if not progress_label or not progress_label.valid then
        return
    end

    progress = math.max(0, math.min(1, progress or 0))
    progress_label.visible = is_current or progress > 0
    progress_label.caption = string.format("%.2f%%", progress * 100)
end

local set_rank_arrows = function(row, is_current, is_pinned)
    if not row or not row.valid then
        return
    end

    local current_arrow = gutil.get_child(row, "upcoming_current_arrow")
    if current_arrow and current_arrow.valid then
        current_arrow.caption = is_current and ">" or ""
    end

    local pinned_arrow = gutil.get_child(row, "upcoming_pinned_arrow")
    if pinned_arrow and pinned_arrow.valid then
        pinned_arrow.caption = is_pinned and ">" or ""
    end
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
    local is_current = player.force.current_research and player.force.current_research.name == entry.tech_name
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
        duration_known = entry.duration ~= nil,
        wait_time_known = entry.wait_time ~= nil,
        rank = rank,
        technology = entry.tech_name
    }

    local rank_flow = row.add({
        type = "flow",
        name = "upcoming_rank_flow",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_nospacing"
    })
    rank_flow.style.width = upcoming_rank_width
    rank_flow.style.height = upcoming_row_height
    rank_flow.style.vertical_align = "center"

    local current_arrow = rank_flow.add({
        type = "label",
        name = "upcoming_current_arrow",
        caption = is_current and ">" or "",
        tooltip = "Currently researching"
    })
    current_arrow.style.width = upcoming_rank_arrow_width
    current_arrow.style.vertical_align = "center"
    current_arrow.style.horizontal_align = "center"
    current_arrow.style.font = "heading-2"
    current_arrow.style.font_color = {r = 0.18, g = 1.0, b = 0.24}

    local pinned_arrow = rank_flow.add({
        type = "label",
        name = "upcoming_pinned_arrow",
        caption = is_pinned and ">" or "",
        tooltip = "High priority"
    })
    pinned_arrow.style.width = upcoming_rank_arrow_width
    pinned_arrow.style.vertical_align = "center"
    pinned_arrow.style.horizontal_align = "center"
    pinned_arrow.style.font = "heading-2"
    pinned_arrow.style.font_color = {r = 1.0, g = 0.18, b = 0.12}

    local rank_lbl = rank_flow.add({
        type = "label",
        style = "lil_einstein_queue_index_label",
        caption = rank .. "."
    })
    rank_lbl.style.width = upcoming_rank_number_width
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
        style = "lil_einstein_upcoming_tech_icon_button",
        sprite = "technology/" .. entry.tech_name,
        tags = {
            lil_einstein_on_click = true,
            handler = "pin_upcoming_tech",
            technology = entry.tech_name
        },
        tooltip = (is_pinned and "High priority - click to clear" or "Click to mark high priority")
    })
    tech_btn.style.width = upcoming_icon_size
    tech_btn.style.height = upcoming_icon_size

    -- Draw the progress last so its highlighted strip sits over the icon's bottom border.
    local progress_bar = icon_stack.add({
        type = "progressbar",
        name = "upcoming_icon_progress",
        value = 0,
        style = "lil_einstein_upcoming_icon_progress_bar",
        ignored_by_interaction = true
    })
    progress_bar.style.top_margin = -upcoming_icon_progress_height

    local progress = get_research_progress(player, entry.tech_name)
    set_icon_progress(progress_bar, progress)

    local level_suffix = entry.level > 1 and (" " .. entry.level) or ""
    local infinite_suffix = xcur.meta.is_infinite and " (infinite)" or ""
    local col = row.add({
        type = "flow",
        direction = "vertical",
        style = "lil_einstein_vertical_flow_nospacing"
    })
    col.style.left_margin = 4
    col.style.bottom_margin = upcoming_content_bottom_margin
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
    time_col.style.height = upcoming_row_height
    time_col.style.top_padding = rank > 1 and 3 or 12

    local progress_label = time_col.add({
        type = "label",
        name = "upcoming_progress_label",
        style = "lil_einstein_queue_subinfo"
    })
    set_progress_text(progress_label, progress, is_current)

    time_col.add({
        type = "label",
        name = "upcoming_duration_label",
        style = "lil_einstein_queue_subinfo",
        caption = format_time(entry.duration)
    })
    if rank > 1 then
        time_col.add({
            type = "label",
            name = "upcoming_wait_label",
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
            local is_pinned = queue.get_pinned_tech(player.force.index) == row.tags.technology
            local is_current = player.force.current_research and player.force.current_research.name == row.tags.technology
            local progress = get_research_progress(player, row.tags.technology)
            local progress_bar = gutil.get_child(row, "upcoming_icon_progress")
            local progress_label = gutil.get_child(row, "upcoming_progress_label")
            set_icon_progress(progress_bar, progress)
            set_progress_text(progress_label, progress, is_current)
            set_rank_arrows(row, is_current, is_pinned)
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
            local dur
            local wait
            if row.tags.duration_known then
                dur = math.max(0, (row.tags.duration or 0) - elapsed)
                if row.tags.rank ~= 1 then
                    dur = row.tags.duration or 0
                end
            end
            if row.tags.wait_time_known then
                wait = math.max(0, (row.tags.wait_time or 0) - elapsed)
            end

            local time_col = gutil.get_child(row, "upcoming_time_col")
            if time_col and time_col.valid then
                local dur_lbl = time_col["upcoming_duration_label"]
                local wait_lbl = time_col["upcoming_wait_label"]
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
