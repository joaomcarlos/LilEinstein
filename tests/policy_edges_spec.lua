package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local old_env = package.preload["model.env"]
t.install_module("model.env", {get_all_sciences = function() return {"automation-science-pack"} end})
package.loaded["model.research_policy"] = nil

local old_globals = {storage = _G.storage, game = _G.game, prototypes = _G.prototypes, script = _G.script}
prototypes = {item = {['automation-science-pack'] = {}}, technology = {automation = {}}}
local policy = require("model.research_policy")

local function find_private(function_value, wanted, seen)
    if type(function_value) ~= "function" then return nil end
    seen = seen or {}
    if seen[function_value] then return nil end
    seen[function_value] = true
    for index = 1, 64 do
        local name, value = debug.getupvalue(function_value, index)
        if not name then break end
        if name == wanted then return value end
        local nested = find_private(value, wanted, seen)
        if nested ~= nil then return nested end
    end
    return nil
end

local function reset()
    storage = {forces = {[1] = {}}}
    game = {tick = 1, get_player = function(index)
        return index == 1 and {name = "tester", valid = true} or nil
    end}
    script = {active_mods = {}}
    policy.init_force(1)
end

local tests = {
    {"handles absent stores, recursive copies, and all setting sanitizers", function()
        reset()
        local sanitize_setting = find_private(policy.set_setting, "sanitize_setting")
        t.assert_true(type(sanitize_setting) == "function")
        local unknown_value, unknown_valid = sanitize_setting("unknown", true)
        t.assert_nil(unknown_value)
        t.assert_false(unknown_valid)
        local default_settings = find_private(policy.get_setting, "default_settings")
        t.assert_true(type(default_settings) == "table")
        default_settings.unhandled_test_setting = {}
        local unhandled_value, unhandled_valid = sanitize_setting("unhandled_test_setting", true)
        t.assert_nil(unhandled_value)
        t.assert_false(unhandled_valid)
        default_settings.unhandled_test_setting = nil
        t.assert_equal(policy.copy_table(3), 3)
        t.assert_equal(policy.copy_table({a = {b = true}}).a.b, true)
        t.assert_equal(policy.set_setting(1, "forecast_seconds", math.huge), true)
        t.assert_equal(policy.get_setting(1, "forecast_seconds"), 0)
        local new_science = policy.get_science_policy(1, "new-science-pack")
        t.assert_equal(new_science.lower_threshold, 0.25)
        t.assert_equal(new_science.upper_threshold, 0.8)
        local saved = storage
        storage = {forces = {}}
        t.assert_equal(policy.get_setting(1, "strategy"), "balanced")
        t.assert_false(policy.set_setting(1, "strategy", "balanced"))
        t.assert_equal(policy.get_science_policy(1, "automation-science-pack").priority, "normal")
        t.assert_equal(policy.get_science_available_state(1, "automation-science-pack", true), true)
        t.assert_true(policy.can_edit(nil) == false)
        storage = saved
        t.assert_true(policy.set_setting(1, "planning_paused", true))
        t.assert_false(policy.set_setting(1, "planning_paused", "yes"))
        t.assert_true(policy.set_setting(1, "finish_current_threshold", 0.75))
        t.assert_true(policy.set_setting(1, "science_lower_threshold", 1.5))
        t.assert_true(policy.set_setting(1, "science_upper_threshold", 1.5))
        t.assert_true(policy.set_setting(1, "parallel_slots", 5.9))
        t.assert_false(policy.set_setting(1, "unknown", true))
    end},
    {"covers every strategy adjustment branch", function()
        reset()
        local cases = {
            cheapest = {effects = {}, expected_positive = true},
            unlocks = {effects = {['unlock-space-platforms'] = true}},
            logistics = {effects = {['worker-robot-speed'] = true}},
            combat = {effects = {['ammo-damage'] = true}},
            space = {effects = {['create-space-platform'] = true}},
            spoilable = {spoilable = true},
            productivity = {effects = {['laboratory-productivity'] = true}}
        }
        for strategy, options in pairs(cases) do
            policy.set_setting(1, "strategy", strategy)
            local xcur = {meta = {research_effects = options.effects or {}, has_spoilable_science = options.spoilable}}
            local adjustment = policy.get_strategy_adjustment(1, xcur, strategy == "cheapest" and 100 or 1)
            t.assert_true(options.expected_positive and adjustment > 0 or adjustment == 35 or adjustment == 60)
        end
        policy.set_setting(1, "strategy", "balanced")
        t.assert_equal(policy.get_strategy_adjustment(1, {meta = {}}, 1), 0)
        for _, strategy in ipairs({"unlocks", "logistics", "combat", "space", "spoilable", "productivity"}) do
            policy.set_setting(1, "strategy", strategy)
            t.assert_equal(policy.get_strategy_adjustment(1, {meta = {research_effects = {}}}, 1), 0)
        end
    end},
    {"handles repeat modes, defaults, and consumption boundaries", function()
        reset()
        local rule = policy.get_repeat_rule(1, "automation")
        rule.mode = "default"
        t.assert_true(policy.should_requeue(1, "automation", nil, true))
        rule.mode = "never"
        t.assert_false(policy.should_requeue(1, "automation", 1, true))
        rule.mode = "once"
        rule.remaining = 0
        t.assert_false(policy.should_requeue(1, "automation", 1, false))
        rule.remaining = 2
        policy.consume_repeat(1, "automation")
        t.assert_equal(rule.remaining, 1)
        policy.consume_repeat(1, "automation")
        t.assert_equal(rule.mode, "never")
        rule.mode = "to_level"
        rule.max_level = 3
        t.assert_false(policy.should_requeue(1, "automation", nil, false))
        t.assert_true(policy.should_requeue(1, "automation", 3, false))
        t.assert_false(policy.should_requeue(1, "automation", 4, false))
        local next_rule = policy.cycle_repeat_rule(1, "other", 2)
        next_rule.mode = "once"
        next_rule.remaining = 1
        next_rule = policy.cycle_repeat_rule(1, "other", 2)
        next_rule = policy.cycle_repeat_rule(1, "other", 2)
        t.assert_equal(next_rule.mode, "to_level")
        t.assert_true(next_rule.max_level >= 7)
    end},
    {"sanitizes portable data and rejects unsupported shapes", function()
        reset()
        t.assert_false(policy.sanitize_settings(nil))
        local sanitized = policy.sanitize_settings({
            settings = {strategy = "bad", planning_paused = true, parallel_slots = "bad", unknown = 1},
            sciences = {['automation-science-pack'] = {priority = "bad", lower_threshold = 2, upper_threshold = 1},
                ['unknown-pack'] = {priority = "avoid"}},
            repeat_rules = {automation = {mode = "once", remaining = 0},
                unknown = {mode = "to_level", max_level = 4}}
        })
        t.assert_false(sanitized.settings.strategy ~= nil)
        t.assert_true(sanitized.settings.planning_paused)
        t.assert_equal(sanitized.sciences["automation-science-pack"].priority, "normal")
        t.assert_equal(sanitized.sciences["automation-science-pack"].lower_threshold, 1)
        t.assert_equal(sanitized.repeat_rules.automation.remaining, 0)
        t.assert_nil(sanitized.sciences["unknown-pack"])
        t.assert_nil(sanitized.repeat_rules.unknown)
        local saved = storage
        storage = {forces = {}}
        t.assert_false(policy.import_settings(1, {}))
        t.assert_equal(#policy.get_history(1), 0)
        t.assert_equal(#policy.get_presets(1), 0)
        storage = saved
    end},
    {"covers action history, preset validation, availability, and optional integration", function()
        reset()
        policy.record_action(1, nil, nil, nil)
        t.assert_equal(policy.get_history(1)[1].player, "system")
        t.assert_false(policy.set_preset(1, string.rep("x", 41), {}))
        t.assert_false(policy.set_preset(99, "x", {}))
        policy.set_cluster_science_available_state(1, "stale", "automation-science-pack", true)
        policy.prune_cluster_science_states(1, {})
        t.assert_nil(storage.forces[1].research_policy.cluster_science_available.stale)
        policy.set_science_available_state(1, "automation-science-pack", true)
        t.assert_true(policy.get_science_available_state(1, "automation-science-pack", false))
        t.assert_true(policy.parallel_mod_available() == false)
        script.active_mods["simultaneous-research"] = "1.0"
        t.assert_true(policy.parallel_mod_available())
        local saved = storage
        storage = {forces = {}}
        t.assert_true(policy.parallel_mod_available())
        policy.prune_cluster_science_states(1, {})
        storage = saved
    end}
    ,{"covers portable exports and missing-store cluster guards", function()
        reset()
        local exported = policy.export_settings(1)
        t.assert_true(exported.settings ~= nil)
        t.assert_true(exported.sciences ~= nil)
        t.assert_true(exported.repeat_rules ~= nil)
        local saved = storage
        storage = {forces = {}}
        t.assert_equal(policy.export_settings(1).settings, nil)
        t.assert_equal(policy.get_repeat_rule(1, "missing").mode, "default")
        t.assert_equal(policy.get_cluster_science_available_state(1, "missing", "science", true), true)
        policy.set_cluster_science_available_state(1, "missing", "science", true)
        storage = saved
        t.assert_equal(policy.get_cluster_science_available_state(1, "cluster", "science", true), true)
        policy.record_action(99, nil, nil, nil)
    end}
}

local passed = t.run("policy_edges_spec", tests)
package.preload["model.env"] = old_env
package.loaded["model.research_policy"] = nil
_G.storage = old_globals.storage
_G.game = old_globals.game
_G.prototypes = old_globals.prototypes
_G.script = old_globals.script
return passed
