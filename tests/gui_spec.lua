package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local names = {"view.gui.gutil", "model.state", "lib.const", "view.gui.builder", "view.gui.components", "view.gui.debug_report", "view.gui"}
local original = {}
for _, name in ipairs(names) do
    original[name] = package.preload[name]
    package.loaded[name] = nil
end

local settings = {}
local calls = {}
local components = {}
for _, name in ipairs({
    "clear_runtime_cache", "repopulate_all", "repopulate_policy", "refresh_research_details",
    "refresh_upcoming", "refresh_upcoming_times", "refresh_science_counts", "refresh_science_pack_panel",
    "tick_science_pack_panel", "tick_research_graph",
    "refresh_research_status", "refresh_research_progress", "refresh_research_metrics",
    "refresh_research_graph", "refresh_research_status_bar", "repopulate_tech", "show_research_graph_hover", "hide_research_graph_hover"
}) do
    components[name] = function(...) calls[#calls + 1] = name end
end
components.request_upcoming = function() calls[#calls + 1] = "request_upcoming"; return true end
components.tick_upcoming = function() calls[#calls + 1] = "tick_upcoming"; return true end

local function child(name)
    return {
        name = name,
        visible = true,
        text = "search",
        focus = function() calls[#calls + 1] = name .. ":focus" end,
        select = function() calls[#calls + 1] = name .. ":select" end
    }
end

local function make_anchor(screen)
    local anchor = {
        name = "lil_einstein_gui",
        valid = true,
        visible = true,
        content_flow = child("content_flow"),
        policy_panel = child("policy_panel"),
        research_details_panel = child("research_details_panel"),
        science_pack_panel = child("science_pack_panel"),
        science_bottom = child("science_bottom"),
        top_flow = child("top_flow"),
        footer_frame = child("footer_frame"),
        search_textfield = child("search_textfield"),
        search_button = child("search_button")
    }
    anchor.policy_panel.visible = false
    anchor.research_details_panel.visible = false
    anchor.science_pack_panel.visible = false
    anchor.science_bottom.visible = true
    function anchor.destroy()
        screen.lil_einstein_gui = nil
        anchor.valid = false
    end
    return anchor
end

local player = {index = 1, force = {index = 1}, gui = {screen = {}}, opened = nil}
game = {players = {player}, get_player = function(index) return index == 1 and player or nil end}
local gutil = {
    clear_child_cache = function() calls[#calls + 1] = "clear_child_cache" end,
    get_child = function(anchor, name) return anchor[name] end
}
local state = {
    get_player_setting = function(_, key, default) return settings[key] == nil and default or settings[key] end,
    set_player_setting = function(_, key, value) settings[key] = value end,
    clear_player_setting = function(_, key) settings[key] = nil end,
    get_force_setting = function(_, key, default) return settings[key] == nil and default or settings[key] end
}
local builder = {
    build = function(_, parent)
        parent.lil_einstein_gui = make_anchor(parent)
    end,
    build_debug_report = function(_, parent, report)
        local modal
        modal = {
            valid = true,
            report = report,
            destroy = function()
                modal.valid = false
                parent.lil_einstein_debug_report = nil
            end
        }
        parent.lil_einstein_debug_report = modal
        player.opened = modal
    end
}
local debug_report = {generate = function() calls[#calls + 1] = "generate_debug_report"; return "snapshot" end}

t.install_module("view.gui.gutil", gutil)
t.install_module("model.state", state)
t.install_module("lib.const", {default_settings = {force = {master_enable = "right"}}})
t.install_module("view.gui.builder", builder)
t.install_module("view.gui.components", components)
t.install_module("view.gui.debug_report", debug_report)
local gui = require("view.gui")

local function reset()
    settings = {}
    calls = {}
    player.gui.screen = {}
    player.opened = nil
    player.force = {index = 1}
end

local tests = {
    {"gets and toggles the screen GUI", function()
        reset()
        t.assert_nil(gui.get(99))
        t.assert_false(gui.is_open(1))
        gui.toggle(1)
        t.assert_true(gui.is_open(1))
        t.assert_true(#calls > 0)
        gui.toggle(1)
        t.assert_false(gui.is_open(1))
        t.assert_nil(settings.search_text)
    end},
    {"initializes an already-open player by closing its window", function()
        reset()
        gui.toggle(1)
        player.opened = player.gui.screen.lil_einstein_gui
        gui.init_player(1)
        t.assert_false(gui.is_open(1))
    end},
    {"switches policy and research detail panels", function()
        reset()
        gui.toggle(1)
        local anchor = player.gui.screen.lil_einstein_gui
        gui.toggle_policy_panel(1)
        t.assert_true(anchor.policy_panel.visible)
        t.assert_false(anchor.content_flow.visible)
        t.assert_false(settings.research_details_open)
        gui.toggle_policy_panel(1)
        t.assert_true(anchor.content_flow.visible)
        gui.toggle_research_details(1)
        t.assert_true(anchor.research_details_panel.visible)
        t.assert_false(anchor.policy_panel.visible)
        t.assert_false(anchor.top_flow.visible)
        t.assert_false(anchor.footer_frame.visible)
        gui.toggle_research_details(1)
        t.assert_true(anchor.content_flow.visible)
        t.assert_true(anchor.top_flow.visible)
        t.assert_true(anchor.footer_frame.visible)
    end},
    {"opens the selected science-pack inspector in the science pane", function()
        reset()
        gui.toggle(1)
        local anchor = player.gui.screen.lil_einstein_gui
        gui.toggle_science_pack_details(1, "science_a")
        t.assert_true(anchor.science_pack_panel.visible)
        t.assert_false(anchor.science_bottom.visible)
        t.assert_true(anchor.content_flow.visible)
        t.assert_false(anchor.policy_panel.visible)
        t.assert_false(anchor.research_details_panel.visible)
        t.assert_true(settings.science_pack_panel_open)
        t.assert_equal(settings.science_pack_panel_science, "science_a")

        gui.toggle_science_pack_details(1, "science_a")
        t.assert_false(anchor.science_pack_panel.visible)
        t.assert_true(anchor.science_bottom.visible)
        t.assert_nil(settings.science_pack_panel_science)
        t.assert_false(settings.science_pack_panel_open)
    end},
    {"makes the inspector visible when another panel hid the content flow", function()
        reset()
        gui.toggle(1)
        local anchor = player.gui.screen.lil_einstein_gui
        anchor.content_flow.visible = false
        anchor.research_details_panel.visible = true

        gui.toggle_science_pack_details(1, "science_a")

        t.assert_true(anchor.content_flow.visible)
        t.assert_true(anchor.science_pack_panel.visible)
        t.assert_false(anchor.research_details_panel.visible)
    end},
    {"focuses, defocuses, and updates the search field", function()
        reset()
        gui.toggle(1)
        local anchor = player.gui.screen.lil_einstein_gui
        gui.focus_search(1)
        t.assert_true(anchor.search_textfield.visible)
        t.assert_true(settings.search_is_focused)
        anchor.search_textfield.text = "automation"
        gui.update_search_field(1)
        t.assert_equal(settings.search_text, "automation")
        gui.defocus_search(1)
        t.assert_false(anchor.search_textfield.visible)
        t.assert_false(settings.search_is_focused)
        t.assert_equal(player.opened, anchor)
        t.assert_false(gui.is_search_focussed(1))
    end},
    {"opens and closes the copy-ready debug report modal", function()
        reset()
        gui.toggle(1)
        gui.open_debug_report(1)
        t.assert_true(gui.is_debug_report_open(1))
        t.assert_equal(player.gui.screen.lil_einstein_debug_report.report, "snapshot")
        gui.close_debug_report(1)
        t.assert_false(gui.is_debug_report_open(1))
        t.assert_equal(player.opened, player.gui.screen.lil_einstein_gui)
    end},
    {"runs bounded repopulation jobs and forwards refreshes", function()
        reset()
        gui.toggle(1)
        gui.request_repopulate_open(1)
        gui.request_repopulate_open(1)
        t.assert_equal(gui.tick_repopulate(1), "upcoming_request")
        t.assert_equal(gui.tick_repopulate(1), "finish_progress")
        t.assert_equal(gui.tick_repopulate(1), "finish_metrics")
        t.assert_equal(gui.tick_repopulate(1), "finish_graph")
        t.assert_equal(gui.tick_repopulate(1), "finish")
        t.assert_equal(gui.tick_repopulate(1), "upcoming_request")
        t.assert_equal(gui.tick_repopulate(1), "finish_progress")
        t.assert_equal(gui.tick_repopulate(1), "finish_metrics")
        t.assert_equal(gui.tick_repopulate(1), "finish_graph")
        t.assert_equal(gui.tick_repopulate(1), "finish")
        t.assert_equal(gui.tick_repopulate(1), "idle")
        gui.repopulate_open(1)
        gui.refresh_upcoming(1)
        gui.refresh_upcoming_times(1)
        gui.refresh_science_counts(1)
        gui.tick_science_counts(1)
        gui.tick_research_graph(1)
        gui.refresh_research_status(1)
        gui.refresh_research_progress(1)
        gui.refresh_research_metrics(1)
        gui.refresh_research_status_bar(1)
        gui.refresh_research_graph(1)
        gui.show_research_graph_hover(1, 4)
        gui.hide_research_graph_hover(1)
        t.assert_true(#calls >= 15)
    end},
    {"rejects invalid or missing GUI anchors during background work", function()
        reset()
        t.assert_equal(gui.tick_repopulate(1), "idle")
        gui.toggle_policy_panel(1)
        gui.toggle_research_details(1)
        gui.toggle(99)
        player.gui.screen.lil_einstein_gui = {valid = true}
        gui.toggle_policy_panel(1)
        gui.toggle_research_details(1)
        player.gui.screen.lil_einstein_gui = nil
        gui.toggle_policy_panel(1)
        gui.toggle_research_details(1)
        player.gui.screen.lil_einstein_gui = {valid = false}
        gui.request_repopulate_open(1)
        t.assert_equal(gui.tick_repopulate(1), "invalid")
    end},
    {"restores remembered panels and advances the incremental upcoming stage", function()
        reset()
        settings.policy_panel_open = true
        gui.toggle(1)
        t.assert_true(player.gui.screen.lil_einstein_gui.policy_panel.visible)

        reset()
        settings.research_details_open = true
        gui.toggle(1)
        t.assert_true(player.gui.screen.lil_einstein_gui.research_details_panel.visible)

        reset()
        local old_build = builder.build
        builder.build = function() end
        gui.toggle(1)
        builder.build = old_build
        t.assert_false(gui.is_open(1))

        reset()
        gui.toggle(1)
        local old_request = components.request_upcoming
        local old_tick = components.tick_upcoming
        components.request_upcoming = function() return false end
        components.tick_upcoming = function() return true end
        gui.request_repopulate_open(1)
        t.assert_equal(gui.tick_repopulate(1), "upcoming_request")
        t.assert_equal(gui.tick_repopulate(1), "upcoming")
        components.request_upcoming = old_request
        components.tick_upcoming = old_tick
    end}
}

local passed = t.run("gui_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original[name]
    package.loaded[name] = nil
end
return passed
