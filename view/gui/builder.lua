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
    direction = "horizontal",
    children = {{
        type = "label",
        name = "research_status_bar",
        style = "lil_einstein_research_status_bar",
        caption = {"lil_einstein-status.idle"},
        tooltip = {"lil_einstein-status.idle-tooltip"},
        ignored_by_interaction = true
    }}
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
            type = "button",
            name = "policy_panel_button",
            style = "lil_einstein_button",
            caption = {"lil_einstein-policy.open-control-center"},
            tooltip = {"lil_einstein-policy.control-center"},
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_policy_panel",
                ignore_force_enable = true
            }
        }, {
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
            caption = {"lil_einstein-throughput.state-measuring"}
        }, {
            type = "flow",
            style = "lil_einstein_horizontal_flow_nospacing",
            direction = "horizontal",
            children = {{
                type = "label",
                name = "research_health_reason",
                style = "lil_einstein_research_health_reason",
                caption = {"lil_einstein-throughput.measuring-evidence"}
            }, {
                type = "button",
                name = "research_health_details_button",
                style = "lil_einstein_research_health_details_button",
                caption = {"lil_einstein-throughput.details"},
                tags = {
                    lil_einstein_on_click = true,
                    handler = "toggle_research_details",
                    ignore_force_enable = true
                }
            }, {
                type = "sprite-button",
                name = "research_health_copy_debug_button",
                style = "lil_einstein_research_health_copy_button",
                sprite = "utility/copy",
                hovered_sprite = "utility/copy",
                clicked_sprite = "utility/copy",
                tooltip = {"lil_einstein-debug.copy-report-tooltip"},
                tags = {
                    lil_einstein_on_click = true,
                    handler = "open_debug_report",
                    ignore_force_enable = true
                }
            }}
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

local policy_section = function(name, caption)
    return {
        type = "frame",
        name = name .. "_section",
        style = "inside_shallow_frame",
        direction = "vertical",
        children = {{
            type = "label",
            style = "heading_2_label",
            caption = caption
        }, {
            type = "flow",
            name = name,
            direction = "vertical"
        }}
    }
end

local decision_stage_heading = function(name, sprite_name, title, subtitle)
    return {
        type = "flow",
        name = name .. "_heading",
        style = "lil_einstein_decision_console_stage_heading",
        direction = "horizontal",
        children = {{
            type = "sprite",
            name = name .. "_step",
            sprite = sprite_name,
            style = "lil_einstein_decision_console_step",
            ignored_by_interaction = true
        }, {
            type = "flow",
            direction = "vertical",
            children = {{
                type = "label",
                style = "lil_einstein_decision_console_stage_title",
                caption = title
            }, {
                type = "label",
                style = "lil_einstein_decision_console_stage_subtitle",
                caption = subtitle
            }}
        }}
    }
end

local policy_panel = {
    type = "frame",
    name = "policy_panel",
    style = "lil_einstein_decision_console_panel",
    direction = "vertical",
    visible = false,
    tags = {ignore_force_enable = true},
    children = {{
        type = "flow",
        name = "decision_console_header",
        style = "lil_einstein_decision_console_header",
        direction = "horizontal",
        children = {{
            type = "empty-widget",
            style = "lil_einstein_decision_console_header_spacer",
            ignored_by_interaction = true
        }, {
            type = "flow",
            name = "decision_console_header_main",
            style = "lil_einstein_decision_console_header_main",
            direction = "horizontal",
            children = {{
                type = "flow",
                name = "decision_console_header_title",
                style = "lil_einstein_decision_console_header_title",
                direction = "vertical",
                children = {{
                    type = "label",
                    style = "heading_1_label",
                    caption = "Decision Console"
                }, {
                    type = "label",
                    caption = {"lil_einstein-policy.control-center"}
                }}
            }, {
                type = "flow",
                name = "decision_console_header_mode",
                style = "lil_einstein_decision_console_header_mode",
                direction = "vertical",
                children = {{
                    type = "label",
                    caption = "Operating mode"
                }, {
                    type = "label",
                    name = "decision_mode_value",
                    style = "heading_2_label",
                    caption = "Balanced"
                }, {
                    type = "label",
                    name = "decision_mode_detail",
                    caption = "Maintains steady progress while staying ready to switch."
                }}
            }, {
                type = "flow",
                name = "decision_console_header_health",
                style = "lil_einstein_decision_console_header_health",
                direction = "vertical",
                children = {{
                    type = "label",
                    caption = "Health"
                }, {
                    type = "flow",
                    direction = "horizontal",
                    children = {{
                        type = "sprite",
                        name = "decision_health_icon",
                        sprite = "utility/status_working",
                        ignored_by_interaction = true
                    }, {
                        type = "label",
                        name = "decision_health_value",
                        style = "heading_2_label",
                        caption = "Good"
                    }}
                }, {
                    type = "label",
                    name = "decision_health_detail",
                    caption = "Ready to switch."
                }}
            }, {
                type = "flow",
                name = "decision_console_header_next",
                style = "lil_einstein_decision_console_header_next",
                direction = "vertical",
                children = {{
                    type = "label",
                    caption = "Next planned research"
                }, {
                    type = "flow",
                    direction = "horizontal",
                    children = {{
                        type = "sprite",
                        name = "decision_next_research_icon",
                        sprite = "utility/technology_white",
                        ignored_by_interaction = true
                    }, {
                        type = "label",
                        name = "decision_next_research_name",
                        caption = "No planned research"
                    }}
                }, {
                    type = "label",
                    name = "decision_next_research_start",
                    caption = "Est. start: --"
                }}
            }, {
                type = "label",
                name = "decision_rationale",
                style = "lil_einstein_decision_console_header_rationale",
                caption = "Reserve-for-type protection is active."
            }}
        }, {
            type = "flow",
            name = "decision_console_header_back",
            style = "lil_einstein_decision_console_back",
            direction = "vertical",
            children = {{
                type = "button",
                name = "decision_back_button",
                style = "lil_einstein_decision_console_back_button",
                caption = {"lil_einstein-policy.back-to-research"},
                tags = {
                    lil_einstein_on_click = true,
                    handler = "toggle_policy_panel",
                    ignore_force_enable = true
                }
            }}
        }}
    }, {
        type = "flow",
        name = "decision_console_stage_row",
        style = "lil_einstein_decision_console_stage_row",
        direction = "horizontal",
        children = {{
            type = "flow",
            name = "decision_choose_stage",
            style = "lil_einstein_decision_console_stage_choose",
            direction = "vertical",
            children = {
                decision_stage_heading("decision_choose", "lil_einstein_mockup_decision_console_step_1", "Choose", "What should we research next?"),
                {
                    type = "frame",
                    name = "decision_choose_card",
                    style = "lil_einstein_decision_console_stage_card",
                    direction = "horizontal",
                    children = {{
                        type = "flow",
                        name = "decision_choose_controls",
                        direction = "vertical",
                        children = {{
                            type = "drop-down",
                            name = "decision_strategy_dropdown",
                            items = {"Balanced"},
                            selected_index = 1,
                            tags = {lil_einstein_on_state_change = true, handler = "policy_strategy"}
                        }, {
                            type = "checkbox",
                            name = "decision_manual_override",
                            caption = "Allow instant plan-demand override",
                            state = false,
                            tags = {lil_einstein_on_state_change = true, handler = "toggle_policy_setting", setting_name = "instant_switch_override"}
                        }, {
                            type = "checkbox",
                            name = "decision_lock_current",
                            caption = "Pause after current research",
                            state = false,
                            tags = {lil_einstein_on_state_change = true, handler = "toggle_policy_setting", setting_name = "planning_paused"}
                        }}
                    }, {
                        type = "frame",
                        name = "decision_candidate_card",
                        direction = "vertical",
                        children = {{
                            type = "label",
                            caption = "Top candidate"
                        }, {
                            type = "flow",
                            direction = "horizontal",
                            children = {{
                                type = "sprite",
                                name = "decision_candidate_icon",
                                sprite = "utility/technology_white",
                                ignored_by_interaction = true
                            }, {
                                type = "label",
                                name = "decision_candidate_name",
                                caption = "No candidate"
                            }}
                        }, {
                            type = "label",
                            name = "decision_candidate_score",
                            caption = "Score: --"
                        }, {
                            type = "label",
                            name = "decision_candidate_priority",
                            caption = "Priority: --"
                        }}
                    }}
                }
            }
        }, {
            type = "sprite",
            name = "decision_stage_arrow_one",
            sprite = "lil_einstein_mockup_decision_console_stage_arrow",
            style = "lil_einstein_decision_console_stage_arrow",
            ignored_by_interaction = true
        }, {
            type = "flow",
            name = "decision_science_stage",
            style = "lil_einstein_decision_console_stage_science",
            direction = "vertical",
            children = {
                decision_stage_heading("decision_science", "lil_einstein_mockup_decision_console_step_2", "Check science", "Do we have (or will we have) what we need?"),
                {
                    type = "frame",
                    name = "decision_science_card",
                    style = "lil_einstein_decision_console_stage_card",
                    direction = "vertical",
                    children = {{
                        type = "flow",
                        direction = "horizontal",
                        children = {{
                            type = "sprite",
                            name = "decision_science_status_dot",
                            sprite = "utility/status_working",
                            ignored_by_interaction = true
                        }, {
                            type = "label",
                            name = "decision_science_status",
                            caption = "Science sufficient"
                        }}
                    }, {
                        type = "label",
                        name = "decision_science_detail",
                        caption = "Supply runtime covers the switch window."
                    }, {
                        type = "label",
                        name = "decision_science_detail_two",
                        caption = "All required packs are above minimum."
                    }, {
                        type = "flow",
                        name = "decision_science_footer",
                        style = "lil_einstein_decision_console_stage_footer",
                        direction = "horizontal",
                        children = {{
                            type = "button",
                            name = "decision_recalculate_button",
                            caption = "Recalculate now",
                            tags = {lil_einstein_on_click = true, handler = "policy_recalculate"}
                        }, {
                            type = "label",
                            name = "decision_last_checked",
                            caption = "Last checked: --"
                        }}
                    }}
                }
            }
        }, {
            type = "sprite",
            name = "decision_stage_arrow_two",
            sprite = "lil_einstein_mockup_decision_console_stage_arrow",
            style = "lil_einstein_decision_console_stage_arrow",
            ignored_by_interaction = true
        }, {
            type = "flow",
            name = "decision_switch_stage",
            style = "lil_einstein_decision_console_stage_switch",
            direction = "vertical",
            children = {
                decision_stage_heading("decision_switch", "lil_einstein_mockup_decision_console_step_3", "Switch", "When should we switch?"),
                {
                    type = "frame",
                    name = "decision_switch_card",
                    style = "lil_einstein_decision_console_stage_card",
                    direction = "horizontal",
                    children = {{
                        type = "flow",
                        direction = "vertical",
                        children = {{
                            type = "label",
                            caption = "Minimum switch time"
                        }, {
                            type = "flow",
                            direction = "horizontal",
                            children = {{
                                type = "button",
                                style = "lil_einstein_settings_stepper_left",
                                tags = {lil_einstein_on_click = true, handler = "adjust_policy_setting", setting_name = "min_switch_seconds", delta = -5}
                            }, {
                                type = "label",
                                name = "decision_min_switch_value",
                                caption = "20s"
                            }, {
                                type = "button",
                                style = "lil_einstein_settings_stepper_right",
                                tags = {lil_einstein_on_click = true, handler = "adjust_policy_setting", setting_name = "min_switch_seconds", delta = 5}
                            }}
                        }, {
                            type = "label",
                            caption = "Instant plan-demand override is enabled."
                        }}
                    }, {
                        type = "flow",
                        name = "decision_switch_summary",
                        direction = "vertical",
                        children = {{
                            type = "label",
                            caption = "Summary"
                        }, {
                            type = "label",
                            name = "decision_switch_in",
                            caption = "Switch in: --"
                        }, {
                            type = "label",
                            name = "decision_parallel_slots",
                            caption = "Parallel slots: --"
                        }, {
                            type = "label",
                            name = "decision_supply_horizon",
                            caption = "Supply horizon: --"
                        }, {
                            type = "label",
                            name = "decision_plan_override",
                            caption = "Plan override: --"
                        }}
                    }}
                }
            }
        }}
    }, {
        type = "flow",
        name = "policy_tab_bar",
        direction = "horizontal",
        style = "lil_einstein_decision_console_tab_bar",
        children = {
            {type = "button", name = "policy_tab_automation", style = "lil_einstein_decision_console_tab", caption = {"lil_einstein-policy.automation"},
                tags = {lil_einstein_on_click = true, handler = "policy_tab", tab = "automation"}},
            {type = "button", name = "policy_tab_budget", style = "lil_einstein_decision_console_tab", caption = {"lil_einstein-policy.plan-budget"},
                tags = {lil_einstein_on_click = true, handler = "policy_tab", tab = "budget"}},
            {type = "button", name = "policy_tab_science", style = "lil_einstein_decision_console_tab", caption = {"lil_einstein-policy.science-policies"},
                tags = {lil_einstein_on_click = true, handler = "policy_tab", tab = "science"}},
            {type = "button", name = "policy_tab_objectives", style = "lil_einstein_decision_console_tab", caption = {"lil_einstein-policy.manual-objectives"},
                tags = {lil_einstein_on_click = true, handler = "policy_tab", tab = "objectives"}},
            {type = "button", name = "policy_tab_presets", style = "lil_einstein_decision_console_tab", caption = {"lil_einstein-policy.plan-presets"},
                tags = {lil_einstein_on_click = true, handler = "policy_tab", tab = "presets"}},
            {type = "button", name = "policy_tab_history", style = "lil_einstein_decision_console_tab", caption = {"lil_einstein-policy.history"},
                tags = {lil_einstein_on_click = true, handler = "policy_tab", tab = "history"}}
        }
    }, {
        type = "flow",
        name = "decision_console_content",
        style = "lil_einstein_decision_console_content",
        direction = "horizontal",
        children = {{
            type = "flow",
            name = "decision_automation_surface",
            direction = "horizontal",
            children = {{
                type = "frame",
                name = "decision_automation_behavior",
                style = "lil_einstein_decision_console_behavior",
                direction = "vertical"
            }, {
                type = "frame",
                name = "decision_automation_settings",
                style = "lil_einstein_decision_console_settings",
                direction = "vertical"
            }, {
                type = "frame",
                name = "decision_evidence_snapshot",
                style = "lil_einstein_decision_console_evidence",
                direction = "vertical"
            }, {
                type = "frame",
                name = "decision_recent_changes",
                style = "lil_einstein_decision_console_history",
                direction = "vertical"
            }}
        }, {
            type = "scroll-pane",
            name = "policy_scroll_pane",
            direction = "vertical",
            visible = false,
            children = {{
                type = "table",
                name = "policy_sections_table",
                column_count = 1,
                children = {
                    policy_section("policy_general_flow", {"lil_einstein-policy.automation"}),
                    policy_section("policy_budget_flow", {"lil_einstein-policy.plan-budget"}),
                    policy_section("policy_science_flow", {"lil_einstein-policy.science-policies"}),
                    policy_section("policy_trigger_flow", {"lil_einstein-policy.manual-objectives"}),
                    policy_section("policy_preset_flow", {"lil_einstein-policy.plan-presets"}),
                    policy_section("policy_history_flow", {"lil_einstein-policy.history"})
                }
            }}
        }}
    }, {
        type = "flow",
        name = "decision_console_footer",
        direction = "horizontal",
        children = {{
            type = "label",
            name = "decision_console_footer_status",
            caption = ""
        }}
    }}
}

local research_details_panel
local legacy_research_details_panel = {
    type = "frame",
    name = "research_details_panel",
    style = "inside_shallow_frame",
    direction = "vertical",
    visible = false,
    tags = {ignore_force_enable = true},
    children = {{
        type = "flow",
        direction = "horizontal",
        children = {{
            type = "label",
            style = "heading_1_label",
            caption = {"lil_einstein-throughput.details-title"}
        }, {
            type = "flow",
            style = "lil_einstein_horizontal_flow_right",
            children = {{
                type = "button",
                caption = {"lil_einstein-throughput.back"},
                tags = {
                    lil_einstein_on_click = true,
                    handler = "toggle_research_details",
                    ignore_force_enable = true
                }
            }}
        }}
    }, {
        type = "label",
        name = "research_details_headline",
        style = "heading_2_label",
        caption = {"lil_einstein-throughput.state-measuring"}
    }, {
        type = "label",
        name = "research_details_evidence",
        caption = {"lil_einstein-throughput.measuring-evidence"}
    }, {
        type = "label",
        name = "research_details_scope_note",
        caption = {"lil_einstein-throughput.scope-note"}
    }, {
        type = "label",
        name = "research_details_overlap_note",
        caption = {"lil_einstein-throughput.overlap-note"}
    }, {
        type = "frame",
        name = "research_details_pack_demand",
        style = "lil_einstein_throughput_demand_frame",
        direction = "vertical",
        children = {{
            type = "label",
            name = "research_details_pack_demand_title",
            style = "bold_label",
            caption = {"lil_einstein-throughput.pack-demand-title"}
        }, {
            type = "label",
            name = "research_details_pack_demand_scope",
            caption = {"lil_einstein-throughput.pack-demand-scope"}
        }, {
            type = "table",
            name = "research_details_pack_demand_header",
            style = "lil_einstein_throughput_demand_table",
            column_count = 4,
            children = {{
                type = "label",
                name = "research_details_pack_demand_header_science",
                style = "bold_label",
                caption = {"lil_einstein-throughput.pack-table-science"}
            }, {
                type = "label",
                name = "research_details_pack_demand_header_maximum",
                style = "bold_label",
                caption = {"lil_einstein-throughput.pack-table-maximum"}
            }, {
                type = "label",
                name = "research_details_pack_demand_header_working",
                style = "bold_label",
                caption = {"lil_einstein-throughput.pack-table-working"}
            }, {
                type = "label",
                name = "research_details_pack_demand_header_produced",
                style = "bold_label",
                caption = {"lil_einstein-throughput.pack-table-produced"}
            }}
        }, {
            type = "label",
            name = "research_details_pack_demand_empty",
            caption = {"lil_einstein-throughput.pack-demand-none"},
            visible = false
        }, {
            type = "table",
            name = "research_details_pack_demand_rows",
            style = "lil_einstein_throughput_demand_table",
            column_count = 4
        }}
    }, {
        type = "label",
        name = "research_details_ceiling_hint",
        caption = {"lil_einstein-throughput.raise-ceiling"},
        visible = false
    }, {
        type = "table",
        name = "research_details_header",
        style = "lil_einstein_throughput_table",
        column_count = 6,
        children = {{
            type = "label",
            name = "research_details_header_location",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-location"}
        }, {
            type = "label",
            name = "research_details_header_missing",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-missing"}
        }, {
            type = "label",
            name = "research_details_header_labs",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-labs"}
        }, {
            type = "label",
            name = "research_details_header_capacity",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-capacity-detail"}
        }, {
            type = "label",
            name = "research_details_header_cause",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-cause"}
        }, {
            type = "label",
            name = "research_details_header_action",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-action"}
        }}
    }, {
        type = "scroll-pane",
        name = "research_details_scroll_pane",
        style = "lil_einstein_vertical_scroll_pane",
        direction = "vertical",
        children = {{
            type = "flow",
            name = "research_details_rows",
            direction = "vertical"
        }}
    }, {
        type = "frame",
        name = "research_lab_inspection_panel",
        style = "inside_shallow_frame",
        direction = "vertical",
        visible = false,
        children = {{
            type = "flow",
            direction = "horizontal",
            children = {{
                type = "label",
                style = "heading_2_label",
                caption = {"lil_einstein-throughput.inspect-labs-title"}
            }, {
                type = "flow",
                style = "lil_einstein_horizontal_flow_right",
                children = {{
                    type = "button",
                    caption = {"lil_einstein-throughput.back-to-details"},
                    tags = {
                        lil_einstein_on_click = true,
                        handler = "hide_research_lab_inspection",
                        ignore_force_enable = true
                    }
                }}
            }}
        }, {
            type = "label",
            name = "research_lab_inspection_summary",
            caption = {"lil_einstein-throughput.inspect-labs-summary", "", 0, ""}
        }, {
            type = "table",
            name = "research_lab_inspection_header",
            style = "lil_einstein_throughput_table",
            column_count = 4,
            children = {{
                type = "label",
                name = "research_lab_inspection_header_name",
                style = "bold_label",
                caption = {"lil_einstein-throughput.lab-column-name"}
            }, {
                type = "label",
                name = "research_lab_inspection_header_location",
                style = "bold_label",
                caption = {"lil_einstein-throughput.lab-column-location"}
            }, {
                type = "label",
                name = "research_lab_inspection_header_status",
                style = "bold_label",
                caption = {"lil_einstein-throughput.lab-column-status"}
            }, {
                type = "label",
                name = "research_lab_inspection_header_missing",
                style = "bold_label",
                caption = {"lil_einstein-throughput.lab-column-missing"}
            }}
        }, {
            type = "label",
            name = "research_lab_inspection_empty",
            caption = {"lil_einstein-throughput.no-affected-labs"},
            visible = false
        }, {
            type = "scroll-pane",
            name = "research_lab_inspection_scroll_pane",
            style = "lil_einstein_vertical_scroll_pane",
            direction = "vertical",
            children = {{
                type = "table",
                name = "research_lab_inspection_rows",
                style = "lil_einstein_throughput_table",
                column_count = 4
            }}
        }}
    }}
}

research_details_panel = {
    type = "frame",
    name = "research_details_panel",
    style = "lil_einstein_throughput_details_panel",
    direction = "vertical",
    visible = false,
    tags = {ignore_force_enable = true},
    children = {{
        type = "flow",
        name = "research_details_title_flow",
        style = "lil_einstein_throughput_title_flow",
        direction = "horizontal",
        children = {{
            type = "flow",
            name = "research_details_title_stack",
            style = "lil_einstein_vertical_flow_nospacing",
            direction = "vertical",
            children = {{
                type = "label",
                name = "research_details_eyebrow",
                caption = {"lil_einstein-throughput.panel-kicker"}
            }, {
                type = "label",
                name = "research_details_title",
                style = "lil_einstein_throughput_title",
                caption = {"lil_einstein-throughput.details-title"}
            }}
        }, {
            type = "label",
            name = "research_details_current_research",
            style = "lil_einstein_throughput_title_meta",
            caption = {"lil_einstein-throughput.current-research-none"}
        }, {
            type = "button",
            name = "research_details_back_button",
            style = "lil_einstein_throughput_back_button",
            caption = {"lil_einstein-throughput.back"},
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_research_details",
                ignore_force_enable = true
            }
        }}
    }, {
        type = "frame",
        name = "research_details_warning",
        style = "lil_einstein_throughput_warning",
        direction = "horizontal",
        children = {{
            type = "sprite",
            name = "research_details_warning_icon",
            sprite = "utility/status_not_working",
            style = "lil_einstein_throughput_warning_icon"
        }, {
            type = "flow",
            name = "research_details_warning_text",
            style = "lil_einstein_throughput_warning_text",
            direction = "vertical",
            children = {{
                type = "label",
                name = "research_details_warning_headline",
                style = "lil_einstein_throughput_warning_headline",
                caption = {"lil_einstein-throughput.warning-clear"}
            }, {
                type = "label",
                name = "research_details_warning_evidence",
                style = "lil_einstein_throughput_warning_evidence",
                caption = {"lil_einstein-throughput.warning-evidence-none"}
            }, {
                type = "label",
                name = "research_details_warning_checked",
                style = "lil_einstein_throughput_warning_checked",
                caption = {"lil_einstein-throughput.last-checked", "0s"}
            }}
        }, {
            type = "button",
            name = "research_details_analyze_button",
            style = "lil_einstein_throughput_analyze_button",
            caption = {"lil_einstein-throughput.analyze-bottleneck"},
            tags = {
                lil_einstein_on_click = true,
                handler = "analyze_research_throughput",
                ignore_force_enable = true
            }
        }}
    }, {
        type = "frame",
        name = "research_details_analysis",
        style = "lil_einstein_throughput_analysis",
        direction = "horizontal",
        visible = false,
        children = {{
            type = "label",
            name = "research_details_analysis_text",
            style = "lil_einstein_throughput_analysis_text",
            caption = {"lil_einstein-throughput.analysis-not-run"}
        }, {
            type = "button",
            name = "research_details_analysis_close",
            style = "lil_einstein_throughput_analysis_close",
            caption = {"lil_einstein-throughput.close-analysis"},
            tags = {
                lil_einstein_on_click = true,
                handler = "close_research_throughput_analysis",
                ignore_force_enable = true
            }
        }}
    }, {
        type = "table",
        name = "research_details_table_header",
        style = "lil_einstein_throughput_header",
        column_count = 7,
        children = {{
            type = "label",
            name = "research_details_header_science",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-science"}
        }, {
            type = "label",
            name = "research_details_header_capacity",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-capacity"}
        }, {
            type = "label",
            name = "research_details_header_active",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-active"}
        }, {
            type = "label",
            name = "research_details_header_produced",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-produced"}
        }, {
            type = "label",
            name = "research_details_header_gap",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-gap"}
        }, {
            type = "label",
            name = "research_details_header_runtime",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-runtime"}
        }, {
            type = "label",
            name = "research_details_header_status",
            style = "bold_label",
            caption = {"lil_einstein-throughput.column-status"}
        }}
    }, {
        type = "scroll-pane",
        name = "research_details_scroll_pane",
        style = "lil_einstein_throughput_scroll_pane",
        direction = "vertical",
        children = {{
            type = "flow",
            name = "research_details_rows",
            style = "lil_einstein_throughput_rows",
            direction = "vertical"
        }}
    }, {
        type = "label",
        name = "research_details_footer",
        style = "lil_einstein_throughput_footer",
        caption = {"lil_einstein-throughput.footer-overproducing"}
    }}
}

local science_pack_panel = {
    type = "frame",
    name = "science_pack_panel",
    style = "lil_einstein_science_pack_details_panel",
    direction = "vertical",
    visible = false,
    tags = {ignore_force_enable = true},
    children = {{
        type = "flow",
        name = "science_pack_panel_header",
        style = "lil_einstein_science_pack_title_flow",
        direction = "horizontal",
        children = {{
            type = "flow",
            direction = "horizontal",
            children = {{
                type = "sprite",
                name = "science_pack_panel_icon",
                sprite = "item/iron-plate",
                style = "lil_einstein_science_pack_title_icon"
            }, {
                type = "flow",
                direction = "vertical",
                children = {{
                    type = "label",
                    name = "science_pack_panel_name",
                    style = "lil_einstein_science_pack_title",
                    caption = "Science pack"
                }, {
                    type = "label",
                    name = "science_pack_panel_state",
                    caption = ""
                }}
            }}
        }, {
            type = "flow",
            style = "lil_einstein_horizontal_flow_right",
            children = {{
                type = "label",
                name = "science_pack_panel_live",
                caption = {"lil_einstein-science-pack.live-while-open"}
            }, {
                type = "label",
                name = "science_pack_panel_timer",
                caption = {"lil_einstein-science-pack.refreshes-in", 0}
            }, {
                type = "button",
                style = "lil_einstein_throughput_back_button",
                name = "science_pack_panel_back",
                caption = {"lil_einstein-science-pack.back"},
                tags = {
                    lil_einstein_on_click = true,
                    handler = "close_science_pack_details",
                    ignore_force_enable = true
                }
            }}
        }}
    }, {
        type = "flow",
        name = "science_pack_panel_summary",
        style = "lil_einstein_science_pack_summary",
        direction = "horizontal",
        children = {{
            type = "label",
            name = "science_pack_panel_current_stock",
            style = "lil_einstein_science_pack_summary_value",
            caption = ""
        }, {
            type = "label",
            name = "science_pack_panel_flow_summary",
            style = "lil_einstein_science_pack_summary_value",
            caption = ""
        }}
    }, {
        type = "scroll-pane",
        name = "science_pack_panel_scroll_pane",
        style = "lil_einstein_science_pack_scroll_pane",
        direction = "vertical",
        children = {{
            type = "flow",
            name = "science_pack_panel_body",
            style = "lil_einstein_science_pack_body",
            direction = "vertical",
            children = {{
                type = "flow",
                name = "science_pack_panel_evidence",
                style = "lil_einstein_science_pack_evidence",
                direction = "horizontal",
                children = {{
                    type = "frame",
                    name = "science_pack_panel_labs",
                    style = "lil_einstein_science_pack_sprite_section",
                    direction = "vertical",
                    children = {{
                        type = "label",
                        style = "heading_2_label",
                        caption = {"lil_einstein-science-pack.labs-title"}
                    }, {
                        type = "label",
                        name = "science_pack_panel_labs_summary",
                        caption = ""
                    }, {
                        type = "table",
                        name = "science_pack_panel_labs_header",
                        style = "lil_einstein_science_pack_sprite_table",
                        column_count = 4,
                        children = {{
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.cluster"}
                        }, {
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.supplied"}
                        }, {
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.starved"}
                        }, {
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.demand"}
                        }}
                    }, {
                        type = "label",
                        name = "science_pack_panel_labs_empty",
                        caption = {"lil_einstein-science-pack.no-labs"},
                        visible = false
                    }, {
                        type = "table",
                        name = "science_pack_panel_labs_rows",
                        style = "lil_einstein_science_pack_sprite_table",
                        column_count = 4
                    }}
                }, {
                    type = "frame",
                    name = "science_pack_panel_planet_stock",
                    style = "lil_einstein_science_pack_sprite_section",
                    direction = "vertical",
                    children = {{
                        type = "label", style = "heading_2_label",
                        caption = {"lil_einstein-science-pack.planet-stock-title"}
                    }, {
                        type = "label",
                        name = "science_pack_panel_planet_stock_summary",
                        caption = ""
                    }, {
                        type = "table",
                        name = "science_pack_panel_planet_stock_header",
                        style = "lil_einstein_science_pack_sprite_table",
                        column_count = 2,
                        children = {{
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.planet"}
                        }, {
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.stock"}
                        }}
                    }, {
                        type = "label",
                        name = "science_pack_panel_planet_stock_empty",
                        caption = {"lil_einstein-science-pack.no-planets"},
                        visible = false
                    }, {
                        type = "table",
                        name = "science_pack_panel_planet_stock_rows",
                    style = "lil_einstein_science_pack_sprite_table",
                        column_count = 2
                    }}
                }, {
                    type = "frame",
                    name = "science_pack_panel_transit",
                    style = "lil_einstein_science_pack_sprite_section",
                    direction = "vertical",
                    children = {{
                        type = "label", style = "heading_2_label",
                        caption = {"lil_einstein-science-pack.transit-title"}
                    }, {
                        type = "label",
                        name = "science_pack_panel_transit_summary",
                        caption = ""
                    }, {
                        type = "table",
                        name = "science_pack_panel_transit_header",
                        style = "lil_einstein_science_pack_sprite_table",
                        column_count = 4,
                        children = {{
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.route"}
                        }, {
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.stock"}
                        }, {
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.status"}
                        }, {
                            type = "label", style = "bold_label",
                            caption = {"lil_einstein-science-pack.progress"}
                        }}
                    }, {
                        type = "label",
                        name = "science_pack_panel_transit_empty",
                        caption = {"lil_einstein-science-pack.no-transit"},
                        visible = false
                    }, {
                        type = "table",
                        name = "science_pack_panel_transit_rows",
                        style = "lil_einstein_science_pack_sprite_table",
                        column_count = 4
                    }}
                }}
            }, {
                type = "flow",
                name = "science_pack_panel_flow_balance",
                style = "lil_einstein_science_pack_flow_balance",
                direction = "horizontal",
                children = {{
                    type = "label", style = "bold_label",
                    caption = {"lil_einstein-science-pack.flow-balance"}
                }, {
                    type = "label", name = "science_pack_panel_flow_production",
                    style = "lil_einstein_science_pack_flow_balance_label", caption = ""
                }, {
                    type = "label", name = "science_pack_panel_flow_consumption",
                    style = "lil_einstein_science_pack_flow_balance_label", caption = ""
                }, {
                    type = "label", name = "science_pack_panel_flow_net",
                    style = "lil_einstein_science_pack_flow_balance_label", caption = ""
                }}
            }, {
                type = "label",
                name = "science_pack_panel_outlook",
                style = "lil_einstein_science_pack_flow_balance_label",
                caption = ""
            }}
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
    }, science_pack_panel, research_details_panel, policy_panel, footer}
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

builder.build_debug_report = function(player_index, anchor, report)
    local player = game.get_player(player_index)
    if not player or not anchor then
        return nil
    end

    local structure = {
        type = "frame",
        name = "lil_einstein_debug_report",
        style = "inside_shallow_frame",
        direction = "vertical",
        children = {{
            type = "flow",
            direction = "horizontal",
            children = {{
                type = "label",
                style = "heading_1_label",
                caption = {"lil_einstein-debug.report-title"}
            }, {
                type = "empty-widget",
                style = "draggable_space",
                ignored_by_interaction = true
            }, {
                type = "button",
                caption = {"lil_einstein-debug.close"},
                tags = {
                    lil_einstein_on_click = true,
                    handler = "close_debug_report",
                    ignore_force_enable = true
                }
            }}
        }, {
            type = "label",
            caption = {"lil_einstein-debug.report-instruction"}
        }, {
            type = "text-box",
            name = "lil_einstein_debug_report_text"
        }}
    }
    build_recursive(anchor, structure)
    local frame = anchor["lil_einstein_debug_report"]
    local text_box = frame and frame["lil_einstein_debug_report_text"]
    if not frame or not text_box then
        return nil
    end

    frame.auto_center = true
    frame.style.width = 1200
    frame.style.height = 800
    text_box.text = report or ""
    text_box.read_only = true
    text_box.selectable = true
    text_box.word_wrap = false
    text_box.style.width = 1160
    text_box.style.height = 700
    player.opened = text_box
    pcall(function()
        if text_box.valid then
            text_box:focus()
            if text_box.valid then
                text_box:select_all()
            end
        end
    end)
    return frame
end

return builder
