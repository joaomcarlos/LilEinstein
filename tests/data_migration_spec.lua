package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local function run_data_stage()
    local extensions = {}
    data = {
        raw = {
            ["gui-style"] = {default = {}},
            ["item-subgroup"] = {['virtual-signal'] = {}}
        },
        extend = function(_, items)
            for _, item in ipairs(items) do
                extensions[#extensions + 1] = item
            end
        end
    }
    dofile("data.lua")
    dofile("settings.lua")
    return extensions
end

local function find_extension(extensions, kind, name)
    for _, item in ipairs(extensions) do
        if item.type == kind and item.name == name then return item end
    end
end

local tests = {
    {"registers data-stage styles, inputs, signals, sprites, and settings", function()
        local extensions = run_data_stage()
        local styles = data.raw["gui-style"].default
        t.assert_true(styles.lil_einstein_main_frame ~= nil)
        t.assert_equal(styles.lil_einstein_main_frame.type, "frame_style")
        t.assert_true(find_extension(extensions, "custom-input", "lil_einstein_toggle_gui") ~= nil)
        t.assert_true(find_extension(extensions, "shortcut", "lil_einstein_shortcut") ~= nil)
        t.assert_true(find_extension(extensions, "virtual-signal", "lil_einstein-science-alert") ~= nil)
        t.assert_true(find_extension(extensions, "sprite", "lil_einstein_bin_small") ~= nil)
        local warning = find_extension(extensions, "bool-setting", "lil_einstein-show-warnings")
        t.assert_equal(warning.setting_type, "runtime-global")
        t.assert_equal(warning.default_value, false)
        t.assert_true(#extensions > 20, "data stage must register a substantial prototype set")
    end},
    {"migrates legacy queue entries and preserves modern queue tables", function()
        local forces = {
            {index = 1},
            {index = 2},
            {index = 3}
        }
        storage = {
            forces = {
                [1] = {queue = {
                    {technology_name = "automation"},
                    {technology_name = "logistics"},
                    {technology_name = 42},
                    "ignored"
                }},
                [2] = {queue = {queue = {"already-modern"}}}
            }
        }
        game = {forces = forces}
        dofile("migrations/1.1.0.lua")
        t.assert_equal(#storage.forces[1].queue.queue, 2)
        t.assert_equal(storage.forces[1].queue.queue[1], "automation")
        t.assert_equal(storage.forces[1].queue.queue[2], "logistics")
        t.assert_equal(storage.forces[2].queue.queue[1], "already-modern")
        t.assert_nil(storage.forces[3])
    end},
    {"runs blank migrations safely", function()
        storage = nil
        game = {forces = {}}
        dofile("migrations/0.5.0.lua")
        dofile("migrations/0.6.0.lua")
        dofile("migrations/0.6.4.lua")
        dofile("migrations/1.3.4.lua")
    end}
}

local passed = t.run("data_migration_spec", tests)
data = nil
storage = nil
game = nil
return passed
