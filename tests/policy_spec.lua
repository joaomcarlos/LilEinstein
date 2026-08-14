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

tests[#tests + 1] = {"exposes new control-center defaults and megabase strategy", function()
    reset_policy()
    t.assert_equal(policy.get_setting(1, "replan_interval_seconds"), 120)
    t.assert_equal(policy.get_setting(1, "reserve_for_type"), "safety_first")
    t.assert_true(policy.get_setting(1, "instant_switch_override"))
    local found_megabase = false
    for _, name in ipairs(policy.strategy_order) do
        if name == "megabase" then found_megabase = true end
    end
    t.assert_true(found_megabase)
    for _, name in ipairs(policy.reserve_for_type_order) do
        t.assert_true(name == "off" or name == "safety_first" or name == "balanced")
    end
end}

tests[#tests + 1] = {"sanitizes replan_interval_seconds and reserve_for_type", function()
    reset_policy()
    t.assert_true(policy.set_setting(1, "replan_interval_seconds", 1))
    t.assert_equal(policy.get_setting(1, "replan_interval_seconds"), 30)
    t.assert_true(policy.set_setting(1, "replan_interval_seconds", 99999))
    t.assert_equal(policy.get_setting(1, "replan_interval_seconds"), 3600)
    t.assert_true(policy.set_setting(1, "replan_interval_seconds", 90))
    t.assert_equal(policy.get_setting(1, "replan_interval_seconds"), 90)
    t.assert_true(policy.set_setting(1, "replan_interval_seconds", math.huge))
    t.assert_equal(policy.get_setting(1, "replan_interval_seconds"), 30)
    t.assert_true(policy.set_setting(1, "reserve_for_type", "balanced"))
    t.assert_equal(policy.get_setting(1, "reserve_for_type"), "balanced")
    t.assert_false(policy.set_setting(1, "reserve_for_type", "aggressive"))
    t.assert_equal(policy.get_setting(1, "reserve_for_type"), "balanced")
    t.assert_true(policy.set_setting(1, "reserve_for_type", "off"))
    t.assert_equal(policy.get_setting(1, "reserve_for_type"), "off")
    t.assert_true(policy.set_setting(1, "instant_switch_override", false))
    t.assert_false(policy.get_setting(1, "instant_switch_override"))
    t.assert_false(policy.set_setting(1, "instant_switch_override", "yes"))
end}

tests[#tests + 1] = {"applies bounded megabase strategy adjustment", function()
    reset_policy()
    policy.set_setting(1, "strategy", "megabase")
    local infinite_xcur = {meta = {is_infinite = true, research_effects = {}}}
    t.assert_equal(policy.get_strategy_adjustment(1, infinite_xcur, 1), 40)
    local infinite_logistics = {meta = {is_infinite = true,
        research_effects = {['worker-robot-speed'] = true}}}
    t.assert_equal(policy.get_strategy_adjustment(1, infinite_logistics, 1), 60)
    local finite_xcur = {meta = {is_infinite = false, research_effects = {['unlock-recipe'] = true}}}
    t.assert_equal(policy.get_strategy_adjustment(1, finite_xcur, 1), 0)
    t.assert_equal(policy.get_strategy_adjustment(1, nil, 1), 0)
    policy.set_setting(1, "strategy", "balanced")
    t.assert_equal(policy.get_strategy_adjustment(1, infinite_xcur, 1), 0)
end}

tests[#tests + 1] = {"records structured history and keeps string detail backward compatible", function()
    reset_policy()
    game.tick = 100
    policy.record_action(1, 1, "switch", {
        category = "switch",
        reason = "pack-bound",
        trigger = "override",
        before = "tech-a",
        after = "tech-b",
        reserved = {"automation-science-pack"},
        release_reason = "supplied"
    })
    game.tick = 200
    policy.record_action(1, nil, "legacy", "plain string detail")
    local history = policy.get_history(1)
    t.assert_equal(#history, 2)
    local legacy = history[1]
    t.assert_equal(legacy.action, "legacy")
    t.assert_equal(legacy.category, "legacy")
    t.assert_equal(legacy.detail, "plain string detail")
    t.assert_nil(legacy.reason)
    local structured = history[2]
    t.assert_equal(structured.action, "switch")
    t.assert_equal(structured.category, "switch")
    t.assert_equal(structured.reason, "pack-bound")
    t.assert_equal(structured.trigger, "override")
    t.assert_equal(structured.before, "tech-a")
    t.assert_equal(structured.after, "tech-b")
    t.assert_equal(structured.reserved[1], "automation-science-pack")
    t.assert_equal(structured.release_reason, "supplied")
    t.assert_equal(structured.tick, 100)
end}

tests[#tests + 1] = {"filters history by equality predicates and stays bounded", function()
    reset_policy()
    for i = 1, 3 do
        game.tick = i
        policy.record_action(1, nil, "switch", {category = "switch", reason = "r" .. i})
    end
    game.tick = 4
    policy.record_action(1, nil, "queue", {category = "queue", reason = "r4"})
    local only_switch = policy.get_history(1, {category = "switch"})
    t.assert_equal(#only_switch, 3)
    t.assert_equal(only_switch[1].reason, "r3")
    local only_r2 = policy.get_history(1, {category = "switch", reason = "r2"})
    t.assert_equal(#only_r2, 1)
    t.assert_equal(only_r2[1].reason, "r2")
    local queue_only = policy.get_history(1, {action = "queue"})
    t.assert_equal(#queue_only, 1)
    t.assert_equal(policy.get_history(1, {})[1].reason, "r4")
    t.assert_equal(#policy.get_history(1), 4)
    for i = 5, 50 do
        game.tick = i
        policy.record_action(1, nil, "flood", {category = "flood"})
    end
    t.assert_equal(#policy.get_history(1), 40)
end}

tests[#tests + 1] = {"manages instant switch request, consume, and reason preservation", function()
    reset_policy()
    t.assert_false(policy.has_instant_switch_request(1))
    t.assert_nil(policy.get_instant_switch_reason(1))
    t.assert_true(policy.request_instant_switch(1, "plan-demand"))
    t.assert_true(policy.has_instant_switch_request(1))
    t.assert_equal(policy.get_instant_switch_reason(1), "plan-demand")
    local used, reason = policy.consume_instant_switch(1)
    t.assert_true(used)
    t.assert_equal(reason, "plan-demand")
    t.assert_false(policy.has_instant_switch_request(1))
    local used_again = policy.consume_instant_switch(1)
    t.assert_false(used_again)
    policy.request_instant_switch(1, "second")
    policy.clear_instant_switch(1)
    t.assert_false(policy.has_instant_switch_request(1))
end}

tests[#tests + 1] = {"instant switch override respects the gating setting", function()
    reset_policy()
    policy.set_setting(1, "instant_switch_override", false)
    t.assert_true(policy.request_instant_switch(1, "blocked"))
    t.assert_true(policy.has_instant_switch_request(1))
    local used, reason = policy.consume_instant_switch(1)
    t.assert_false(used)
    t.assert_nil(reason)
    t.assert_true(policy.has_instant_switch_request(1))
    policy.set_setting(1, "instant_switch_override", true)
    local used_now, reason_now = policy.consume_instant_switch(1)
    t.assert_true(used_now)
    t.assert_equal(reason_now, "blocked")
end}

tests[#tests + 1] = {"instant switch seam is nil-safe without a store", function()
    storage = {forces = {}}
    t.assert_false(policy.request_instant_switch(1, "x"))
    t.assert_false(policy.has_instant_switch_request(1))
    t.assert_nil(policy.get_instant_switch_reason(1))
    local used, reason = policy.consume_instant_switch(1)
    t.assert_false(used)
    t.assert_nil(reason)
    policy.clear_instant_switch(1)
end}

local passed = t.run("policy_spec", tests)
package.preload["model.env"] = old_env
package.loaded["model.research_policy"] = nil
return passed
