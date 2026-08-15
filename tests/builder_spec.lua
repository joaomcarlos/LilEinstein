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

local function make_element_with_checkbox_state_contract()
    local make_node
    make_node = function()
        local element = {children = {}, style = {}, valid = true}
        element.add = function(prop)
            if (prop.type == "checkbox" or prop.type == "radiobutton") and type(prop.state) ~= "boolean" then
                error("Key \"state\" not found in property tree at ROOT")
            end
            local child = make_node()
            child.name = prop.name
            child.type = prop.type
            for key, value in pairs(prop) do
                if key ~= "style" then child[key] = value end
            end
            if prop.name then element[prop.name] = child end
            table.insert(element.children, child)
            return child
        end
        element.add_tab = function() end
        return element
    end
    return make_node()
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
    {"builds the compact science throughput details surface", function()
        local player = {opened = nil}
        local anchor = make_element(false)
        _G.game = {get_player = function() return player end}
        builder.build(1, anchor)
        local panel = find_named(anchor.lil_einstein_gui, "research_details_panel")
        testlib.assert_equal(panel.type, "frame")
        testlib.assert_true(find_named(panel, "research_details_warning") ~= nil)
        local back = find_named(panel, "research_details_back_button")
        testlib.assert_true(back ~= nil)
        testlib.assert_equal(back.tags.handler, "toggle_research_details")
        testlib.assert_true(find_named(panel, "research_details_analyze_button") ~= nil)
        testlib.assert_true(find_named(panel, "research_details_table_header") ~= nil)
        testlib.assert_true(find_named(panel, "research_details_rows") ~= nil)
        local analyze = find_named(panel, "research_details_analyze_button")
        testlib.assert_equal(analyze.tags.handler, "analyze_research_throughput")
    end},
    {"builds the sprite-backed research decision console shell", function()
        local player = {opened = nil}
        local anchor = make_element(false)
        _G.game = {get_player = function() return player end}
        builder.build(1, anchor)
        local panel = find_named(anchor.lil_einstein_gui, "policy_panel")
        testlib.assert_equal(panel.name, "policy_panel")
        testlib.assert_true(find_named(panel, "decision_console_header") ~= nil)
        testlib.assert_true(find_named(panel, "decision_console_stage_row") ~= nil)
        testlib.assert_true(find_named(panel, "decision_automation_surface") ~= nil)
        testlib.assert_equal(find_named(panel, "decision_back_button").tags.handler, "toggle_policy_panel")
        testlib.assert_equal(find_named(panel, "policy_tab_history").tags.tab, "history")
    end},
    {"builds the science-pack inspector as a top-level replacement surface", function()
        local player = {opened = nil}
        local anchor = make_element(false)
        _G.game = {get_player = function() return player end}
        builder.build(1, anchor)
        local main = anchor.lil_einstein_gui
        local panel = main.science_pack_panel
        testlib.assert_true(panel ~= nil, "science-pack panel must be top-level")
        testlib.assert_true(main.content_flow ~= nil, "normal content must remain separate")
        local right = find_named(main, "right")
        testlib.assert_true(right ~= nil, "normal right content must remain separate")
        testlib.assert_nil(right.science_pack_panel)
        testlib.assert_true(find_named(panel, "science_pack_panel_header") ~= nil)
        testlib.assert_true(find_named(panel, "science_pack_panel_planet_stock_rows") ~= nil)
    end},
    {"science-pack inspector summary labels are built with styles", function()
        local player = {opened = nil}
        local anchor = make_element(false)
        _G.game = {get_player = function() return player end}
        builder.build(1, anchor)
        local panel = anchor.lil_einstein_gui.science_pack_panel
        local back = find_named(panel, "science_pack_panel_back")
        testlib.assert_true(back ~= nil, "back button must exist")
        testlib.assert_equal(back.type, "button", "back must be a button element")
        local flow = find_named(panel, "science_pack_panel_flow_balance")
        testlib.assert_true(flow ~= nil, "flow balance container must exist")
        local production = find_named(flow, "science_pack_panel_flow_production")
        testlib.assert_true(production ~= nil, "flow production label must exist")
        local consumption = find_named(flow, "science_pack_panel_flow_consumption")
        testlib.assert_true(consumption ~= nil, "flow consumption label must exist")
        local net = find_named(flow, "science_pack_panel_flow_net")
        testlib.assert_true(net ~= nil, "flow net label must exist")
        testlib.assert_true(find_named(panel, "science_pack_panel_outlook") ~= nil,
                            "supply outlook label must exist")
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
    end},
    {"passes checkbox state to add as a required boolean", function()
        errors = {}
        local build_recursive = get_upvalue(builder.build, "build_recursive")
        local anchor = make_element_with_checkbox_state_contract()
        testlib.assert_true(build_recursive(anchor, {
            type = "flow",
            name = "decision_choose_controls",
            children = {{
                type = "checkbox",
                name = "decision_manual_override",
                state = false
            }}
        }))
        testlib.assert_equal(anchor.decision_choose_controls.decision_manual_override.state, false)
        testlib.assert_equal(#errors, 0, "checkbox state must be present in LuaGuiElement.add")
    end},
    {"rejects checkbox structures without an initial state", function()
        errors = {}
        local build_recursive = get_upvalue(builder.build, "build_recursive")
        local anchor = make_element_with_checkbox_state_contract()
        testlib.assert_false(build_recursive(anchor, {
            type = "checkbox",
            name = "missing_state"
        }))
        testlib.assert_true(#errors > 0, "missing checkbox state must be reported")
    end}
}

local passed = testlib.run("builder_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original[name]
    package.loaded[name] = nil
end
return passed
