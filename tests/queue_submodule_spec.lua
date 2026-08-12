package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local tests = {
    {"loads the queue data and parser extension seams", function()
        local modqueue = require("model.queue.modqueue")
        local parser = require("model.queue.parser")
        t.assert_equal(type(modqueue), "table")
        t.assert_equal(type(parser), "table")
    end}
}

return t.run("queue_submodule_spec", tests)
