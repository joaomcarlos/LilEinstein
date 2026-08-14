package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local names = {
    "lib.const", "lib.log", "lib.util", "model.state", "model.tech", "model.queue",
    "model.research_policy", "view.gui.analyzer", "view.gui.gutil",
    "view.gui.components.tech", "view.gui.components.upcoming", "view.gui.components"
}
local original_preloads = {}
for _, name in ipairs(names) do
    original_preloads[name] = package.preload[name]
    package.loaded[name] = nil
end

local calls = {}
local force_settings = {}
local player_settings = {
    allowed_science_a = true,
    science_pack_panel_science = "science_a",
    show_tech_filter_category = "military"
}
local research_summary
local research_history = {}
local next_element_index = 0

local function reset_calls()
    for key in pairs(calls) do
        calls[key] = nil
    end
end

local function make_element(name)
    next_element_index = next_element_index + 1
    local element = {
        name = name,
        index = next_element_index,
        valid = true,
        visible = true,
        style = {},
        children = {},
        clear_count = 0
    }
    local named_children = {}

    function element.add(prop)
        local child = make_element(prop.name)
        child.type = prop.type
        for key, value in pairs(prop) do
            if key ~= "name" and key ~= "type" then
                if key == "style" then
                    child.style_name = value
                else
                    child[key] = value
                end
            end
        end
        table.insert(element.children, child)
        if prop.name then
            element[prop.name] = child
            named_children[prop.name] = true
        end
        return child
    end

    function element.clear()
        element.clear_count = element.clear_count + 1
        element.children = {}
        for child_name in pairs(named_children) do
            element[child_name] = nil
        end
        named_children = {}
    end

    return element
end

local function make_graph_segment(name, segment_type)
    local segment = make_element(name)
    segment.type = segment_type or "label"
    segment.visible = true
    return segment
end

local function make_graph_plot(name, overlay)
    local element = make_element(name)
    for _ = 1, 200 do
        table.insert(element.children, {})
    end

    local column = make_element(name .. "_column_1")
    column[name .. "_spacer_1"] = make_graph_segment(name .. "_spacer_1")
    column[name .. "_vertical_before_1"] = make_graph_segment(name .. "_vertical_before_1")
    column[name .. "_horizontal_1"] = make_graph_segment(name .. "_horizontal_1", "progressbar")
    column[name .. "_vertical_after_1"] = make_graph_segment(name .. "_vertical_after_1")
    element[name .. "_column_1"] = column

    if overlay then
        local hover_column = make_element("research_graph_hover_column_1")
        hover_column["research_graph_hover_line_before_1"] = make_graph_segment("hover_before_1")
        hover_column["research_graph_hover_dot_1"] = make_graph_segment("hover_dot_1")
        hover_column["research_graph_hover_line_after_1"] = make_graph_segment("hover_after_1")
        element["research_graph_hover_column_1"] = hover_column
    end
    return element
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
            global_settings = {},
            master_enable = "right"
        },
        player = {
            hide_tech = {hidden = false},
            show_tech = {selected = "all"}
        }
    }
}

local util = {
    get_all_sciences = function()
        return {"science_a", "science_b"}
    end
}

local state = {
    get_force_setting = function(_, setting_name, default)
        if force_settings[setting_name] ~= nil then
            return force_settings[setting_name]
        end
        return default
    end,
    get_player_setting = function(_, setting_name, default)
        if player_settings[setting_name] ~= nil then
            return player_settings[setting_name]
        end
        return default
    end,
    set_player_setting = function(_, setting_name, value)
        player_settings[setting_name] = value
        calls.last_player_setting = setting_name .. "=" .. tostring(value)
    end,
    clear_player_setting = function(_, setting_name)
        player_settings[setting_name] = nil
        calls.last_cleared_setting = setting_name
    end,
    get_translation = function(_, _, name)
        return "translated:" .. name
    end
}

local queue = {
    get_research_summary = function()
        return research_summary
    end,
    get_research_history = function()
        calls.history = (calls.history or 0) + 1
        return research_history, true
    end,
    get_research_display_diagnostic = function()
        return {state = "idle", clusters = {}}
    end,
    get_science_display_counts = function()
        return {science_a = 1234, science_b = 0}
    end,
    get_science_display_breakdown = function()
        return {lab_count = 12, lab_entity_count = 2, network_total = 34, networks = {}}
    end,
    get_science_display_forecast = function()
        return {
            science_a = {production_per_minute = 12, consumption_per_minute = 8},
            science_b = {production_per_minute = 0, consumption_per_minute = 0}
        }
    end,
    get_queue_budget = function()
        return {technology_count = 0, total_seconds = 0, unlock_count = 0, sciences = {}}
    end,
    get_trigger_objectives = function()
        return {}
    end,
    get_preset_names = function()
        return {}
    end,
    get_research_health_snapshot_tick = function()
        return 0
    end
}

local policy = {
    strategy_order = {"balanced"},
    get_setting = function(_, setting_name)
        if setting_name == "strategy" then
            return "balanced"
        elseif setting_name == "performance_mode" then
            return false
        elseif setting_name == "planning_paused" or setting_name == "parallel_research" or
            setting_name == "cluster_mode" then
            return false
        elseif setting_name == "min_switch_seconds" then
            return 30
        elseif setting_name == "forecast_seconds" then
            return 60
        elseif setting_name == "parallel_slots" then
            return 1
        end
        return false
    end,
    get_science_policy = function()
        return {priority = 2, lower_threshold = 0.2, upper_threshold = 0.8}
    end,
    parallel_mod_available = function()
        return false
    end,
    get_history = function()
        return {}
    end
}

local gutil = {
    get_child = function(anchor, child_name)
        return anchor and anchor[child_name]
    end,
    format_cost = function(value)
        return tostring(value or 0)
    end,
    format_si = function(value)
        return tostring(value or 0)
    end,
    format_time = function(value)
        return tostring(value or 0) .. "s"
    end,
    disenable_recursive = function(element, enabled)
        if element then
            element.enabled = enabled
        end
    end
}

local components_tech = {
    populate = function()
        calls.tech_populate = (calls.tech_populate or 0) + 1
    end
}

local components_upcoming = {
    populate = function()
        calls.upcoming_populate = (calls.upcoming_populate or 0) + 1
    end,
    request_populate = function()
        calls.upcoming_request = (calls.upcoming_request or 0) + 1
        return "request-result"
    end,
    tick_populate = function()
        calls.upcoming_tick = (calls.upcoming_tick or 0) + 1
        return "tick-result"
    end,
    refresh_times = function()
        calls.upcoming_times = (calls.upcoming_times or 0) + 1
    end,
    refresh_progress = function()
        calls.upcoming_progress = (calls.upcoming_progress or 0) + 1
    end,
    clear_runtime_cache = function()
        calls.upcoming_clear = (calls.upcoming_clear or 0) + 1
    end
}

t.install_module("lib.const", const)
t.install_module("lib.log", {error = function() calls.logged_error = true end})
t.install_module("lib.util", util)
t.install_module("model.state", state)
t.install_module("model.tech", {})
t.install_module("model.queue", queue)
t.install_module("model.research_policy", policy)
t.install_module("view.gui.analyzer", {})
t.install_module("view.gui.gutil", gutil)
t.install_module("view.gui.components.tech", components_tech)
t.install_module("view.gui.components.upcoming", components_upcoming)

local player = {index = 1, force = {index = 7}, admin = true}
game = {
    tick = 600,
    get_player = function(index)
        return index == player.index and player or nil
    end
}
settings = {global = {}}
prototypes = {item = {}, entity = {}, fluid = {}}

local content = require("view.gui.components")

local function make_anchor()
    local anchor = make_element("anchor")
    anchor.policy_panel = {visible = false}
    anchor.research_details_panel = {visible = false}
    return anchor
end

local tests = {
    {"forwards component populate, refresh, and clear operations", function()
        reset_calls()
        research_summary = nil
        local anchor = make_anchor()

        content.repopulate_dynamic(1, anchor)
        content.repopulate_tech(1, anchor)
        content.refresh_upcoming(1, anchor)
        t.assert_equal(content.request_upcoming(1, anchor), "request-result")
        t.assert_equal(content.tick_upcoming(1, anchor), "tick-result")
        content.refresh_upcoming_times(1, anchor)

        research_summary = {done = 1, total = 2, spm = 10, remaining_seconds = 30}
        content.refresh_research_progress(1, anchor)
        content.clear_runtime_cache()

        t.assert_equal(calls.tech_populate, 2)
        t.assert_equal(calls.upcoming_populate, 2)
        t.assert_equal(calls.upcoming_request, 1)
        t.assert_equal(calls.upcoming_tick, 1)
        t.assert_equal(calls.upcoming_times, 1)
        t.assert_equal(calls.upcoming_progress, 1)
        t.assert_equal(calls.upcoming_clear, 1)
    end},
    {"switches active tabs and suppresses incompatible refreshes", function()
        reset_calls()
        research_summary = nil

        local policy_anchor = make_anchor()
        policy_anchor.policy_panel.visible = true
        content.repopulate_static(1, policy_anchor)
        content.repopulate_dynamic(1, policy_anchor)
        content.repopulate_tech(1, policy_anchor)
        content.refresh_upcoming(1, policy_anchor)
        t.assert_true(content.request_upcoming(1, policy_anchor))
        t.assert_true(content.tick_upcoming(1, policy_anchor))
        t.assert_nil(calls.tech_populate)
        t.assert_nil(calls.upcoming_populate)

        local details_anchor = make_anchor()
        details_anchor.research_details_panel.visible = true
        content.repopulate_static(1, details_anchor)
        content.repopulate_dynamic(1, details_anchor)
        content.repopulate_tech(1, details_anchor)
        content.refresh_upcoming(1, details_anchor)
        content.refresh_master_enable(1, details_anchor)
        t.assert_equal(calls.tech_populate, 1)
        t.assert_equal(calls.upcoming_populate, 1)
    end},
    {"repopulates science and category filter state from player settings", function()
        reset_calls()
        local anchor = make_anchor()
        anchor.force_settings_flow = make_element("force_settings_flow")
        anchor.allowed_science_table = make_element("allowed_science_table")
        anchor.hide_tech_flow = make_element("hide_tech_flow")
        anchor.show_tech_flow = make_element("show_tech_flow")
        anchor.available_tech_lbl = make_element("available_tech_lbl")
        anchor.enable_row = make_element("enable_row")
        anchor.subsettings = make_element("subsettings")

        content.repopulate_static(1, anchor)

        t.assert_equal(anchor.force_settings_flow.clear_count, 1)
        t.assert_equal(anchor.allowed_science_table.clear_count, 1)
        t.assert_equal(#anchor.allowed_science_table.children, 2)
        local science_a = anchor.allowed_science_table.children[1]
        t.assert_true(science_a.allowed_science_btn_science_a.toggled)
        t.assert_equal(science_a.allowed_science_count_science_a.caption, "1234")
        t.assert_equal(anchor.hide_tech_flow.clear_count, 1)
        t.assert_equal(anchor.show_tech_flow.clear_count, 1)

        local selected_row
        for _, row in ipairs(anchor.show_tech_flow.children) do
            if row.military then
                selected_row = row
                break
            end
        end
        t.assert_true(selected_row ~= nil)
        t.assert_equal(selected_row.military.style_name, "lil_einstein_radio_button_on")
        t.assert_equal(anchor.available_tech_lbl.style.bottom_margin, 4)
        t.assert_equal(anchor.enable_row.style.height, 24)
    end},
    {"runs bounded research graph jobs through refresh and tick", function()
        reset_calls()
        content.clear_runtime_cache()
        research_summary = {done = 1, total = 2, spm = 120, remaining_seconds = 30}
        research_history = {[1] = 10}

        local anchor = make_anchor()
        anchor.research_graph_plot = make_graph_plot("research_graph", false)
        anchor.research_graph_hover_overlay = make_graph_plot("research_graph_hover", true)
        content.refresh_research_graph(1, anchor)
        t.assert_equal(calls.history, 1)
        t.assert_nil(calls.last_cleared_setting)

        for _ = 1, 4 do
            content.tick_research_graph(1, anchor)
        end
        t.assert_equal(calls.last_cleared_setting, "research_graph_hover_column")

        local invalid_anchor = make_anchor()
        invalid_anchor.research_graph_plot = make_graph_plot("research_graph", false)
        invalid_anchor.research_graph_hover_overlay = make_graph_plot("research_graph_hover", true)
        content.refresh_research_graph(1, invalid_anchor)
        invalid_anchor.valid = false
        content.tick_research_graph(1, invalid_anchor)
    end},
    {"guards invalid players and anchors on context-dependent refreshes", function()
        reset_calls()
        research_summary = nil
        t.assert_nil(content.refresh_science_counts(99, nil))
        t.assert_nil(content.refresh_research_status(99, nil))
        t.assert_nil(content.refresh_research_progress(99, nil))
        t.assert_nil(content.refresh_research_metrics(99, nil))
        t.assert_nil(content.refresh_research_details(99, nil))
        t.assert_nil(content.refresh_research_graph(99, nil))
        t.assert_nil(content.repopulate_static(99, nil))
        t.assert_nil(content.refresh_master_enable(99, nil))
        content.show_research_graph_hover(99, nil, 0)
        content.hide_research_graph_hover(99, nil)
        t.assert_nil(calls.tech_populate)
        t.assert_nil(calls.upcoming_populate)
    end}
}

local passed = t.run("components_facade_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original_preloads[name]
    package.loaded[name] = nil
end
game = nil
settings = nil
prototypes = nil
return passed
