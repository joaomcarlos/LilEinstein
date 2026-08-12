package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assert_true(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function assert_same(actual, expected, message)
    assert_equal(actual, expected, message or "values are not the same object")
end

local function assert_error_free(name, callback)
    local ok, err = pcall(callback)
    if not ok then
        error(name .. ": " .. tostring(err), 2)
    end
end

local log = require("lib.log")
local ui_slices = require("lib.ui_slices")
local research_weights = require("model.research_weights")
local asset_prefix = "__LilEinstein__/graphics/ui/"

local tests = {}

tests[#tests + 1] = {"routes log, warning, and error messages to a target", function()
    local messages = {}
    local target = {
        print = function(message)
            messages[#messages + 1] = message
        end
    }
    local payload = {"technology-name", "automation"}

    log.log(target, payload)
    log.warn(target, "warning")
    log.error(target, "error")

    assert_equal(#messages, 3, "target message count")
    assert_equal(messages[1][1], "", "log message prefix slot")
    assert_equal(messages[1][2], "[font=default-bold][LilEinstein][/font] ", "log prefix")
    assert_same(messages[1][3], payload, "log payload")
    assert_equal(messages[2][2], "[font=default-bold][LilEinstein] [color=orange]Warning[/color][/font]: ",
        "warning prefix")
    assert_equal(messages[2][3], "warning", "warning payload")
    assert_equal(messages[3][2], "[font=default-bold][LilEinstein] [color=red]Error[/color][/font]: ",
        "error prefix")
    assert_equal(messages[3][3], "error", "error payload")
end}

tests[#tests + 1] = {"keeps print as the public log alias", function()
    assert_same(log.print, log.log, "print must alias log")
end}

tests[#tests + 1] = {"falls back to game.print when no target is supplied", function()
    local old_game = rawget(_G, "game")
    local message
    _G.game = {
        print = function(value)
            message = value
        end
    }

    log.log(nil, "global message")

    _G.game = old_game
    assert_equal(message[1], "", "fallback message prefix slot")
    assert_equal(message[3], "global message", "fallback payload")
end}

tests[#tests + 1] = {"suppresses debug messages until debug mode is enabled", function()
    local messages = {}
    local target = {
        print = function(message)
            messages[#messages + 1] = message
        end
    }

    log.DEBUG = false
    log.debug(target, "hidden")
    assert_equal(#messages, 0, "disabled debug message count")

    log.DEBUG = true
    log.debug(target, "visible")
    log.DEBUG = false

    assert_equal(#messages, 1, "enabled debug message count")
    assert_equal(messages[1][2], "[font=default-bold][LilEinstein] [color=blue]Debug[/color][/font]: ",
        "debug prefix")
    assert_equal(messages[1][3], "visible", "debug payload")
end}

tests[#tests + 1] = {"indexes every UI slice by both public identifiers", function()
    local names = {}
    local keys = {}
    local slice_count = 0

    for index, item in ipairs(ui_slices.slices) do
        slice_count = index
        assert_true(type(item.name) == "string" and item.name ~= "", "slice name")
        assert_true(type(item.key) == "string" and item.key ~= "", "slice key")
        assert_true(not names[item.name], "duplicate slice name: " .. item.name)
        assert_true(not keys[item.key], "duplicate slice key: " .. item.key)
        names[item.name] = true
        keys[item.key] = true

        assert_same(ui_slices.by_name[item.name], item, "name index for " .. item.name)
        assert_same(ui_slices.by_key[item.key], item, "key index for " .. item.key)
        assert_equal(item.file:sub(1, #asset_prefix), asset_prefix, "slice asset path")
        assert_true(item.w > 0 and item.h > 0, "slice dimensions")
        assert_equal(item.image_w, item.w, "source width for " .. item.name)
        assert_equal(item.image_h, item.h, "source height for " .. item.name)
    end

    assert_true(slice_count > 0, "UI slice table must not be empty")
    assert_same(ui_slices.by_name["toggle-on"], ui_slices.by_key.toggle_on,
        "toggle-on name/key indexes must agree")
    assert_same(ui_slices.by_name["toggle-off"], ui_slices.by_key.toggle_off,
        "toggle-off name/key indexes must agree")
end}

tests[#tests + 1] = {"exposes the expected representative UI slice metadata", function()
    local window = ui_slices.by_name["window-background-clean"]
    local separator = ui_slices.by_key.upcoming_row_separator

    assert_true(window ~= nil, "window background slice")
    assert_equal(window.key, "window_background_clean", "window background key")
    assert_equal(window.file, "__LilEinstein__/graphics/ui/window-background-clean.png",
        "window background file")
    assert_equal(window.w, 1672, "window background width")
    assert_equal(window.h, 941, "window background height")

    assert_true(separator ~= nil, "upcoming separator slice")
    assert_equal(separator.name, "upcoming-row-separator", "upcoming separator name")
    assert_equal(separator.w, 525, "upcoming separator width")
    assert_equal(separator.h, 74, "upcoming separator height")
end}

tests[#tests + 1] = {"exports typed research weights and caps", function()
    assert_true(type(research_weights.research_weights) == "table", "research weights table")
    assert_true(type(research_weights.research_caps) == "table", "research caps table")

    for tech_name, weight in pairs(research_weights.research_weights) do
        assert_true(type(tech_name) == "string" and tech_name ~= "", "weight technology name")
        assert_true(type(weight) == "number", "weight for " .. tech_name)
    end

    for tech_name, cap in pairs(research_weights.research_caps) do
        assert_true(type(tech_name) == "string" and tech_name ~= "", "cap technology name")
        assert_true(type(cap) == "number" and cap > 0, "cap for " .. tech_name)
        assert_true(research_weights.research_weights[tech_name] ~= nil,
            "cap must refer to a weighted technology: " .. tech_name)
    end
end}

tests[#tests + 1] = {"preserves priority and hard-cap configuration values", function()
    local weights = research_weights.research_weights
    local caps = research_weights.research_caps

    assert_equal(weights["research-productivity"], 20, "research productivity priority")
    assert_equal(weights["mining-productivity"], 12, "mining productivity priority")
    assert_equal(weights["follower-robot-count"], -10, "follower robot deprioritization")
    assert_equal(weights["artillery-shell-shooting-speed"], -5, "artillery speed deprioritization")
    assert_equal(caps["processing-unit-productivity"], 25, "processing unit cap")
    assert_equal(caps["rocket-part-productivity"], 30, "rocket part cap")
    assert_equal(caps["artillery-shell-shooting-speed"], 10, "artillery speed cap")
end}

local passed = 0
for _, test in ipairs(tests) do
    assert_error_free(test[1], test[2])
    passed = passed + 1
end

print("foundation_spec: " .. passed .. " passed")
return passed
