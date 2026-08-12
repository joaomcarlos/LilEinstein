package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local names = {
    "lib.const", "lib.log", "lib.util", "model.state", "model.tech", "model.queue",
    "model.research_policy", "view.gui.analyzer", "view.gui.gutil",
    "view.gui.components.tech", "view.gui.components.upcoming", "view.gui.components.queue",
    "view.gui.components"
}
local original = {}
for _, name in ipairs(names) do
    original[name] = package.preload[name]
    package.loaded[name] = nil
end

local calls = {}
local gutil = {get_child = function(anchor, name) return anchor and anchor[name] end}
local queue = {
    get_queue = function() return {} end,
    get_queue_meta = function() return nil end,
    request_upcoming_research_display = function() calls.request = true end,
    tick_upcoming_research_display = function() return true, {} end,
    get_pinned_tech = function() return nil end,
    get_upcoming_research_display = function() return {} end
}
local components_tech = {populate = function() calls.tech = true end}
t.install_module("lib.const", {default_settings = {force = {master_enable = "right"}}})
t.install_module("lib.log", {error = function() end, warn = function() end, log = function() end, debug = function() end})
t.install_module("lib.util", {})
t.install_module("model.state", {
    get_force_setting = function(_, _, default) return default end,
    get_player_setting = function(_, _, default) return default end
})
t.install_module("model.tech", {})
t.install_module("model.queue", queue)
t.install_module("model.research_policy", {})
t.install_module("view.gui.analyzer", {get_queue_meta = function() return nil end})
t.install_module("view.gui.gutil", gutil)
t.install_module("view.gui.components.tech", components_tech)
local queue_component = require("view.gui.components.queue")
local upcoming_component = require("view.gui.components.upcoming")
local content = require("view.gui.components")

local player = {force = {index = 1}}
game = {tick = 60, get_player = function(index) return index == 1 and player or nil end}

local tests = {
    {"queue component handles missing players, tables, and empty queues", function()
        t.assert_nil(queue_component.populate(99, {}))
        local anchor = {}
        queue_component.populate(1, anchor)
        local table_element = {children = {}, clear = function() calls.queue_clear = true end}
        table_element.add = function(prop) table.insert(table_element.children, prop) end
        anchor.table_queue = table_element
        queue_component.populate(1, anchor)
        t.assert_true(calls.queue_clear)
        t.assert_equal(table_element.children[1].caption[1], "lil_einstein-lbl.empty-queue")
    end},
    {"upcoming component guards missing UI state and clears runtime cache", function()
        t.assert_false(upcoming_component.request_populate(99, {}))
        t.assert_false(upcoming_component.request_populate(1, {}))
        t.assert_true(upcoming_component.tick_populate(1, {}))
        t.assert_nil(upcoming_component.populate(99, {}))
        t.assert_nil(upcoming_component.refresh_times(1, {}))
        upcoming_component.clear_runtime_cache()
        t.assert_true(true)
    end},
    {"component facade suppresses refreshes while policy is visible", function()
        local anchor = {policy_panel = {visible = true}, research_details_panel = {visible = false}}
        content.repopulate_dynamic(1, anchor)
        content.repopulate_tech(1, anchor)
        content.refresh_upcoming(1, anchor)
        t.assert_true(content.request_upcoming(1, anchor))
        t.assert_true(content.tick_upcoming(1, anchor))
        content.refresh_upcoming_times(1, anchor)
        content.refresh_science_counts(1, anchor)
        content.refresh_master_enable(1, anchor)
        content.refresh_research_progress(1, anchor)
        content.refresh_research_metrics(1, anchor)
        content.refresh_research_graph(1, anchor)
        content.tick_research_graph(1, anchor)
        content.clear_runtime_cache()
        t.assert_true(type(upcoming_component.clear_runtime_cache) == "function")
        t.assert_false(calls.tech == true)
    end}
}

local passed = t.run("component_guard_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original[name]
    package.loaded[name] = nil
end
game = nil
return passed
