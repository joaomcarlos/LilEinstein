package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local old_state = package.preload["model.state"]
local translations = {}
t.install_module("model.state", {
    get_translation = function(player_index, kind, name, field)
        return translations[player_index .. ":" .. kind .. ":" .. name .. ":" .. field]
    end
})
t.reset_modules({"view.gui.gutil"})

local gutil = require("view.gui.gutil")
local tests = {}

tests[#tests + 1] = {"formats compact SI values", function()
    t.assert_equal(gutil.format_si(0), "0")
    t.assert_equal(gutil.format_si(999), "999")
    t.assert_equal(gutil.format_si(1000), "1K")
    t.assert_equal(gutil.format_si(1250), "1.3K")
    t.assert_equal(gutil.format_si(999960), "1M")
    t.assert_equal(gutil.format_si(-1250), "-1.3K")
    t.assert_equal(gutil.format_si(nil), "0")
end}

tests[#tests + 1] = {"keeps non-finite values explicit", function()
    t.assert_equal(gutil.format_si(0 / 0), tostring(0 / 0))
    t.assert_equal(gutil.format_si(math.huge), tostring(math.huge))
end}

tests[#tests + 1] = {"enables descendants while respecting ignore tags", function()
    local ignored = {valid = true, tags = {ignore_force_enable = true}, enabled = false, children = {}}
    local child = {valid = true, enabled = false, children = {}}
    local parent = {valid = true, enabled = false, children = {ignored, child}}
    gutil.disenable_recursive(parent, true)
    t.assert_true(parent.enabled)
    t.assert_false(ignored.enabled)
    t.assert_true(child.enabled)
end}

tests[#tests + 1] = {"resolves and caches GUI children", function()
    local leaf = {valid = true, name = "leaf", children = {}}
    local anchor = {valid = true, index = 1, name = "anchor", children = {{valid = true, name = "branch", children = {leaf}}}}
    t.assert_equal(gutil.get_child(anchor, "leaf"), leaf)
    leaf.valid = false
    t.assert_nil(gutil.get_child(anchor, "leaf"))
    leaf.valid = true
    gutil.clear_child_cache()
    t.assert_equal(gutil.get_child(anchor, "leaf"), leaf)
    anchor.valid = false
    t.assert_nil(gutil.get_child(anchor, "leaf"))
end}

tests[#tests + 1] = {"formats translated technology names and levels", function()
    translations["1:technology:worker-robots-speed-7:localised_name"] = "Worker robot speed 7 (infinite)"
    local xcur = {
        technology = {name = "worker-robots-speed-7", level = 7},
        meta = {is_infinite = true}
    }
    t.assert_equal(gutil.get_tech_name(1, xcur), "Worker robot speed 7 (infinite)")
    t.assert_equal(gutil.get_tech_name(1, xcur, 8), "Worker robot speed 8 (infinite)")
end}

local passed = t.run("gutil_spec", tests)
package.preload["model.state"] = old_state
package.loaded["view.gui.gutil"] = nil
return passed
