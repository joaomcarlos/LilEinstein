package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local module_names = {
    "lib.const",
    "lib.util",
    "model.state",
    "model.tech",
    "model.queue",
    "view.gui.gutil",
    "view.gui.components.upcoming"
}
local original_preloads = {}
for _, name in ipairs(module_names) do
    original_preloads[name] = package.preload[name]
    package.loaded[name] = nil
end

local calls = {}
local immediate_upcoming = {}
local tick_results = {}
local pinned_tech = nil

local function make_element(name, valid)
    local element = {
        name = name,
        valid = valid ~= false,
        visible = true,
        children = {},
        style = {},
        tags = {},
        clear_count = 0
    }

    element.add = function(prop)
        local child = make_element(prop.name, true)
        for key, value in pairs(prop) do
            if key ~= "style" then
                child[key] = value
            end
        end
        if prop.name then
            element[prop.name] = child
        end
        table.insert(element.children, child)
        return child
    end

    element.clear = function()
        element.children = {}
        element.clear_count = element.clear_count + 1
        for key, value in pairs(element) do
            if type(value) == "table" and value.name then
                element[key] = nil
            end
        end
    end

    return element
end

local function find_child(root, name)
    if not root or root.valid == false then
        return nil
    end
    local direct = root[name]
    if direct and direct.valid ~= false then
        return direct
    end
    for _, child in ipairs(root.children or {}) do
        if child.valid ~= false then
            if child.name == name then
                return child
            end
            local nested = find_child(child, name)
            if nested then
                return nested
            end
        end
    end
    return nil
end

local gutil = {
    get_child = find_child,
    get_tooltip_text = function(xcur, player_index, level, cost)
        return {"tooltip", xcur.technology.name, player_index, level, cost}
    end
}

local queue = {
    get_pinned_tech = function(force_index)
        calls.pinned_force_index = force_index
        return pinned_tech
    end,
    get_upcoming_research_display = function(force_index, limit)
        calls.immediate_force_index = force_index
        calls.immediate_limit = limit
        return immediate_upcoming
    end,
    request_upcoming_research_display = function(force_index, limit)
        calls.request_force_index = force_index
        calls.request_limit = limit
        calls.request_count = (calls.request_count or 0) + 1
    end,
    tick_upcoming_research_display = function(force_index, budget)
        calls.tick_force_index = force_index
        calls.tick_budget = budget
        calls.tick_count = (calls.tick_count or 0) + 1
        local result = table.remove(tick_results, 1)
        if not result then
            return true, {}
        end
        return result[1], result[2]
    end
}

t.install_module("lib.const", {})
t.install_module("lib.util", {})
t.install_module("model.state", {})
t.install_module("model.tech", {})
t.install_module("model.queue", queue)
t.install_module("view.gui.gutil", gutil)

local upcoming = require("view.gui.components.upcoming")

local function find_private(function_value, wanted, seen)
    if type(function_value) ~= "function" then
        return nil
    end
    seen = seen or {}
    if seen[function_value] then
        return nil
    end
    seen[function_value] = true
    for index = 1, 64 do
        local name, value = debug.getupvalue(function_value, index)
        if not name then break end
        if name == wanted then return value end
        local nested = find_private(value, wanted, seen)
        if nested ~= nil then return nested end
    end
    return nil
end

local player_force
local player = {
    index = 1,
    valid = true,
    force = nil
}
game = {
    tick = 0,
    get_player = function(index)
        return index == 1 and player or nil
    end
}

local function make_force()
    return {
        index = 1,
        current_research = {name = "automation"},
        research_progress = 0.4,
        technologies = {
            automation = {valid = true, saved_progress = 0.2},
            logistics = {valid = true, saved_progress = 0.25},
            military = {valid = true, saved_progress = 0.6}
        }
    }
end

local function make_anchor()
    local anchor = make_element("anchor")
    local flow = anchor.add({
        type = "flow",
        name = "flow_upcoming"
    })
    return anchor, flow
end

local function make_entry(tech_name, options)
    options = options or {}
    return {
        tech_name = tech_name,
        level = options.level or 1,
        duration = options.duration,
        wait_time = options.wait_time,
        availability_reason = options.availability_reason,
        missing_sciences = options.missing_sciences,
        cost = options.cost or 100,
        xcur = {
            technology = {
                name = tech_name,
                localised_name = options.localised_name or tech_name
            },
            meta = {
                is_infinite = options.is_infinite or false,
                sciences = options.sciences or {"automation-science-pack"}
            }
        }
    }
end

local function reset_test_state()
    upcoming.clear_runtime_cache()
    calls = {}
    immediate_upcoming = {}
    tick_results = {}
    pinned_tech = nil
    player_force = make_force()
    player.force = player_force
    player.valid = true
    game.tick = 0
end

local function get_row(flow, tech_name)
    for _, child in ipairs(flow.children) do
        if child.valid and child.tags and child.tags.technology == tech_name then
            return child
        end
    end
    return nil
end

local tests = {}

tests[#tests + 1] = {"guards missing and invalid players or anchors", function()
    reset_test_state()
    local anchor = make_anchor()

    t.assert_nil(upcoming.populate(99, anchor))
    t.assert_false(upcoming.request_populate(99, anchor))

    local missing_flow = make_element("missing-flow-anchor")
    t.assert_nil(upcoming.populate(1, missing_flow))
    t.assert_false(upcoming.request_populate(1, missing_flow))

    anchor.valid = false
    t.assert_nil(upcoming.populate(1, anchor))
    t.assert_false(upcoming.request_populate(1, anchor))
    t.assert_true(upcoming.tick_populate(1, anchor))
end}

tests[#tests + 1] = {"renders a synchronous populated list with current and pinned state", function()
    reset_test_state()
    pinned_tech = "logistics"
    immediate_upcoming = {
        make_entry("automation", {
            duration = 120,
            wait_time = 0,
            localised_name = "Automation",
            cost = 50
        }),
        make_entry("logistics", {
            level = 2,
            duration = 90,
            wait_time = 30,
            availability_reason = "missing_science",
            missing_sciences = {"logistic-science-pack"},
            is_infinite = true,
            localised_name = "Logistics"
        })
    }
    local anchor, flow = make_anchor()

    upcoming.populate(1, anchor)

    t.assert_equal(calls.immediate_force_index, 1)
    t.assert_equal(calls.immediate_limit, 15)
    t.assert_equal(flow.clear_count, 1)
    t.assert_equal(#flow.children, 3)

    local first = flow.children[1]
    local second = flow.children[3]
    t.assert_equal(first.tags.technology, "automation")
    t.assert_equal(first.tags.rank, 1)
    t.assert_equal(first.tags.duration, 120)
    t.assert_equal(find_child(first, "upcoming_current_arrow").caption, ">")
    t.assert_equal(find_child(first, "upcoming_pinned_arrow").caption, "")
    t.assert_equal(find_child(first, "upcoming_progress_label").caption, "40.00%")
    t.assert_true(find_child(first, "upcoming_icon_progress").visible)
    t.assert_equal(find_child(first, "upcoming_icon_progress").value, 0.4)
    t.assert_equal(find_child(first, "upcoming_duration_label").caption[3], "2m 00s")
    t.assert_equal(first.children[4].style.bottom_margin, 22)

    t.assert_equal(second.tags.technology, "logistics")
    t.assert_equal(second.tags.rank, 2)
    t.assert_equal(find_child(second, "upcoming_current_arrow").caption, "")
    t.assert_equal(find_child(second, "upcoming_pinned_arrow").caption, ">")
    t.assert_equal(find_child(second, "upcoming_progress_label").caption, "25.00%")
    t.assert_equal(find_child(second, "upcoming_duration_label").caption[3], "1m 30s")
    t.assert_equal(find_child(second, "upcoming_wait_label").caption[3][3][3], "30s")
    t.assert_equal(second.children[4].style.bottom_margin, 22)
end}

tests[#tests + 1] = {"renders the empty state for a nil or empty display", function()
    reset_test_state()
    immediate_upcoming = nil
    local anchor, flow = make_anchor()

    upcoming.populate(1, anchor)

    t.assert_equal(flow.clear_count, 1)
    t.assert_equal(#flow.children, 1)
    t.assert_equal(flow.children[1].caption[3], "No upcoming research available")
end}

tests[#tests + 1] = {"starts a bounded refresh job without replacing visible rows", function()
    reset_test_state()
    local anchor, flow = make_anchor()
    local sentinel = flow.add({
        type = "label",
        caption = "existing row"
    })
    tick_results = {
        {false, nil},
        {true, {make_entry("automation", {duration = 10})}}
    }

    t.assert_false(upcoming.request_populate(1, anchor))
    t.assert_equal(calls.request_force_index, 1)
    t.assert_equal(calls.request_limit, 15)
    t.assert_equal(#flow.children, 1)
    t.assert_equal(flow.children[1], sentinel)

    t.assert_false(upcoming.tick_populate(1, anchor))
    t.assert_equal(calls.tick_force_index, 1)
    t.assert_equal(calls.tick_budget, 1)
    t.assert_equal(#flow.children, 1)
    t.assert_equal(flow.children[1], sentinel)

    t.assert_true(upcoming.tick_populate(1, anchor))
    t.assert_equal(#flow.children, 1)
    t.assert_equal(flow.children[1].tags.technology, "automation")
end}

tests[#tests + 1] = {"cancels a refresh job when its anchor is replaced or invalidated", function()
    reset_test_state()
    local anchor = make_anchor()
    local replacement = make_anchor()
    tick_results = {{true, {make_entry("automation", {duration = 10})}}}
    upcoming.request_populate(1, anchor)

    t.assert_true(upcoming.tick_populate(1, replacement))
    t.assert_equal(calls.tick_count, nil)

    tick_results = {{true, {make_entry("automation", {duration = 10})}}}
    upcoming.request_populate(1, anchor)
    anchor.valid = false
    t.assert_true(upcoming.tick_populate(1, anchor))
    t.assert_equal(calls.tick_count, nil)
end}

tests[#tests + 1] = {"updates stable rows in place after a bounded refresh", function()
    reset_test_state()
    immediate_upcoming = {
        make_entry("automation", {duration = 120, wait_time = 0}),
        make_entry("logistics", {duration = 90, wait_time = 30})
    }
    local anchor, flow = make_anchor()
    upcoming.populate(1, anchor)
    local first_row = flow.children[1]
    local clear_count = flow.clear_count
    tick_results = {{true, {
        make_entry("automation", {duration = 80, wait_time = 0}),
        make_entry("logistics", {duration = 60, wait_time = 20})
    }}}

    upcoming.request_populate(1, anchor)
    t.assert_true(upcoming.tick_populate(1, anchor))

    t.assert_equal(flow.clear_count, clear_count)
    t.assert_equal(flow.children[1], first_row)
    t.assert_equal(first_row.tags.duration, 80)
    t.assert_equal(first_row.tags.wait_time, 0)
    t.assert_equal(flow.children[3].tags.duration, 60)
    t.assert_equal(flow.children[3].tags.wait_time, 20)
end}

tests[#tests + 1] = {"re-renders when the row structure changes", function()
    reset_test_state()
    immediate_upcoming = {make_entry("automation", {duration = 20})}
    local anchor, flow = make_anchor()
    upcoming.populate(1, anchor)
    local old_row = flow.children[1]
    local clear_count = flow.clear_count
    tick_results = {{true, {make_entry("logistics", {
        duration = 20,
        availability_reason = "science_not_together"
    })}}}

    upcoming.request_populate(1, anchor)
    t.assert_true(upcoming.tick_populate(1, anchor))

    t.assert_equal(flow.clear_count, clear_count + 1)
    t.assert_true(flow.children[1] ~= old_row)
    t.assert_equal(flow.children[1].tags.technology, "logistics")
end}

tests[#tests + 1] = {"refreshes progress bars, labels, and rank arrows", function()
    reset_test_state()
    pinned_tech = "automation"
    immediate_upcoming = {
        make_entry("automation", {duration = 10}),
        make_entry("logistics", {duration = 20})
    }
    local anchor, flow = make_anchor()
    upcoming.populate(1, anchor)

    player_force.current_research = {name = "logistics"}
    player_force.research_progress = 0.75
    upcoming.refresh_progress(1, anchor)

    local automation = flow.children[1]
    local logistics = flow.children[3]
    t.assert_equal(find_child(automation, "upcoming_icon_progress").value, 0.2)
    t.assert_equal(find_child(automation, "upcoming_progress_label").caption, "20.00%")
    t.assert_equal(find_child(automation, "upcoming_current_arrow").caption, "")
    t.assert_equal(find_child(automation, "upcoming_pinned_arrow").caption, ">")
    t.assert_equal(find_child(logistics, "upcoming_icon_progress").value, 0.75)
    t.assert_equal(find_child(logistics, "upcoming_progress_label").caption, "75.00%")
    t.assert_equal(find_child(logistics, "upcoming_current_arrow").caption, ">")
    t.assert_equal(find_child(logistics, "upcoming_pinned_arrow").caption, "")

    t.assert_nil(upcoming.refresh_progress(99, anchor))
    t.assert_nil(upcoming.refresh_progress(1, make_element("missing-flow")))
end}

tests[#tests + 1] = {"refreshes countdowns from cached render data", function()
    reset_test_state()
    immediate_upcoming = {
        make_entry("automation", {duration = 120, wait_time = 5}),
        make_entry("logistics", {duration = 90, wait_time = 30})
    }
    local anchor, flow = make_anchor()
    upcoming.populate(1, anchor)
    game.tick = 60

    upcoming.refresh_times(1, anchor)

    local first = flow.children[1]
    local second = flow.children[3]
    t.assert_equal(find_child(first, "upcoming_duration_label").caption[3], "1m 59s")
    t.assert_nil(find_child(first, "upcoming_wait_label"))
    t.assert_equal(find_child(second, "upcoming_duration_label").caption[3], "1m 30s")
    t.assert_equal(find_child(second, "upcoming_wait_label").caption[3][3][3], "29s")

    t.assert_nil(upcoming.refresh_times(1, make_element("missing-flow")))
    t.assert_nil(upcoming.refresh_times(99, anchor))
end}

tests[#tests + 1] = {"keeps unknown durations explicit during time refresh", function()
    reset_test_state()
    immediate_upcoming = {
        make_entry("automation", {}),
        make_entry("logistics", {})
    }
    local anchor, flow = make_anchor()
    upcoming.populate(1, anchor)
    game.tick = 120

    upcoming.refresh_times(1, anchor)

    local first = flow.children[1]
    local second = flow.children[3]
    t.assert_equal(find_child(first, "upcoming_duration_label").caption[3], "calculating...")
    t.assert_equal(find_child(second, "upcoming_duration_label").caption[3], "calculating...")
    t.assert_equal(find_child(second, "upcoming_wait_label").caption[3][3][3], "calculating...")
end}

tests[#tests + 1] = {"covers hour formatting, dense sciences, and progress guards", function()
    reset_test_state()
    local sciences = {}
    for index = 1, 9 do
        sciences[index] = "science-" .. index
    end
    immediate_upcoming = {
        make_entry("hours", {duration = 3660, sciences = sciences}),
        make_entry("other-tech", {duration = 15, availability_reason = "other"}),
        make_entry("missing-tech", {duration = 0, wait_time = 3665})
    }
    player_force.technologies["missing-tech"] = {valid = false, saved_progress = 0.5}
    pinned_tech = "hours"
    local anchor, flow = make_anchor()
    upcoming.populate(1, anchor)

    local first = flow.children[1]
    t.assert_equal(find_child(first, "upcoming_duration_label").caption[3], "1h 01m")
    local wait_caption = find_child(flow.children[5], "upcoming_wait_label").caption
    t.assert_equal(wait_caption[3][3][3], "1h 01m")
    t.assert_equal(first.children[4].children[2].children[2].style.left_margin, -2)
    local function find_status(root)
        for _, child in ipairs(root.children or {}) do
            if child.type == "label" and type(child.caption) == "table" and child.caption[1] == "?" then
                return child
            end
            local nested = find_status(child)
            if nested then
                return nested
            end
        end
        return nil
    end
    t.assert_nil(find_status(flow).tooltip)

    local progress_bar = find_child(first, "upcoming_icon_progress")
    progress_bar.valid = false
    upcoming.refresh_progress(1, anchor)
    local progress_label = find_child(first, "upcoming_progress_label")
    progress_label.valid = false
    progress_bar.valid = true
    progress_bar.visible = false
    upcoming.refresh_progress(1, anchor)
    pinned_tech = nil
    upcoming.refresh_progress(1, anchor)
    player.valid = false
    upcoming.refresh_progress(1, anchor)
    player.valid = true

    immediate_upcoming = {{tech_name = "no-xcur"}}
    local malformed_anchor = make_anchor()
    upcoming.populate(1, malformed_anchor)
    t.assert_equal(#malformed_anchor.children[1].children, 0)
end}

tests[#tests + 1] = {"covers private row and arrow guards", function()
    reset_test_state()
    local set_arrows = find_private(upcoming.refresh_progress, "set_rank_arrows")
    local add_row = find_private(upcoming.populate, "add_upcoming_row")
    t.assert_true(type(set_arrows) == "function")
    t.assert_true(type(add_row) == "function")
    set_arrows(nil, false, false)
    t.assert_nil(add_row(make_element("parent"), 1, make_entry("automation"), 99))
end}

tests[#tests + 1] = {"clears cached display state and pending jobs", function()
    reset_test_state()
    immediate_upcoming = {make_entry("automation", {duration = 10})}
    local anchor = make_anchor()
    upcoming.populate(1, anchor)
    upcoming.request_populate(1, anchor)
    upcoming.clear_runtime_cache()

    t.assert_true(upcoming.tick_populate(1, anchor))
    t.assert_equal(calls.tick_count, nil)
end}

local passed = t.run("upcoming_component_spec", tests)
for _, name in ipairs(module_names) do
    package.preload[name] = original_preloads[name]
    package.loaded[name] = nil
end
game = nil
return passed
