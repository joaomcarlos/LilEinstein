package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local names = {"lib.util", "lib.const", "model.env"}
local original_preloads = {}
local original_loaded = {}
for _, name in ipairs(names) do
    original_preloads[name] = package.preload[name]
    original_loaded[name] = package.loaded[name]
    package.loaded[name] = nil
end

t.install_module("lib.util", {
    insert_unique = function(array, value)
        for _, item in ipairs(array) do if item == value then return end end
        table.insert(array, value)
    end
})
t.install_module("lib.const", {categories = {items = {prototypes = {"item", "assembling-machine"}}}})

local old_globals = {storage = _G.storage, prototypes = _G.prototypes}
local science = {name = "automation-science-pack", get_spoil_ticks = function() return 0 end}
local machine = {name = "machine", type = "item", place_result = {type = "assembling-machine"}, get_spoil_ticks = function() return 0 end}
local tech = {
    name = "edge-tech",
    max_level = 4294960000,
    research_trigger = {type = "craft-item"},
    research_unit_ingredients = {{name = science.name}},
    effects = {
        {type = "unlock-recipe", recipe = "edge-recipe"},
        {type = "give-item-modifier", item = machine.name}
    },
    prerequisites = {},
    successors = {}
}
prototypes = {
    get_entity_filtered = function() return {{lab_inputs = {science.name}}} end,
    item = {[science.name] = science, [machine.name] = machine},
    recipe = {['edge-recipe'] = {products = {{type = "item", name = machine.name}}}},
    technology = {['edge-tech'] = tech}
}
storage = {}

local env = require("model.env")
local tests = {
    {"initializes missing environment storage and resolves allowed effect prototypes", function()
        env.init()
        t.assert_equal(#env.get_all_sciences(), 1)
        local meta = env.get_single_tech_meta("edge-tech")
        t.assert_true(meta.is_infinite)
        t.assert_true(meta.has_trigger)
        t.assert_true(meta.research_effects["unlock-recipe"])
        t.assert_true(meta.research_prototypes.item)
        t.assert_true(meta.research_prototypes["assembling-machine"])
        t.assert_nil(env.get_single_tech_meta("missing"))
    end},
    {"returns cached environment structures without rebuilding them", function()
        local sciences = env.get_all_sciences()
        t.assert_equal(env.get_all_sciences(), sciences)
        t.assert_equal(env.get_all_tech_meta()["edge-tech"].prototype, tech)
    end}
}

local passed = t.run("env_edges_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original_preloads[name]
    package.loaded[name] = original_loaded[name]
end
_G.storage = old_globals.storage
_G.prototypes = old_globals.prototypes
return passed
