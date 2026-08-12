package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
t.reset_modules({"model.env", "model.tech"})

local function make_item(name, spoil_ticks, place_result)
    return {
        name = name,
        get_spoil_ticks = function() return spoil_ticks or 0 end,
        place_result = place_result
    }
end

local function make_technology(name)
    return {
        name = name,
        prerequisites = {},
        successors = {},
        effects = {},
        research_unit_ingredients = {{name = "automation-science-pack"}},
        researched = false,
        enabled = true,
        hidden = false,
        max_level = 1
    }
end

local tech_a = make_technology("tech-a")
local tech_b = make_technology("tech-b")
local tech_c = make_technology("tech-c")
tech_a.successors = {[tech_b.name] = tech_b}
tech_b.prerequisites = {[tech_a.name] = tech_a}
tech_b.successors = {[tech_c.name] = tech_c}
tech_c.prerequisites = {[tech_b.name] = tech_b}
tech_b.research_unit_ingredients = {{name = "logistic-science-pack"}}
tech_a.hidden = true
tech_b.research_trigger = {type = "craft-item"}
tech_a.effects = {{type = "unlock-recipe", recipe = "test-recipe"}}
tech_b.effects = {{type = "give-item-modifier", item = "test-machine"}}

prototypes = {
    get_entity_filtered = function()
        return {
            {lab_inputs = {"automation-science-pack", "logistic-science-pack"}},
            {lab_inputs = {"logistic-science-pack"}}
        }
    end,
    item = {
        ["automation-science-pack"] = make_item("automation-science-pack", 0),
        ["logistic-science-pack"] = make_item("logistic-science-pack", 60),
        ["test-machine"] = make_item("test-machine", 0, {type = "assembling-machine"})
    },
    recipe = {
        ["test-recipe"] = {products = {{type = "item", name = "test-machine"}}}
    },
    technology = {
        [tech_a.name] = tech_a,
        [tech_b.name] = tech_b,
        [tech_c.name] = tech_c
    }
}

local env = require("model.env")
local tech = require("model.tech")
local tests = {}

local function reset_runtime()
    storage = {env = {}, forces = {[1] = {}}}
    game = {
        forces = {
            [1] = {index = 1, technologies = prototypes.technology}
        }
    }
    for _, item in pairs(prototypes.technology) do
        item.researched = false
        item.enabled = true
    end
    tech_a.hidden = true
    tech_b.research_trigger = {type = "craft-item"}
    env.init()
end

tests[#tests + 1] = {"discovers unique sciences and metadata", function()
    reset_runtime()
    local sciences = env.get_all_sciences()
    t.assert_equal(#sciences, 2)
    t.assert_has_value(sciences, "automation-science-pack")
    t.assert_has_value(sciences, "logistic-science-pack")

    local meta = env.get_single_tech_meta("tech-a")
    t.assert_true(meta.has_successors)
    t.assert_true(meta.has_prerequisites == false)
    t.assert_true(meta.all_successors["tech-b"])
    t.assert_true(meta.all_successors["tech-c"])
    t.assert_true(meta.research_effects["unlock-recipe"])
    t.assert_true(meta.research_prototypes["assembling-machine"])
    t.assert_true(env.get_single_tech_meta("missing") == nil)
end}

tests[#tests + 1] = {"records trigger, infinite, and spoilable metadata", function()
    reset_runtime()
    tech_c.max_level = 4294960000
    env.init()
    local meta_b = env.get_single_tech_meta("tech-b")
    local meta_c = env.get_single_tech_meta("tech-c")
    t.assert_true(meta_b.has_trigger)
    t.assert_true(meta_c.is_infinite)
    t.assert_true(meta_b.has_spoilable_science)
end}

tests[#tests + 1] = {"initializes tech state and propagates blockers", function()
    reset_runtime()
    tech.init_force(1)
    local all = tech.get_all_tech_state_ext(1)
    t.assert_equal(all["tech-a"].available, true)
    t.assert_equal(all["tech-b"].available, false)
    t.assert_true(all["tech-c"].blocked_by["tech-b"])
    t.assert_true(all["tech-b"].disabled_by["tech-a"])
end}

tests[#tests + 1] = {"updates researched state and successor availability", function()
    reset_runtime()
    tech.init_force(1)
    local all = tech.get_all_tech_state_ext(1)
    tech_a.researched = true
    tech.update_researched(1, "tech-a")
    t.assert_true(all["tech-b"].available)
    t.assert_nil(all["tech-b"].blocked_by["tech-a"])
    t.assert_nil(all["tech-b"].disabled_by["tech-a"])
end}

tests[#tests + 1] = {"reapplies blockers when research is reversed", function()
    reset_runtime()
    tech.init_force(1)
    local all = tech.get_all_tech_state_ext(1)
    tech_a.researched = true
    tech.update_researched(1, "tech-a")
    tech_a.researched = false
    tech_a.enabled = false
    tech.update_researched(1, "tech-a")
    t.assert_true(all["tech-b"].disabled_by["tech-a"])
    t.assert_true(all["tech-c"].blocked_by["tech-b"])
end}

tests[#tests + 1] = {"suspends technologies and tracks inherited queue state", function()
    reset_runtime()
    tech.init_force(1)
    local all = tech.get_all_tech_state_ext(1)
    tech.suspend(1, "tech-b", true)
    t.assert_true(tech.get_single_tech_state_ext(1, "tech-b").suspended)
    tech.update_queued(1, "tech-b", true)
    t.assert_true(all["tech-a"].inherited_by["tech-b"])
    tech.update_queued(1, "tech-b", false)
    t.assert_nil(all["tech-a"].inherited_by["tech-b"])
    all["tech-b"].has_trigger = true
    tech.update_researched(1, "tech-b")
    t.assert_true(all["tech-c"].blocked_by["tech-b"])
    t.assert_nil(tech.get_single_tech_state_ext(1, "missing"))
    tech.suspend(1, "missing", true)
end}

local passed = t.run("env_tech_spec", tests)
package.loaded["model.env"] = nil
package.loaded["model.tech"] = nil
return passed
