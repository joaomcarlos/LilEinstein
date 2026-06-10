local const = require("lib.const")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local analyzer = require("view.gui.analyzer")

local gutil = require("view.gui.gutil")
local gctech = require("view.gui.components.tech")
local gcupcoming = require("view.gui.components.upcoming")

local content = {}

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

    for k, v in pairs(const.default_settings.force.settings) do
        if k == "consecutive_tech_cap" then goto skip_setting end
        local st = state.get_force_setting(force_index, k, v)
        local prop = {
            type = "checkbox",
            name = k,
            caption = {"lil_einstein-force-settings." .. k},
            state = st,
            -- state = false,
            tags = {
                lil_einstein_on_state_change = true,
                handler = "toggle_checkbox_force",
                setting_name = k
            }
        }
        flow.add(prop)
        ::skip_setting::
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
        direction = "horizontal"
    })
    cap_fl.add({
        type = "label",
        caption = {"lil_einstein-force-settings.consecutive_tech_cap"}
    })
    cap_fl.add({
        type = "sprite-button",
        style = "lil_einstein_icon_button",
        sprite = "lil_einstein_arrow_left_small",
        hovered_sprite = "lil_einstein_arrow_left_small_black",
        clicked_sprite = "lil_einstein_arrow_left_small_black",
        tags = {
            lil_einstein_on_click = true,
            handler = "consecutive_tech_cap_dec"
        },
        tooltip = "-1"
    })
    cap_fl.add({
        type = "label",
        name = "consecutive_tech_cap_value",
        caption = tostring(cap_val),
        style = "lil_einstein_queue_index_label"
    })
    cap_fl.add({
        type = "sprite-button",
        style = "lil_einstein_icon_button",
        sprite = "lil_einstein_arrow_right_small",
        hovered_sprite = "lil_einstein_arrow_right_small_black",
        clicked_sprite = "lil_einstein_arrow_right_small_black",
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
        game.print("[LilEinstein] ERROR: Did not find allowed science table, please open a bug report on the mod portal")
        return
    end
    scitbl.clear()

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
            style = "lil_einstein_science_pack_button",
            sprite = "lil_einstein_mockup_science_slot_bg",
            toggled = state.get_player_setting(player_index, "allowed_" .. s, false),
            tooltip = {"item-name." .. s},
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_allowed_science",
                science = s
            }
        }
        local btn = container.add(sprop)
        btn.style.width = 46
        btn.style.height = 55
        local science_icon = container.add({
            type = "sprite",
            sprite = "item/" .. s,
            tooltip = {"item-name." .. s},
            ignored_by_interaction = true
        })
        science_icon.style.size = 28
        science_icon.style.top_margin = -48

        if count > 0 then
            local count_label = container.add({
                type = "label",
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

    -- Dynamically adjust height based on number of sciences
    local sp = gutil.get_child(anchor, "sci_scroll")
    sp.style.height = 55
    if #sci > 14 and #sci <= 28 then
        sp.style.height = 110
    elseif #sci > 28 then
        sp.style.height = 165
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
            type = "sprite-button",
            name = k,
            style = "lil_einstein_radio_button",
            sprite = k == selected and "lil_einstein_mockup_radio_on" or "lil_einstein_mockup_radio_off",
            hovered_sprite = k == selected and "lil_einstein_mockup_radio_on" or "lil_einstein_mockup_radio_off",
            clicked_sprite = k == selected and "lil_einstein_mockup_radio_on" or "lil_einstein_mockup_radio_off",
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
        lbl.style.font_color = {0.945, 0.745, 0.392}
    end
    if st == "left" then
        enbl = false
        if lbl then
            lbl.style = "label"
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
    -- lbl.style.bottom_margin = 10
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

return content
