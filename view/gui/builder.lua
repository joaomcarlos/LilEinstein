local const = require('lib.const')
local util = require('lib.util')
local builder = {}

---------------------------------------------------------------------------------------------------
--- Left pane content
---------------------------------------------------------------------------------------------------
local brand_header = {
    type = "frame",
    name = "brand_header",
    style = "lil_einstein_brand_frame",
    direction = "horizontal"
}

local lab_panel = {
    type = "frame",
    name = "lab_panel_frame",
    style = "lil_einstein_lab_frame",
    direction = "horizontal"
}

local footer = {
    type = "frame",
    name = "footer_frame",
    style = "lil_einstein_footer_frame",
    direction = "horizontal"
}

local master_enable = {
    -- Master toggle
    type = "frame",
    name = "enable_row",
    style = "lil_einstein_subheader_frame",
    direction = "horizontal",
    children = {{
        type = "sprite-button",
        name = "master_enable",
        style = "lil_einstein_enable_switch_button",
        sprite = "lil_einstein_mockup_enable_switch_off",
        hovered_sprite = "lil_einstein_mockup_enable_switch_off",
        clicked_sprite = "lil_einstein_mockup_enable_switch_off",
        tags = {
            lil_einstein_on_click = true,
            handler = "master_enable"
        }
    }, {
        type = "label",
        name = "master_enable_label",
        caption = "Enable research queue manager",
        tags = {
            lil_einstein_on_click = true,
            handler = "master_enable"
        }
    }, {
        type = "flow",
        style = "lil_einstein_horizontal_flow_right",
        name = "master_enable_flow"
    }}
}

-- Announcement level dropdown
local announcements = {}
for i, a in ipairs(const.announcements) do
    table.insert(announcements, {"lil_einstein-force-settings.announce_" .. a})
end
local announcement_level = {
    type = "flow",
    direction = "horizontal",
    children = {{
        type = "label",
        caption = "Announcements"
    }, {
        type = "flow",
        style = "lil_einstein_horizontal_flow_right",
        children = {{
            type = "drop-down",
            name = "announcement_level",
            items = announcements,
            tags = {
                lil_einstein_on_state_change = true,
                handler = "announcement_level",
                setting_name = "announcement_level"
            }
        }}
    }}
}

-- Top left settings part
local generic_settings = {
    type = "frame",
    name = "generic_settings_frame",
    -- style = "lil_einstein_subheader_frame",
    style = "lil_einstein_top_settings_frame",
    direction = "vertical",
    children = {master_enable, {
        type = "frame",
        name = "subsettings",
        style = "lil_einstein_transparent_frame",
        direction = "vertical",
        -- children = {announcement_level, {
        children = {{
            type = "flow",
            name = "force_settings_flow",
            direction = "vertical",
            children = {{
                type = "checkbox",
                name = "requeue_infinite_tech",
                caption = "Requeue infinite tech",
                state = const.default_settings.force.settings.requeue_infinite_tech,
                tags = {
                    lil_einstein_on_state_change = true,
                    handler = "requeue_infinite_tech"
                }
            }}
        }}
    }}
}

-- Bottom left queue pane
local queue = {
    type = "frame",
    style = "inside_shallow_frame",
    name = "frame_queue",
    direction = "vertical",
    children = {{
        type = "frame",
        style = "lil_einstein_subheader_frame",
        direction = "horizontal",
        children = {{
            type = "label",
            style = "heading_2_label",
            caption = "Research queue"
        }}
    }, {
        type = "scroll-pane",
        style = "lil_einstein_vertical_scroll_pane",
        name = "pane_queue",
        direction = "vertical",
        children = {{
            type = "table",
            name = "table_queue",
            column_count = 6
        }}
    }}
}

-- Upcoming research preview pane
local upcoming = {
    type = "frame",
    style = "lil_einstein_transparent_frame",
    name = "frame_upcoming",
    direction = "vertical",
    children = {{
        type = "frame",
        style = "lil_einstein_upcoming_header_frame",
        direction = "horizontal",
        children = {{
            type = "label",
            style = "heading_2_label",
            caption = "Upcoming"
        }}
    }, {
        type = "scroll-pane",
        style = "lil_einstein_vertical_scroll_pane",
        name = "pane_upcoming",
        direction = "vertical",
        children = {{
            type = "flow",
            name = "flow_upcoming",
            direction = "vertical",
            style = "lil_einstein_vertical_flow_nospacing"
        }}
    }}
}

---------------------------------------------------------------------------------------------------
--- Right pane content
---------------------------------------------------------------------------------------------------

local allowed_science = {
    type = "frame",
    style = "lil_einstein_allowed_science_frame",
    name = "allowed_sciences",
    direction = "vertical",
    children = {{
        type = "scroll-pane",
        name = "sci_scroll",
        direction = "vertical",
        style = "lil_einstein_vertical_scroll_pane",
        children = {{
            type = "table",
            name = "allowed_science_table",
            column_count = 14
        }}
    }}
}

-- Bottom left section for filter
local science_filter = {
    type = "frame",
    style = "lil_einstein_filter_frame",
    name = "science_filter",
    direction = "vertical",
    children = {{
        type = "frame",
        style = "lil_einstein_filter_header_frame",
        direction = "horizontal",
        children = {{
            type = "label",
            caption = "Hide by characteristic",
            style = "heading_2_label"
        }}
    }, {
        type = "flow",
        name = "hide_tech_flow",
        direction = "vertical"
    }, {
        type = "label",
        caption = "Filter by category",
        style = "heading_2_label"
    }, {
        type = "flow",
        name = "show_tech_flow",
        direction = "vertical"
    }}
}

-- Bottom right section for science list
local science_pane = {
    type = "frame",
    style = "lil_einstein_technology_frame",
    name = "science_flow",
    direction = "vertical",
    children = {{
        type = "frame",
        name = "filter_row",
        style = "lil_einstein_tech_header_frame",
        direction = "horizontal",
        children = {{
            type = "label",
            style = "heading_2_label",
            caption = "Available technology",
            name = "available_tech_lbl"
        }, {
            type = "flow",
            style = "lil_einstein_horizontal_flow_right",
            children = {{
                type = "textfield",
                name = "search_textfield",
                visible = false,
                tags = {
                    lil_einstein_on_change = true,
                    handler = "search_textfield"
                }
            }, {
                type = "sprite-button",
                style = "lil_einstein_icon_button",
                name = "search_button",
                sprite = "utility/search",
                hovered_sprite = "utility/search_icon",
                clicked_sprite = "utility/search_icon",
                tags = {
                    lil_einstein_on_click = true,
                    handler = "search"
                }
            }}
        }}
    }, {
        type = "scroll-pane",
        style = "lil_einstein_vertical_scroll_pane",
        name = "available_sciences",
        direction = "vertical",
        children = {{
        type = "table",
        name = "available_technology_table",
        column_count = 1,
        tags = {
            ignore_enable = true
        }

        }}
    }}
}

---------------------------------------------------------------------------------------------------
--- Master structure
---------------------------------------------------------------------------------------------------

local structure = {
    type = "frame",
    style = "lil_einstein_main_frame",
    name = "lil_einstein_gui",
    direction = "vertical",
    children = {{
        type = "flow",
        style = "lil_einstein_horizontal_flow_nospacing",
        name = "top_flow",
        direction = "horizontal",
        children = {brand_header, {
            type = "flow",
            style = "lil_einstein_vertical_flow_nospacing",
            name = "top_right",
            direction = "vertical",
            children = {{
                type = "flow",
                style = "lil_einstein_horizontal_flow_nospacing",
                name = "top_right_upper",
                direction = "horizontal",
                children = {generic_settings, lab_panel, {
                    type = "sprite-button",
                    name = "close_button",
                    style = "lil_einstein_close_button",
                    sprite = "utility/close",
                    hovered_sprite = "utility/close",
                    clicked_sprite = "utility/close",
                    tags = {
                        lil_einstein_on_click = true,
                        handler = "close"
                    }
                }}
            }, allowed_science}
        }}
    }, {
        type = "flow",
        style = "lil_einstein_horizontal_flow_nospacing",
        name = "content_flow",
        children = {{
            -- Left frame
            type = "frame",
            style = "lil_einstein_main_left_frame",
            name = "left",
            direction = "vertical",
            children = {upcoming}
        }, {
            -- Right frame
            type = "flow",
            -- style = "lil_einstein_main_right_flow",
            style = "lil_einstein_vertical_flow_nospacing",
            name = "right",
            direction = "vertical",
            children = {{
                type = "flow",
                style = "lil_einstein_horizontal_flow_nospacing",
                name = "science_bottom",
                direction = "horizontal",
                children = {science_filter, science_pane}
            }}
        }}
    }, footer}
}

-- Builder
local build_recursive
build_recursive = function(parent, structure)
    if not structure.type then
        game.print("[LilEinstein] Error: Got empty structure, please open a bug report on the mod portal")
        return false
    end

    -- Build the properties array
    local prop = {}
    for k, v in pairs(structure) do
        if k ~= "children" then
            prop[k] = v
        end
    end

    -- Add the element
    local new = parent.add(prop)

    -- Recursive add elements
    for _, child in pairs(structure.children or {}) do
        if not build_recursive(new, child) then
            game.print("[LilEinstein] Error while generating children of " .. structure.name ..
                           ", please open a bug report on the mod portal")
        end
    end

    -- Map tabs if any
    if structure.mapping then
        for _, map in pairs(structure.mapping) do
            new.add_tab(new[map[1]], new[map[2]])
        end
    end
    return true
end

-- Main entry point
builder.build = function(player_index, anchor)
    local player = game.get_player(player_index)
    if not player then
        return
    end

    -- Build the static frame and populate with static content
    build_recursive(anchor, structure)

    -- Center the GUI and set as opened
    local main = anchor["lil_einstein_gui"]
    main.auto_center = true
    main.style.height = 941
    player.opened = main
end

return builder
