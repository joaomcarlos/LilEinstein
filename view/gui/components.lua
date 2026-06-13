local const = require("lib.const")
local logger = require("lib.log")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local analyzer = require("view.gui.analyzer")

local gutil = require("view.gui.gutil")
local gctech = require("view.gui.components.tech")
local gcupcoming = require("view.gui.components.upcoming")

local content = {}
local ordered_force_settings = {"requeue_infinite_tech", "auto_research"}
local research_graph_column_count = 200
local research_graph_sample_seconds = 3
local research_graph_plot_width = 456
local research_graph_plot_height = 118
local research_graph_hover_dot_height = 3
local research_graph_hover_column_setting = "research_graph_hover_column"
local research_bottle_steps = {0, 2, 5, 10, 15, 20, 30, 40, 50, 70, 80, 90, 95, 99}
local research_drip_cycle_ticks = 180
local research_drip_visible_ticks = 60
local research_drip_frame_count = 5

local get_science_tooltip = function(player_index, force_index, science, total_count)
    local item_name = state.get_translation(player_index, "item", science, "localised_name") or science
    local detail = queue.get_science_count_breakdown(force_index, science)
    local networks = {}
    for _, item in pairs(detail.networks or {}) do
        table.insert(networks, item)
    end
    table.sort(networks, function(a, b)
        if a.count == b.count then
            return a.label < b.label
        end
        return a.count > b.count
    end)

    local tt = "[font=heading-2]" .. tostring(item_name) .. "[/font]\n" ..
                   "Total: " .. gutil.format_cost(total_count or 0) .. "\n" ..
                   "In labs: " .. gutil.format_cost(detail.lab_count or 0) .. " in " ..
                   tostring(detail.lab_entity_count or 0) .. " labs\n" ..
                   "In networks: " .. gutil.format_cost(detail.network_total or 0)

    if #networks > 0 then
        tt = tt .. "\n\n"
        for i, item in ipairs(networks) do
            tt = tt .. item.label .. ": " .. gutil.format_cost(item.count or 0)
            if i < #networks then
                tt = tt .. "\n"
            end
        end
    else
        tt = tt .. "\n\nNo detected robot networks"
    end

    return tt
end

local refresh_science_counts = function(player_index, anchor)
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local force_index = p.force.index
    local science_counts = queue.get_science_counts(force_index)

    for _, science in pairs(util.get_all_sciences()) do
        local count = science_counts[science] or 0
        local btn = gutil.get_child(anchor, "allowed_science_btn_" .. science)
        if btn then
            btn.tooltip = get_science_tooltip(player_index, force_index, science, count)
        end

        local label_name = "allowed_science_count_" .. science
        local count_label = gutil.get_child(anchor, label_name)
        if count > 0 then
            local caption = gutil.format_cost(count)
            if count_label then
                count_label.caption = caption
            elseif btn and btn.parent then
                count_label = btn.parent.add({
                    type = "label",
                    name = label_name,
                    caption = caption,
                    ignored_by_interaction = true
                })
                count_label.style.width = 44
                count_label.style.horizontal_align = "center"
                count_label.style.top_margin = -6
                count_label.style.font = "default-small"
                count_label.style.font_color = {r = 1, g = 1, b = 1}
            end
        elseif count_label then
            count_label.destroy()
        end
    end
end

local format_spaced_number = function(value)
    local str = tostring(math.floor((value or 0) + 0.5))
    local res = str:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", "")
    return res
end

local format_time = function(seconds)
    if not seconds then
        return "--"
    end
    seconds = math.max(0, math.floor(seconds + 0.5))
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    if minutes > 0 then
        return tostring(minutes) .. "m" .. string.format("%02ds", secs)
    end
    return tostring(secs) .. "s"
end

local format_axis_value = function(value)
    value = math.max(0, value or 0)
    if value <= 0 then
        return "0"
    end
    if value < 1000 then
        return tostring(math.floor(value + 0.5))
    end
    if value < 1000000 then
        return tostring(math.floor((value / 1000) + 0.5)) .. "k"
    end
    local label = gutil.format_cost(math.floor((value / 1000) + 0.5) * 1000)
    return label:gsub("K", "k")
end

local get_axis_max = function(history, spm)
    local max_value = spm or 0
    for _, value in ipairs(history or {}) do
        if value and value > max_value then
            max_value = value
        end
    end
    if max_value <= 0 then
        return 1000
    end
    if max_value < 1000 then
        return math.floor(max_value) + 1
    end
    return (math.floor(max_value / 1000) + 1) * 1000
end

local get_research_graph_ratio = function(value, axis_max)
    if not axis_max or axis_max <= 0 then
        return 0
    end

    local ratio = (value or 0) / axis_max
    if ratio > 1 then
        return 1
    elseif ratio < 0 then
        return 0
    end
    return ratio
end

local get_research_graph_y = function(value, axis_max)
    return math.ceil((1 - get_research_graph_ratio(value, axis_max)) * (research_graph_plot_height - 1))
end

local get_research_graph_hover_tooltip = function(value, column_index)
    local seconds_ago = (research_graph_column_count - column_index) * research_graph_sample_seconds
    return {"", "[font=default-bold]SPM:[/font] ", format_spaced_number(value), "\n",
            "[font=default-bold]Time:[/font] ", format_time(seconds_ago), " ago"}
end

local get_bottle_sprite = function(summary)
    if not summary or not summary.is_researching then
        return "lil_einstein_research_bottle_icon_fill_00"
    end

    local pct = math.max(0, math.min(99, (summary.progress or 0) * 100))
    local selected = 0
    for _, step in ipairs(research_bottle_steps) do
        if pct >= step then
            selected = step
        end
    end
    return "lil_einstein_research_bottle_icon_fill_" .. string.format("%02d", selected)
end

local get_research_drip_sprite = function(summary)
    if not summary or not summary.is_researching then
        return nil
    end

    local phase = game.tick % research_drip_cycle_ticks
    if phase >= research_drip_visible_ticks then
        return nil
    end

    local frame_ticks = research_drip_visible_ticks / research_drip_frame_count
    local frame = math.floor(phase / frame_ticks) + 1
    if frame > research_drip_frame_count then
        frame = research_drip_frame_count
    end
    return "lil_einstein_research_bottle_drip_" .. string.format("%02d", frame)
end

local get_research_graph_column_width = function(i)
    local left = math.floor(((i - 1) * research_graph_plot_width) / research_graph_column_count)
    local right = math.floor((i * research_graph_plot_width) / research_graph_column_count)
    return math.max(1, right - left)
end

local ensure_research_graph_columns = function(plot)
    if not plot then
        return
    end
    if #plot.children == research_graph_column_count then
        local col = plot["research_graph_column_1"]
        if col and col["research_graph_vertical_before_1"] and col["research_graph_horizontal_1"] and
            col["research_graph_vertical_after_1"] and col["research_graph_horizontal_1"].type == "progressbar" then
            return
        end
    end

    plot.clear()
    for i = 1, research_graph_column_count do
        local column_width = get_research_graph_column_width(i)
        local col = plot.add({
            type = "flow",
            name = "research_graph_column_" .. i,
            direction = "vertical",
            style = "lil_einstein_research_graph_column"
        })
        col.style.width = column_width
        col.add({
            type = "empty-widget",
            name = "research_graph_spacer_" .. i,
            style = "lil_einstein_research_graph_line_spacer"
        })
        local vertical_before = col.add({
            type = "progressbar",
            name = "research_graph_vertical_before_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_data_segment",
            ignored_by_interaction = true
        })
        vertical_before.visible = false
        vertical_before.style.width = 1
        local horizontal = col.add({
            type = "progressbar",
            name = "research_graph_horizontal_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_data_segment",
            ignored_by_interaction = true
        })
        horizontal.style.width = column_width
        horizontal.style.height = 1
        local vertical_after = col.add({
            type = "progressbar",
            name = "research_graph_vertical_after_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_data_segment",
            ignored_by_interaction = true
        })
        vertical_after.visible = false
        vertical_after.style.width = 1
    end
end

local ensure_research_graph_hover_columns = function(overlay)
    if not overlay then
        return
    end
    if #overlay.children == research_graph_column_count then
        local col = overlay["research_graph_hover_column_1"]
        if col and col["research_graph_hover_line_before_1"] and col["research_graph_hover_dot_1"] and
            col["research_graph_hover_line_after_1"] then
            return
        end
    end

    overlay.clear()
    for i = 1, research_graph_column_count do
        local column_width = get_research_graph_column_width(i)
        local col = overlay.add({
            type = "flow",
            name = "research_graph_hover_column_" .. i,
            direction = "vertical",
            style = "lil_einstein_research_graph_hover_column",
            tags = {
                lil_einstein_on_hover = true,
                handler = "research_graph_hover",
                column_index = i
            },
            tooltip = get_research_graph_hover_tooltip(0, i),
            raise_hover_events = true
        })
        col.style.width = column_width

        local line_before = col.add({
            type = "progressbar",
            name = "research_graph_hover_line_before_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_hover_line",
            ignored_by_interaction = true
        })
        line_before.visible = false

        local dot = col.add({
            type = "progressbar",
            name = "research_graph_hover_dot_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_hover_dot",
            ignored_by_interaction = true
        })
        dot.visible = false

        local line_after = col.add({
            type = "progressbar",
            name = "research_graph_hover_line_after_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_hover_line",
            ignored_by_interaction = true
        })
        line_after.visible = false
    end
end

local set_research_graph_spacer = function(spacer, height)
    if not spacer then
        return
    end
    height = math.max(0, math.floor(height or 0))
    if height > 0 then
        spacer.style.height = height
        spacer.visible = true
    else
        spacer.visible = false
    end
end

local set_research_graph_segment = function(segment, width, height)
    if not segment then
        return
    end
    width = math.max(1, math.floor(width or 1))
    height = math.max(0, math.floor(height or 0))
    if height > 0 then
        segment.value = 1
        segment.style.width = width
        segment.style.height = height
        segment.style.bar_width = height
        segment.visible = true
    else
        segment.visible = false
    end
end

local hide_research_graph_hover_column = function(col, i)
    if not col then
        return
    end

    local line_before = col["research_graph_hover_line_before_" .. i]
    local dot = col["research_graph_hover_dot_" .. i]
    local line_after = col["research_graph_hover_line_after_" .. i]
    if line_before then
        line_before.visible = false
    end
    if dot then
        dot.visible = false
    end
    if line_after then
        line_after.visible = false
    end
end

local clear_research_graph_hover_columns = function(anchor)
    local overlay = gutil.get_child(anchor, "research_graph_hover_overlay")
    if not overlay then
        return
    end

    for i = 1, research_graph_column_count do
        hide_research_graph_hover_column(overlay["research_graph_hover_column_" .. i], i)
    end
end

local set_research_graph_hover_marker = function(col, column_index, value, axis_max)
    if not col then
        return
    end

    local line_before = col["research_graph_hover_line_before_" .. column_index]
    local dot = col["research_graph_hover_dot_" .. column_index]
    local line_after = col["research_graph_hover_line_after_" .. column_index]
    if not line_before or not dot or not line_after then
        return
    end

    local y = get_research_graph_y(value, axis_max)
    local dot_top = y - math.floor(research_graph_hover_dot_height / 2)
    dot_top = math.max(0, math.min(research_graph_plot_height - research_graph_hover_dot_height, dot_top))

    set_research_graph_segment(line_before, 1, dot_top)
    set_research_graph_segment(dot, get_research_graph_column_width(column_index), research_graph_hover_dot_height)
    set_research_graph_segment(line_after, 1, research_graph_plot_height - dot_top - research_graph_hover_dot_height)
end

local get_research_context = function(player_index, anchor)
    local p = game.get_player(player_index)
    if not p or not anchor then
        return nil, nil
    end

    local summary = queue.get_research_summary(p.force.index)
    return p, summary
end

local refresh_research_progress = function(player_index, anchor)
    local _, summary = get_research_context(player_index, anchor)
    if not summary then
        return
    end

    local bottle = gutil.get_child(anchor, "research_bottle_sprite")
    if bottle and bottle.type == "sprite" then
        bottle.sprite = get_bottle_sprite(summary)
    end

    local drip = gutil.get_child(anchor, "research_bottle_drip_sprite")
    if drip and drip.type == "sprite" then
        local drip_sprite = get_research_drip_sprite(summary)
        if drip_sprite then
            drip.sprite = drip_sprite
            drip.visible = true
        else
            drip.visible = false
        end
    end

    gcupcoming.refresh_progress(player_index, anchor)

    local progress_value = gutil.get_child(anchor, "research_graph_progress_value")
    if progress_value then
        progress_value.caption = format_spaced_number(summary.done) .. " / " .. format_spaced_number(summary.total)
    end
end

local refresh_research_metrics = function(player_index, anchor)
    local _, summary = get_research_context(player_index, anchor)
    if not summary then
        return
    end

    local spm_value = gutil.get_child(anchor, "research_graph_spm_value")
    if spm_value then
        spm_value.caption = format_spaced_number(summary.spm)
    end

    local remaining_value = gutil.get_child(anchor, "research_graph_remaining_value")
    if remaining_value then
        remaining_value.caption = format_time(summary.remaining_seconds)
    end
end

local refresh_research_graph_hover = function(player_index, anchor, history, axis_max)
    clear_research_graph_hover_columns(anchor)

    local column_index = state.get_player_setting(player_index, research_graph_hover_column_setting)
    column_index = math.floor(tonumber(column_index) or 0)
    if column_index < 1 or column_index > research_graph_column_count then
        state.clear_player_setting(player_index, research_graph_hover_column_setting)
        return
    end

    if not history or not axis_max then
        local p, summary = get_research_context(player_index, anchor)
        if not p or not summary then
            return
        end
        history = queue.get_research_history(p.force.index, research_graph_column_count)
        axis_max = get_axis_max(history, summary.spm)
    end

    local overlay = gutil.get_child(anchor, "research_graph_hover_overlay")
    ensure_research_graph_hover_columns(overlay)
    if not overlay then
        return
    end

    local col = overlay["research_graph_hover_column_" .. column_index]
    local value = history[column_index] or 0
    if col then
        col.tooltip = get_research_graph_hover_tooltip(value, column_index)
        set_research_graph_hover_marker(col, column_index, value, axis_max)
    end
end

local show_research_graph_hover = function(player_index, anchor, column_index)
    column_index = math.floor(tonumber(column_index) or 0)
    if column_index < 1 or column_index > research_graph_column_count then
        return
    end

    state.set_player_setting(player_index, research_graph_hover_column_setting, column_index)
    refresh_research_graph_hover(player_index, anchor)
end

local hide_research_graph_hover = function(player_index, anchor)
    state.clear_player_setting(player_index, research_graph_hover_column_setting)
    clear_research_graph_hover_columns(anchor)
end

local refresh_research_graph = function(player_index, anchor)
    local p, summary = get_research_context(player_index, anchor)
    if not p or not summary then
        return
    end

    local history, has_history = queue.get_research_history(p.force.index, research_graph_column_count)
    local axis_max = get_axis_max(history, summary.spm)
    for i = 1, 8 do
        local label = gutil.get_child(anchor, "research_graph_axis_" .. i)
        if label then
            label.caption = format_axis_value(axis_max * (8 - i) / 7)
        end
    end

    local plot = gutil.get_child(anchor, "research_graph_plot")
    ensure_research_graph_columns(plot)
    local overlay = gutil.get_child(anchor, "research_graph_hover_overlay")
    ensure_research_graph_hover_columns(overlay)
    if not plot then
        return
    end

    for i = 1, research_graph_column_count do
        local col = plot["research_graph_column_" .. i]
        local hover_col = overlay and overlay["research_graph_hover_column_" .. i]
        local value = history[i] or 0
        if hover_col then
            hover_col.tooltip = get_research_graph_hover_tooltip(value, i)
        end
        if col then
            local spacer = col["research_graph_spacer_" .. i]
            local vertical_before = col["research_graph_vertical_before_" .. i]
            local horizontal = col["research_graph_horizontal_" .. i]
            local vertical_after = col["research_graph_vertical_after_" .. i]
            if spacer and vertical_before and horizontal and vertical_after then
                local column_width = get_research_graph_column_width(i)
                local previous_value = history[i - 1] or value

                local y = get_research_graph_y(value, axis_max)
                local previous_y = get_research_graph_y(previous_value, axis_max)
                local vertical_before_height = 0
                local vertical_after_height = 0
                if previous_y < y then
                    set_research_graph_spacer(spacer, previous_y)
                    vertical_before_height = y - previous_y
                else
                    set_research_graph_spacer(spacer, y)
                    vertical_after_height = previous_y - y
                end

                if has_history or value > 0 or previous_value > 0 then
                    set_research_graph_segment(vertical_before, 1, vertical_before_height)
                    set_research_graph_segment(horizontal, column_width, 1)
                    set_research_graph_segment(vertical_after, 1, vertical_after_height)
                else
                    vertical_before.visible = false
                    horizontal.visible = false
                    vertical_after.visible = false
                end
            end
        end
    end

    refresh_research_graph_hover(player_index, anchor, history, axis_max)
end

local refresh_research_status = function(player_index, anchor)
    refresh_research_progress(player_index, anchor)
    refresh_research_metrics(player_index, anchor)
    refresh_research_graph(player_index, anchor)
end

local add_force_setting_row = function(flow, force_index, setting_name, top_margin)
    local st = state.get_force_setting(force_index, setting_name, const.default_settings.force.settings[setting_name])
    local row = flow.add({
        type = "flow",
        name = setting_name .. "_row",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_nospacing"
    })
    row.style.height = 21
    row.style.top_margin = top_margin or 0
    row.style.vertical_align = "center"

    row.add({
        type = "button",
        name = setting_name,
        style = st and "lil_einstein_settings_checkbox_on" or "lil_einstein_settings_checkbox_off",
        tags = {
            lil_einstein_on_click = true,
            handler = "toggle_checkbox_force_click",
            setting_name = setting_name
        },
        tooltip = {"lil_einstein-force-settings." .. setting_name}
    })

    local label = row.add({
        type = "label",
        name = setting_name .. "_label",
        caption = {"lil_einstein-force-settings." .. setting_name},
        tags = {
            lil_einstein_on_click = true,
            handler = "toggle_checkbox_force_click",
            setting_name = setting_name
        },
        tooltip = {"lil_einstein-force-settings." .. setting_name}
    })
    label.style.left_margin = 7
    label.style.top_margin = -1
    label.style.font_color = {0.92, 0.92, 0.92}
end

local populate_force_settings = function(player_index, anchor)
    -- Dropdown
    -- local name = "announcement_level"
    -- local dl
    -- for i, v in ipairs(const.announcements) do
    --     if v == const.default_settings.force.announcement_level then
    --         dl = i
    --     end
    -- end
    -- local elm = gutil.get_child(anchor, name)
    -- local lvl = state.get_force_setting(player_index, name, dl)
    -- elm.selected_index = lvl

    -- Checkboxes
    local flow = gutil.get_child(anchor, "force_settings_flow")
    if not flow then
        -- For some reason when an equipment grid is opened and we try to open the queue
        -- The game crashes because we can't find the flow
        -- As containment we just exit here
        return
    end
    flow.clear()

    -- player_index may differ from force_index; state functions need force_index
    local p = game.get_player(player_index)
    local force_index = p and p.force.index or player_index

    for i, setting_name in ipairs(ordered_force_settings) do
        add_force_setting_row(flow, force_index, setting_name, i == 1 and 0 or 5)
    end

    if const.default_settings.force.global_settings then
        for k, v in pairs(const.default_settings.force.global_settings) do
            local tt = {"",
                        "[font=default-bold]This is a global mod setting, which is located under\nsettings > mod settings > map[/font]\n",
                        "", {"mod-setting-description." .. v}, ""}
            local state = settings.global[v].value
            local ifl = flow.add({
                type = "flow",
                direction = "horizontal",
                tooltip = tt
            })
            ifl.add({
                type = "checkbox",
                name = v,
                caption = {"", {"mod-setting-name." .. v}},
                state = state,
                enabled = false,
                tooltip = tt
            })
            ifl.add({
                type = "sprite",
                sprite = "info",
                tooltip = tt
            })
        end
    end

    -- Consecutive tech cap with +/- buttons
    local cap_val = state.get_force_setting(force_index, "consecutive_tech_cap", const.default_settings.force.settings.consecutive_tech_cap)
    local cap_fl = flow.add({
        type = "flow",
        name = "consecutive_tech_cap_row",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_nospacing"
    })
    cap_fl.style.top_margin = 8
    cap_fl.style.vertical_align = "center"
    cap_fl.add({
        type = "label",
        caption = {"lil_einstein-force-settings.consecutive_tech_cap"}
    })
    local right = cap_fl.add({
        type = "flow",
        name = "consecutive_tech_cap_controls",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_nospacing"
    })
    right.style.horizontally_stretchable = true
    right.style.horizontal_align = "right"
    right.style.left_margin = 11

    local value_frame = right.add({
        type = "frame",
        name = "consecutive_tech_cap_value_frame",
        style = "lil_einstein_number_input_frame",
        direction = "horizontal"
    })
    local value_lbl = value_frame.add({
        type = "label",
        name = "consecutive_tech_cap_value",
        caption = tostring(cap_val)
    })
    value_lbl.style.width = 43
    value_lbl.style.horizontal_align = "center"
    value_lbl.style.font_color = {0.92, 0.92, 0.92}

    right.add({
        type = "button",
        style = "lil_einstein_settings_stepper_left",
        tags = {
            lil_einstein_on_click = true,
            handler = "consecutive_tech_cap_dec"
        },
        tooltip = "-1"
    })
    right.add({
        type = "button",
        style = "lil_einstein_settings_stepper_right",
        tags = {
            lil_einstein_on_click = true,
            handler = "consecutive_tech_cap_inc"
        },
        tooltip = "+1"
    })
end

local populate_science_filters = function(player_index, anchor)
    local scitbl = gutil.get_child(anchor, "allowed_science_table")
    if not scitbl then
        logger.error(nil, "Did not find allowed science table, please open a bug report on the mod portal")
        return
    end
    scitbl.clear()
    scitbl.style.height = 64

    local sci = util.get_all_sciences()

    local p = game.get_player(player_index)
    local force_index = p and p.force.index or player_index
    local science_counts = queue.get_science_counts(force_index)

    -- Add all the sciences as icons to the table
    for _, s in pairs(sci) do
        local container = scitbl.add({
            type = "flow",
            direction = "vertical"
        })
        container.style.width = 46
        container.style.horizontal_align = "center"

        local count = science_counts[s] or 0
        local sprop = {
            type = "sprite-button",
            name = "allowed_science_btn_" .. s,
            style = "lil_einstein_science_pack_button",
            sprite = "item/" .. s,
            hovered_sprite = "item/" .. s,
            clicked_sprite = "item/" .. s,
            toggled = state.get_player_setting(player_index, "allowed_" .. s, false),
            tooltip = get_science_tooltip(player_index, force_index, s, count),
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_allowed_science",
                science = s
            }
        }
        local btn = container.add(sprop)
        btn.style.width = 46
        btn.style.height = 55

        if count > 0 then
            local count_label = container.add({
                type = "label",
                name = "allowed_science_count_" .. s,
                caption = gutil.format_cost(count),
                ignored_by_interaction = true
            })
            count_label.style.width = 44
            count_label.style.horizontal_align = "center"
            count_label.style.top_margin = -6
            count_label.style.font = "default-small"
            count_label.style.font_color = {r = 1, g = 1, b = 1}
        end
    end

end

local populate_hide_categories = function(player_index, anchor)
    local flow = gutil.get_child(anchor, "hide_tech_flow")
    flow.clear()
    for k, v in pairs(const.default_settings.player.hide_tech) do
        local state = state.get_player_setting(player_index, k, v)
        local prop = {
            type = "checkbox",
            name = k,
            caption = {"lil_einstein-hide-tech." .. k},
            state = state,
            tags = {
                lil_einstein_on_state_change = true,
                handler = "toggle_checkbox_player",
                setting_name = k
            }
        }
        flow.add(prop)
    end
end

local populate_show_categories = function(player_index, anchor)
    local flow = gutil.get_child(anchor, "show_tech_flow")
    flow.clear()
    local setting = "show_tech_filter_category"
    local selected = state.get_player_setting(player_index, setting, const.default_settings.player.show_tech.selected)
    for k, v in pairs(const.categories) do
        local row = flow.add({
            type = "flow",
            direction = "horizontal",
            style = "lil_einstein_horizontal_flow_nospacing"
        })
        row.style.height = 23
        local prop = {
            type = "button",
            name = k,
            style = k == selected and "lil_einstein_radio_button_on" or "lil_einstein_radio_button_off",
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_radiobutton_player",
                setting_name = setting,
                value = k
            }
        }
        row.add(prop)
        local label = row.add({
            type = "label",
            caption = {"lil_einstein-filter-category." .. k},
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_radiobutton_player",
                setting_name = setting,
                value = k
            }
        })
        label.style.left_margin = 6
    end
end

local set_master_enable = function(player_index, anchor)
    -- Get player and force
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local f = p.force

    -- Get the master switch
    local sw = gutil.get_child(anchor, "master_enable")
    if not sw then
        return
    end

    -- Get the state from storage or default settings
    local st = state.get_force_setting(f.index, "master_enable")
    if st == nil then
        st = const.default_settings.force.master_enable
    end

    -- Set the state
    if sw.type == "switch" then
        sw.switch_state = st
    else
        if st == "left" then
            sw.sprite = "lil_einstein_mockup_enable_switch_off"
            sw.hovered_sprite = "lil_einstein_mockup_enable_switch_off"
            sw.clicked_sprite = "lil_einstein_mockup_enable_switch_off"
            sw.toggled = false
        else
            sw.sprite = "lil_einstein_mockup_enable_switch_on"
            sw.hovered_sprite = "lil_einstein_mockup_enable_switch_on"
            sw.clicked_sprite = "lil_einstein_mockup_enable_switch_on"
            sw.toggled = true
        end
    end

    -- Disable/enable the rest of the content based on the state
    -- Forward delcare recursive function

    -- The new enabled state for the elements
    local enbl = true
    local lbl = gutil.get_child(anchor, "master_enable_label")
    if lbl then
        lbl.style = "bold_label"
        lbl.style.left_margin = 9
        lbl.style.top_margin = 1
        lbl.style.font_color = {0.945, 0.745, 0.392}
    end
    if st == "left" then
        enbl = false
        if lbl then
            lbl.style = "label"
            lbl.style.left_margin = 9
            lbl.style.top_margin = 1
        end
    end

    -- Loop through entry point elements
    for _, c in pairs({"queue_pane", "frame_upcoming", "right"}) do
        -- Get the child element, then call recursive function for that element
        gutil.disenable_recursive(gutil.get_child(anchor, c), enbl)
    end
end

local update_styles = function(player_index, anchor)
    local lbl
    lbl = gutil.get_child(anchor, "available_tech_lbl")
    if lbl then
        lbl.style.bottom_margin = 4
    end

    lbl = gutil.get_child(anchor, "master_enable_flow")
    if lbl then
        lbl.style.top_margin = 24
    end

    lbl = gutil.get_child(anchor, "master_enable_label")
    local row = gutil.get_child(anchor, "enable_row")
    if row then
        row.style.height = 24
        row.style.top_margin = 1
    end

    row = gutil.get_child(anchor, "subsettings")
    if row then
        row.style.top_margin = 16
    end

    row = gutil.get_child(anchor, "force_settings_flow")
    if row then
        row.style.vertical_spacing = 0
    end
end

content.repopulate_static = function(player_index, anchor)
    populate_force_settings(player_index, anchor)
    populate_science_filters(player_index, anchor)
    populate_hide_categories(player_index, anchor)
    populate_show_categories(player_index, anchor)
    update_styles(player_index, anchor)
end

content.repopulate_dynamic = function(player_index, anchor)
    gctech.populate(player_index, anchor)
    gcupcoming.populate(player_index, anchor)
    refresh_research_status(player_index, anchor)
    set_master_enable(player_index, anchor)
end

content.repopulate_all = function(player_index, anchor)
    content.repopulate_static(player_index, anchor)
    content.repopulate_dynamic(player_index, anchor)
end

content.repopulate_tech = function(player_index, anchor)
    gctech.populate(player_index, anchor)
end

content.refresh_upcoming = function(player_index, anchor)
    gcupcoming.populate(player_index, anchor)
end

content.refresh_upcoming_times = function(player_index, anchor)
    gcupcoming.refresh_times(player_index, anchor)
end

content.refresh_science_counts = function(player_index, anchor)
    refresh_science_counts(player_index, anchor)
end

content.refresh_research_status = function(player_index, anchor)
    refresh_research_status(player_index, anchor)
end

content.refresh_research_progress = function(player_index, anchor)
    refresh_research_progress(player_index, anchor)
end

content.refresh_research_metrics = function(player_index, anchor)
    refresh_research_metrics(player_index, anchor)
end

content.refresh_research_graph = function(player_index, anchor)
    refresh_research_graph(player_index, anchor)
end

content.show_research_graph_hover = function(player_index, anchor, column_index)
    show_research_graph_hover(player_index, anchor, column_index)
end

content.hide_research_graph_hover = function(player_index, anchor)
    hide_research_graph_hover(player_index, anchor)
end

return content
