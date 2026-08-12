package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local old_env = package.preload["model.env"]
t.install_module("model.env", {
    get_all_sciences = function()
        return {"automation-science-pack", "logistic-science-pack"}
    end
})
t.reset_modules({"model.research_policy"})

prototypes = {
    item = {
        ["automation-science-pack"] = {},
        ["logistic-science-pack"] = {}
    },
    technology = {
        ["automation"] = {},
        ["logistics"] = {}
    }
}

local policy = require("model.research_policy")
local tests = {}

local function reset_policy()
    storage = {forces = {[1] = {}}}
    game = {
        tick = 10,
        get_player = function(index)
            return index == 1 and {name = "tester"} or nil
        end
    }
    script = {active_mods = {}}
    policy.init_force(1)
end

tests[#tests + 1] = {"initializes defaults and science policies", function()
    reset_policy()
    t.assert_equal(policy.get_setting(1, "strategy"), "balanced")
    t.assert_false(policy.get_setting(1, "planning_paused"))
    local science = policy.get_science_policy(1, "automation-science-pack")
    t.assert_equal(science.priority, "normal")
    t.assert_equal(science.lower_threshold, 0.25)
    t.assert_equal(science.upper_threshold, 0.80)
end}

tests[#tests + 1] = {"sanitizes settings and rejects invalid values", function()
    reset_policy()
    t.assert_true(policy.set_setting(1, "min_switch_seconds", 1))
    t.assert_equal(policy.get_setting(1, "min_switch_seconds"), 5)
    t.assert_true(policy.set_setting(1, "forecast_seconds", 99999))
    t.assert_equal(policy.get_setting(1, "forecast_seconds"), 3600)
    t.assert_false(policy.set_setting(1, "strategy", "not-a-strategy"))
    t.assert_false(policy.set_setting(1, "missing", true))
end}

tests[#tests + 1] = {"cycles science priority and returns its scoring weight", function()
    reset_policy()
    t.assert_equal(policy.cycle_science_priority(1, "automation-science-pack"), "preferred")
    t.assert_equal(policy.get_science_priority_weight(1, "automation-science-pack"), 15)
    policy.cycle_science_priority(1, "automation-science-pack")
    t.assert_equal(policy.cycle_science_priority(1, "automation-science-pack"), "avoid")
    t.assert_equal(policy.get_science_priority_weight(1, "automation-science-pack"), -1000)
end}

tests[#tests + 1] = {"keeps science thresholds ordered", function()
    reset_policy()
    t.assert_equal(policy.adjust_science_threshold(1, "automation-science-pack", "lower", 1), 1.25)
    t.assert_equal(policy.get_science_policy(1, "automation-science-pack").upper_threshold, 1.25)
    t.assert_equal(policy.adjust_science_threshold(1, "automation-science-pack", "upper", -2), 0)
    local item = policy.get_science_policy(1, "automation-science-pack")
    t.assert_equal(item.lower_threshold, 0)
    t.assert_equal(item.upper_threshold, 0)
end}

tests[#tests + 1] = {"resolves technology science priority with avoid taking precedence", function()
    reset_policy()
    local xcur = {meta = {sciences = {"automation-science-pack", "logistic-science-pack"}}}
    policy.cycle_science_priority(1, "logistic-science-pack")
    t.assert_equal(policy.get_tech_science_priority(1, xcur), 15)
    policy.cycle_science_priority(1, "automation-science-pack")
    policy.cycle_science_priority(1, "automation-science-pack")
    policy.cycle_science_priority(1, "automation-science-pack")
    t.assert_equal(policy.get_tech_science_priority(1, xcur), -1000)
end}

tests[#tests + 1] = {"applies strategy-specific adjustments", function()
    reset_policy()
    local xcur = {meta = {research_effects = {['unlock-recipe'] = true}}}
    policy.set_setting(1, "strategy", "unlocks")
    t.assert_equal(policy.get_strategy_adjustment(1, xcur, 100), 35)
    policy.set_setting(1, "strategy", "cheapest")
    t.assert_true(policy.get_strategy_adjustment(1, xcur, 100) > 0)
    policy.set_setting(1, "strategy", "balanced")
    t.assert_equal(policy.get_strategy_adjustment(1, xcur, 100), 0)
end}

tests[#tests + 1] = {"cycles and consumes repeat rules", function()
    reset_policy()
    local rule = policy.cycle_repeat_rule(1, "automation", 1)
    t.assert_equal(rule.mode, "never")
    rule = policy.cycle_repeat_rule(1, "automation", 1)
    t.assert_equal(rule.mode, "once")
    t.assert_equal(rule.remaining, 1)
    t.assert_true(policy.should_requeue(1, "automation", 2, false))
    policy.consume_repeat(1, "automation")
    t.assert_equal(policy.get_repeat_rule(1, "automation").mode, "never")
    t.assert_false(policy.should_requeue(1, "automation", 2, true))
end}

tests[#tests + 1] = {"supports continuous and to-level repeat rules", function()
    reset_policy()
    local rule = policy.get_repeat_rule(1, "automation")
    rule.mode = "continuous"
    t.assert_true(policy.should_requeue(1, "automation", nil, false))
    local max_level = policy.adjust_repeat_max_level(1, "automation", -10, 4)
    t.assert_equal(max_level, 5)
    t.assert_true(policy.should_requeue(1, "automation", 5, false))
    t.assert_false(policy.should_requeue(1, "automation", 6, false))
end}

tests[#tests + 1] = {"enforces multiplayer edit permissions", function()
    reset_policy()
    local player = {valid = true, admin = false, force = {index = 1}}
    t.assert_true(policy.can_edit(player))
    policy.set_setting(1, "multiplayer_lock", true)
    t.assert_false(policy.can_edit(player))
    player.admin = true
    t.assert_true(policy.can_edit(player))
    t.assert_false(policy.can_edit(nil))
end}

tests[#tests + 1] = {"records a bounded action history", function()
    reset_policy()
    for i = 1, 45 do
        game.tick = i
        policy.record_action(1, 1, "action-" .. i, i)
    end
    local history = policy.get_history(1)
    t.assert_equal(#history, 40)
    t.assert_equal(history[1].action, "action-45")
    t.assert_equal(history[40].action, "action-6")
end}

tests[#tests + 1] = {"copies and deletes presets", function()
    reset_policy()
    local value = {strategy = "balanced", nested = {enabled = true}}
    t.assert_true(policy.set_preset(1, "  base  ", value))
    value.nested.enabled = false
    t.assert_true(policy.get_presets(1).base.nested.enabled)
    t.assert_false(policy.set_preset(1, "", value))
    policy.delete_preset(1, "base")
    t.assert_nil(policy.get_presets(1).base)
end}

tests[#tests + 1] = {"sanitizes and imports portable settings", function()
    reset_policy()
    local incoming = {
        settings = {strategy = "productivity", parallel_slots = 99, unknown = true},
        sciences = {
            ["automation-science-pack"] = {priority = "urgent", lower_threshold = 1.5, upper_threshold = 1.0},
            ["unknown-pack"] = {priority = "avoid"}
        },
        repeat_rules = {
            automation = {mode = "to_level", max_level = 12},
            unknown = {mode = "continuous"}
        }
    }
    local sanitized = policy.sanitize_settings(incoming)
    t.assert_equal(sanitized.settings.strategy, "productivity")
    t.assert_equal(sanitized.settings.parallel_slots, 20)
    t.assert_equal(sanitized.sciences["automation-science-pack"].lower_threshold, 1.0)
    t.assert_nil(sanitized.sciences["unknown-pack"])
    t.assert_equal(sanitized.repeat_rules.automation.max_level, 12)
    t.assert_true(policy.import_settings(1, incoming))
    t.assert_equal(policy.get_setting(1, "strategy"), "productivity")
end}

tests[#tests + 1] = {"stores force and cluster science availability", function()
    reset_policy()
    t.assert_equal(policy.get_science_available_state(1, "automation-science-pack", true), true)
    policy.set_science_available_state(1, "automation-science-pack", false)
    t.assert_false(policy.get_science_available_state(1, "automation-science-pack", true))
    policy.set_cluster_science_available_state(1, "surface:network", "automation-science-pack", true)
    t.assert_true(policy.get_cluster_science_available_state(1, "surface:network", "automation-science-pack", false))
    policy.set_cluster_science_available_state(1, "old", "automation-science-pack", true)
    policy.prune_cluster_science_states(1, {['surface:network'] = true})
    t.assert_nil(storage.forces[1].research_policy.cluster_science_available.old)
end}

tests[#tests + 1] = {"detects optional parallel research support", function()
    reset_policy()
    t.assert_false(policy.parallel_mod_available())
    script.active_mods["simultaneous-research"] = "0.7.5"
    t.assert_true(policy.parallel_mod_available())
end}

local passed = t.run("policy_spec", tests)
package.preload["model.env"] = old_env
package.loaded["model.research_policy"] = nil
return passed
