package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local testlib = require("tests.testlib")
local names = {"lib.const", "lib.log", "lib.util", "view.gui.builder"}
local original = {}
for _, name in ipairs(names) do
    original[name] = package.preload[name]
    package.loaded[name] = nil
end

local errors = {}
testlib.install_module("lib.const", {announcements = {"low", "normal", "high"}})
testlib.install_module("lib.log", {error = function(_, message) errors[#errors + 1] = message end})
testlib.install_module("lib.util", {})
local builder = require("view.gui.builder")

local function get_upvalue(function_value, wanted)
    for index = 1, 32 do
        local name, value = debug.getupvalue(function_value, index)
        if not name then return nil end
        if name == wanted then return value end
    end
    return nil
end

local function make_element(fail_first, fail_name)
    local element = {
        children = {}, style = {}, valid = true, failed = not fail_first, fail_name = fail_name
    }

    element.add = function(prop)
        if element.fail_name and prop.name == element.fail_name then
            error("simulated permanently unsupported element")
        end
        if not element.failed then
            element.failed = true
            error("simulated unsupported property")
        end
        local child = make_element(false, element.fail_name)
        for key, value in pairs(prop) do
            if key ~= "style" then child[key] = value end
        end
        if prop.name then element[prop.name] = child end
        table.insert(element.children, child)
        return child
    end

    element.add_tab = function(first, second)
        element.tabs = element.tabs or {}
        table.insert(element.tabs, {first, second})
    end

    return element
end

local function find_named(element, wanted)
    if element.name == wanted then
        return element
    end
    for _, child in ipairs(element.children or {}) do
        local found = find_named(child, wanted)
        if found then
            return found
        end
    end
end

local tests = {
    {"does nothing when the player has disappeared", function()
        _G.game = {get_player = function() return nil end}
        testlib.assert_nil(builder.build(1, make_element(false)))
    end},
    {"recursively builds the main GUI structure and opens it", function()
        local player = {opened = nil}
        local anchor = make_element(false)
        _G.game = {get_player = function() return player end}
        builder.build(1, anchor)
        local main = anchor.lil_einstein_gui
        testlib.assert_true(main ~= nil, "main GUI frame")
        testlib.assert_true(#main.children > 0, "main GUI children")
        testlib.assert_true(main.auto_center)
        testlib.assert_equal(main.style.height, 941)
        testlib.assert_equal(player.opened, main)
        testlib.assert_true(main.footer_frame ~= nil, "footer frame")
        testlib.assert_true(main.footer_frame.research_status_bar ~= nil, "research status bar")
        local details_button = find_named(main, "research_health_details_button")
        local copy_debug_button = find_named(main, "research_health_copy_debug_button")
        testlib.assert_equal(details_button.type, "button")
        testlib.assert_equal(copy_debug_button.type, "sprite-button")
        testlib.assert_equal(copy_debug_button.sprite, "utility/copy")
        testlib.assert_true(anchor.brand_header == nil, "brand header belongs below main frame")
    end},
    {"retries an element without style after the first add fails", function()
        errors = {}
        local player = {opened = nil}
        local anchor = make_element(true)
        _G.game = {get_player = function() return player end}
        builder.build(1, anchor)
        testlib.assert_true(anchor.lil_einstein_gui ~= nil, "fallback must still add the root")
        testlib.assert_equal(#errors, 0, "successful fallback must not log an error")
    end},
    {"logs and continues when a nested element cannot be added", function()
        errors = {}
        local player = {opened = nil}
        local anchor = make_element(false, "search_button")
        _G.game = {get_player = function() return player end}
        builder.build(1, anchor)
        testlib.assert_true(anchor.lil_einstein_gui ~= nil, "the parent frame must still be built")
        testlib.assert_true(#errors > 0, "a permanently unsupported child must be logged")
    end},
    {"builds a focused, selectable debug report text box", function()
        local player = {opened = nil}
        local anchor = make_element(false)
        _G.game = {get_player = function() return player end}
        local frame = builder.build_debug_report(1, anchor, "debug text")
        testlib.assert_true(frame ~= nil, "debug report frame")
        local text_box = frame.lil_einstein_debug_report_text
        testlib.assert_equal(text_box.text, "debug text")
        testlib.assert_true(text_box.read_only)
        testlib.assert_true(text_box.selectable)
        testlib.assert_false(text_box.word_wrap)
        testlib.assert_equal(player.opened, text_box)
    end},
    {"does not dereference report text after it becomes invalid on open", function()
        local text_box
        local player = setmetatable({}, {
            __newindex = function(self, key, value)
                if key == "opened" and value.name == "lil_einstein_debug_report_text" then
                    text_box = value
                    setmetatable(value, {
                        __index = function(element, field)
                            if field ~= "valid" and rawget(element, "valid") == false then
                                error("LuaGuiElement API call when LuaGuiElement was invalid")
                            end
                            return rawget(element, field)
                        end
                    })
                    value.valid = false
                end
                rawset(self, key, value)
            end
        })
        local anchor = make_element(false)
        _G.game = {get_player = function() return player end}
        local ok, err = pcall(function()
            builder.build_debug_report(1, anchor, "debug text")
        end)
        testlib.assert_true(ok, err)
        testlib.assert_false(text_box.valid)
    end},
    {"covers private builder fallbacks, empty structures, and tab mappings", function()
        errors = {}
        local build_recursive = get_upvalue(builder.build, "build_recursive")
        testlib.assert_true(type(build_recursive) == "function")

        local sprite_parent = make_element(true)
        testlib.assert_true(build_recursive(sprite_parent, {type = "sprite", name = "sprite"}))
        local empty_parent = make_element(true)
        testlib.assert_false(build_recursive(empty_parent, {name = "empty"}))

        local mapped_parent = make_element(true)
        testlib.assert_true(build_recursive(mapped_parent, {
            type = "flow",
            name = "mapped",
            children = {{type = "label", name = "left"}, {type = "label", name = "right"}},
            mapping = {{"left", "right"}}
        }))
        local mapped = mapped_parent.mapped
        testlib.assert_equal(#mapped.tabs, 1)
        testlib.assert_equal(mapped.tabs[1][1], mapped.left)
        testlib.assert_equal(mapped.tabs[1][2], mapped.right)
    end}
}

local passed = testlib.run("builder_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original[name]
    package.loaded[name] = nil
end
return passed
