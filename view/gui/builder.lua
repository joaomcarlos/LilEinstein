local const = require('lib.const')
local logger = require("lib.log")
local util = require('lib.util')
local builder = {}

local fallback_add = function(parent, prop)
    local ok, new = pcall(parent.add, prop)
    if ok then
        return new
    end

    local retry = {}
    for k, v in pairs(prop) do
        retry[k] = v
    end

    retry.style = nil
    if retry.type == "sprite" then
        retry.type = "empty-widget"
        retry.sprite = nil
    elseif retry.type == "sprite-button" then
        retry.sprite = nil
        retry.hovered_sprite = nil
        retry.clicked_sprite = nil
    end

    ok, new = pcall(parent.add, retry)
    if ok then
        return new
    end

    logger.error(nil, "Could not add GUI element " .. tostring(prop.name) .. ": " .. tostring(new))
    return nil
end

local research_graph_axis_labels = {}
for i = 1, 8 do
    table.insert(research_graph_axis_labels, {
        type = "label",
        name = "research_graph_axis_" .. i,
        style = "lil_einstein_research_graph_axis_label",
        caption = ""
    })
end

local research_graph_x_labels = {}
for _, item in ipairs({"10", "8", "6", "4", "2", "0"}) do
    table.insert(research_graph_x_labels, {
        type = "label",
        style = "lil_einstein_research_graph_x_label",
        caption = item
    })
end

local research_graph_stat_row = function(name, label, label_style, value_style)
    return {
        type = "flow",
        name = name .. "_row",
        style = "lil_einstein_research_graph_stat_row",
        direction = "horizontal",
        ignored_by_interaction = true,
        children = {{
            type = "label",
            style = label_style or "lil_einstein_research_graph_stat_label",
            caption = label,
            ignored_by_interaction = true
        }, {
            type = "label",
            name = name,
            style = value_style or "lil_einstein_research_graph_stat_value",
            caption = "",
            ignored_by_interaction = true
        }}
    }
end

---------------------------------------------------------------------------------------------------
--- Left pane content
---------------------------------------------------------------------------------------------------
local brand_header = {
    type = "frame",
    name = "brand_header",
    style = "lil_einstein_brand_frame",
    direction = "horizontal"
}

local research_graph_panel = {
    type = "frame",
    name = "research_graph_panel",
    style = "lil_einstein_research_graph_panel",
    direction = "vertical",
    children = {{
        type = "flow",
        name = "research_graph_body",
        style = "lil_einstein_research_graph_body",
        direction = "horizontal",
        children = {{
            type = "flow",
            name = "research_graph_axis_labels",
            style = "lil_einstein_research_graph_axis_labels",
            direction = "vertical",
            children = research_graph_axis_labels
        }, {
            type = "flow",
            name = "research_graph_plot_stack",
            style = "lil_einstein_research_graph_plot_stack",
            direction = "vertical",
            children = {{
                type = "frame",
                name = "research_graph_plot_frame",
                style = "lil_einstein_research_graph_plot_frame",
                direction = "vertical",
                children = {{
                    type = "flow",
                    name = "research_graph_plot",
                    style = "lil_einstein_research_graph_plot",
                    direction = "horizontal"
                }, {
                    type = "flow",
                    name = "research_graph_hover_overlay",
                    style = "lil_einstein_research_graph_hover_overlay",
                    direction = "horizontal"
                }, {
                    type = "flow",
                    name = "research_graph_stats",
                    style = "lil_einstein_research_graph_stats",
                    direction = "vertical",
                    ignored_by_interaction = true,
                    children = {
                        research_graph_stat_row(
                            "research_graph_progress_value",
                            "Progress:",
                            "lil_einstein_research_graph_progress_stat_label",
                            "lil_einstein_research_graph_progress_stat_value"
                        ),
                        research_graph_stat_row("research_graph_spm_value", "Science per Minute:"),
                        research_graph_stat_row("research_graph_remaining_value", "Remaining time estimate:")
                    }
                }}
            }, {
                type = "flow",
                name = "research_graph_x_axis",
                style = "lil_einstein_research_graph_x_axis",
                direction = "horizontal",
                children = research_graph_x_labels
            }}
        }}
    }}
}

local lab_panel = {
    type = "frame",
    name = "lab_panel_frame",
    style = "lil_einstein_lab_frame",
    direction = "horizontal",
    children = {research_graph_panel}
}

local footer = {
    type = "frame",
    name = "footer_frame",
    style = "lil_einstein_footer_frame",
    direction = "horizontal"
}

local master_enable = {
    -- Master toggle
    type = "flow",
    name = "enable_row",
    style = "lil_einstein_horizontal_flow_centered",
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
    type = "flow",
    name = "generic_settings_frame",
    style = "lil_einstein_top_settings_flow",
    direction = "vertical",
    children = {master_enable, {
        type = "flow",
        name = "subsettings",
        direction = "vertical",
        -- children = {announcement_level, {
        children = {{
            type = "flow",
            name = "force_settings_flow",
            direction = "vertical"
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
        style = "lil_einstein_upcoming_scroll_pane",
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
    direction = "horizontal",
    children = {{
        type = "table",
        name = "allowed_science_table",
        style = "lil_einstein_allowed_science_table",
        column_count = 14
    }, {
        type = "flow",
        name = "research_health_panel",
        style = "lil_einstein_research_health_panel",
        direction = "vertical",
        children = {{
            type = "label",
            name = "research_health_state",
            style = "lil_einstein_research_health_state",
            caption = "RESEARCH HEALTH"
        }, {
            type = "label",
            name = "research_health_reason",
            style = "lil_einstein_research_health_reason",
            caption = "Calculating..."
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
                    type = "button",
                    name = "close_button",
                    style = "lil_einstein_close_button",
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
        logger.error(nil, "Got empty structure, please open a bug report on the mod portal")
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
    local new = fallback_add(parent, prop)
    if not new then
        return false
    end

    -- Recursive add elements
    for _, child in pairs(structure.children or {}) do
        if not build_recursive(new, child) then
            logger.error(nil, "Error while generating children of " .. tostring(structure.name) ..
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
