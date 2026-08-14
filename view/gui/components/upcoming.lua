local const = require("lib.const")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local gutil = require("view.gui.gutil")

local gcupcoming = {}

-- Cache for lightweight per-second countdown refresh
local upcoming_ui_cache = {}
local upcoming_render_jobs = {}
local upcoming_row_width = 525
local upcoming_row_height = 74
local upcoming_rank_width = 49
local upcoming_rank_arrow_width = 9
local upcoming_rank_number_width = 31
local upcoming_icon_gap = 8
local upcoming_icon_size = 74
local upcoming_icon_progress_height = 4
local upcoming_name_width = 272
local upcoming_science_icon_size = 14
local upcoming_time_width = 68
local upcoming_content_bottom_margin = 22

local localize_with_fallback = function(key, fallback, ...)
    return {"?", {key, ...}, fallback}
end

local format_time = function(seconds)
    if not seconds then
        return localize_with_fallback("lil_einstein-upcoming.calculating", "calculating...")
    end
    if seconds <= 0 then
        return localize_with_fallback("lil_einstein-upcoming.seconds", "0s", 0)
    end
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    if hours > 0 then
        return localize_with_fallback(
            "lil_einstein-upcoming.hours-minutes",
            string.format("%dh %02dm", hours, mins),
            hours,
            string.format("%02d", mins)
        )
    elseif mins > 0 then
        return localize_with_fallback(
            "lil_einstein-upcoming.minutes-seconds",
            string.format("%dm %02ds", mins, secs),
            mins,
            string.format("%02d", secs)
        )
    else
        return localize_with_fallback(
            "lil_einstein-upcoming.seconds",
            string.format("%ds", secs),
            secs
        )
    end
end

local format_wait_time = function(seconds)
    local time = format_time(seconds)
    return localize_with_fallback(
        "lil_einstein-upcoming.in-time",
        {"", "in ", time},
        time
    )
end

local get_availability_tooltip = function(entry)
    if entry.availability_reason == "science_not_together" then
        return localize_with_fallback(
            "lil_einstein-upcoming.science-not-together-tooltip",
            "Not selected: the required science packs are not available together to one compatible lab cluster."
        )
    end
    if entry.availability_reason ~= "missing_science" then
        return nil
    end

    local tooltip = {"", localize_with_fallback(
        "lil_einstein-upcoming.missing-science-tooltip",
        "Not selected: required science packs are unavailable:"
    )}
    for _, science in ipairs(entry.missing_sciences or {}) do
        table.insert(tooltip, " [item=" .. science .. "]")
    end
    return tooltip
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
    if not progress_bar.visible then
        progress_bar.visible = true
    end
    if progress_bar.value ~= progress then
        progress_bar.value = progress
    end
end

local set_progress_text = function(progress_label, progress, is_current)
    if not progress_label or not progress_label.valid then
        return
    end

    progress = math.max(0, math.min(1, progress or 0))
    local visible = is_current or progress > 0
    local caption = string.format("%.2f%%", progress * 100)
    if progress_label.visible ~= visible then
        progress_label.visible = visible
    end
    if progress_label.caption ~= caption then
        progress_label.caption = caption
    end
end

local set_rank_arrows = function(row, is_current, is_pinned)
    if not row or not row.valid then
        return
    end

    local current_arrow = gutil.get_child(row, "upcoming_current_arrow")
    if current_arrow and current_arrow.valid then
        local caption = is_current and ">" or ""
        if current_arrow.caption ~= caption then
            current_arrow.caption = caption
        end
    end

    local pinned_arrow = gutil.get_child(row, "upcoming_pinned_arrow")
    if pinned_arrow and pinned_arrow.valid then
        local caption = is_pinned and ">" or ""
        if pinned_arrow.caption ~= caption then
            pinned_arrow.caption = caption
        end
    end
end

local get_structure_key = function(entry)
    return table.concat({
        entry.tech_name or "",
        tostring(entry.level or ""),
        entry.availability_reason or "",
        table.concat(entry.missing_sciences or {}, ",")
    }, "|")
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
        technology = entry.tech_name,
        structure_key = get_structure_key(entry)
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
        tooltip = localize_with_fallback(
            "lil_einstein-upcoming.currently-researching",
            "Currently researching"
        )
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
        tooltip = localize_with_fallback("lil_einstein-upcoming.high-priority", "High priority")
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
        tooltip = is_pinned and localize_with_fallback(
            "lil_einstein-upcoming.clear-high-priority",
            "High priority - click to clear"
        ) or localize_with_fallback(
            "lil_einstein-upcoming.mark-high-priority",
            "Click to mark high priority"
        )
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
    progress_bar.style.width = upcoming_icon_size
    progress_bar.style.height = upcoming_icon_progress_height
    progress_bar.style.bar_width = upcoming_icon_size

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
    if entry.availability_reason then
        local status_key = entry.availability_reason == "science_not_together" and
            "science-not-together" or "missing-science"
        local status_label = sci_flow.add({
            type = "label",
            style = "lil_einstein_queue_subinfo",
            caption = localize_with_fallback(
                "lil_einstein-upcoming." .. status_key,
                status_key == "science-not-together" and "Packs not together" or "Missing packs"
            ),
            tooltip = get_availability_tooltip(entry)
        })
        status_label.style.left_margin = 5
        status_label.style.font_color = {r = 1.0, g = 0.64, b = 0.2}
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
            caption = format_wait_time(entry.wait_time)
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

local get_rendered_rows = function(flow)
    local rows = {}
    for _, child in ipairs(flow.children) do
        if child.valid and child.tags and child.tags.technology then
            table.insert(rows, child)
        end
    end
    return rows
end

local structure_matches = function(flow, upcoming)
    local rows = get_rendered_rows(flow)
    if #rows ~= #upcoming then
        return false, rows
    end
    for index, entry in ipairs(upcoming) do
        if rows[index].tags.structure_key ~= get_structure_key(entry) then
            return false, rows
        end
    end
    return true, rows
end

local update_existing_rows = function(rows, upcoming)
    for index, entry in ipairs(upcoming) do
        rows[index].tags = {
            duration = entry.duration or 0,
            wait_time = entry.wait_time or 0,
            duration_known = entry.duration ~= nil,
            wait_time_known = entry.wait_time ~= nil,
            rank = index,
            technology = entry.tech_name,
            structure_key = get_structure_key(entry)
        }
    end
end

local render_upcoming = function(flow, upcoming, player_index)
    flow.clear()
    if #upcoming == 0 then
        flow.add({
            type = "label",
            caption = localize_with_fallback(
                "lil_einstein-upcoming.none-available",
                "No upcoming research available"
            )
        })
        return
    end
    for index, entry in ipairs(upcoming) do
        add_upcoming_row(flow, index, entry, player_index)
        if index < #upcoming then
            add_separator(flow)
        end
    end
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

    local pinned_tech = queue.get_pinned_tech(player.force.index)
    local current_research = player.force.current_research
    local current_tech = current_research and current_research.name
    for _, row in ipairs(flow.children) do
        if row.valid and row.tags and row.tags.technology then
            local is_pinned = pinned_tech == row.tags.technology
            local is_current = current_tech == row.tags.technology
            local progress = get_research_progress(player, row.tags.technology)
            local progress_bar = gutil.get_child(row, "upcoming_icon_progress")
            local progress_label = gutil.get_child(row, "upcoming_progress_label")
            set_icon_progress(progress_bar, progress)
            set_progress_text(progress_label, progress, is_current)
            set_rank_arrows(row, is_current, is_pinned)
        end
    end
end

gcupcoming.request_populate = function(player_index, anchor)
    local player = game.get_player(player_index)
    if not player then
        return false
    end

    local flow = gutil.get_child(anchor, "flow_upcoming")
    if not flow then
        return false
    end
    queue.request_upcoming_research_display(player.force.index, 15)
    upcoming_render_jobs[player_index] = {
        anchor = anchor,
        flow = flow,
        force_index = player.force.index
    }
    return false
end

gcupcoming.tick_populate = function(player_index, anchor)
    local job = upcoming_render_jobs[player_index]
    if not job then
        return true
    end
    if not job.anchor.valid or job.anchor ~= anchor or not job.flow.valid then
        upcoming_render_jobs[player_index] = nil
        return true
    end
    local complete, upcoming = queue.tick_upcoming_research_display(job.force_index, 1)
    if not complete then
        return false
    end
    upcoming = upcoming or {}
    upcoming_ui_cache[player_index] = {
        tick = game.tick,
        data = upcoming
    }
    local matches, rows = structure_matches(job.flow, upcoming)
    if matches then
        update_existing_rows(rows, upcoming)
    else
        render_upcoming(job.flow, upcoming, player_index)
    end
    upcoming_render_jobs[player_index] = nil
    return true
end

gcupcoming.populate = function(player_index, anchor)
    upcoming_render_jobs[player_index] = nil
    local player = game.get_player(player_index)
    if not player then
        return
    end

    local flow = gutil.get_child(anchor, "flow_upcoming")
    if not flow then
        return
    end
    -- Direct player actions run inside the current event and cannot wait for a
    -- background snapshot or a later on_tick. Keep this path synchronous while
    -- automatic rebuilds use request_populate/tick_populate.
    local upcoming = queue.get_upcoming_research_display(player.force.index, 15) or {}

    upcoming_ui_cache[player_index] = {
        tick = game.tick,
        data = upcoming
    }
    render_upcoming(flow, upcoming, player_index)
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
                    wait_lbl.caption = format_wait_time(wait)
                end
            end
        end
    end
end

gcupcoming.clear_runtime_cache = function()
    upcoming_ui_cache = {}
    upcoming_render_jobs = {}
end

return gcupcoming
