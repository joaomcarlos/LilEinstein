package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local names = {
    "lib.util",
    "model.tech",
    "model.queue",
    "view.gui.analyzer",
    "view.gui.gutil",
    "view.gui.debug_report"
}
local originals = {}
for _, name in ipairs(names) do
    originals[name] = package.preload[name]
    package.loaded[name] = nil
end

local alpha = {
    technology = {
        name = "alpha",
        level = 1,
        researched = false,
        research_unit_count = 100
    },
    available = true,
    suspended = false,
    queued = true,
    meta = {sciences = {"automation-science-pack"}, is_infinite = false}
}
local beta = {
    technology = {
        name = "beta",
        level = 2,
        researched = false,
        research_unit_count = 200
    },
    available = true,
    suspended = false,
    queued = false,
    meta = {sciences = {"logistic-science-pack"}, is_infinite = true}
}
local force = {
    index = 1,
    name = "player",
    current_research = {name = "alpha"},
    research_progress = 0.25,
    technologies = {
        alpha = {saved_progress = 0.25},
        beta = {saved_progress = 0}
    },
    research_queue = {{name = "alpha"}, {name = "beta"}}
}
local player = {index = 1, force = force}

_G.game = {
    tick = 1200,
    get_player = function(index) return index == 1 and player or nil end
}

local queue = {
    get_upcoming_research_display = function()
        return {
            {
                tech_name = "alpha",
                level = 1,
                cost = 100,
                duration = 90,
                wait_time = nil,
                xcur = alpha,
                has_science = true,
                availability_reason = nil,
                missing_sciences = {}
            },
            {
                tech_name = "beta",
                level = 2,
                cost = 200,
                duration = 180,
                wait_time = 90,
                xcur = beta,
                has_science = false,
                availability_reason = "missing_science",
                missing_sciences = {"logistic-science-pack"}
            }
        }
    end,
    get_tech_order = function() return {"alpha", "beta"} end,
    get_tech_ub = function(_, tech_name) return tech_name == "beta" and 3 or 1 end,
    score_tech_detailed = function(xcur)
        return {
            importance = xcur.technology.name == "alpha" and 10 or 20,
            level_boost = 2,
            user_boost = 1,
            science_priority = 4,
            strategy_boost = 5,
            total = xcur.technology.name == "alpha" and 30 or 40
        }
    end,
    science_is_available = function(xcur) return xcur == alpha end,
    get_tech_enabled = function() return true end,
    get_research_summary = function()
        return {progress = 0.25, done = 25, total = 100, spm = 12.5, remaining_seconds = 90}
    end,
    get_research_display_diagnostic = function()
        return {
            state = "pack_bound",
            actual_spm = 12.5,
            expected_spm = 20,
            working_spm = 12.5,
            utilization = 0.625,
            total_labs = 5,
            compatible_labs = 5,
            working_labs = 4,
            incompatible_labs = 0,
            sampling_ready = true,
            sample_count = 10,
            dominant_cause = {kind = "missing_science", lost_spm = 7.5, labs = 1, material = true},
            causes = {{kind = "missing_science", lost_spm = 7.5, labs = 1, material = true}},
            missing_sciences = {{science = "logistic-science-pack", missing_per_minute = 2, lost_spm = 7.5, labs = 1}}
        }
    end,
    get_science_display_counts = function()
        return { ["automation-science-pack"] = 123, ["logistic-science-pack"] = 4 }
    end,
    get_science_display_forecast = function()
        return {
            ["automation-science-pack"] = {stock = 123, consumption_per_minute = 5, production_per_minute = 8, net_per_minute = 3},
            ["logistic-science-pack"] = {stock = 4, consumption_per_minute = 6, production_per_minute = 1, net_per_minute = -5, depletion_seconds = 48}
        }
    end,
    get_science_availability = function()
        return { ["automation-science-pack"] = true, ["logistic-science-pack"] = false }
    end,
    get_science_flow_history = function()
        return {
            {tick = 1080, values = {
                ["automation-science-pack"] = {consumption_per_minute = 4},
                ["logistic-science-pack"] = {consumption_per_minute = 5}
            }},
            {tick = 1140, values = {
                ["automation-science-pack"] = {consumption_per_minute = 5},
                ["logistic-science-pack"] = {consumption_per_minute = 6}
            }},
            {tick = 1200, values = {
                ["automation-science-pack"] = {consumption_per_minute = 5},
                ["logistic-science-pack"] = {consumption_per_minute = 6}
            }}
        }
    end,
    get_research_history = function(_, count)
        local history = {}
        for index = 1, count do history[index] = index end
        return history
    end,
    get_research_speed = function() return 0.2 end,
    get_research_health_snapshot_tick = function() return 1170 end,
    get_research_control_state = function()
        return {
            live_current_tech = "alpha",
            cached_current_tech = "stale-alpha",
            cached_smart_tech = "alpha",
            target_tech = "alpha",
            temp_tech = "beta",
            temp_tech_timeout_tick = 1300,
            last_switch_tick = 1100,
            is_stuck = false,
            stored_queue = {"alpha", "beta"},
            runtime_queue = {"alpha", "beta"}
        }
    end,
    get_tech_missing_science = function() return {beta = true} end,
    get_queue = function() return {"alpha", "beta"} end,
    get_current_researching = function() return "stale-alpha" end
}

local analyzer = {
    get_filtered_technologies_player = function() return {alpha, beta} end
}
local tech = {
    get_all_tech_state_ext = function() return {alpha = alpha, beta = beta} end
}
local util = {get_all_sciences = function() return {"automation-science-pack", "logistic-science-pack"} end}
local gutil = {format_si = function(value) return tostring(value or 0) end}

t.install_module("lib.util", util)
t.install_module("model.tech", tech)
t.install_module("model.queue", queue)
t.install_module("view.gui.analyzer", analyzer)
t.install_module("view.gui.gutil", gutil)
local debug_report = require("view.gui.debug_report")

local tests = {
    {"includes the queue, score, graph, science, and warning sections", function()
        local report = debug_report.generate(1)
        t.assert_true(report:find("CURRENT RESEARCH", 1, true) ~= nil)
        t.assert_true(report:find("UPCOMING RESEARCH", 1, true) ~= nil)
        t.assert_true(report:find("beta|2|0.00%|3m 00s|1m 30s|NO", 1, true) ~= nil)
        t.assert_true(report:find("IW|LB|UB|SP|ST", 1, true) ~= nil)
        t.assert_true(report:find("RESEARCH GRAPH", 1, true) ~= nil)
        t.assert_true(report:find("0|40.000", 1, true) ~= nil)
        t.assert_true(report:find("SCIENCE PACKS", 1, true) ~= nil)
        t.assert_true(report:find("logistic-science-pack|4|6|5|6", 1, true) ~= nil)
        t.assert_true(report:find("WARNINGS", 1, true) ~= nil)
        t.assert_true(report:find("pack_bound", 1, true) ~= nil)
        t.assert_true(report:find("current_cache_mismatch", 1, true) ~= nil)
    end}
}

local passed = t.run("debug_report_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = originals[name]
    package.loaded[name] = nil
end
return passed
