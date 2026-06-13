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
local research_graph_column_count = 152
local research_graph_column_width = 3
local research_graph_plot_height = 118
local research_bottle_steps = {0, 2, 5, 10, 15, 20, 30, 40, 50, 70, 80, 90, 95, 99}

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
    local label = gutil.format_cost(math.floor((value or 0) + 0.5))
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
        return math.ceil(max_value)
    end
    return math.ceil(max_value / 1000) * 1000
end

local get_bottle_sprite = function(summary)
    if not summary or not summary.is_researching then
        return "lil_einstein_research_bottle_fill_00"
    end

    local pct = math.max(0, math.min(99, (summary.progress or 0) * 100))
    local selected = 0
    for _, step in ipairs(research_bottle_steps) do
        if pct >= step then
            selected = step
        end
    end
    return "lil_einstein_research_bottle_fill_" .. string.format("%02d", selected)
end

local ensure_research_graph_columns = function(plot)
    if not plot then
        return
    end
    if #plot.children == research_graph_column_count then
        local col = plot["research_graph_column_1"]
        if col and col["research_graph_vertical_before_1"] and col["research_graph_horizontal_1"] and
            col["research_graph_vertical_after_1"] then
            return
        end
    end

    plot.clear()
    for i = 1, research_graph_column_count do
        local col = plot.add({
            type = "flow",
            name = "research_graph_column_" .. i,
            direction = "vertical",
            style = "lil_einstein_research_graph_column"
        })
        col.add({
            type = "empty-widget",
            name = "research_graph_spacer_" .. i,
            style = "lil_einstein_research_graph_line_spacer"
        })
        local vertical_before = col.add({
            type = "line",
            name = "research_graph_vertical_before_" .. i,
            direction = "vertical",
            style = "lil_einstein_research_graph_data_line",
            ignored_by_interaction = true
        })
        vertical_before.visible = false
        vertical_before.style.width = 1
        local horizontal = col.add({
            type = "line",
            name = "research_graph_horizontal_" .. i,
            direction = "horizontal",
            style = "lil_einstein_research_graph_data_line",
            ignored_by_interaction = true
        })
        horizontal.style.width = research_graph_column_width
        horizontal.style.height = 1
        local vertical_after = col.add({
            type = "line",
            name = "research_graph_vertical_after_" .. i,
            direction = "vertical",
            style = "lil_einstein_research_graph_data_line",
            ignored_by_interaction = true
        })
        vertical_after.visible = false
        vertical_after.style.width = 1
    end
end

local refresh_research_status = function(player_index, anchor)
    local p = game.get_player(player_index)
    if not p or not anchor then
        return
    end

    local summary = queue.get_research_summary(p.force.index)
    local bottle = gutil.get_child(anchor, "research_bottle_sprite")
    if bottle and bottle.type == "sprite" then
        bottle.sprite = get_bottle_sprite(summary)
    end

    local progress_value = gutil.get_child(anchor, "research_graph_progress_value")
    if progress_value then
        progress_value.caption = format_spaced_number(summary.done) .. " / " .. format_spaced_number(summary.total)
    end

    local spm_value = gutil.get_child(anchor, "research_graph_spm_value")
    if spm_value then
        spm_value.caption = format_spaced_number(summary.spm)
    end

    local remaining_value = gutil.get_child(anchor, "research_graph_remaining_value")
    if remaining_value then
        remaining_value.caption = format_time(summary.remaining_seconds)
    end

    local history = queue.get_research_history(p.force.index, research_graph_column_count)
    local axis_max = get_axis_max(history, summary.spm)
    for i = 1, 8 do
        local label = gutil.get_child(anchor, "research_graph_axis_" .. i)
        if label then
            label.caption = format_axis_value(axis_max * (8 - i) / 7)
        end
    end

    local plot = gutil.get_child(anchor, "research_graph_plot")
    ensure_research_graph_columns(plot)
    if not plot then
        return
    end

    for i = 1, research_graph_column_count do
        local col = plot["research_graph_column_" .. i]
        local value = history[i] or 0
        if col then
            local spacer = col["research_graph_spacer_" .. i]
            local vertical_before = col["research_graph_vertical_before_" .. i]
            local horizontal = col["research_graph_horizontal_" .. i]
            local vertical_after = col["research_graph_vertical_after_" .. i]
            if spacer and vertical_before and horizontal and vertical_after then
                local ratio = value / axis_max
                if ratio > 1 then
                    ratio = 1
                elseif ratio < 0 then
                    ratio = 0
                end
                local previous_value = history[i - 1] or value
                local previous_ratio = previous_value / axis_max
                if previous_ratio > 1 then
                    previous_ratio = 1
                elseif previous_ratio < 0 then
                    previous_ratio = 0
                end

                local y = math.floor((1 - ratio) * (research_graph_plot_height - 1))
                local previous_y = math.floor((1 - previous_ratio) * (research_graph_plot_height - 1))
                local vertical_before_height = 0
                local vertical_after_height = 0
                if previous_y < y then
                    spacer.style.height = previous_y
                    vertical_before_height = y - previous_y
                else
                    spacer.style.height = y
                    vertical_after_height = previous_y - y
                end

                if vertical_before_height > 0 then
                    vertical_before.style.height = vertical_before_height
                    vertical_before.visible = true
                else
                    vertical_before.visible = false
                end
                horizontal.style.width = research_graph_column_width
                horizontal.style.height = 1
                horizontal.visible = true
                if vertical_after_height > 0 then
                    vertical_after.style.height = vertical_after_height
                    vertical_after.visible = true
                else
                    vertical_after.visible = false
                end
            end
        end
    end
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

return content
