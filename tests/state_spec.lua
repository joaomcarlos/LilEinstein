package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local old_translate = package.preload["model.state.translate"]
local translations = {}
t.install_module("model.state.translate", {
    request = function(player_index) translations[player_index] = true end,
    tick_request = function() translations.ticked = true end,
    store = function(player_index, id, translated_string) translations[player_index .. ":" .. id] = translated_string end,
    get = function(player_index, kind, name, field)
        return translations[player_index .. ":" .. kind .. ":" .. name .. ":" .. field]
    end
})
t.reset_modules({"model.state"})

local state = require("model.state")
local tests = {}

local function reset_state()
    storage = {
        players = {[1] = {}},
        forces = {[1] = {}}
    }
    game = {tick = 100}
    translations = {}
    state.init_player(1)
    state.init_force(1)
end

tests[#tests + 1] = {"initializes player and force state", function()
    reset_state()
    t.assert_true(storage.players[1].state ~= nil)
    t.assert_true(storage.forces[1].state.tick_flags ~= nil)
    t.assert_true(translations[1])
end}

tests[#tests + 1] = {"reads, writes, clears, and toggles player settings", function()
    reset_state()
    t.assert_equal(state.get_player_setting(1, "show", "default"), "default")
    state.set_player_setting(1, "show", false)
    t.assert_false(state.get_player_setting(1, "show", true))
    state.toggle_player_setting(1, "show")
    t.assert_true(state.get_player_setting(1, "show", false))
    state.clear_player_setting(1, "show")
    t.assert_equal(state.get_player_setting(1, "show", "default"), "default")
end}

tests[#tests + 1] = {"turns non-boolean settings off", function()
    reset_state()
    state.set_player_setting(1, "mode", "balanced")
    state.toggle_player_setting(1, "mode")
    t.assert_false(state.get_player_setting(1, "mode", true))
    state.set_force_setting(1, "mode", "balanced")
    state.toggle_force_setting(1, "mode")
    t.assert_false(state.get_force_setting(1, "mode", true))
end}

tests[#tests + 1] = {"reads, writes, clears, and toggles force settings", function()
    reset_state()
    t.assert_equal(state.get_force_setting(1, "mode", "default"), "default")
    state.set_force_setting(1, "mode", false)
    t.assert_false(state.get_force_setting(1, "mode", true))
    state.toggle_force_setting(1, "mode")
    t.assert_true(state.get_force_setting(1, "mode", false))
    state.clear_force_setting(1, "mode")
    t.assert_equal(state.get_force_setting(1, "mode", "default"), "default")
end}

tests[#tests + 1] = {"expires one-shot update flags at the requested tick", function()
    reset_state()
    local force = {index = 1}
    state.request_gui_update(nil)
    state.request_next_research(nil)
    state.request_queue_sync(nil)
    t.assert_false(state.gui_needs_update(nil))
    storage.forces[1].state = nil
    t.assert_false(state.gui_needs_update(force))
    storage.forces[1].state = {}
    t.assert_false(state.gui_needs_update(force))
    storage.forces[1].state.tick_flags = {}
    state.request_next_research(force)
    state.request_queue_sync(force)
    game.tick = 102
    t.assert_true(state.research_needs_next(force))
    t.assert_true(state.queue_needs_sync(force))
    state.request_gui_update(force)
    t.assert_false(state.gui_needs_update(force))
    game.tick = 103
    t.assert_true(state.gui_needs_update(force))
    t.assert_false(state.gui_needs_update(force))

    state.request_ingame_queue_cleanup(force)
    game.tick = 700
    t.assert_false(state.ingame_queue_needs_cleanup(force))
    game.tick = 1303
    t.assert_true(state.ingame_queue_needs_cleanup(force))
end}

tests[#tests + 1] = {"stores and retrieves translated strings", function()
    reset_state()
    state.store_translation(1, 7, "Automation", {"technology-name.automation"})
    t.assert_equal(state.get_translation(1, "technology", "automation", "localised_name"), nil)
    translations["1:technology:automation:localised_name"] = "Automation"
    t.assert_equal(state.get_translation(1, "technology", "automation", "localised_name"), "Automation")
end}

tests[#tests + 1] = {"forwards translation tick requests", function()
    reset_state()
    state.tick_request_translation()
    t.assert_true(translations.ticked)
end}

local passed = t.run("state_spec", tests)
package.preload["model.state.translate"] = old_translate
package.loaded["model.state"] = nil
return passed
