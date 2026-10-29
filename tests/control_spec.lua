package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
package.loaded["lib.gui_schedule"] = nil
local schedule = require("lib.gui_schedule")
local status_bar_ticks = 600

local function load_control()
    local handlers = {}
    local modules = {}
    local runtime = setmetatable({
        storage = {forces = {}, players = {}},
        game = {tick = 0, forces = {}, surfaces = {}, players = {}},
        settings = {global = {
            ["lil_einstein-show-warnings"] = {value = false},
            ["lil_einstein-notify-switches"] = {value = false},
            ["lil_einstein-warn-every-n-seconds"] = {value = 60}
        }},
        defines = {events = setmetatable({}, {
            __index = function(_, name) return name end
        })}
    }, {__index = _G})
    runtime._G = runtime
    runtime.script = {
        active_mods = {},
        on_event = function(events, handler)
            for _, event in ipairs(type(events) == "table" and events or {events}) do
                handlers[event] = handler
            end
        end,
        on_init = function(handler) handlers.init = handler end,
        on_load = function() end,
        on_configuration_changed = function(handler) handlers.configuration_changed = handler end,
        on_nth_tick = function() end
    }
    -- Isolate module globals while exercising the real model and event handlers.
    runtime.require = function(name)
        if not modules[name] then
            if name == "model.cmd" then
                modules[name] = {register_commands = function() end}
            elseif name:match("^view%.") then
                modules[name] = {}
            else
                modules[name] = assert(loadfile(name:gsub("%.", "/") .. ".lua", "t", runtime))()
            end
        end
        return modules[name]
    end
    local force = {index = 4, name = "new-force", research_queue = {}}
    local completed = {
        name = "enable-logistics-tab", force = force, researched = false, valid = true,
        enabled = true, hidden = false, max_level = 1, prerequisites = {}, successors = {}
    }
    local successor = {
        name = "successor", force = force, researched = false, valid = true,
        enabled = true, hidden = false, max_level = 1,
        prerequisites = {[completed.name] = completed}, successors = {}
    }
    completed.successors[successor.name] = successor
    force.technologies = {[completed.name] = completed, [successor.name] = successor}
    runtime.game.forces[force.index] = force
    runtime.prototypes = {
        technology = force.technologies,
        get_entity_filtered = function() return {} end
    }
    assert(loadfile("control.lua", "t", runtime))()
    modules["model.env"].init()
    modules["model.lab"].init()
    return runtime, handlers, modules, force, completed
end

local tests = {
    {"keeps the status bar on a ten-second cadence", function()
        t.assert_true(schedule.is_due(600, status_bar_ticks))
        t.assert_true(schedule.is_due(1200, status_bar_ticks))
        t.assert_false(schedule.is_due(599, status_bar_ticks))
    end},
    {"refreshes only connected players with the UI open", function()
        local open = { [1] = true, [2] = false }
        local refreshed = {}
        schedule.refresh_open_players({
            {index = 1},
            {index = 2},
            {index = 3}
        }, function(player_index)
            return open[player_index] == true
        end, function(player_index, advance)
            table.insert(refreshed, {index = player_index, advance = advance})
        end)

        t.assert_equal(#refreshed, 1)
        t.assert_equal(refreshed[1].index, 1)
        t.assert_true(refreshed[1].advance)
    end},
    {"defers research events until the new force is initialized", function()
        for _, event in ipairs({
            "on_research_finished", "on_research_reversed", "on_research_queued",
            "on_research_moved", "on_research_cancelled"
        }) do
            local runtime, handlers, modules, force, completed = load_control()
            completed.researched = true
            handlers[event]({force = force, research = completed})
            t.assert_nil(runtime.storage.forces[force.index])

            handlers.on_force_created({force = force})
            local all = modules["model.tech"].get_all_tech_state_ext(force.index)
            t.assert_true(all.successor.available)
            t.assert_true(runtime.storage.forces[force.index].queue ~= nil)
            t.assert_equal(#runtime.storage.forces[force.index].research_policy.history, 0)
        end
    end},
    {"defers force creation and research until global initialization", function()
        local runtime, handlers, modules, force, completed = load_control()
        runtime.storage = {}
        completed.researched = true
        handlers.on_research_finished({research = completed})
        handlers.on_force_created({force = force})
        t.assert_nil(runtime.storage.forces)

        handlers.init()
        t.assert_true(modules["model.tech"].get_all_tech_state_ext(force.index).successor.available)
        t.assert_true(runtime.storage.forces[force.index].queue ~= nil)
    end},
    {"leaves partially initialized force state untouched by research", function()
        local runtime, handlers, _, force, completed = load_control()
        local sf = {state = {}, tech = {}}
        runtime.storage.forces[force.index] = sf
        handlers.on_research_finished({research = completed})
        t.assert_equal(runtime.storage.forces[force.index], sf)
        t.assert_nil(sf.queue)
        t.assert_nil(sf.research_policy)
    end},
    {"synchronizes research queued before force initialization", function()
        local runtime, handlers, modules, force, completed = load_control()
        force.research_queue = {completed}
        handlers.on_research_queued({force = force})
        handlers.on_force_created({force = force})

        runtime.game.tick = 1
        t.assert_true(modules["model.state"].queue_needs_sync(force))
        modules["model.queue"].sync_ingame_queue(force)
        t.assert_equal(modules["model.queue"].get_queue(force.index)[1], completed.name)
    end},
    {"preserves an initialized force's plan during configuration changes", function()
        local runtime, handlers, modules, force, completed = load_control()
        handlers.on_force_created({force = force})
        modules["model.queue"].add(force, "successor", nil, true)
        force.research_queue = {completed}
        handlers.configuration_changed()

        t.assert_nil(runtime.storage.forces[force.index].state.tick_flags.queue_needs_update)
        t.assert_equal(modules["model.queue"].get_queue(force.index)[1], "successor")
    end},
    {"processes research normally after force initialization", function()
        local runtime, handlers, modules, force, completed = load_control()
        handlers.on_force_created({force = force})
        local sf = runtime.storage.forces[force.index]
        local all = modules["model.tech"].get_all_tech_state_ext(force.index)
        t.assert_false(all.successor.available)

        completed.researched = true
        handlers.on_research_finished({research = completed})
        t.assert_true(all.successor.available)
        t.assert_equal(sf.research_policy.history[1].action, "research_finished")
        t.assert_equal(sf.state.tick_flags.needs_next_research, 1)

        sf.state.tick_flags.needs_next_research = nil
        completed.researched = false
        handlers.on_research_reversed({research = completed})
        t.assert_equal(sf.state.tick_flags.needs_next_research, 1)
        t.assert_equal(runtime.storage.forces[force.index], sf)
    end}
}

return t.run("control_spec", tests)
