-- Magic numbers
local ui_slices = require("lib.ui_slices")
local outer_gui_height = 941
local left_frame_width = 552
local right_bottomleft_frame_width = 382
local right_bottomright_frame_width = 660
local tab_width = (left_frame_width) / 2 -- TODO: Update when adding more tabs
local tab_left_padding = (tab_width - 64) / 2

local slice_graphical_set = function(key, fallback_width, fallback_height)
    local slice = ui_slices.by_key[key]
    if not slice then
        return nil
    end
    return {
        base = {
            filename = slice.file,
            width = slice.w or fallback_width,
            height = slice.h or fallback_height
        }
    }
end

---------------------------------------------------------------------------------------------------
--- Main skeleton components
---------------------------------------------------------------------------------------------------
-- Flows
data.raw["gui-style"].default["lil_einstein_horizontal_flow"] = {
    type = "horizontal_flow_style"
    -- horizontally_stretchable = "on"
    -- vertically_stretchable = "on"
}
data.raw["gui-style"].default["lil_einstein_main_flow"] = {
    type = "horizontal_flow_style",
    horizontally_stretchable = "on",
    horizontal_spacing = 12
    -- vertically_stretchable = "on"
}

data.raw["gui-style"].default["lil_einstein_horizontal_flow_right"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow",
    horizontal_align = "right",
    horizontally_stretchable = "on",
    vertical_align = "center"
}

data.raw["gui-style"].default["lil_einstein_horizontal_flow_spaced"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow",
    horizontal_spacing = 12
}
data.raw["gui-style"].default["lil_einstein_horizontal_flow_nospacing"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow",
    horizontal_spacing = 0
}

data.raw["gui-style"].default["lil_einstein_horizontal_flow_padded"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow",
    left_padding = 4,
    right_padding = 4
}
data.raw["gui-style"].default["lil_einstein_horizontal_flow_centered"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow",
    horizontally_stretchable = "on",
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_horizontal_flow_queue_status"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow",
    horizontally_stretchable = "on",
    vertically_stretchable = "on",
    horizontal_align = "center",
    vertical_align = "center"
}

data.raw["gui-style"].default["lil_einstein_vertical_flow"] = {
    type = "vertical_flow_style",
    -- vertically_stretchable = "on"
    horizontally_stretchable = "on"
}
data.raw["gui-style"].default["lil_einstein_vertical_flow_spaced"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow",
    vertical_spacing = 12
}
data.raw["gui-style"].default["lil_einstein_vertical_flow_nospacing"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow",
    vertical_spacing = 0
}
data.raw["gui-style"].default["lil_einstein_vflow_leftpadded"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow",
    left_padding = 18
}

-- Top level frame
data.raw["gui-style"].default["lil_einstein_main_frame"] = {
    type = "frame_style",
    graphical_set = slice_graphical_set("window_background_clean", 1672, 941),
    horizontal_flow_style = data.raw["gui-style"].default["lil_einstein_main_flow"],
    vertical_flow_style = data.raw["gui-style"].default["lil_einstein_vertical_flow_nospacing"],
    padding = 0,
    width = 1672,
    height = outer_gui_height
}

data.raw["gui-style"].default["lil_einstein_inside_deep_frame"] = {
    type = "frame_style",
    parent = "inside_deep_frame",
    horizontally_stretchable = "on",
    vertically_stretchable = "on"
}

-- Sub section frames
data.raw["gui-style"].default["lil_einstein_shallow_frame"] = {
    type = "frame_style",
    parent = "inside_shallow_frame",
    padding = 10
}
data.raw["gui-style"].default["lil_einstein_horizontal_shallow_frame"] = {
    type = "frame_style",
    parent = "lil_einstein_shallow_frame",
    horizontally_stretchable = "on"
}
data.raw["gui-style"].default["lil_einstein_vertical_shallow_frame"] = {
    type = "frame_style",
    parent = "lil_einstein_shallow_frame",
    vertically_stretchable = "on"
}

-- Scroll panes

data.raw["gui-style"].default["lil_einstein_vertical_scroll_pane"] = {
    type = "scroll_pane_style",
    parent = "scroll_pane",
    graphical_set = {},
    horizontally_stretchable = "on",
    extra_padding_when_activated = 0,
    padding = 0,
    right_margin = 0,
    always_draw_borders = false,
    vertically_stretchable = "stretch_and_expand",
    scrollbars_go_outside = true
}

---------------------------------------------------------------------------------------------------
--- Subheader
---------------------------------------------------------------------------------------------------

data.raw["gui-style"].default["lil_einstein_subheader_frame"] = {
    type = "frame_style",
    horizontal_flow_style = data.raw["gui-style"].default["lil_einstein_horizontal_flow_centered"],
    -- horizontally_stretchable = "on",
    vertical_align = "center",
    horizontal_align = "center"
}

data.raw["gui-style"].default["lil_einstein_transparent_frame"] = {
    type = "frame_style",
    padding = 0,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_brand_frame"] = {
    type = "frame_style",
    horizontal_flow_style = data.raw["gui-style"].default["lil_einstein_horizontal_flow_spaced"],
    width = 755,
    height = 287,
    padding = 0,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_hero_panel"] = {
    type = "image_style",
    parent = "image",
    width = 755,
    height = 287,
    horizontally_stretchable = "off",
    vertically_stretchable = "off",
    horizontally_squashable = "off",
    vertically_squashable = "off",
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_top_settings_frame"] = {
    type = "frame_style",
    width = 320,
    height = 143,
    vertically_stretchable = "off",
    padding = 12,
    top_margin = 52,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_lab_frame"] = {
    type = "frame_style",
    width = 529,
    height = 195,
    padding = 0,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_lab_panel"] = {
    type = "image_style",
    parent = "image",
    width = 550,
    height = 143,
    horizontally_stretchable = "off",
    vertically_stretchable = "off",
    horizontally_squashable = "off",
    vertically_squashable = "off",
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_footer_frame"] = {
    type = "frame_style",
    width = 1672,
    height = 56,
    padding = 0,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_footer_panel"] = {
    type = "image_style",
    parent = "image",
    width = 1635,
    height = 40,
    horizontally_stretchable = "off",
    vertically_stretchable = "off",
    horizontally_squashable = "off",
    vertically_squashable = "off",
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_close_button"] = {
    type = "button_style",
    parent = "frame_button",
    width = 39,
    height = 39,
    padding = 0,
    top_margin = 31
}

data.raw["gui-style"].default["lil_einstein_border_top"] = {
    type = "image_style",
    parent = "image",
    width = 1672,
    height = 38,
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_border_side"] = {
    type = "image_style",
    parent = "image",
    width = 25,
    height = 848,
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_border_bottom"] = {
    type = "image_style",
    parent = "image",
    width = 1672,
    height = 55,
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_row_background"] = {
    type = "image_style",
    parent = "image",
    width = 525,
    height = 52,
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_tech_row_background"] = {
    type = "image_style",
    parent = "image",
    width = 650,
    height = 74,
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_drag_handle"] = {
    type = "image_style",
    parent = "image",
    width = 32,
    height = 52,
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_row_arrow_button"] = {
    type = "button_style",
    parent = "frame_button",
    width = 30,
    height = 28,
    padding = 0
}

data.raw["gui-style"].default["lil_einstein_radio_button"] = {
    type = "button_style",
    parent = "frame_button",
    width = 14,
    height = 14,
    padding = 0
}

data.raw["gui-style"].default["lil_einstein_science_pack_button"] = {
    type = "button_style",
    parent = "slot_button",
    width = 46,
    height = 55,
    padding = 0
}

data.raw["gui-style"].default["lil_einstein_row_flow"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    vertical_align = "center",
    height = 52
}

data.raw["gui-style"].default["lil_einstein_tech_row_flow"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    vertical_align = "center",
    height = 74
}

data.raw["gui-style"].default["lil_einstein_upcoming_row_frame"] = {
    type = "frame_style",
    horizontal_flow_style = data.raw["gui-style"].default["lil_einstein_row_flow"],
    width = 525,
    height = 52,
    padding = 0,
    graphical_set = slice_graphical_set("upcoming_row_bg", 525, 52)
}

data.raw["gui-style"].default["lil_einstein_available_row_frame"] = {
    type = "frame_style",
    horizontal_flow_style = data.raw["gui-style"].default["lil_einstein_tech_row_flow"],
    width = 650,
    height = 74,
    padding = 0,
    graphical_set = slice_graphical_set("tech_row_bg", 650, 74)
}

---------------------------------------------------------------------------------------------------
--- Tabbed pane (left)
---------------------------------------------------------------------------------------------------
---
data.raw["gui-style"].default["lil_einstein_main_left_frame"] = {
    type = "frame_style",
    width = 558,
    height = 598,
    top_padding = 10,
    left_padding = 36,
    right_padding = 0,
    bottom_padding = 0,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_tabbed_pane_frame"] = {
    type = "frame_style",
    parent = "lil_einstein_shallow_frame",
    horizontally_stretchable = "on",
    vertically_stretchable = "on",
    left_margin = 8,
    right_margin = 8,
    top_margin = 3,
    bottom_margin = 3
}

data.raw["gui-style"].default["lil_einstein_tabbed_pane"] = {
    type = "tabbed_pane_style",
    parent = "filter_tabbed_pane",
    horizontally_stretchable = "on"
}
data.raw["gui-style"].default["lil_einstein_tab"] = {
    type = "tab_style",
    parent = "filter_group_tab",
    horizontally_stretchable = "on",
    width = tab_width,
    left_padding = tab_left_padding
}

data.raw["gui-style"].default["lil_einstein_tab_scroll_pane"] = {
    type = "scroll_pane_style",
    parent = "scroll_pane",
    horizontally_stretchable = "on",
    vertically_stretchable = "on",
    always_draw_borders = true
}
data.raw["gui-style"].default["lil_einstein_horizontal_tech_name_pane"] = {
    type = "scroll_pane_style",
    parent = "scroll_pane",
    graphical_set = {},
    horizontally_stretchable = "on",
    vertically_stretchable = "off",
    always_draw_borders = false,
    extra_padding_when_activated = 0,
    padding = 0,
    height = 70
}

data.raw["gui-style"].default["lil_einstein_tab_icon"] = {
    type = "image_style",
    parent = "image",
    horizontally_stretchable = "off",
    vertically_stretchable = "off",
    horizontally_squashable = "off",
    vertically_squashable = "off",
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_queue_prio_textfield"] = {
    type = "textbox_style",
    parent = "textbox",
    horizontal_align = "right",
    width = 32
}

data.raw["gui-style"].default["lil_einstein_textfield_small"] = {
    type = "textbox_style",
    parent = "textbox",
    horizontal_align = "center",
    width = 40
}

---------------------------------------------------------------------------------------------------
--- Search (right)
---------------------------------------------------------------------------------------------------

data.raw["gui-style"].default["lil_einstein_main_right_flow"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow",
    horizontally_stretchable = "on"
}
-- Top frame
data.raw["gui-style"].default["lil_einstein_allowed_science_frame"] = {
    type = "frame_style",
    width = 891,
    height = 74,
    vertically_stretchable = "off",
    padding = 8,
    graphical_set = {}
}
-- Bottom left frame
data.raw["gui-style"].default["lil_einstein_filter_frame"] = {
    type = "frame_style",
    width = 395,
    height = 598,
    top_padding = 12,
    left_padding = 17,
    right_padding = 0,
    bottom_padding = 0,
    graphical_set = {}
}
-- Bottom right frame
data.raw["gui-style"].default["lil_einstein_technology_frame"] = {
    type = "frame_style",
    width = 693,
    height = 598,
    top_padding = 12,
    left_padding = 20,
    right_padding = 0,
    bottom_padding = 0,
    graphical_set = {}
}

-- Content
data.raw["gui-style"].default["lil_einstein_technology_table"] = {
    type = "table_style",
    parent = "table",
    horizontally_stretchable = "on"
}

---------------------------------------------------------------------------------------------------
--- Generic elements
---------------------------------------------------------------------------------------------------

data.raw["gui-style"].default["lil_einstein_button"] = {
    type = "button_style",
    parent = "slot_button",
    font = "heading-2",
    default_font_color = {0.9, 0.9, 0.9},
    minimal_width = 0,
    height = 24,
    right_padding = 8,
    left_padding = 8
}

data.raw["gui-style"].default["lil_einstein_allowed_button_all"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 55,
    height = 27,
    padding = 0,
    default_graphical_set = slice_graphical_set("allowed_button_all", 55, 27),
    hovered_graphical_set = slice_graphical_set("allowed_button_all", 55, 27),
    clicked_graphical_set = slice_graphical_set("allowed_button_all", 55, 27)
}

data.raw["gui-style"].default["lil_einstein_allowed_button_none"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 58,
    height = 27,
    padding = 0,
    default_graphical_set = slice_graphical_set("allowed_button_none", 58, 27),
    hovered_graphical_set = slice_graphical_set("allowed_button_none", 58, 27),
    clicked_graphical_set = slice_graphical_set("allowed_button_none", 58, 27)
}

data.raw["gui-style"].default["lil_einstein_allowed_button_produced"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 75,
    height = 27,
    padding = 0,
    default_graphical_set = slice_graphical_set("allowed_button_produced", 75, 27),
    hovered_graphical_set = slice_graphical_set("allowed_button_produced", 75, 27),
    clicked_graphical_set = slice_graphical_set("allowed_button_produced", 75, 27)
}

data.raw["gui-style"].default["lil_einstein_allowed_button_invert"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 66,
    height = 27,
    padding = 0,
    default_graphical_set = slice_graphical_set("allowed_button_invert", 66, 27),
    hovered_graphical_set = slice_graphical_set("allowed_button_invert", 66, 27),
    clicked_graphical_set = slice_graphical_set("allowed_button_invert", 66, 27)
}

data.raw["gui-style"].default["lil_einstein_upcoming_header_frame"] = {
    type = "frame_style",
    parent = "lil_einstein_subheader_frame",
    width = 525,
    height = 36,
    top_padding = 6,
    right_padding = 6,
    bottom_padding = 6,
    left_padding = 36,
    horizontal_align = "left",
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_filter_header_frame"] = {
    type = "frame_style",
    parent = "lil_einstein_subheader_frame",
    width = 361,
    height = 36,
    padding = 6,
    horizontal_align = "left",
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_tech_header_frame"] = {
    type = "frame_style",
    parent = "lil_einstein_subheader_frame",
    width = 647,
    height = 36,
    padding = 6,
    horizontal_align = "left",
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_icon_button"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 24,
    height = 24,
    padding = 0
}

data.raw["gui-style"].default["lil_einstein_enable_switch_button"] = {
    type = "button_style",
    parent = "lil_einstein_icon_button",
    width = 35,
    height = 19,
    padding = 0
}

data.raw["gui-style"].default["lil_einstein_header"] = {
    type = "label_style",
    parent = "heading_2_label",
    horizontally_stretchable = "stretch_and_expand"
}

data.raw["gui-style"].default["lil_einstein_queue_index_label"] = {
    type = "label_style",
    parent = "label",
    width = 25,
    horizontal_align = "right"
}
data.raw["gui-style"].default["lil_einstein_queue_subinfo"] = {
    type = "label_style",
    parent = "label",
    font = "default-small",
    padding = 0,
    margin = 0,
    left_margin = 5
}

---------------------------------------------------------------------------------------------------
--- Technology elements
---------------------------------------------------------------------------------------------------

local function default_glow(tint_value, scale_value)
    return {
        position = {200, 128},
        corner_size = 8,
        tint = tint_value,
        scale = scale_value,
        draw_type = "outer"
    }
end
local default_shadow_color = {0, 0, 0, 0.35}
local default_shadow = default_glow(default_shadow_color, 0.5)
local tech_btn_height = 64
local tech_btn_width = tech_btn_height * 0.85

data.raw["gui-style"].default["lil_einstein_image_science"] = {
    type = "image_style",
    size = 28,
    -- right_margin = -12,
    -- -- horizontally_squashable = "on",
    -- -- vertically_squashable = "on",
    -- stretch_image_to_widget_size = true,
    horizontally_stretchable = "on",
    vertically_stretchable = "on",
    horizontal_align = "center",
    vertical_align = "center",
    padding = 0,
    margin = 0
}

data.raw["gui-style"].default["lil_einstein_tech_btn"] = {
    type = "button_style",
    height = tech_btn_height,
    width = tech_btn_width,
    padding = 0
}

local default_available = {
    base = {
        position = {296, 136},
        corner_size = 8
    },
    shadow = default_shadow
}
local elevated_available = {
    base = {
        position = {312, 136},
        corner_size = 8
    },
    shadow = default_shadow
}
local highlighted_available = {
    base = {
        position = {330, 136},
        corner_size = 8
    },
    shadow = default_shadow
}

data.raw["gui-style"].default["lil_einstein_tech_btn_available"] = {
    type = "button_style",
    parent = "lil_einstein_tech_btn",
    default_graphical_set = default_available,
    hovered_graphical_set = elevated_available,
    selected_hovered_graphical_set = elevated_available,
    clicked_graphical_set = elevated_available,
    selected_graphical_set = elevated_available,
    selected_clicked_graphical_set = elevated_available,
    disabled_graphical_set = default_available,
    highlighted_graphical_set = highlighted_available
}

data.raw["gui-style"].default["lil_einstein_tech_btn_conditional"] = {
    type = "button_style",
    parent = "lil_einstein_tech_btn",
    default_graphical_set = {
        base = {
            position = {296, 153},
            corner_size = 8
        },
        shadow = default_shadow
    },
    hovered_graphical_set = {
        base = {
            position = {312, 153},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_hovered_graphical_set = {
        base = {
            position = {312, 153},
            corner_size = 8
        },
        shadow = default_shadow
    },
    clicked_graphical_set = {
        base = {
            position = {312, 153},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_graphical_set = {
        base = {
            position = {312, 153},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_clicked_graphical_set = {
        base = {
            position = {312, 153},
            corner_size = 8
        },
        shadow = default_shadow
    },
    disabled_graphical_set = {
        base = {
            position = {296, 153},
            corner_size = 8
        },
        shadow = default_shadow
    },
    highlighted_graphical_set = {
        base = {
            position = {330, 153},
            corner_size = 8
        },
        shadow = default_shadow
    }
}

data.raw["gui-style"].default["lil_einstein_tech_btn_researched"] = {
    type = "button_style",
    parent = "lil_einstein_tech_btn",
    default_graphical_set = {
        base = {
            position = {296, 187},
            corner_size = 8
        },
        shadow = default_shadow
    },
    hovered_graphical_set = {
        base = {
            position = {312, 187},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_hovered_graphical_set = {
        base = {
            position = {312, 187},
            corner_size = 8
        },
        shadow = default_shadow
    },
    clicked_graphical_set = {
        base = {
            position = {312, 187},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_graphical_set = {
        base = {
            position = {312, 187},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_clicked_graphical_set = {
        base = {
            position = {312, 187},
            corner_size = 8
        },
        shadow = default_shadow
    },
    disabled_graphical_set = {
        base = {
            position = {296, 187},
            corner_size = 8
        },
        shadow = default_shadow
    },
    highlighted_graphical_set = {
        base = {
            position = {330, 187},
            corner_size = 8
        },
        shadow = default_shadow
    }
}

data.raw["gui-style"].default["lil_einstein_tech_btn_unavailable"] = {
    type = "button_style",
    parent = "lil_einstein_tech_btn",
    default_graphical_set = {
        base = {
            position = {296, 170},
            corner_size = 8
        },
        shadow = default_shadow
    },
    hovered_graphical_set = {
        base = {
            position = {312, 170},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_hovered_graphical_set = {
        base = {
            position = {312, 170},
            corner_size = 8
        },
        shadow = default_shadow
    },
    clicked_graphical_set = {
        base = {
            position = {312, 170},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_graphical_set = {
        base = {
            position = {312, 170},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_clicked_graphical_set = {
        base = {
            position = {312, 170},
            corner_size = 8
        },
        shadow = default_shadow
    },
    disabled_graphical_set = {
        base = {
            position = {296, 170},
            corner_size = 8
        },
        shadow = default_shadow
    },
    highlighted_graphical_set = {
        base = {
            position = {330, 170},
            corner_size = 8
        },
        shadow = default_shadow
    }
}

data.raw["gui-style"].default["lil_einstein_tech_btn_blocked"] = {
    type = "button_style",
    parent = "lil_einstein_tech_btn",
    default_graphical_set = {
        base = {
            position = {347, 204},
            corner_size = 8
        },
        shadow = default_shadow
    },
    hovered_graphical_set = {
        base = {
            position = {363, 204},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_hovered_graphical_set = {
        base = {
            position = {363, 204},
            corner_size = 8
        },
        shadow = default_shadow
    },
    clicked_graphical_set = {
        base = {
            position = {363, 204},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_graphical_set = {
        base = {
            position = {363, 204},
            corner_size = 8
        },
        shadow = default_shadow
    },
    selected_clicked_graphical_set = {
        base = {
            position = {363, 204},
            corner_size = 8
        },
        shadow = default_shadow
    },
    disabled_graphical_set = {
        base = {
            position = {347, 204},
            corner_size = 8
        },
        shadow = default_shadow
    },
    highlighted_graphical_set = {
        base = {
            position = {381, 204},
            corner_size = 8
        },
        shadow = default_shadow
    }
}

data.raw["gui-style"].default["lil_einstein_research_progress"] = {
    type = "progressbar_style",
    parent = "progressbar",
    bar_width = 16,
    color = {r = 0.0, g = 1.0, b = 0.0}
}
