package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local names = {"model.env", "model.state", "model.tech", "model.queue", "model.lab", "lib.log", "view.gui"}
local old_preloads = {}
for _, name in ipairs(names) do
    old_preloads[name] = package.preload[name]
end

local calls = {}
local queue = {
    clear = function(force) calls.clear = force end,
    add = function(force, name) calls.add = calls.add or {}; table.insert(calls.add, name) end,
    init_force = function() calls.queue_init = true end
}
local state = {
    init_player = function() calls.player_init = true end,
    init_force = function() calls.state_init = true end
}
local tech = {
    init_force = function() calls.tech_init = true end
}
local lab = {
    init = function() calls.lab_init = true end,
    init_force = function() calls.lab_force_init = true end,
    get_labs_fill_rate = function() return {['automation-science-pack'] = 100} end
}
local env = {init = function() calls.env_init = true end}
local gui = {init_player = function() calls.gui_init = true end}
local logger = {
    log = function() calls.log = (calls.log or 0) + 1 end
}
for name, value in pairs({
    ["model.env"] = env,
    ["model.state"] = state,
    ["model.tech"] = tech,
    ["model.queue"] = queue,
    ["model.lab"] = lab,
    ["lib.log"] = logger,
    ["view.gui"] = gui
}) do
    t.install_module(name, value)
end
t.reset_modules({"model.cmd"})

local registered = {}
commands = {
    add_command = function(name, help, handler)
        registered[name] = {help = help, handler = handler}
    end
}
serpent = {block = function(value) return "SERPENT:" .. tostring(value) end}
log = function() calls.raw_log = (calls.raw_log or 0) + 1 end
prototypes = {
    technology = {
        ["triggered"] = {research_trigger = {}, name = "triggered"},
        ["normal"] = {research_trigger = nil, name = "normal"},
        ["existing"] = {research_trigger = nil, name = "existing"},
        ["automation"] = {research_trigger = nil, name = "automation"}
    }
}

local force = {
    index = 1,
    technologies = {
        triggered = {
            researched = false,
            prerequisites = {},
            research_recursive = function() calls.triggered_research = true end
        },
        normal = {
            researched = false,
            prerequisites = {},
            research_recursive = function() calls.normal_research = true end
        },
        existing = {
            researched = false,
            prerequisites = {},
            research_recursive = function() calls.existing_research = true end
        },
        automation = {
            researched = false,
            prerequisites = {},
            research_recursive = function() calls.automation_research = true end
        }
    },
    reset = function() calls.force_reset = true end
}
local admin = {
    name = "Subject314159",
    force = force,
    print = function(message) calls.printed = message end
}
local stranger = {
    name = "not-admin",
    force = force,
    print = function(message) calls.printed = message end
}
game = {
    tick = 42,
    forces = {[1] = force},
    players = {[1] = {index = 1, force = force}},
    get_player = function(index)
        if index == 1 then return admin end
        if index == 2 then return stranger end
    end
}
storage = {players = {}, forces = {}}

local cmd = require("model.cmd")
local tests = {}

tests[#tests + 1] = {"registers all debug commands", function()
    cmd.register_commands()
    t.assert_true(registered.reinit ~= nil)
    t.assert_true(registered.dump ~= nil)
    t.assert_true(registered.unblock ~= nil)
    t.assert_true(registered.test1 ~= nil)
end}

tests[#tests + 1] = {"rejects commands from non-admin players", function()
    registered.unblock.handler({player_index = 2})
    t.assert_equal(calls.printed[1], "unknown-command")
    registered.test1.handler({player_index = 2})
    registered.unblock.handler({player_index = 99})
end}

tests[#tests + 1] = {"reinitializes through the public command", function()
    registered.reinit.handler({player_index = 1})
    t.assert_true(calls.env_init)
    t.assert_true(calls.lab_init)
    t.assert_true(calls.state_init)
    t.assert_true(calls.tech_init)
    t.assert_true(calls.queue_init)
    t.assert_true(calls.lab_force_init)
    t.assert_true(calls.player_init)
    t.assert_true(calls.gui_init)
end}

tests[#tests + 1] = {"dumps lab data through logger and raw log", function()
    registered.dump.handler({player_index = 1})
    t.assert_true((calls.raw_log or 0) >= 2)
    t.assert_true((calls.log or 0) >= 1)
end}

tests[#tests + 1] = {"unblocks available trigger technologies", function()
    force.technologies.triggered.prerequisites = {{researched = true}}
    registered.unblock.handler({player_index = 1})
    t.assert_true(calls.triggered_research)
end}

tests[#tests + 1] = {"runs the test1 queue setup command", function()
    registered.test1.handler({player_index = 1})
    t.assert_true(calls.clear == force)
    t.assert_true(calls.force_reset)
    t.assert_equal(#calls.add, 4)
    t.assert_true(calls.force_reset)
    t.assert_true(calls.automation_research)
    admin.force = nil
    registered.test1.handler({player_index = 1})
    admin.force = force
end}

tests[#tests + 1] = {"initializes missing storage and reports when nothing can unblock", function()
    storage = nil
    registered.reinit.handler({player_index = 1})
    t.assert_true(storage.forces ~= nil)
    for _, item in pairs(force.technologies) do
        item.researched = true
    end
    registered.unblock.handler({player_index = 1})
    t.assert_true((calls.log or 0) >= 2)
    game.players = {[1] = {}}
    registered.reinit.handler({player_index = 1})
end}

local passed = t.run("cmd_spec", tests)
package.loaded["model.cmd"] = nil
for _, name in ipairs(names) do
    package.preload[name] = old_preloads[name]
    package.loaded[name] = nil
end
return passed
