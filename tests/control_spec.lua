package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
package.loaded["lib.gui_schedule"] = nil
local schedule = require("lib.gui_schedule")
local status_bar_ticks = 600

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
    end}
}

return t.run("control_spec", tests)
