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

data.raw["gui-style"].default["lil_einstein_upcoming_scroll_pane"] = {
    type = "scroll_pane_style",
    parent = "lil_einstein_vertical_scroll_pane",
    width = 525,
    height = 524,
    horizontally_stretchable = "off",
    vertically_stretchable = "off",
    scrollbars_go_outside = true
}

data.raw["gui-style"].default["lil_einstein_throughput_demand_frame"] = {
    type = "frame_style",
    parent = "inside_shallow_frame",
    width = 1510,
    padding = 4,
    graphical_set = {}
}
data.raw["gui-style"].default["lil_einstein_throughput_table"] = {
    type = "table_style",
    parent = "table",
    width = 1510,
    horizontal_spacing = 4,
    vertical_spacing = 4
}
data.raw["gui-style"].default["lil_einstein_throughput_demand_table"] = {
    type = "table_style",
    parent = "lil_einstein_throughput_table",
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_science_pack_sprite_section"] = {
    type = "frame_style",
    parent = "inside_shallow_frame",
    width = 485,
    padding = 8,
    vertical_spacing = 6,
    graphical_set = {}
}
data.raw["gui-style"].default["lil_einstein_science_pack_sprite_table"] = {
    type = "table_style",
    parent = "table",
    width = 465,
    horizontal_spacing = 4,
    vertical_spacing = 4
}
data.raw["gui-style"].default["lil_einstein_throughput_pack_cell"] = {
    type = "vertical_flow_style",
    parent = "vertical_flow",
    width = 415,
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_throughput_pack_table"] = {
    type = "table_style",
    parent = "table",
    width = 415,
    horizontal_spacing = 4,
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_throughput_missing_label"] = {
    type = "label_style",
    parent = "label",
    font_color = {1.00, 0.35, 0.20},
    single_line = false
}

data.raw["gui-style"].default["lil_einstein_throughput_details_panel"] = {
    type = "frame_style",
    parent = "frame",
    width = 1672,
    height = 941,
    padding = 0,
    graphical_set = {
        base = {
            filename = "__LilEinstein__/graphics/ui/science-throughput-background-clean.png",
            width = 1672,
            height = 941
        }
    }
}
data.raw["gui-style"].default["lil_einstein_decision_console_panel"] = {
    type = "frame_style",
    parent = "frame",
    width = 1672,
    height = 941,
    padding = 0,
    graphical_set = {
        base = {
            filename = "__LilEinstein__/graphics/ui/decision-console-background-clean.png",
            width = 1672,
            height = 941
        }
    }
}
data.raw["gui-style"].default["lil_einstein_decision_console_header"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 1672,
    height = 252,
    padding = 0
}
data.raw["gui-style"].default["lil_einstein_decision_console_header_spacer"] = {
    type = "empty_widget_style",
    parent = "empty_widget",
    width = 482,
    height = 252
}
data.raw["gui-style"].default["lil_einstein_decision_console_header_main"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 892,
    height = 224,
    top_margin = 28,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_header_title"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 206,
    height = 96,
    vertical_align = "center",
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_decision_console_header_mode"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 154,
    height = 120,
    left_margin = 8,
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_decision_console_header_health"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 166,
    height = 120,
    left_margin = 8,
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_decision_console_header_next"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 214,
    height = 120,
    left_margin = 8,
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_decision_console_header_rationale"] = {
    type = "label_style",
    parent = "label",
    width = 136,
    height = 132,
    left_margin = 8,
    single_line = false,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_back"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 204,
    height = 86,
    top_margin = 151,
    left_margin = 2,
    padding = 0,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_back_button"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 198,
    height = 46,
    padding = 0
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_row"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 1596,
    height = 234,
    left_margin = 38,
    top_margin = 6,
    vertical_align = "top"
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    height = 224,
    vertical_spacing = 4
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_choose"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_decision_console_stage",
    width = 500
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_science"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_decision_console_stage",
    width = 512,
    left_margin = 4
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_switch"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_decision_console_stage",
    width = 500,
    left_margin = 4
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_heading"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    height = 44,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_step"] = {
    type = "image_style",
    parent = "image",
    width = 39,
    height = 39,
    right_margin = 8
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_title"] = {
    type = "label_style",
    parent = "heading_2_label",
    height = 28,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_subtitle"] = {
    type = "label_style",
    parent = "label",
    height = 20,
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_card"] = {
    type = "frame_style",
    parent = "inside_shallow_frame",
    height = 136,
    padding = 8
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_arrow"] = {
    type = "image_style",
    parent = "image",
    width = 40,
    height = 52,
    top_margin = 70,
    left_margin = 4,
    right_margin = 4
}
data.raw["gui-style"].default["lil_einstein_decision_console_stage_footer"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    height = 28,
    top_margin = 4,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_tab_bar"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 900,
    height = 32,
    left_margin = 38,
    top_margin = 2,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_tab"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 150,
    height = 32,
    padding = 0
}
data.raw["gui-style"].default["lil_einstein_decision_console_content"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 1596,
    height = 335,
    left_margin = 38,
    top_margin = 5,
    vertical_align = "top"
}
data.raw["gui-style"].default["lil_einstein_decision_console_panel_small"] = {
    type = "frame_style",
    parent = "inside_shallow_frame",
    height = 328,
    padding = 8,
    vertical_align = "top"
}
data.raw["gui-style"].default["lil_einstein_decision_console_behavior"] = {
    type = "frame_style",
    parent = "lil_einstein_decision_console_panel_small",
    width = 310
}
data.raw["gui-style"].default["lil_einstein_decision_console_settings"] = {
    type = "frame_style",
    parent = "lil_einstein_decision_console_panel_small",
    width = 310,
    left_margin = 10
}
data.raw["gui-style"].default["lil_einstein_decision_console_evidence"] = {
    type = "frame_style",
    parent = "lil_einstein_decision_console_panel_small",
    width = 500,
    left_margin = 10
}
data.raw["gui-style"].default["lil_einstein_decision_console_history"] = {
    type = "frame_style",
    parent = "lil_einstein_decision_console_panel_small",
    width = 416,
    left_margin = 10
}
data.raw["gui-style"].default["lil_einstein_decision_console_content_title"] = {
    type = "label_style",
    parent = "heading_2_label",
    height = 28,
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_decision_console_note"] = {
    type = "label_style",
    parent = "label",
    height = 34,
    single_line = false
}
data.raw["gui-style"].default["lil_einstein_decision_console_value"] = {
    type = "label_style",
    parent = "label",
    width = 78,
    horizontal_align = "right",
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_decision_console_science_table"] = {
    type = "table_style",
    parent = "table",
    width = 484,
    column_count = 5,
    horizontal_spacing = 6,
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_decision_console_history_row"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 398,
    height = 42,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_decision_console_history_time"] = {
    type = "label_style",
    parent = "label",
    width = 66,
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_decision_console_history_detail"] = {
    type = "label_style",
    parent = "label",
    width = 320,
    single_line = false
}
data.raw["gui-style"].default["lil_einstein_science_pack_details_panel"] = {
    type = "frame_style",
    parent = "frame",
    width = 1672,
    height = 941,
    padding = 0,
    graphical_set = {
        base = {
            filename = "__LilEinstein__/graphics/ui/science-throughput-background-clean.png",
            width = 1672,
            height = 941
        }
    }
}
data.raw["gui-style"].default["lil_einstein_science_pack_title_flow"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_throughput_title_flow"
}
data.raw["gui-style"].default["lil_einstein_science_pack_title"] = {
    type = "label_style",
    parent = "lil_einstein_throughput_title",
    width = 880
}
data.raw["gui-style"].default["lil_einstein_science_pack_title_icon"] = {
    type = "image_style",
    parent = "image",
    width = 42,
    height = 42,
    left_margin = 4,
    right_margin = 10
}
data.raw["gui-style"].default["lil_einstein_science_pack_summary"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 1588,
    height = 64,
    left_margin = 42,
    padding = 8,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_science_pack_summary_value"] = {
    type = "label_style",
    parent = "label",
    width = 760,
    height = 42,
    vertical_align = "center",
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_science_pack_scroll_pane"] = {
    type = "scroll_pane_style",
    parent = "lil_einstein_vertical_scroll_pane",
    width = 1578,
    height = 700,
    left_margin = 42,
    horizontally_stretchable = "off",
    vertically_stretchable = "off"
}
data.raw["gui-style"].default["lil_einstein_science_pack_body"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 1578,
    vertical_spacing = 8
}
data.raw["gui-style"].default["lil_einstein_science_pack_evidence"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 1578,
    horizontal_spacing = 16
}
data.raw["gui-style"].default["lil_einstein_science_pack_section"] = {
    type = "frame_style",
    parent = "frame",
    width = 515,
    padding = 8,
    graphical_set = {}
}
data.raw["gui-style"].default["lil_einstein_science_pack_table"] = {
    type = "table_style",
    parent = "table",
    width = 499,
    horizontal_spacing = 4,
    vertical_spacing = 4
}
data.raw["gui-style"].default["lil_einstein_science_pack_flow_balance"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 1578,
    height = 42,
    horizontal_spacing = 24,
    top_margin = 8,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_science_pack_flow_balance_label"] = {
    type = "label_style",
    parent = "label",
    single_line = true,
    minimal_width = 0,
    maximal_width = 380
}
data.raw["gui-style"].default["lil_einstein_throughput_title_flow"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 1578,
    height = 78,
    left_margin = 47,
    top_margin = 20,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_throughput_title"] = {
    type = "label_style",
    parent = "frame_title",
    width = 980,
    height = 46,
    vertical_align = "center",
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_throughput_title_meta"] = {
    type = "label_style",
    parent = "label",
    width = 470,
    height = 32,
    horizontal_align = "right",
    vertical_align = "center",
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_throughput_back_button"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 120,
    height = 32,
    padding = 0
}
data.raw["gui-style"].default["lil_einstein_throughput_warning"] = {
    type = "frame_style",
    parent = "frame",
    width = 1588,
    height = 96,
    left_margin = 42,
    padding = 10,
    graphical_set = {
        base = {
            filename = "__LilEinstein__/graphics/ui/science-throughput-warning-bg.png",
            width = 1588,
            height = 96
        }
    }
}
data.raw["gui-style"].default["lil_einstein_throughput_warning_text"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 1140,
    height = 76,
    vertical_align = "center",
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_throughput_warning_headline"] = {
    type = "label_style",
    parent = "heading_2_label",
    width = 1140,
    height = 30,
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_throughput_warning_evidence"] = {
    type = "label_style",
    parent = "label",
    width = 1140,
    height = 28,
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_throughput_warning_checked"] = {
    type = "label_style",
    parent = "label",
    width = 1140,
    height = 18,
    font = "default-small",
    font_color = {0.65, 0.65, 0.65},
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_throughput_warning_icon"] = {
    type = "image_style",
    parent = "image",
    width = 24,
    height = 24,
    left_margin = 4,
    right_margin = 10
}
data.raw["gui-style"].default["lil_einstein_throughput_analyze_button"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 245,
    height = 32,
    padding = 0
}
data.raw["gui-style"].default["lil_einstein_throughput_analysis"] = {
    type = "frame_style",
    parent = "frame",
    width = 1588,
    height = 42,
    left_margin = 42,
    padding = 4,
    graphical_set = {
        base = {
            filename = "__LilEinstein__/graphics/ui/science-throughput-analysis-bg.png",
            width = 1588,
            height = 42
        }
    }
}
data.raw["gui-style"].default["lil_einstein_throughput_analysis_text"] = {
    type = "label_style",
    parent = "label",
    width = 1390,
    height = 28,
    single_line = true,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_throughput_analysis_close"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 120,
    height = 28,
    padding = 0
}
data.raw["gui-style"].default["lil_einstein_throughput_header"] = {
    type = "table_style",
    parent = "table",
    width = 1578,
    height = 34,
    left_margin = 42,
    horizontal_spacing = 4,
    vertical_spacing = 0
}
data.raw["gui-style"].default["lil_einstein_throughput_cell"] = {
    type = "label_style",
    parent = "label",
    height = 44,
    vertical_align = "center",
    single_line = true
}
data.raw["gui-style"].default["lil_einstein_throughput_science_cell"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 300,
    height = 44,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_throughput_science_icon"] = {
    type = "image_style",
    parent = "image",
    width = 32,
    height = 32,
    left_margin = 4,
    right_margin = 8
}
data.raw["gui-style"].default["lil_einstein_throughput_gap_cell"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 220,
    height = 44,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_throughput_meter"] = {
    type = "progressbar_style",
    parent = "progressbar",
    width = 132,
    height = 14,
    bar_width = 132,
    color = {r = 0.45, g = 0.85, b = 0.22},
    padding = 0,
    margin = 0,
    bar_background = {}
}
data.raw["gui-style"].default["lil_einstein_throughput_gap_label"] = {
    type = "label_style",
    parent = "label",
    width = 78,
    height = 28,
    left_margin = 6,
    vertical_align = "center",
    single_line = true,
    horizontal_align = "right"
}
data.raw["gui-style"].default["lil_einstein_throughput_zero_line"] = {
    type = "line_style",
    parent = "line",
    width = 1,
    height = 16,
    color = {0.85, 0.85, 0.85},
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_throughput_runtime_cell"] = {
    type = "label_style",
    parent = "lil_einstein_throughput_cell",
    width = 150
}
data.raw["gui-style"].default["lil_einstein_throughput_status_cell"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    width = 330,
    height = 44,
    vertical_align = "center"
}
data.raw["gui-style"].default["lil_einstein_throughput_status_icon"] = {
    type = "image_style",
    parent = "image",
    width = 18,
    height = 18,
    left_margin = 4,
    right_margin = 8
}
data.raw["gui-style"].default["lil_einstein_throughput_rows"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow_nospacing",
    width = 1578,
    left_margin = 42,
    vertical_spacing = 3
}
data.raw["gui-style"].default["lil_einstein_throughput_row"] = {
    type = "frame_style",
    parent = "frame",
    width = 1578,
    height = 48,
    padding = 2,
    graphical_set = {}
}
data.raw["gui-style"].default["lil_einstein_throughput_row_table"] = {
    type = "table_style",
    parent = "table",
    width = 1570,
    height = 44,
    horizontal_spacing = 4,
    vertical_spacing = 0
}
data.raw["gui-style"].default["lil_einstein_throughput_scroll_pane"] = {
    type = "scroll_pane_style",
    parent = "scroll_pane",
    width = 1578,
    height = 630,
    left_margin = 42,
    padding = 0,
    graphical_set = {},
    horizontally_stretchable = "off",
    vertically_stretchable = "off",
    scrollbars_go_outside = true
}
data.raw["gui-style"].default["lil_einstein_throughput_footer"] = {
    type = "label_style",
    parent = "label",
    width = 1578,
    height = 26,
    left_margin = 47,
    top_margin = 3,
    font = "default-small",
    single_line = true
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

data.raw["gui-style"].default["lil_einstein_top_settings_flow"] = {
    type = "vertical_flow_style",
    parent = "lil_einstein_vertical_flow",
    width = 320,
    height = 143,
    vertically_stretchable = "off",
    padding = 12,
    top_margin = 52
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

data.raw["gui-style"].default["lil_einstein_research_graph_panel"] = {
    type = "frame_style",
    parent = "inside_shallow_frame",
    width = 520,
    height = 146,
    top_margin = 49,
    padding = 0,
    vertically_stretchable = "off",
    graphical_set = {
        base = {
            filename = "__LilEinstein__/graphics/ui/research-graph-panel-bg.png",
            width = 520,
            height = 146
        }
    }
}

data.raw["gui-style"].default["lil_einstein_research_graph_body"] = {
    type = "horizontal_flow_style",
    width = 520,
    height = 146,
    horizontal_spacing = 4,
    left_padding = 8,
    right_padding = 8,
    bottom_padding = 3
}

data.raw["gui-style"].default["lil_einstein_research_graph_axis_labels"] = {
    type = "vertical_flow_style",
    width = 31,
    height = 118,
    vertical_spacing = 4,
    top_margin = 0
}

data.raw["gui-style"].default["lil_einstein_research_graph_axis_label"] = {
    type = "label_style",
    parent = "label",
    width = 31,
    height = 11,
    font = "default-small",
    font_color = {0.45, 0.45, 0.45},
    horizontal_align = "right",
    padding = 0,
    margin = 0
}

data.raw["gui-style"].default["lil_einstein_research_graph_plot_stack"] = {
    type = "vertical_flow_style",
    width = 456,
    height = 137,
    vertical_spacing = 0
}

data.raw["gui-style"].default["lil_einstein_research_graph_plot_frame"] = {
    type = "frame_style",
    width = 456,
    height = 118,
    padding = 0,
    graphical_set = {
        base = {
            filename = "__LilEinstein__/graphics/ui/research-graph-grid.png",
            width = 456,
            height = 118
        }
    }
}

data.raw["gui-style"].default["lil_einstein_research_graph_plot"] = {
    type = "horizontal_flow_style",
    width = 456,
    height = 118,
    horizontal_spacing = 0,
    left_padding = 0,
    right_padding = 0,
    vertical_align = "top"
}

data.raw["gui-style"].default["lil_einstein_research_graph_hover_overlay"] = {
    type = "horizontal_flow_style",
    width = 456,
    height = 118,
    top_margin = -118,
    horizontal_spacing = 0,
    left_padding = 0,
    right_padding = 0,
    vertical_align = "top"
}

data.raw["gui-style"].default["lil_einstein_research_graph_column"] = {
    type = "vertical_flow_style",
    width = 2,
    height = 118,
    vertical_spacing = 0,
    horizontal_align = "left"
}

data.raw["gui-style"].default["lil_einstein_research_graph_hover_column"] = {
    type = "vertical_flow_style",
    width = 2,
    height = 118,
    vertical_spacing = 0,
    horizontal_align = "center"
}

data.raw["gui-style"].default["lil_einstein_research_graph_line_spacer"] = {
    type = "empty_widget_style",
    width = 1,
    height = 118
}

data.raw["gui-style"].default["lil_einstein_research_graph_data_segment"] = {
    type = "progressbar_style",
    parent = "progressbar",
    width = 1,
    height = 1,
    bar_width = 1,
    color = {r = 1.0, g = 0.75, b = 0.16},
    padding = 0,
    margin = 0,
    bar_background = {}
}

data.raw["gui-style"].default["lil_einstein_research_graph_hover_line"] = {
    type = "progressbar_style",
    parent = "progressbar",
    width = 1,
    height = 1,
    bar_width = 1,
    color = {r = 0.62, g = 0.62, b = 0.62, a = 0.85},
    padding = 0,
    margin = 0,
    bar_background = {}
}

data.raw["gui-style"].default["lil_einstein_research_graph_hover_dot"] = {
    type = "progressbar_style",
    parent = "progressbar",
    width = 2,
    height = 3,
    bar_width = 3,
    color = {r = 1.0, g = 0.78, b = 0.18, a = 1.0},
    padding = 0,
    margin = 0,
    bar_background = {}
}

data.raw["gui-style"].default["lil_einstein_research_graph_stats"] = {
    type = "vertical_flow_style",
    width = 300,
    height = 51,
    left_margin = 146,
    top_margin = -62,
    vertical_spacing = 2
}

data.raw["gui-style"].default["lil_einstein_research_graph_stat_row"] = {
    type = "horizontal_flow_style",
    width = 300,
    height = 15,
    horizontal_spacing = 0
}

data.raw["gui-style"].default["lil_einstein_research_graph_stat_label"] = {
    type = "label_style",
    parent = "label",
    width = 144,
    height = 15,
    font = "default-small",
    font_color = {0.84, 0.82, 0.75},
    padding = 0,
    margin = 0
}

data.raw["gui-style"].default["lil_einstein_research_graph_stat_value"] = {
    type = "label_style",
    parent = "label",
    width = 156,
    height = 15,
    font = "default-bold",
    font_color = {1.0, 0.80, 0.22},
    horizontal_align = "right",
    padding = 0,
    margin = 0
}

data.raw["gui-style"].default["lil_einstein_research_graph_progress_stat_label"] = {
    type = "label_style",
    parent = "lil_einstein_research_graph_stat_label",
    width = 70
}

data.raw["gui-style"].default["lil_einstein_research_graph_progress_stat_value"] = {
    type = "label_style",
    parent = "lil_einstein_research_graph_stat_value",
    width = 230
}

data.raw["gui-style"].default["lil_einstein_research_graph_x_axis"] = {
    type = "horizontal_flow_style",
    width = 456,
    height = 14,
    horizontal_spacing = 0
}

data.raw["gui-style"].default["lil_einstein_research_graph_x_label"] = {
    type = "label_style",
    parent = "label",
    width = 76,
    height = 14,
    font = "default-small",
    font_color = {0.37, 0.37, 0.37},
    horizontal_align = "center",
    padding = 0,
    margin = 0
}

data.raw["gui-style"].default["lil_einstein_footer_frame"] = {
    type = "frame_style",
    width = 1672,
    height = 56,
    padding = 0,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_research_status_bar"] = {
    type = "label_style",
    parent = "label",
    width = 1585,
    height = 40,
    font = "default-small",
    font_color = {0.82, 0.80, 0.72},
    horizontal_align = "right",
    vertical_align = "center",
    top_margin = 10,
    single_line = true,
    padding = 0,
    margin = 0
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
    top_margin = 31,
    default_graphical_set = {},
    hovered_graphical_set = {},
    clicked_graphical_set = {},
    disabled_graphical_set = {}
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

data.raw["gui-style"].default["lil_einstein_upcoming_separator"] = {
    type = "image_style",
    parent = "image",
    width = 525,
    height = 4,
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
    height = 74,
    stretch_image_to_widget_size = true
}

data.raw["gui-style"].default["lil_einstein_row_arrow_button"] = {
    type = "button_style",
    parent = "frame_button",
    width = 35,
    height = 26,
    padding = 0,
    default_graphical_set = {},
    hovered_graphical_set = {},
    clicked_graphical_set = {},
    disabled_graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_radio_button"] = {
    type = "button_style",
    parent = "frame_button",
    width = 18,
    height = 18,
    padding = 0,
    default_graphical_set = {},
    hovered_graphical_set = {},
    clicked_graphical_set = {},
    disabled_graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_radio_button_off"] = {
    type = "button_style",
    parent = "lil_einstein_radio_button",
    default_graphical_set = slice_graphical_set("filter_radio_off", 18, 18),
    hovered_graphical_set = slice_graphical_set("filter_radio_off", 18, 18),
    clicked_graphical_set = slice_graphical_set("filter_radio_off", 18, 18),
    disabled_graphical_set = slice_graphical_set("filter_radio_off", 18, 18)
}

data.raw["gui-style"].default["lil_einstein_radio_button_on"] = {
    type = "button_style",
    parent = "lil_einstein_radio_button",
    default_graphical_set = slice_graphical_set("filter_radio_on", 18, 18),
    hovered_graphical_set = slice_graphical_set("filter_radio_on", 18, 18),
    clicked_graphical_set = slice_graphical_set("filter_radio_on", 18, 18),
    disabled_graphical_set = slice_graphical_set("filter_radio_on", 18, 18)
}

data.raw["gui-style"].default["lil_einstein_science_pack_button"] = {
    type = "button_style",
    parent = "slot_button",
    width = 46,
    height = 55,
    padding = 0,
    default_graphical_set = {},
    hovered_graphical_set = {},
    clicked_graphical_set = {},
    disabled_graphical_set = {},
    selected_graphical_set = {},
    selected_hovered_graphical_set = {},
    selected_clicked_graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_row_flow"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow_nospacing",
    vertical_align = "center",
    height = 74
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
    height = 74,
    padding = 0,
    graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_upcoming_icon_stack"] = {
    type = "vertical_flow_style",
    width = 74,
    height = 74,
    vertical_spacing = 0
}

data.raw["gui-style"].default["lil_einstein_available_row_frame"] = {
    type = "frame_style",
    horizontal_flow_style = data.raw["gui-style"].default["lil_einstein_tech_row_flow"],
    width = 650,
    height = 74,
    padding = 0,
    graphical_set = {}
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
    height = 78,
    vertically_stretchable = "off",
    padding = 6,
    graphical_set = {}
}
data.raw["gui-style"].default["lil_einstein_research_health_panel"] = {
    type = "vertical_flow_style",
    parent = "vertical_flow",
    width = 220,
    height = 64,
    left_margin = 7,
    top_margin = 1,
    vertical_spacing = 2
}
data.raw["gui-style"].default["lil_einstein_allowed_science_table"] = {
    type = "table_style",
    width = 644,
    horizontal_spacing = 0,
    vertical_spacing = 0
}
data.raw["gui-style"].default["lil_einstein_research_health_state"] = {
    type = "label_style",
    parent = "label",
    width = 220,
    height = 20,
    font = "default-bold",
    font_color = {0.84, 0.82, 0.75},
    padding = 0,
    margin = 0
}
data.raw["gui-style"].default["lil_einstein_research_health_reason"] = {
    type = "label_style",
    parent = "label",
    width = 124,
    height = 40,
    font = "default-small",
    font_color = {0.70, 0.69, 0.64},
    single_line = false,
    padding = 0,
    margin = 0
}
data.raw["gui-style"].default["lil_einstein_research_health_details_button"] = {
    type = "button_style",
    parent = "lil_einstein_button",
    width = 56,
    height = 24,
    left_margin = 4,
    padding = 0,
    font = "default-small"
}
data.raw["gui-style"].default["lil_einstein_research_health_copy_button"] = {
    type = "button_style",
    parent = "lil_einstein_icon_button",
    width = 24,
    height = 24,
    left_margin = 4,
    padding = 0
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

data.raw["gui-style"].default["lil_einstein_upcoming_header_flow"] = {
    type = "horizontal_flow_style",
    parent = "lil_einstein_horizontal_flow",
    width = 525,
    height = 36,
    top_padding = 6,
    right_padding = 6,
    bottom_padding = 6,
    left_padding = 36,
    horizontal_align = "left",
    vertical_align = "center"
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
    width = 39,
    height = 24,
    padding = 0,
    default_graphical_set = {},
    hovered_graphical_set = {},
    clicked_graphical_set = {},
    disabled_graphical_set = {},
    selected_graphical_set = {},
    selected_hovered_graphical_set = {},
    selected_clicked_graphical_set = {}
}

data.raw["gui-style"].default["lil_einstein_settings_checkbox_off"] = {
    type = "button_style",
    parent = "frame_button",
    width = 17,
    height = 17,
    padding = 0,
    default_graphical_set = slice_graphical_set("filter_checkbox_off", 17, 17),
    hovered_graphical_set = slice_graphical_set("filter_checkbox_off", 17, 17),
    clicked_graphical_set = slice_graphical_set("filter_checkbox_off", 17, 17),
    disabled_graphical_set = slice_graphical_set("filter_checkbox_off", 17, 17)
}

data.raw["gui-style"].default["lil_einstein_settings_checkbox_on"] = {
    type = "button_style",
    parent = "frame_button",
    width = 17,
    height = 17,
    padding = 0,
    default_graphical_set = slice_graphical_set("settings_checkbox_on_1", 17, 17),
    hovered_graphical_set = slice_graphical_set("settings_checkbox_on_2", 17, 17),
    clicked_graphical_set = slice_graphical_set("settings_checkbox_on_2", 17, 17),
    disabled_graphical_set = slice_graphical_set("settings_checkbox_on_1", 17, 17)
}

data.raw["gui-style"].default["lil_einstein_number_input_frame"] = {
    type = "frame_style",
    width = 45,
    height = 26,
    padding = 0,
    left_padding = 1,
    right_padding = 1,
    top_padding = 3,
    graphical_set = slice_graphical_set("number_input_bg", 45, 26),
    horizontal_flow_style = data.raw["gui-style"].default["lil_einstein_horizontal_flow_centered"]
}

data.raw["gui-style"].default["lil_einstein_settings_stepper_left"] = {
    type = "button_style",
    parent = "frame_button",
    width = 23,
    height = 26,
    padding = 0,
    default_graphical_set = slice_graphical_set("stepper_left", 23, 26),
    hovered_graphical_set = slice_graphical_set("stepper_left", 23, 26),
    clicked_graphical_set = slice_graphical_set("stepper_left", 23, 26),
    disabled_graphical_set = slice_graphical_set("stepper_left", 23, 26)
}

data.raw["gui-style"].default["lil_einstein_settings_stepper_right"] = {
    type = "button_style",
    parent = "frame_button",
    width = 23,
    height = 26,
    padding = 0,
    default_graphical_set = slice_graphical_set("stepper_right", 23, 26),
    hovered_graphical_set = slice_graphical_set("stepper_right", 23, 26),
    clicked_graphical_set = slice_graphical_set("stepper_right", 23, 26),
    disabled_graphical_set = slice_graphical_set("stepper_right", 23, 26)
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
local transparent_graphical_set = {}
local upcoming_progress_fill = {
    base = {
        position = {305, 39},
        corner_size = 4
    }
}

data.raw["gui-style"].default["lil_einstein_upcoming_icon_progress_bar"] = {
    type = "progressbar_style",
    parent = "progressbar",
    width = 60,
    height = 4,
    bar_width = 60,
    bar = upcoming_progress_fill,
    bar_background = transparent_graphical_set,
    color = {r = 0.22, g = 0.95, b = 0.18},
    padding = 0,
    margin = 0
}

data.raw["gui-style"].default["lil_einstein_upcoming_tech_icon_button"] = {
    type = "button_style",
    parent = "lil_einstein_tech_btn",
    width = 74,
    height = 74,
    padding = 0,
    clicked_vertical_offset = 0,
    default_graphical_set = transparent_graphical_set,
    hovered_graphical_set = transparent_graphical_set,
    clicked_graphical_set = transparent_graphical_set,
    disabled_graphical_set = transparent_graphical_set,
    selected_graphical_set = transparent_graphical_set,
    selected_hovered_graphical_set = transparent_graphical_set,
    selected_clicked_graphical_set = transparent_graphical_set
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
