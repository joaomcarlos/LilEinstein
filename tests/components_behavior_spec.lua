package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local module_names = {
    "lib.const", "lib.log", "lib.util", "model.state", "model.tech", "model.queue",
    "model.research_policy", "view.gui.analyzer", "view.gui.gutil",
    "view.gui.components.tech", "view.gui.components.upcoming", "view.gui.components"
}
local original_preloads = {}
local original_loaded = {}
for _, name in ipairs(module_names) do
    original_preloads[name] = package.preload[name]
    original_loaded[name] = package.loaded[name]
    package.loaded[name] = nil
end

local next_element_index = 0
local player_settings = {}
local force_settings = {}
local policy_settings = {}
local science_counts = {}
local science_breakdown = {}
local science_forecast = {}
local science_pack_insight
local research_summary
local research_diagnostic
local research_history = {}
local research_history_has_data = true
local queue_budget
local trigger_objectives = {}
local preset_names = {}
local policy_history = {}
local state_writes = {}
local reject_button_single_line = false

local function make_element(name, parent)
    next_element_index = next_element_index + 1
    local element = {
        name = name,
        index = next_element_index,
        valid = true,
        visible = true,
        enabled = true,
        style = {},
        children = {},
        parent = parent,
        clear_count = 0,
        _named = {}
    }

    function element.add(prop)
        local child = make_element(prop.name, element)
        for key, value in pairs(prop) do
            if key == "style" then
                if type(value) == "string" then
                    child.style_name = value
                elseif type(value) == "table" then
                    child.style = value
                end
            elseif key ~= "name" and key ~= "type" then
                child[key] = value
            end
        end
        child.initial_caption = prop.caption
        child.type = prop.type
        if prop.type == "button" and reject_button_single_line then
            child.style = setmetatable({}, {
                __newindex = function(style, key, value)
                    if key == "single_line" then
                        error("Expected Label style type but was Button")
                    end
                    rawset(style, key, value)
                end
            })
        end
        table.insert(element.children, child)
        if prop.name then
            element[prop.name] = child
            element._named[prop.name] = child
        end
        return child
    end

    function element.clear()
        element.clear_count = element.clear_count + 1
        for _, child in ipairs(element.children) do
            child.valid = false
        end
        for child_name in pairs(element._named) do
            element[child_name] = nil
        end
        element._named = {}
        element.children = {}
    end

    function element.destroy()
        if not element.valid then
            return
        end
        element.valid = false
        if element.parent then
            if element.parent._named[element.name] == element then
                element.parent._named[element.name] = nil
                element.parent[element.name] = nil
            end
            for index, child in ipairs(element.parent.children) do
                if child == element then
                    table.remove(element.parent.children, index)
                    break
                end
            end
        end
    end

    return element
end

local function add_named(parent, name, element_type)
    return parent.add({type = element_type or "flow", name = name})
end

local function find_element(parent, name)
    if not parent or not parent.valid then
        return nil
    end
    if parent.name == name then
        return parent
    end
    for _, child in ipairs(parent.children or {}) do
        local result = find_element(child, name)
        if result then
            return result
        end
    end
    return nil
end

local function find_by_tag(parent, key, value)
    if not parent or not parent.valid then
        return nil
    end
    if parent.tags and parent.tags[key] == value then
        return parent
    end
    for _, child in ipairs(parent.children or {}) do
        local result = find_by_tag(child, key, value)
        if result then
            return result
        end
    end
    return nil
end

local function caption_head(caption)
    return type(caption) == "table" and caption[1] or caption
end

local function reset_fixture()
    player_settings = {
        allowed_science_a = true,
        science_pack_panel_science = "science_a",
        hide_tech = true,
        show_tech_filter_category = "military",
        plan_preset_name = "night-plan"
    }
    force_settings = {
        requeue_infinite_tech = true,
        auto_research = false,
        consecutive_tech_cap = 4,
        master_enable = "right"
    }
    policy_settings = {
        strategy = "throughput",
        planning_paused = false,
        parallel_research = true,
        cluster_mode = true,
        performance_mode = false,
        min_switch_seconds = 35,
        forecast_seconds = 120,
        parallel_slots = 3,
        multiplayer_lock = true
    }
    science_counts = {science_a = 0, science_b = 0}
    science_breakdown = {
        science_a = {
            lab_count = 24,
            lab_entity_count = 3,
            network_total = 15,
            networks = {
                {label = "orbit", count = 3},
                {label = "main", count = 12}
            }
        },
        science_b = {lab_count = 0, lab_entity_count = 0, network_total = 0, networks = {}}
    }
    science_forecast = {
        science_a = {production_per_minute = 1200, consumption_per_minute = 8, depletion_seconds = 41.6},
        science_b = {production_per_minute = 0, consumption_per_minute = 0, recovery_seconds = 12.4}
    }
    science_pack_insight = {
        science = "science_a",
        current_stock = 12345,
        production_per_minute = 1200,
        consumption_per_minute = 8,
        net_per_minute = 1192,
        next_refresh_tick = 7440,
        labs = {
            surface_name = "nauvis",
            stock = 24,
            compatible_labs = 12,
            supplied_labs = 9,
            starved_labs = 3,
            maximum_per_minute = 240,
            working_per_minute = 180,
            clusters = {{
                key = "nauvis-main",
                label = "Main lab network",
                surface_name = "nauvis",
                total_labs = 12,
                compatible_labs = 12,
                supplied_labs = 9,
                starved_labs = 3,
                maximum_per_minute = 240,
                working_per_minute = 180
            }}
        },
        planet_stock_rows = {
            {name = "Nauvis", stock = 37},
            {name = "Vulcanus", stock = 0}
        },
        in_transit = {
            total = 12,
            routes = {{platform = "platform-1", from = "nauvis", to = "vulcanus", stock = 12}}
        }
    }
    research_summary = {done = 1234, total = 5678, spm = 1234, remaining_seconds = 125}
    research_diagnostic = {
        state = "pack_bound",
        available = true,
        actual_spm = 123,
        expected_spm = 240,
        working_spm = 123,
        working_labs = 2,
        compatible_labs = 2,
        incompatible_labs = 1,
        material_loss_spm = 117,
        dominant_cluster_key = "network-main",
        dominant_missing_science = {
            science = "science_a",
            missing_per_minute = 14,
            lost_spm = 117,
            labs = 2
        },
        causes = {
            {kind = "missing_science", lost_spm = 117, labs = 2},
            {kind = "power", lost_spm = 6, labs = 1}
        },
        missing_sciences = {
            {science = "science_a", missing_per_minute = 14, lost_spm = 117, labs = 2}
        },
        science_pack_rates = {
            {science = "science_a", maximum_per_minute = 240, working_per_minute = 123}
        },
        clusters = {
            {
                key = "network-main",
                scope = "network",
                surface_name = "Nauvis",
                network_id = 7,
                representative_position = {x = 12.4, y = -8.6},
                working_labs = 2,
                compatible_labs = 2,
                incompatible_labs = 1,
                working_spm = 123,
                expected_spm = 240,
                lost_spm = 117,
                missing_sciences = {
                    {science = "science_a", missing_per_minute = 14, lost_spm = 117, labs = 2}
                },
                causes = {
                    {kind = "missing_science", lost_spm = 117, labs = 2},
                    {kind = "power", lost_spm = 6, labs = 1}
                },
                dominant_cause = {kind = "missing_science"},
                local_stock = {science_a = 9},
                lab_descriptors = {
                    {
                        unit_number = 101,
                        prototype_name = "lab",
                        surface_name = "Nauvis",
                        position = {x = 12.4, y = -8.6},
                        compatible = true,
                        working = false,
                        status_key = "missing_science",
                        missing_sciences = {"science_a"}
                    },
                    {
                        unit_number = 102,
                        prototype_name = "lab",
                        surface_name = "Nauvis",
                        position = {x = 18.2, y = -4.1},
                        compatible = true,
                        working = false,
                        status_key = "missing_science",
                        missing_sciences = {"science_a"}
                    }
                },
                science_pack_rates = {
                    {science = "science_a", maximum_per_minute = 240, working_per_minute = 123}
                }
            }
        }
    }
    research_history = {10, 20, 30}
    research_history_has_data = true
    queue_budget = {
        technology_count = 4,
        total_seconds = 3665,
        unlock_count = 2,
        limiting_science = "science_a",
        repeat_truncated = true,
        sciences = {
            science_a = {required = 120, available = 80, deficit = 40, production_per_minute = 12},
            science_b = {required = 20, available = 40, deficit = 0, production_per_minute = 4}
        }
    }
    trigger_objectives = {
        {
            tech_name = "rocket-silo",
            ready = true,
            trigger_type = "craft-item",
            xcur = {
                technology = {localised_name = "Rocket silo"},
                meta = {prototype = {research_trigger = {type = "craft-item", item = {name = "iron-plate"}, count = 3}}}
            }
        }
    }
    preset_names = {"night-plan", "science-first"}
    policy_history = {
        {tick = 7140, player = "Ada", action = "policy", detail = "throughput"},
        {tick = 7020, player = "Bob", action = "threshold", detail = "science_a"}
    }
    state_writes = {}
end

local const = {
    categories = {all = "All", military = "Military"},
    default_settings = {
        force = {
            settings = {
                requeue_infinite_tech = true,
                auto_research = false,
                consecutive_tech_cap = 3
            },
            global_settings = {map_setting = "lil_einstein-map-setting"},
            master_enable = "right"
        },
        player = {
            hide_tech = {hide_tech = false},
            show_tech = {selected = "all"}
        }
    }
}

local state = {
    get_force_setting = function(force_index, setting_name, default)
        return force_settings[setting_name] ~= nil and force_settings[setting_name] or default
    end,
    get_player_setting = function(_, setting_name, default)
        return player_settings[setting_name] ~= nil and player_settings[setting_name] or default
    end,
    set_player_setting = function(_, setting_name, value)
        player_settings[setting_name] = value
        state_writes[setting_name] = value
    end,
    clear_player_setting = function(_, setting_name)
        player_settings[setting_name] = nil
        state_writes[setting_name] = "cleared"
    end,
    get_translation = function(_, kind, name)
        return "Localized " .. kind .. " " .. name
    end
}

local queue = {
    get_science_display_counts = function()
        return science_counts
    end,
    get_science_display_breakdown = function(_, science)
        return science_breakdown[science] or {}
    end,
    get_science_display_forecast = function()
        return science_forecast
    end,
    get_science_pack_insight = function()
        return science_pack_insight
    end,
    get_research_health_snapshot_tick = function()
        return 3
    end,
    get_research_summary = function()
        return research_summary
    end,
    get_research_diagnostic = function()
        return research_diagnostic
    end,
    get_research_display_diagnostic = function()
        return research_diagnostic
    end,
    get_research_history = function()
        return research_history, research_history_has_data
    end,
    get_science_forecast = function()
        return science_forecast
    end,
    get_queue_budget = function()
        return queue_budget
    end,
    get_trigger_objectives = function()
        return trigger_objectives
    end,
    get_preset_names = function()
        return preset_names
    end
}

local policy = {
    strategy_order = {"balanced", "throughput", "conservative"},
    reserve_for_type_order = {"off", "safety_first", "balanced"},
    get_setting = function(_, setting_name)
        return policy_settings[setting_name]
    end,
    get_science_policy = function(_, science)
        if science == "science_a" then
            return {priority = 2, lower_threshold = 0.25, upper_threshold = 0.80}
        end
        return {priority = 1, lower_threshold = 0.10, upper_threshold = 0.90}
    end,
    parallel_mod_available = function()
        return false
    end,
    get_history = function()
        return policy_history
    end
}

local util = {
    get_all_sciences = function()
        return {"science_a", "science_b"}
    end
}

local function format_number(value)
    return tostring(value or 0)
end

local gutil = {
    get_child = find_element,
    format_cost = format_number,
    format_si = format_number,
    disenable_recursive = function(element, enabled)
        if not element then
            return
        end
        if not element.tags or not element.tags.ignore_force_enable then
            element.enabled = enabled
        end
        for _, child in ipairs(element.children or {}) do
            if not element.tags or not element.tags.ignore_enable then
                gutil.disenable_recursive(child, enabled)
            end
        end
    end
}

local noop_tech = {populate = function() end}
local noop_upcoming = {
    populate = function() end,
    request_populate = function() return "requested" end,
    tick_populate = function() return "ticked" end,
    refresh_progress = function() end,
    refresh_times = function() end,
    clear_runtime_cache = function() end
}

t.install_module("lib.const", const)
t.install_module("lib.log", {error = function() end})
t.install_module("lib.util", util)
t.install_module("model.state", state)
t.install_module("model.tech", {})
t.install_module("model.queue", queue)
t.install_module("model.research_policy", policy)
t.install_module("view.gui.analyzer", {})
t.install_module("view.gui.gutil", gutil)
t.install_module("view.gui.components.tech", noop_tech)
t.install_module("view.gui.components.upcoming", noop_upcoming)

local old_game = _G.game
local old_settings = _G.settings
local old_prototypes = _G.prototypes
local player = {index = 1, force = {index = 7}, admin = true}
_G.game = {
    tick = 7200,
    get_player = function(index)
        return index == player.index and player or nil
    end
}
_G.settings = {global = {["lil_einstein-map-setting"] = {value = false}}}
_G.prototypes = {
    item = {iron_plate = {localised_name = "Iron plate"}},
    entity = {},
    fluid = {}
}

local components = require("view.gui.components")

local function find_private(function_value, wanted, seen)
    if type(function_value) ~= "function" then
        return nil
    end
    seen = seen or {}
    if seen[function_value] then
        return nil
    end
    seen[function_value] = true
    for index = 1, 64 do
        local name, value = debug.getupvalue(function_value, index)
        if not name then
            break
        end
        if name == wanted then
            return value
        end
        local nested = find_private(value, wanted, seen)
        if nested ~= nil then
            return nested
        end
    end
    return nil
end

local function make_static_anchor()
    local anchor = make_element("anchor")
    add_named(anchor, "force_settings_flow")
    add_named(anchor, "allowed_science_table", "table")
    add_named(anchor, "hide_tech_flow")
    add_named(anchor, "show_tech_flow")
    add_named(anchor, "available_tech_lbl", "label")
    add_named(anchor, "enable_row")
    add_named(anchor, "subsettings")
    return anchor
end

local function make_science_pack_anchor()
    local anchor = make_static_anchor()
    local panel = add_named(anchor, "science_pack_panel", "frame")
    panel.visible = true
    for _, name in ipairs({
        "science_pack_panel_icon", "science_pack_panel_name", "science_pack_panel_state",
        "science_pack_panel_current_stock", "science_pack_panel_timer",
        "science_pack_panel_labs_summary", "science_pack_panel_planet_stock_summary",
        "science_pack_panel_transit_summary", "science_pack_panel_flow_balance"
    }) do
        add_named(panel, name, "label")
    end
    local labs = add_named(panel, "science_pack_panel_labs", "frame")
    add_named(labs, "science_pack_panel_labs_rows", "table")
    add_named(labs, "science_pack_panel_labs_empty", "label")
    local planets = add_named(panel, "science_pack_panel_planet_stock", "frame")
    add_named(planets, "science_pack_panel_planet_stock_rows", "table")
    add_named(planets, "science_pack_panel_planet_stock_empty", "label")
    local transit = add_named(panel, "science_pack_panel_transit", "frame")
    add_named(transit, "science_pack_panel_transit_rows", "table")
    add_named(transit, "science_pack_panel_transit_empty", "label")
    return anchor
end

local function make_details_anchor()
    local anchor = make_element("anchor")
    local panel = add_named(anchor, "research_details_panel")
    panel.visible = true
    add_named(panel, "research_details_headline", "label")
    add_named(panel, "research_details_evidence", "label")
    add_named(panel, "research_details_scope_note", "label")
    add_named(panel, "research_details_overlap_note", "label")
    add_named(panel, "research_details_ceiling_hint", "label")
    local header = add_named(panel, "research_details_header", "table")
    for _, name in ipairs({"location", "missing", "labs", "capacity", "cause", "action"}) do
        add_named(header, "research_details_header_" .. name, "label")
    end
    local pane = add_named(panel, "research_details_scroll_pane", "scroll-pane")
    pane.style = {}
    add_named(panel, "research_details_rows")
    local inspection = add_named(panel, "research_lab_inspection_panel", "frame")
    inspection.visible = false
    add_named(inspection, "research_lab_inspection_summary", "label")
    local inspection_header = add_named(inspection, "research_lab_inspection_header", "table")
    for _, name in ipairs({"name", "location", "status", "missing"}) do
        add_named(inspection_header, "research_lab_inspection_header_" .. name, "label")
    end
    add_named(inspection, "research_lab_inspection_empty", "label")
    local inspection_pane = add_named(inspection, "research_lab_inspection_scroll_pane", "scroll-pane")
    inspection_pane.style = {}
    add_named(inspection, "research_lab_inspection_rows", "table")
    local demand = add_named(panel, "research_details_pack_demand")
    local demand_header = add_named(demand, "research_details_pack_demand_header", "table")
    for _, name in ipairs({"science", "maximum", "working", "produced"}) do
        add_named(demand_header, "research_details_pack_demand_header_" .. name, "label")
    end
    add_named(demand, "research_details_pack_demand_rows", "table")
    add_named(demand, "research_details_pack_demand_empty", "label")
    add_named(anchor, "research_graph_spm_value", "label")
    add_named(anchor, "research_health_panel", "frame")
    add_named(anchor, "research_health_state", "label")
    add_named(anchor, "research_health_reason", "label")
    add_named(anchor, "research_graph_remaining_value", "label")
    add_named(anchor, "research_status_bar", "label")
    return anchor
end

local function make_policy_anchor()
    local anchor = make_element("anchor")
    add_named(anchor, "policy_tab_bar")
    add_named(anchor, "policy_tab_automation", "button")
    add_named(anchor, "policy_tab_budget", "button")
    add_named(anchor, "policy_tab_science", "button")
    add_named(anchor, "policy_tab_objectives", "button")
    add_named(anchor, "policy_tab_presets", "button")
    add_named(anchor, "policy_tab_history", "button")
    add_named(anchor, "policy_scroll_pane", "scroll-pane")
    add_named(anchor, "policy_sections_table", "table")
    add_named(anchor, "policy_general_flow_section", "frame")
    add_named(anchor, "policy_budget_flow_section", "frame")
    add_named(anchor, "policy_science_flow_section", "frame")
    add_named(anchor, "policy_trigger_flow_section", "frame")
    add_named(anchor, "policy_preset_flow_section", "frame")
    add_named(anchor, "policy_history_flow_section", "frame")
    add_named(anchor, "policy_general_flow")
    add_named(anchor, "policy_budget_flow")
    add_named(anchor, "policy_science_flow")
    add_named(anchor, "policy_trigger_flow")
    add_named(anchor, "policy_preset_flow")
    add_named(anchor, "policy_history_flow")
    return anchor
end

local tests = {
    {"builds rotating research insights from cached health data", function()
        reset_fixture()

        local insights = components.build_research_status_insights({
            available = true,
            state = "pack_bound",
            material_loss_spm = 198800,
            compatible_labs = 502,
            working_labs = 40,
            missing_sciences = {
                {science = "agricultural-science-pack", labs = 247, lost_spm = 106400},
                {science = "cryogenic-science-pack", labs = 217, lost_spm = 93000}
            }
        }, {
            is_researching = true,
            progress = 0.8843,
            remaining_seconds = 780,
            spm = 28319
        }, {
            live_current_tech = "research-productivity",
            target_tech = "mining-productivity-3",
            temp_tech = "research-productivity"
        }, {
            promethium = {depletion_seconds = 68}
        })

        t.assert_equal(insights[1].kind, "pack_bound")
        t.assert_equal(insights[1].loss_spm, 198800)
        t.assert_equal(insights[1].labs, 462)
        t.assert_equal(insights[2].kind, "missing_pack")
        t.assert_equal(insights[2].science, "agricultural-science-pack")
        t.assert_equal(insights[3].science, "cryogenic-science-pack")
        t.assert_equal(insights[4].kind, "temporary")
        t.assert_equal(insights[5].kind, "science_risk")
        t.assert_equal(insights[6].kind, "progress")
    end},
    {"falls back to a neutral research insight when no research is active", function()
        reset_fixture()

        local insights = components.build_research_status_insights({
            available = false,
            state = "idle"
        }, {
            is_researching = false,
            spm = 0
        }, {}, {})

        t.assert_equal(#insights, 1)
        t.assert_equal(insights[1].kind, "idle")
    end},
    {"refreshes the rotating status bar from cached data", function()
        reset_fixture()
        local anchor = make_details_anchor()
        components.clear_runtime_cache()

        components.refresh_research_status_bar(1, anchor, false)
        t.assert_equal(caption_head(find_element(anchor, "research_status_bar").caption),
                       "lil_einstein-status.pack-bound")
        components.refresh_research_status_bar(1, anchor, true)
        t.assert_equal(caption_head(find_element(anchor, "research_status_bar").caption),
                       "lil_einstein-status.missing-pack")
    end},
    {"renders force settings, science filters, category filters, and styles", function()
        reset_fixture()
        local anchor = make_static_anchor()

        components.repopulate_static(1, anchor)

        local force_flow = find_element(anchor, "force_settings_flow")
        t.assert_equal(force_flow.clear_count, 1)
        t.assert_equal(find_element(force_flow, "requeue_infinite_tech").style_name,
                       "lil_einstein_settings_checkbox_on")
        t.assert_equal(find_element(force_flow, "auto_research").style_name,
                       "lil_einstein_settings_checkbox_off")
        t.assert_equal(find_element(force_flow, "requeue_infinite_tech").tags.setting_name,
                       "requeue_infinite_tech")
        t.assert_equal(find_element(force_flow, "consecutive_tech_cap_value").caption, "4")
        t.assert_false(find_element(force_flow, "lil_einstein-map-setting").state)
        t.assert_false(find_element(force_flow, "lil_einstein-map-setting").enabled)

        local science_table = find_element(anchor, "allowed_science_table")
        t.assert_equal(science_table.clear_count, 1)
        t.assert_equal(#science_table.children, 2)
        local science_a = find_element(science_table, "allowed_science_btn_science_a")
        t.assert_true(science_a.toggled)
        t.assert_equal(science_a.tags.handler, "open_science_pack_details")
        t.assert_nil(find_element(science_table, "allowed_science_count_science_a"))

        local hidden = find_element(anchor, "hide_tech")
        t.assert_true(hidden.state)
        t.assert_equal(hidden.tags.setting_name, "hide_tech")
        local military = find_element(anchor, "military")
        t.assert_equal(military.style_name, "lil_einstein_radio_button_on")
        t.assert_equal(military.tags.value, "military")
        t.assert_equal(find_element(anchor, "available_tech_lbl").style.bottom_margin, 4)
        t.assert_equal(find_element(anchor, "enable_row").style.height, 24)
        t.assert_equal(find_element(anchor, "subsettings").style.top_margin, 16)
    end},
    {"refreshes science counts, labels, and evidence-rich tooltips incrementally", function()
        reset_fixture()
        local anchor = make_static_anchor()
        components.clear_runtime_cache()
        components.repopulate_static(1, anchor)

        science_counts.science_a = 12345
        components.refresh_science_counts(1, anchor)
        local count_label = find_element(anchor, "allowed_science_count_science_a")
        local button = find_element(anchor, "allowed_science_btn_science_a")
        t.assert_equal(count_label.caption, "12345")
        t.assert_true(string.find(button.tooltip, "Localized item science_a", 1, true) ~= nil)
        t.assert_true(string.find(button.tooltip, "Total: 12345", 1, true) ~= nil)
        t.assert_true(string.find(button.tooltip, "In labs: 24 in 3 labs", 1, true) ~= nil)
        t.assert_true(string.find(button.tooltip, "Priority: 2", 1, true) ~= nil)
        t.assert_true(string.find(button.tooltip, "Production / consumption: 1200 / 8 per minute", 1, true) ~= nil)
        t.assert_true(string.find(button.tooltip, "Estimated depletion: 42s", 1, true) ~= nil)
        t.assert_true(string.find(button.tooltip, "main: 12\norbit: 3", 1, true) ~= nil)

        science_breakdown.science_a.networks = {
            {label = "same-b", count = 3},
            {label = "same-a", count = 3}
        }
        components.clear_runtime_cache()
        components.refresh_science_counts(1, anchor, 2)
        components.refresh_science_counts(1, anchor, 2)
        t.assert_equal(find_element(anchor, "allowed_science_count_science_a").caption, "12345")

        science_counts.science_a = 23456
        components.clear_runtime_cache()
        components.refresh_science_counts(1, anchor)
        t.assert_equal(find_element(anchor, "allowed_science_count_science_a").caption, "23456")
        science_counts.science_a = 0
        components.clear_runtime_cache()
        components.refresh_science_counts(1, anchor)
        t.assert_nil(find_element(anchor, "allowed_science_count_science_a"))
        components.refresh_science_counts(1, anchor)
    end},
    {"refreshes the open science-pack panel without rebuilding its root", function()
        reset_fixture()
        local anchor = make_science_pack_anchor()
        components.clear_runtime_cache()

        components.refresh_science_pack_panel(1, anchor)
        local panel = find_element(anchor, "science_pack_panel")
        t.assert_equal(find_element(panel, "science_pack_panel_name").caption,
                       "Localized item science_a")
        t.assert_equal(find_element(panel, "science_pack_panel_labs_summary").caption[1],
                       "lil_einstein-science-pack.labs-summary")
        t.assert_equal(find_element(panel, "science_pack_panel_planet_stock_rows").clear_count, 1)
        t.assert_equal(#find_element(panel, "science_pack_panel_planet_stock_rows").children, 4)
        t.assert_equal(#find_element(panel, "science_pack_panel_transit_rows").children, 4)
        t.assert_equal(find_element(panel, "science_pack_panel_timer").caption[1],
                       "lil_einstein-science-pack.refreshes-in")

        local planet_rows = find_element(panel, "science_pack_panel_planet_stock_rows")
        local first_planet_caption = planet_rows.children[1].caption
        science_pack_insight.planet_stock_rows[1].stock = 99
        components.refresh_science_pack_panel(1, anchor)
        t.assert_equal(planet_rows.clear_count, 1)
        t.assert_equal(first_planet_caption, "Nauvis")
        t.assert_equal(planet_rows.children[2].caption, "99")

        panel.visible = false
        local calls = 0
        local old_insight = queue.get_science_pack_insight
        queue.get_science_pack_insight = function()
            calls = calls + 1
            return science_pack_insight
        end
        components.refresh_science_pack_panel(1, anchor)
        t.assert_equal(calls, 0)
        queue.get_science_pack_insight = old_insight
    end},
    {"renders rich research health metrics and throughput detail rows", function()
        reset_fixture()
        local anchor = make_details_anchor()
        components.clear_runtime_cache()

        components.refresh_research_metrics(1, anchor)

        t.assert_equal(find_element(anchor, "research_graph_spm_value").caption, "1 234")
        t.assert_equal(find_element(anchor, "research_graph_remaining_value").caption, "2m05s")
        t.assert_equal(caption_head(find_element(anchor, "research_health_state").caption),
                       "lil_einstein-throughput.headline-missing-pack")
        t.assert_equal(find_element(anchor, "research_health_state").style.font_color[1], 1.00)
        t.assert_true(type(find_element(anchor, "research_health_panel").tooltip) == "table")
        local health_reason = find_element(anchor, "research_health_reason").caption
        t.assert_equal(health_reason[4][1], "lil_einstein-throughput.inspect-location")

        local panel = find_element(anchor, "research_details_panel")
        local rows = find_element(panel, "research_details_rows")
        t.assert_equal(#rows.children, 1)
        t.assert_equal(rows.children[1].tags.cluster_key, "network-main")
        t.assert_equal(find_element(rows, "research_details_cells_1").style_name,
                       "lil_einstein_throughput_table")
        t.assert_equal(caption_head(find_element(rows, "research_details_location_1").caption),
                       "lil_einstein-throughput.location-network")
        t.assert_equal(find_element(rows, "research_details_location_1").tooltip[2], 12)
        t.assert_equal(caption_head(find_element(rows, "research_details_missing_1").caption),
                       "lil_einstein-throughput.missing-pack-summary")
        t.assert_equal(caption_head(find_element(rows, "research_details_action_1").caption),
                       "lil_einstein-throughput.action-restock")
        t.assert_true(find_element(rows, "research_details_action_detail_1").visible)
        local inspect_labs = find_element(rows, "research_details_inspect_labs_1")
        t.assert_true(inspect_labs.visible)
        t.assert_equal(caption_head(inspect_labs.caption), "lil_einstein-throughput.inspect-labs")
        t.assert_equal(inspect_labs.caption[2], 2)
        t.assert_equal(inspect_labs.tags.handler, "inspect_research_cluster_labs")
        t.assert_equal(inspect_labs.tags.cluster_key, "network-main")
        t.assert_equal(#find_element(rows, "research_details_pack_table_1").children, 10)
        t.assert_equal(#find_element(panel, "research_details_pack_demand_rows").children, 4)
        t.assert_true(find_element(panel, "research_details_pack_demand_header").visible)
        t.assert_false(find_element(panel, "research_details_pack_demand_empty").visible)

        components.show_research_lab_inspection(1, anchor, "network-main")
        local inspection = find_element(panel, "research_lab_inspection_panel")
        t.assert_true(inspection.visible)
        t.assert_false(find_element(panel, "research_details_headline").visible)
        t.assert_equal(#find_element(inspection, "research_lab_inspection_rows").children, 8)
        t.assert_equal(caption_head(find_element(inspection, "research_lab_inspection_summary").caption),
                       "lil_einstein-throughput.inspect-labs-summary")
        t.assert_equal(find_element(inspection, "research_lab_inspection_name_1").caption[3], 101)
        components.hide_research_lab_inspection(1, anchor)
        t.assert_false(inspection.visible)
        t.assert_true(find_element(panel, "research_details_headline").visible)

        research_diagnostic.state = "at_capacity"
        components.refresh_research_metrics(1, anchor)
        t.assert_true(find_element(panel, "research_details_ceiling_hint").visible)
        t.assert_equal(caption_head(find_element(anchor, "research_health_state").caption),
                       "lil_einstein-throughput.headline-output")

        for _, kind in ipairs({"power", "disabled", "frozen", "no_labs", "no_compatible_labs", "no_capacity"}) do
            research_diagnostic = {
                state = "operational_fault",
                available = true,
                actual_spm = 12,
                expected_spm = 80,
                material_loss_spm = 68,
                dominant_cause = {kind = kind, labs = 1, lost_spm = 68},
                causes = {{kind = kind, lost_spm = 68, labs = 1}},
                clusters = {},
                missing_sciences = {},
                science_pack_rates = {}
            }
            components.refresh_research_metrics(1, anchor)
        end
        research_diagnostic = {
            state = "measuring", available = true, expected_spm = 80, actual_spm = 0,
            causes = {}, clusters = {}, missing_sciences = {}, science_pack_rates = {}
        }
        components.refresh_research_metrics(1, anchor)
        research_diagnostic.state = "degraded_unexplained"
        components.refresh_research_metrics(1, anchor)
        research_diagnostic.available = false
        components.refresh_research_metrics(1, anchor)

        local direct_cluster = {
            key = "direct",
            scope = "direct",
            surface_name = "Nauvis",
            compatible_labs = 0,
            incompatible_labs = 1,
            causes = {},
            missing_sciences = {},
            science_pack_rates = {},
            lost_spm = 0
        }
        research_diagnostic = {
            state = "operational_fault", available = true, actual_spm = 0, expected_spm = 0,
            dominant_cause = {kind = "no_compatible_labs", labs = 1, lost_spm = 0},
            causes = {}, missing_sciences = {}, science_pack_rates = {},
            clusters = {direct_cluster}, dominant_cluster_key = "direct"
        }
        components.refresh_research_metrics(1, anchor)
        research_diagnostic.clusters = {}
        components.refresh_research_metrics(1, anchor)

        local many_causes = {}
        for index = 1, 25 do
            many_causes[index] = {kind = "power", labs = 1, lost_spm = index}
        end
        research_diagnostic.available = true
        research_diagnostic.state = "pack_bound"
        research_diagnostic.dominant_missing_science = nil
        research_diagnostic.dominant_cause = {kind = "missing_science", labs = 1, lost_spm = 25}
        research_diagnostic.causes = many_causes
        components.refresh_research_metrics(1, anchor)
    end},
    {"classifies throughput rows by need, use, production, and gap", function()
        local diagnostic = {
            science_pack_rates = {
                {science = "science_a", maximum_per_minute = 100, working_per_minute = 100},
                {science = "science_b", maximum_per_minute = 100, working_per_minute = 40},
                {science = "science_c", maximum_per_minute = 100, working_per_minute = 100},
                {science = "science_d", maximum_per_minute = 0, working_per_minute = 0}
            },
            dominant_missing_science = {science = "science_b"}
        }
        local forecast = {
            science_a = {production_per_minute = 70},
            science_b = {production_per_minute = 40},
            science_c = {production_per_minute = 140},
            science_d = {production_per_minute = 0}
        }
        local rows = components.build_science_throughput_rows(
            {"science_a", "science_b", "science_c", "science_d"}, diagnostic, forecast)
        local by_science = {}
        for _, row in ipairs(rows) do
            by_science[row.science] = row
        end
        t.assert_equal(rows[1].science, "science_b")
        t.assert_equal(by_science.science_a.status, "bottleneck")
        t.assert_equal(by_science.science_a.need, 100)
        t.assert_equal(by_science.science_a.used, 100)
        t.assert_equal(by_science.science_a.produced, 70)
        t.assert_equal(by_science.science_a.gap, -30)
        t.assert_equal(by_science.science_b.status, "starving")
        t.assert_equal(by_science.science_c.status, "overproducing")
        t.assert_equal(by_science.science_d.status, "balanced")
    end},
    {"does not apply label-only style properties to the inspect button", function()
        reset_fixture()
        local anchor = make_details_anchor()
        reject_button_single_line = true
        local ok, err = pcall(function()
            components.refresh_research_details(1, anchor)
        end)
        reject_button_single_line = false
        t.assert_true(ok, err)
        local inspect_labs = find_element(anchor, "research_details_inspect_labs_1")
        t.assert_equal(inspect_labs.style.width, 415)
    end},
    {"creates throughput row cells with their initial captions", function()
        reset_fixture()
        local anchor = make_details_anchor()

        components.refresh_research_details(1, anchor)

        local rows = find_element(anchor, "research_details_rows")
        t.assert_equal(caption_head(find_element(rows, "research_details_location_1").initial_caption),
                       "lil_einstein-throughput.location-network")
        t.assert_equal(caption_head(find_element(rows, "research_details_missing_1").initial_caption),
                       "lil_einstein-throughput.missing-pack-summary")
        t.assert_equal(caption_head(find_element(rows, "research_details_labs_1").initial_caption),
                       "lil_einstein-throughput.labs-cell")
        t.assert_equal(caption_head(find_element(rows, "research_details_capacity_1").initial_caption),
                       "lil_einstein-throughput.capacity-cell")
    end},
    {"rebuilds details rows that predate the lab inspection controls", function()
        reset_fixture()
        local anchor = make_details_anchor()
        local rows = find_element(anchor, "research_details_rows")
        rows.add({
            type = "frame",
            name = "research_details_row_1",
            tags = {cluster_key = "network-main"}
        })
        components.clear_runtime_cache()

        components.refresh_research_details(1, anchor)

        local rebuilt = find_element(rows, "research_details_inspect_labs_1")
        t.assert_true(rebuilt ~= nil)
        t.assert_equal(caption_head(find_element(rows, "research_details_location_1").caption),
                       "lil_einstein-throughput.location-network")
    end},
    {"renders the research graph incrementally and updates hover markers", function()
        reset_fixture()
        research_summary.spm = 2000000
        research_summary.remaining_seconds = nil
        research_history = {3000000, -10, 2000000}
        local anchor = make_element("anchor")
        for index = 1, 8 do
            add_named(anchor, "research_graph_axis_" .. index, "label")
        end
        local plot = add_named(anchor, "research_graph_plot")
        local overlay = add_named(anchor, "research_graph_hover_overlay")

        components.refresh_research_graph(1, anchor)
        t.assert_equal(#plot.children, 200)
        t.assert_equal(#overlay.children, 200)
        for _ = 1, 6 do
            components.tick_research_graph(1, anchor)
        end
        local column = find_element(overlay, "research_graph_hover_column_2")
        components.show_research_graph_hover(1, anchor, 2)
        t.assert_true(find_element(column, "research_graph_hover_dot_2").visible)
        t.assert_true(type(column.tooltip) == "table")
        components.show_research_graph_hover(1, anchor, 0)
        components.hide_research_graph_hover(1, anchor)
        t.assert_equal(state_writes.research_graph_hover_column, "cleared")

        research_history = {}
        research_history_has_data = false
        components.refresh_research_graph(1, anchor)
        for _ = 1, 6 do
            components.tick_research_graph(1, anchor)
        end

        local no_plot = make_element("anchor-no-plot")
        components.refresh_research_graph(1, no_plot)
        components.tick_research_graph(1, no_plot)
        components.show_research_graph_hover(1, no_plot, 1)
        components.show_research_graph_hover(1, nil, 1)
    end},
    {"covers graph helper guards and diagnostic action fallbacks", function()
        reset_fixture()
        local set_spacer = find_private(components.tick_research_graph, "set_research_graph_spacer")
        local set_segment = find_private(components.tick_research_graph, "set_research_graph_segment")
        local set_marker = find_private(components.show_research_graph_hover, "set_research_graph_hover_marker")
        local get_action = find_private(components.refresh_research_details, "get_diagnostic_action")
        local get_causes = find_private(components.refresh_research_details, "get_cluster_causes_caption")
        local set_width = find_private(components.refresh_research_details, "set_details_cell_width")
        local get_missing = find_private(components.refresh_research_details, "get_cluster_missing_pack")
        local refresh_demand = find_private(components.refresh_research_details, "refresh_research_pack_demand_table")
        local refresh_pack = find_private(components.refresh_research_details, "refresh_research_pack_table")
        local format_time = find_private(components.refresh_research_metrics, "format_time")
        local format_axis = find_private(components.refresh_research_graph, "format_axis_value")
        local get_axis_max = find_private(components.refresh_research_graph, "get_axis_max")
        local get_ratio = find_private(components.refresh_research_graph, "get_research_graph_ratio")
        local format_policy_time = find_private(components.repopulate_policy, "format_policy_time")
        local refresh_science_counts = find_private(components.refresh_science_counts, "refresh_science_counts")
        t.assert_true(type(set_spacer) == "function")
        t.assert_true(type(set_segment) == "function")
        t.assert_true(type(set_marker) == "function")
        t.assert_true(type(get_action) == "function")

        t.assert_equal(format_time(nil), "--")
        t.assert_equal(format_time(42), "42s")
        t.assert_equal(format_axis(12), "12")
        t.assert_equal(format_axis(0), "0")
        t.assert_equal(get_axis_max({}, 0), 1000)
        t.assert_equal(get_ratio(1, 0), 0)
        t.assert_equal(get_ratio(2, 1), 1)
        t.assert_equal(get_ratio(-1, 1), 0)
        t.assert_equal(format_policy_time(60), "1.0m")
        t.assert_equal(format_policy_time(math.huge), "∞")
        t.assert_true(type(refresh_science_counts) == "function")

        local science_anchor = make_static_anchor()
        for _ = 1, 5 do
            refresh_science_counts(1, science_anchor, 1)
        end

        set_spacer(nil, 10)
        local spacer = make_element("spacer")
        spacer.visible = false
        set_spacer(spacer, 8)
        set_spacer(spacer, 8)
        set_spacer(spacer, 0)
        set_spacer(spacer, 0)

        set_segment(nil, 1, 1)
        local segment = make_element("segment")
        segment.visible = true
        segment.value = 0
        set_segment(segment, 4, 3)
        set_segment(segment, 4, 0)
        set_marker(nil, 1, 0, 100)
        set_marker(make_element("empty-column"), 1, 0, 100)

        for _, kind in ipairs({"missing_science", "power", "disabled", "frozen", "no_labs",
                               "no_compatible_labs", "no_capacity", "other"}) do
            get_action({dominant_cause = {kind = kind}}, nil)
        end
        get_action(nil, {incompatible_labs = 1, compatible_labs = 0, causes = {}})
        get_action({state = "at_capacity"}, nil)
        get_action({state = "measuring"}, nil)
        get_causes({causes = {}, incompatible_labs = 0, compatible_labs = 0})
        get_causes({causes = {}, incompatible_labs = 1, compatible_labs = 0})
        get_causes({causes = {{kind = "other", labs = 1, lost_spm = 2}}})
        set_width(nil, 10)
        get_missing({}, "missing")

        local demand_panel = make_element("demand-panel")
        add_named(demand_panel, "research_details_pack_demand")
        refresh_demand(demand_panel, {science_pack_rates = {}, expected_spm = 0}, {})
        refresh_pack(make_element("pack-cell"), {}, 1)
        local progress_anchor = make_details_anchor()
        add_named(progress_anchor, "research_graph_progress_value", "label")
        components.refresh_research_progress(1, progress_anchor)
        components.refresh_research_details(99, progress_anchor)
    end},
    {"populates policy controls, science forecasts, budgets, triggers, presets, and history", function()
        reset_fixture()
        local anchor = make_policy_anchor()

        components.repopulate_policy(1, anchor)

        t.assert_equal(find_element(anchor, "policy_general_flow_section").visible, true)
        t.assert_equal(find_element(anchor, "policy_budget_flow_section").visible, false)
        t.assert_equal(find_element(anchor, "policy_tab_automation").enabled, false)
        t.assert_equal(find_element(anchor, "policy_tab_budget").enabled, true)

        local general = find_element(anchor, "policy_general_flow")
        t.assert_equal(general.clear_count, 1)
        local strategy = find_by_tag(general, "handler", "policy_strategy")
        t.assert_equal(strategy.selected_index, 2)
        t.assert_equal(strategy.items[2][1], "lil_einstein-strategy.throughput")
        local paused = find_by_tag(general, "setting_name", "planning_paused")
        t.assert_equal(paused.style_name, "lil_einstein_settings_checkbox_off")
        t.assert_true(find_by_tag(general, "setting_name", "replan_interval_seconds") ~= nil)
        t.assert_true(find_by_tag(general, "setting_name", "instant_switch_override") ~= nil)
        t.assert_true(find_by_tag(general, "setting_name", "reserve_for_type") ~= nil)
        t.assert_true(find_by_tag(general, "setting_name", "plan_horizon_minutes") ~= nil)
        t.assert_equal(find_by_tag(general, "setting_name", "finish_current_threshold"), nil)

        local science_flow = find_element(anchor, "policy_science_flow")
        t.assert_equal(#science_flow.children, 2)
        local priority = find_by_tag(science_flow, "handler", "cycle_science_priority")
        t.assert_equal(priority.caption[1], "lil_einstein-science-priority.2")
        local rates = find_element(science_flow, "")
        t.assert_true(rates == nil or rates.valid)
        local rate_caption
        for _, child in ipairs(science_flow.children[1].children) do
            if type(child.caption) == "string" and string.find(child.caption, "runtime 42s", 1, true) then
                rate_caption = child.caption
            end
        end
        t.assert_true(rate_caption ~= nil)

        local budget = find_element(anchor, "policy_budget_flow")
        t.assert_equal(caption_head(budget.children[1].caption), "lil_einstein-policy.budget-summary")
        t.assert_equal(caption_head(budget.children[2].caption), "lil_einstein-policy.budget-repeat-truncated")
        t.assert_equal(budget.children[3].caption[2][1], "lil_einstein-policy.limiting-science")
        t.assert_equal(#budget.children, 5)

        local trigger = find_by_tag(anchor, "handler", "show_trigger_technology")
        t.assert_equal(trigger.tags.technology, "rocket-silo")
        t.assert_true(type(trigger.tooltip) == "table")
        local preset = find_element(anchor, "policy_preset_name")
        t.assert_equal(preset.text, "night-plan")
        t.assert_equal(find_element(anchor, "policy_exchange_string").tags.handler, "policy_exchange_string")
        t.assert_equal(find_element(anchor, "policy_history_flow").children[2].children[1].tags.setting_name,
                       "multiplayer_lock")
        t.assert_equal(find_by_tag(find_element(anchor, "policy_history_flow"), "handler", "policy_history_filter") ~= nil,
                       true)
        t.assert_equal(#find_element(anchor, "policy_history_flow").children, 4)

        queue_budget.repeat_unbounded = true
        queue_budget.repeat_truncated = false
        queue_budget.limiting_science = nil
        queue_budget.sciences = {}
        components.repopulate_policy(1, anchor)
        t.assert_equal(caption_head(find_element(anchor, "policy_budget_flow").children[2].caption),
                       "lil_einstein-policy.budget-repeat-unbounded")

        prototypes.entity.assembler = {localised_name = "Assembler"}
        prototypes.fluid.water = {localised_name = "Water"}
        prototypes.item.space_platform_starter_pack = {localised_name = "Starter pack"}
        trigger_objectives = {
            {tech_name = "craft-one", ready = true, trigger_type = "craft-item",
                xcur = {technology = {localised_name = "Craft one"}, meta = {prototype = {research_trigger =
                    {type = "craft-item", item = "iron-plate", count = 1}}}}},
            {tech_name = "craft-many", ready = false, trigger_type = "craft-item",
                xcur = {technology = {localised_name = "Craft many"}, meta = {prototype = {research_trigger =
                    {type = "craft-item", item = "iron-plate", count = 2}}}}},
            {tech_name = "mine", ready = true, trigger_type = "mine-entity",
                xcur = {technology = {localised_name = "Mine"}, meta = {prototype = {research_trigger =
                    {type = "mine-entity", entity = "assembler"}}}}},
            {tech_name = "fluid", ready = true, trigger_type = "craft-fluid",
                xcur = {technology = {localised_name = "Fluid"}, meta = {prototype = {research_trigger =
                    {type = "craft-fluid", fluid = "water", amount = 3}}}}},
            {tech_name = "build", ready = true, trigger_type = "build-entity",
                xcur = {technology = {localised_name = "Build"}, meta = {prototype = {research_trigger =
                    {type = "build-entity", entity = "assembler"}}}}},
            {tech_name = "orbit", ready = true, trigger_type = "send-item-to-orbit",
                xcur = {technology = {localised_name = "Orbit"}, meta = {prototype = {research_trigger =
                    {type = "send-item-to-orbit", item = "space_platform_starter_pack"}}}}},
            {tech_name = "capture", ready = true, trigger_type = "capture-spawner",
                xcur = {technology = {localised_name = "Capture"}, meta = {prototype = {research_trigger =
                    {type = "capture-spawner", entity = "assembler"}}}}},
            {tech_name = "capture-any", ready = true, trigger_type = "capture-spawner",
                xcur = {technology = {localised_name = "Capture any"}, meta = {prototype = {research_trigger =
                    {type = "capture-spawner"}}}}},
            {tech_name = "platform", ready = true, trigger_type = "create-space-platform",
                xcur = {technology = {localised_name = "Platform"}, meta = {prototype = {research_trigger =
                    {type = "create-space-platform"}}}}},
            {tech_name = "scripted", ready = true, trigger_type = "scripted",
                xcur = {technology = {localised_name = "Scripted"}, meta = {prototype = {research_trigger =
                    {type = "scripted", trigger_description = "Do the thing"}}}}},
            {tech_name = "unknown", ready = false, trigger_type = "unknown",
                xcur = {technology = {localised_name = "Unknown"}, meta = {prototype = {research_trigger =
                    {type = "mystery"}}}}},
            {tech_name = "no-trigger", ready = false, trigger_type = "unknown",
                xcur = {technology = {localised_name = "No trigger"}, meta = {prototype = {research_trigger = nil}}}
            }
        }
        components.repopulate_policy(1, anchor)
        t.assert_equal(#find_element(anchor, "policy_trigger_flow").children, 12)
        trigger_objectives = {}
        components.repopulate_policy(1, anchor)
        t.assert_equal(#find_element(anchor, "policy_trigger_flow").children, 1)
        policy_history = {}
        components.repopulate_policy(1, anchor)
        t.assert_equal(#find_element(anchor, "policy_history_flow").children, 3)

        science_forecast.science_a.depletion_seconds = math.huge
        science_forecast.science_b.recovery_seconds = 7200
        components.repopulate_policy(1, anchor)
        t.assert_true(#find_element(anchor, "policy_science_flow").children > 0)
        components.repopulate_all(1, anchor)
    end},
    {"guards panel-specific refreshes and toggles the master enable state", function()
        reset_fixture()
        local anchor = make_element("anchor")
        local policy_panel = add_named(anchor, "policy_panel", "frame")
        policy_panel.visible = true
        local details_panel = add_named(anchor, "research_details_panel", "frame")
        details_panel.visible = false
        local force_flow = add_named(anchor, "force_settings_flow")
        local master = add_named(anchor, "master_enable", "switch")
        local queue_pane = add_named(anchor, "queue_pane")
        local upcoming = add_named(anchor, "frame_upcoming")
        local right = add_named(anchor, "right")

        components.repopulate_static(1, anchor)
        components.repopulate_dynamic(1, anchor)
        components.refresh_science_counts(1, anchor)
        components.refresh_research_status(1, anchor)
        components.refresh_research_metrics(1, anchor)
        t.assert_equal(force_flow.clear_count, 0)
        t.assert_equal(#queue_pane.children, 0)
        t.assert_equal(#upcoming.children, 0)
        t.assert_equal(master.switch_state, nil)

        policy_panel.visible = false
        force_settings.master_enable = "left"
        components.refresh_master_enable(1, anchor)
        t.assert_equal(master.switch_state, "left")
        t.assert_false(queue_pane.enabled)
        t.assert_false(upcoming.enabled)
        t.assert_false(right.enabled)

        force_settings.master_enable = "right"
        components.refresh_master_enable(1, anchor)
        t.assert_equal(master.switch_state, "right")
        t.assert_true(queue_pane.enabled)
        t.assert_true(upcoming.enabled)
        t.assert_true(right.enabled)

        details_panel.visible = true
        local before = force_flow.clear_count
        components.refresh_master_enable(1, anchor)
        t.assert_equal(force_flow.clear_count, before)

        local sprite_anchor = make_element("sprite-anchor")
        local sprite_switch = add_named(sprite_anchor, "master_enable", "button")
        local sprite_label = add_named(sprite_anchor, "master_enable_label", "label")
        sprite_label.style = nil
        sprite_label._style = {}
        setmetatable(sprite_label, {
            __index = function(element, key)
                if key == "style" then
                    return rawget(element, "_style")
                end
                return rawget(element, key)
            end,
            __newindex = function(element, key, value)
                if key == "style" and type(value) == "string" then
                    rawget(element, "_style").style_name = value
                else
                    rawset(element, key, value)
                end
            end
        })
        add_named(sprite_anchor, "queue_pane")
        add_named(sprite_anchor, "frame_upcoming")
        add_named(sprite_anchor, "right")
        force_settings.master_enable = nil
        components.refresh_master_enable(1, sprite_anchor)
        t.assert_true(sprite_switch.toggled)

        local left_anchor = make_element("left-anchor")
        local left_switch = add_named(left_anchor, "master_enable", "button")
        local left_label = add_named(left_anchor, "master_enable_label", "label")
        left_label.style = nil
        left_label._style = {}
        setmetatable(left_label, getmetatable(sprite_label))
        add_named(left_anchor, "queue_pane")
        add_named(left_anchor, "frame_upcoming")
        add_named(left_anchor, "right")
        force_settings.master_enable = "left"
        components.refresh_master_enable(1, left_anchor)
        t.assert_false(left_switch.toggled)
    end}
}

reset_fixture()
local passed = t.run("components_behavior_spec", tests)
for _, name in ipairs(module_names) do
    package.preload[name] = original_preloads[name]
    package.loaded[name] = original_loaded[name]
end
_G.game = old_game
_G.settings = old_settings
_G.prototypes = old_prototypes
return passed
