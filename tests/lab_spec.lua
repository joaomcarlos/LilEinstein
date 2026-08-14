package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local old_env = package.preload["model.env"]
local science_list = {"automation-science-pack", "logistic-science-pack"}
t.install_module("model.env", {
    get_all_sciences = function()
        return science_list
    end
})
t.reset_modules({"model.lab"})

local lab = require("model.lab")
local tests = {}

local function make_inventory(contents)
    return {
        is_empty = function() return #contents == 0 end,
        get_contents = function() return contents end
    }
end

local function make_entity(force_index, unit_number, contents, inputs)
    return {
        valid = true,
        unit_number = unit_number,
        force = {index = force_index},
        frozen = false,
        electric_buffer_size = 0,
        energy = 100,
        disabled_by_script = false,
        disabled_by_control_behavior = false,
        prototype = {lab_inputs = inputs or {"automation-science-pack", "logistic-science-pack"}},
        get_inventory = function() return make_inventory(contents) end
    }
end

local function reset_lab()
    storage = {
        lab = {},
        forces = {[1] = {lab = {all_labs = {}, lab_content = {}}}}
    }
    game = {surfaces = {}}
    defines = {inventory = {lab_input = 1}}
    lab.init()
end

tests[#tests + 1] = {"initializes global lab cursors", function()
    reset_lab()
    t.assert_equal(storage.lab.all_forces[1], nil)
    t.assert_equal(storage.lab.current_force_idx, 0)
    t.assert_equal(storage.lab.current_lab_idx, 0)
end}

tests[#tests + 1] = {"registers each lab once and returns valid entities", function()
    reset_lab()
    lab.register(nil)
    local entity = make_entity(1, 42, {})
    lab.register(entity)
    lab.register(entity)
    t.assert_equal(#storage.forces[1].lab.all_labs, 1)
    t.assert_equal(storage.forces[1].lab.all_labs[1], 42)
    t.assert_equal(lab.get_registered_labs(1)[1], entity)
end}

tests[#tests + 1] = {"filters invalid registered entities", function()
    reset_lab()
    local entity = make_entity(1, 42, {})
    lab.register(entity)
    entity.valid = false
    t.assert_equal(#lab.get_registered_labs(1), 0)
end}

tests[#tests + 1] = {"calculates fill rate from recorded snapshots", function()
    reset_lab()
    storage.forces[1].lab.lab_content = {
        [1] = {
            all_ticks = {10, 20},
            [10] = {['automation-science-pack'] = 5},
            [20] = {['automation-science-pack'] = 3, ['logistic-science-pack'] = 1}
        },
        [2] = {all_ticks = {10}}
    }
    local fill = lab.get_labs_fill_rate(1)
    t.assert_equal(fill["automation-science-pack"], 100)
    t.assert_equal(fill["logistic-science-pack"], 50)
end}

tests[#tests + 1] = {"calculates science availability from powered labs", function()
    reset_lab()
    local first = make_entity(1, 1, {{name = "automation-science-pack", count = 10}},
        {"automation-science-pack", "logistic-science-pack"})
    local second = make_entity(1, 2, {{name = "logistic-science-pack", count = 10}},
        {"automation-science-pack", "logistic-science-pack"})
    lab.register(first)
    lab.register(second)
    local availability = lab.get_science_availability(1)
    t.assert_equal(availability["automation-science-pack"].allowing, 2)
    t.assert_equal(availability["automation-science-pack"].with, 1)
    t.assert_equal(availability["automation-science-pack"].frac, 0.5)
    t.assert_equal(availability["logistic-science-pack"].with, 1)
end}

tests[#tests + 1] = {"skips frozen, empty, and disabled labs", function()
    reset_lab()
    local entity = make_entity(1, 1, {{name = "automation-science-pack", count = 1}})
    entity.frozen = true
    lab.register(entity)
    local availability = lab.get_science_availability(1)
    t.assert_equal(availability["automation-science-pack"].allowing, 0)
end}

tests[#tests + 1] = {"returns runtime content without exposing missing storage", function()
    reset_lab()
    t.assert_equal(lab.get_runtime_lab_content(1), storage.forces[1].lab.lab_content)
    t.assert_equal(#lab.get_runtime_lab_content(99), 0)
end}

tests[#tests + 1] = {"initializes a force and discovers surface labs", function()
    reset_lab()
    local entity = make_entity(1, 7, {})
    game.surfaces = {{find_entities_filtered = function() return {entity} end}}
    lab.init_force(1)
    lab.init_force(1)
    t.assert_equal(#storage.lab.all_forces, 1)
    t.assert_equal(#storage.forces[1].lab.all_labs, 1)
    t.assert_equal(storage.forces[1].lab.all_labs[1], 7)
end}

tests[#tests + 1] = {"staggeredly records live lab inventory and status", function()
    reset_lab()
    local entity = make_entity(1, 8, {{name = "automation-science-pack", count = 12}})
    entity.status = "working"
    lab.register(entity)
    storage.lab.all_forces = {1}
    storage.lab.current_force_idx = 0
    storage.lab.current_lab_idx = 0
    game.tick = 42
    lab.tick_update()
    local content = storage.forces[1].lab.lab_content[8]
    t.assert_equal(content.latest_contents[1].name, "automation-science-pack")
    t.assert_equal(content.latest_contents[1].count, 12)
    t.assert_equal(content.latest_status, "working")
    t.assert_equal(content.latest_tick, 42)
    t.assert_equal(content[42]["automation-science-pack"], 12)
end}

tests[#tests + 1] = {"resumes bounded lab sampling across scheduler calls", function()
    reset_lab()
    science_list = {}
    for index = 1, 7 do
        science_list[index] = "science-" .. tostring(index)
    end
    for unit_number = 1, 75 do
        local entity = make_entity(1, unit_number, {})
        entity.status = "missing-science-packs"
        lab.register(entity)
    end
    storage.lab.all_forces = {1}
    storage.lab.current_force_idx = 0
    storage.lab.current_lab_idx = 0

    game.tick = 42
    lab.tick_update()
    t.assert_nil(storage.forces[1].lab.lab_content[1].latest_tick,
        "the first 74-lab batch must remain bounded")

    game.tick = 84
    lab.tick_update()
    t.assert_equal(storage.forces[1].lab.lab_content[1].latest_tick, 84,
        "the next scheduler call must resume at the unsampled lab")

    science_list = {"automation-science-pack", "logistic-science-pack"}
end}

tests[#tests + 1] = {"skips labs without an inventory and expires old snapshots", function()
    reset_lab()
    local entity = make_entity(1, 10, {})
    entity.get_inventory = function() return nil end
    lab.register(entity)
    storage.lab.all_forces = {1}
    storage.lab.current_force_idx = 0
    storage.lab.current_lab_idx = 0
    game.tick = 1000
    storage.forces[1].lab.lab_content[10].all_ticks = {1}
    storage.forces[1].lab.lab_content[10][1] = {['automation-science-pack'] = 1}
    lab.tick_update()
    t.assert_equal(storage.forces[1].lab.lab_content[10].latest_contents, nil)

    entity.get_inventory = function() return make_inventory({}) end
    storage.lab.current_force_idx = 1
    storage.lab.current_lab_idx = 1
    lab.tick_update()
    t.assert_true(storage.forces[1].lab.lab_content[10].all_ticks[1] == game.tick)
end}

tests[#tests + 1] = {"removes invalid labs during the staggered update", function()
    reset_lab()
    storage.forces[1].lab.all_labs = {9}
    storage.forces[1].lab.lab_content = {[9] = {lab = {valid = false}}}
    storage.lab.all_forces = {1}
    storage.lab.current_force_idx = 0
    storage.lab.current_lab_idx = 0
    lab.tick_update()
    t.assert_equal(#storage.forces[1].lab.all_labs, 0)
    t.assert_nil(storage.forces[1].lab.lab_content[9])
end}

tests[#tests + 1] = {"initializes missing global and force lab stores safely", function()
    storage = {forces = {[1] = {}}}
    game = {surfaces = {}}
    defines = {inventory = {lab_input = 1}}
    lab.init()
    lab.init_force(1)
    t.assert_equal(storage.forces[1].lab.all_labs[1], nil)
    storage.lab.all_forces = {}
    lab.tick_update()
end}

tests[#tests + 1] = {"selects bounded stagger budgets for larger science sets", function()
    reset_lab()
    storage.lab.all_forces = {1}
    storage.lab.current_force_idx = 1
    storage.lab.current_lab_idx = 1
    science_list = {}
    for index = 1, 7 do science_list[index] = "science-" .. index end
    lab.tick_update()
    science_list = {}
    for index = 1, 512 do science_list[index] = "science-" .. index end
    lab.tick_update()
    science_list = {"automation-science-pack", "logistic-science-pack"}
end}

local passed = t.run("lab_spec", tests)
package.preload["model.env"] = old_env
package.loaded["model.lab"] = nil
return passed
