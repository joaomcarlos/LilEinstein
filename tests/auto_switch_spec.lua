package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
t.reset_modules({"model.auto_switch"})

local auto_switch = require("model.auto_switch")

local tests = {}

local science_list = {"automation-science-pack", "logistic-science-pack"}
local runtime_lab_content = {}

local function make_inventory(contents)
    return {
        is_empty = function() return #contents == 0 end,
        get_contents = function() return contents end
    }
end

local function make_lab(unit_number, contents, inputs, options)
    options = options or {}
    return {
        valid = options.valid ~= false,
        unit_number = unit_number,
        frozen = options.frozen or false,
        electric_buffer_size = options.electric_buffer_size or 0,
        energy = options.energy == nil and 100 or options.energy,
        disabled_by_script = options.disabled_by_script or false,
        disabled_by_control_behavior = options.disabled_by_control_behavior or false,
        prototype = {lab_inputs = inputs or science_list},
        get_inventory = function() return make_inventory(contents or {}) end
    }
end

local function reset()
    runtime_lab_content = {}
    science_list = {"automation-science-pack", "logistic-science-pack"}
    game = {tick = 100}
    defines = {inventory = {lab_input = 1}}
    auto_switch.invalidate()
end

local function get_avail(force_index, force_refresh)
    return auto_switch.get_availability(force_index, force_refresh, runtime_lab_content, science_list)
end

local function get_missing(force_index, technology)
    return auto_switch.get_missing_sciences(force_index, technology, runtime_lab_content, science_list)
end

tests[#tests + 1] = {"counts exact mixed-pack with allowing and fraction", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    runtime_lab_content[2] = {lab = make_lab(2,
        {{name = "logistic-science-pack", count = 10}})}
    local avail = get_avail(1, true)
    t.assert_equal(avail["automation-science-pack"].with, 1)
    t.assert_equal(avail["automation-science-pack"].allowing, 2)
    t.assert_equal(avail["automation-science-pack"].fraction, 0.5)
    t.assert_equal(avail["logistic-science-pack"].with, 1)
    t.assert_equal(avail["logistic-science-pack"].allowing, 2)
    t.assert_equal(avail["logistic-science-pack"].fraction, 0.5)
    t.assert_equal(avail.__lab_count, 2)
end}

tests[#tests + 1] = {"skips frozen labs", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 1}}, nil, {frozen = true})}
    local avail = get_avail(1, true)
    t.assert_equal(avail["automation-science-pack"].allowing, 0)
    t.assert_equal(avail.__lab_count, 0)
end}

tests[#tests + 1] = {"skips unpowered labs", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 1}}, nil,
        {electric_buffer_size = 100, energy = 0})}
    local avail = get_avail(1, true)
    t.assert_equal(avail["automation-science-pack"].allowing, 0)
    t.assert_equal(avail.__lab_count, 0)
end}

tests[#tests + 1] = {"skips disabled labs", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 1}}, nil,
        {disabled_by_script = true})}
    local avail = get_avail(1, true)
    t.assert_equal(avail["automation-science-pack"].allowing, 0)
    t.assert_equal(avail.__lab_count, 0)
end}

tests[#tests + 1] = {"counts empty labs in the accepting denominator", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1, {})}
    local avail = get_avail(1, true)
    t.assert_equal(avail["automation-science-pack"].allowing, 1,
        "an empty lab that accepts the pack must count in the denominator")
    t.assert_equal(avail["automation-science-pack"].with, 0)
    t.assert_equal(avail["automation-science-pack"].fraction, 0)
    t.assert_equal(avail.__lab_count, 1)
end}

tests[#tests + 1] = {"skips invalid labs", function()
    reset()
    local entity = make_lab(1, {{name = "automation-science-pack", count = 1}})
    entity.valid = false
    runtime_lab_content[1] = {lab = entity}
    local avail = get_avail(1, true)
    t.assert_equal(avail["automation-science-pack"].allowing, 0)
    t.assert_equal(avail.__lab_count, 0)
end}

tests[#tests + 1] = {"returns safe empty data for missing force", function()
    reset()
    local avail = auto_switch.get_availability(99, true, {}, science_list)
    t.assert_equal(avail.__lab_count, 0)
    t.assert_equal(avail["automation-science-pack"].allowing, 0)
    t.assert_equal(avail["automation-science-pack"].with, 0)
    t.assert_equal(avail["automation-science-pack"].fraction, 0)
end}

tests[#tests + 1] = {"caches scan per force within the bounded interval", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    local first = get_avail(1, true)
    t.assert_equal(first["automation-science-pack"].with, 1)
    -- Change lab content; cached result must not reflect the change.
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "logistic-science-pack", count = 10}})}
    local cached = get_avail(1)
    t.assert_equal(cached["automation-science-pack"].with, 1,
        "cache must reuse the previous scan within the interval")
    t.assert_equal(cached.__tick, first.__tick)
end}

tests[#tests + 1] = {"force_refresh bypasses the cache", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    get_avail(1, true)
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "logistic-science-pack", count = 10}})}
    local refreshed = get_avail(1, true)
    t.assert_equal(refreshed["automation-science-pack"].with, 0,
        "force_refresh must rescan labs")
    t.assert_equal(refreshed["logistic-science-pack"].with, 1)
end}

tests[#tests + 1] = {"invalidate clears the cache", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    get_avail(1, true)
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "logistic-science-pack", count = 10}})}
    auto_switch.invalidate(1)
    local after = get_avail(1)
    t.assert_equal(after["automation-science-pack"].with, 0,
        "invalidation must force a fresh scan")
    t.assert_equal(after["logistic-science-pack"].with, 1)
end}

tests[#tests + 1] = {"detects missing required pack for a technology", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "logistic-science-pack", count = 10}})}
    local technology = {
        valid = true,
        research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
    }
    local missing = get_missing(1, technology)
    t.assert_equal(missing["automation-science-pack"], true)
    t.assert_nil(missing["logistic-science-pack"])
end}

tests[#tests + 1] = {"returns empty for no-lab snapshot", function()
    reset()
    local technology = {
        valid = true,
        research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
    }
    local missing = get_missing(1, technology)
    t.assert_nil(next(missing))
end}

tests[#tests + 1] = {"returns empty for technology without ingredients", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    local technology = {
        valid = true,
        research_unit_ingredients = {}
    }
    local missing = get_missing(1, technology)
    t.assert_nil(next(missing))
end}

tests[#tests + 1] = {"returns empty for invalid technology", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    local technology = {
        valid = false,
        research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
    }
    local missing = get_missing(1, technology)
    t.assert_nil(next(missing))
end}

tests[#tests + 1] = {"flags a pack below the AutoSwitch threshold when some accepting labs are empty", function()
    reset()
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    runtime_lab_content[2] = {lab = make_lab(2, {})}
    local technology = {
        valid = true,
        research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
    }
    local missing = get_missing(1, technology)
    t.assert_equal(missing["automation-science-pack"], true,
        "a pack held by only 50% of accepting labs is below the 0.80 threshold and must be flagged missing")
end}

tests[#tests + 1] = {"flags a low but nonzero pack fraction at the AutoSwitch threshold", function()
    reset()
    for unit_number = 1, 10 do
        local contents = unit_number <= 2 and
            {{name = "automation-science-pack", count = 10}} or
            {{name = "logistic-science-pack", count = 10}}
        runtime_lab_content[unit_number] = {lab = make_lab(unit_number, contents)}
    end
    local technology = {
        valid = true,
        research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
    }
    local missing = get_missing(1, technology)
    t.assert_equal(missing["automation-science-pack"], true,
        "a 20% supplied pack fraction must be considered materially pack-bound")
end}

tests[#tests + 1] = {"counts a completely empty lab in the accepting denominator", function()
    reset()
    -- One lab holds the pack, one lab is completely starved (empty inventory).
    -- The empty lab still accepts the pack, so it must count in `allowing`.
    runtime_lab_content[1] = {lab = make_lab(1,
        {{name = "automation-science-pack", count = 10}})}
    runtime_lab_content[2] = {lab = make_lab(2, {})}
    local avail = get_avail(1, true)
    t.assert_equal(avail["automation-science-pack"].allowing, 2,
        "an empty lab that accepts the pack must count in the denominator")
    t.assert_equal(avail["automation-science-pack"].with, 1)
    t.assert_equal(avail["automation-science-pack"].fraction, 0.5)
    t.assert_equal(avail.__lab_count, 2,
        "an empty lab that accepts science must count in lab_count")
end}

tests[#tests + 1] = {"flags a pack missing when all accepting labs are completely empty", function()
    reset()
    -- All labs are completely starved (empty inventories). The tech requires
    -- a pack that no lab holds. This is genuine pack-bound starvation, not a
    -- no-lab snapshot, so auto_switch must flag the pack missing.
    runtime_lab_content[1] = {lab = make_lab(1, {})}
    runtime_lab_content[2] = {lab = make_lab(2, {})}
    local technology = {
        valid = true,
        research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
    }
    local missing = get_missing(1, technology)
    t.assert_equal(missing["automation-science-pack"], true,
        "a pack held by zero accepting labs must be flagged missing even when all labs are empty")
end}

local passed = t.run("auto_switch_spec", tests)
package.loaded["model.auto_switch"] = nil
return passed
