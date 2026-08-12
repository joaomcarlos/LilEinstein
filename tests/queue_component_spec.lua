package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local module_names = {
    "lib.const",
    "lib.util",
    "model.state",
    "model.tech",
    "model.queue",
    "view.gui.analyzer",
    "view.gui.gutil",
    "view.gui.components.queue"
}
local original_preloads = {}
local original_loaded = {}
for _, name in ipairs(module_names) do
    original_preloads[name] = package.preload[name]
    original_loaded[name] = package.loaded[name]
    package.loaded[name] = nil
end

local queue_meta = nil
local tech_states = {}
local current_researching = nil
local player

local function make_element(name)
    local element = {
        name = name,
        children = {},
        style = {},
        valid = true,
        clear_count = 0
    }
    element.add = function(properties)
        local child = make_element(properties.name)
        for key, value in pairs(properties) do
            if key ~= "style" then
                child[key] = value
            end
        end
        child.requested_style = properties.style
        table.insert(element.children, child)
        if properties.name then
            element[properties.name] = child
        end
        return child
    end
    element.clear = function()
        element.children = {}
        element.clear_count = element.clear_count + 1
    end
    return element
end

local function make_meta(tech_name, options)
    options = options or {}
    return {
        tech_name = tech_name,
        is_smart_researching = options.is_smart_researching or false,
        is_inherited = options.is_inherited or false,
        inherit_by = options.inherit_by or {},
        is_researching = options.is_researching or false,
        misses_science = options.misses_science or false,
        missing_science = options.missing_science or {},
        is_blocked = options.is_blocked or false,
        blocking_reasons = options.blocking_reasons or {},
        new_unblocked = options.new_unblocked or {},
        inherit_unblocked = options.inherit_unblocked or {},
        new_blocked = options.new_blocked or {},
        inherit_blocked = options.inherit_blocked or {}
    }
end

local function make_xcur(tech_name, sciences)
    return {
        technology = {name = tech_name},
        meta = {sciences = sciences or {"automation-science-pack"}}
    }
end

local state = {
    get_translation = function(_, kind, name, field)
        if field == "localised_name" then
            return "Localized " .. name
        end
        return kind .. ":" .. name
    end
}

local tech = {
    get_single_tech_state_ext = function(_, tech_name)
        return tech_states[tech_name]
    end
}

local queue = {
    get_current_researching = function()
        return current_researching
    end
}

local analyzer = {
    get_queue_meta = function()
        return queue_meta
    end
}

local gutil = {
    get_child = function(anchor, name)
        return anchor and anchor[name]
    end,
    get_tooltip_text = function(xcur, player_index)
        return {"tooltip", xcur.technology.name, player_index}
    end,
    get_tech_name = function(_, xcur)
        return "Name " .. xcur.technology.name
    end
}

t.install_module("lib.const", {})
t.install_module("lib.util", {})
t.install_module("model.state", state)
t.install_module("model.tech", tech)
t.install_module("model.queue", queue)
t.install_module("view.gui.analyzer", analyzer)
t.install_module("view.gui.gutil", gutil)

local old_game = _G.game
local function reset_fixture()
    queue_meta = nil
    tech_states = {}
    current_researching = nil
    player = {
        index = 1,
        force = {
            index = 1,
            research_progress = 0.375,
            technologies = {}
        }
    }
    _G.game = {
        get_player = function(player_index)
            return player_index == player.index and player or nil
        end
    }
end

local function set_queue(metas)
    queue_meta = metas
    for _, meta in ipairs(metas or {}) do
        tech_states[meta.tech_name] = make_xcur(meta.tech_name, meta.sciences)
        player.force.technologies[meta.tech_name] = {name = meta.tech_name}
    end
end

local function make_anchor()
    local anchor = make_element("anchor")
    anchor.table_queue = make_element("table_queue")
    return anchor
end

local function row_at(table_element, index)
    local row = {children = {}}
    local first_child = ((index - 1) * 6) + 1
    for offset = 0, 5 do
        row.children[offset + 1] = table_element.children[first_child + offset]
    end
    return row
end

local function status_sprite(row)
    return row.children[3].children[1].sprite
end

local function status_tooltip(row)
    return row.children[3].children[1].tooltip
end

local function tech_button(row)
    return row.children[4].children[1]
end

reset_fixture()
local gcqueue = require("view.gui.components.queue")
local tests = {}

tests[#tests + 1] = {"guards missing players, tables, and empty or filtered queues", function()
    reset_fixture()
    local anchor = make_anchor()
    local table_element = anchor.table_queue

    t.assert_nil(gcqueue.populate(99, anchor))
    t.assert_equal(table_element.clear_count, 0)

    local missing_table_anchor = {}
    t.assert_nil(gcqueue.populate(1, missing_table_anchor))

    queue_meta = nil
    gcqueue.populate(1, anchor)
    t.assert_equal(table_element.clear_count, 1)
    t.assert_equal(#table_element.children, 1)
    t.assert_equal(table_element.children[1].caption[1], "lil_einstein-lbl.empty-queue")

    queue_meta = {}
    gcqueue.populate(1, anchor)
    t.assert_equal(table_element.clear_count, 2)
    t.assert_equal(#table_element.children, 1)
    t.assert_equal(table_element.children[1].caption[1], "lil_einstein-lbl.empty-queue")
end}

tests[#tests + 1] = {"renders queue rows and boundary action tags", function()
    reset_fixture()
    local first = make_meta("automation")
    local middle = make_meta("logistics")
    local last = make_meta("military")
    set_queue({first, middle, last})
    local anchor = make_anchor()

    gcqueue.populate(1, anchor)

    local rows = {row_at(anchor.table_queue, 1), row_at(anchor.table_queue, 2), row_at(anchor.table_queue, 3)}
    t.assert_equal(#rows, 3)
    for index, row in ipairs(rows) do
        t.assert_equal(row.children[1].children[1].caption, index)
        t.assert_equal(row.children[4].children[1].name, ({"automation", "logistics", "military"})[index])
        t.assert_equal(row.children[4].children[1].tags.handler, "show_technology_screen")
        t.assert_equal(row.children[6].children[1].tags.handler, "remove_from_queue")
        t.assert_equal(row.children[6].children[1].tags.technology, row.children[4].children[1].name)
    end

    local first_buttons = rows[1].children[2].children
    local middle_buttons = rows[2].children[2].children
    local last_buttons = rows[3].children[2].children
    t.assert_false(first_buttons[1].enabled)
    t.assert_true(first_buttons[1].tags.ignore_force_enable)
    t.assert_equal(first_buttons[1].tags.handler, "promote_research")
    t.assert_nil(first_buttons[2].enabled)
    t.assert_nil(middle_buttons[1].enabled)
    t.assert_nil(middle_buttons[2].enabled)
    t.assert_nil(last_buttons[1].enabled)
    t.assert_false(last_buttons[2].enabled)
    t.assert_true(last_buttons[2].tags.ignore_force_enable)
    t.assert_equal(last_buttons[2].tags.handler, "demote_research")
end}

tests[#tests + 1] = {"renders current progress and status priority states", function()
    reset_fixture()
    current_researching = "current"
    local current = make_meta("current", {is_researching = true})
    set_queue({current})
    local current_anchor = make_anchor()
    gcqueue.populate(1, current_anchor)
    local current_row = row_at(current_anchor.table_queue, 1)
    t.assert_equal(status_sprite(current_row), "lil_einstein_progress_medium")
    t.assert_equal(status_tooltip(current_row)[1], "lil_einstein-tt.researching")
    t.assert_equal(#current_row.children[4].children, 2)
    t.assert_equal(current_row.children[4].children[2].value, 0.375)

    reset_fixture()
    local smart = make_meta("smart", {
        is_smart_researching = true,
        is_inherited = true,
        is_researching = true,
        misses_science = true,
        is_blocked = true,
        inherit_by = {"parent"}
    })
    set_queue({smart})
    local smart_anchor = make_anchor()
    gcqueue.populate(1, smart_anchor)
    local smart_row = row_at(smart_anchor.table_queue, 1)
    t.assert_equal(status_sprite(smart_row), "lil_einstein_progress_smart_medium")
    t.assert_equal(status_tooltip(smart_row)[1], "lil_einstein-tt.auto_researching")
end}

tests[#tests + 1] = {"renders inherited, missing-science, blocked, and pending symbols", function()
    reset_fixture()
    local inherited = make_meta("inherited", {is_inherited = true, inherit_by = {"parent"}})
    set_queue({inherited})
    local anchor = make_anchor()
    gcqueue.populate(1, anchor)
    local row = row_at(anchor.table_queue, 1)
    t.assert_equal(status_sprite(row), "lil_einstein_inherit_medium")
    t.assert_equal(status_tooltip(row)[1], "lil_einstein-tt.inherited-by")
    t.assert_equal(status_tooltip(row)[2], "Localized parent")

    reset_fixture()
    local missing = make_meta("missing", {
        misses_science = true,
        missing_science = {
            ["automation-science-pack"] = true,
            ["logistic-science-pack"] = true
        }
    })
    set_queue({missing})
    anchor = make_anchor()
    gcqueue.populate(1, anchor)
    row = row_at(anchor.table_queue, 1)
    t.assert_equal(status_sprite(row), "lil_einstein_no_science_medium")
    t.assert_equal(status_tooltip(row)[1], "lil_einstein-tt.missing_science")
    t.assert_true(string.find(status_tooltip(row)[2], "automation-science-pack", 1, true) ~= nil)

    reset_fixture()
    local blocked = make_meta("blocked", {
        is_blocked = true,
        blocking_reasons = {
            prerequisite = {"parent", "other"},
            disabled = {"switch"}
        }
    })
    set_queue({blocked})
    anchor = make_anchor()
    gcqueue.populate(1, anchor)
    row = row_at(anchor.table_queue, 1)
    t.assert_equal(status_sprite(row), "lil_einstein_blocked_medium")
    t.assert_equal(status_tooltip(row)[1], "lil_einstein-tt.blocked")
    local blocked_tooltip = status_tooltip(row)
    local blocked_reasons = {}
    for index = 2, #blocked_tooltip[2] do
        blocked_reasons[blocked_tooltip[2][index][1]] = true
    end
    t.assert_true(blocked_reasons["lil_einstein-tt.blocked_prerequisite"])
    t.assert_true(blocked_reasons["lil_einstein-tt.blocked_disabled"])

    reset_fixture()
    set_queue({make_meta("pending")})
    anchor = make_anchor()
    gcqueue.populate(1, anchor)
    row = row_at(anchor.table_queue, 1)
    t.assert_equal(status_sprite(row), "lil_einstein_queue_medium")
    t.assert_nil(status_tooltip(row))
end}

tests[#tests + 1] = {"renders predecessor details and dense science rows", function()
    reset_fixture()
    local detailed = make_meta("detailed", {
        new_unblocked = {"new-parent", "new-parent-2"},
        inherit_unblocked = {"inherited-parent", "inherited-parent-2"},
        new_blocked = {"new-blocker", "new-blocker-2"},
        inherit_blocked = {"inherited-blocker", "inherited-blocker-2"}
    })
    set_queue({detailed})
    local anchor = make_anchor()
    gcqueue.populate(1, anchor)
    local info = row_at(anchor.table_queue, 1).children[5]
    t.assert_equal(info.children[2].children[1].caption[1], "lil_einstein-lbl.prerequisite-tech")
    t.assert_equal(info.children[2].children[1].caption[2], 4)
    t.assert_equal(info.children[3].children[1].caption[1], "lil_einstein-lbl.blocked-tech-only")
    t.assert_equal(info.children[3].children[1].caption[2], 4)
    t.assert_equal(#info.children, 3)

    reset_fixture()
    local sciences = {}
    for index = 1, 10 do
        sciences[index] = "science-" .. index
    end
    local dense = make_meta("dense")
    dense.sciences = sciences
    set_queue({dense})
    anchor = make_anchor()
    gcqueue.populate(1, anchor)
    info = row_at(anchor.table_queue, 1).children[5]
    local science_flow = info.children[2]
    t.assert_equal(#science_flow.children, 10)
    t.assert_true(science_flow.children[2].style.left_margin < 0)
    t.assert_equal(science_flow.children[10].sprite, "item/science-10")
    t.assert_true(tech_button(row_at(anchor.table_queue, 1)).tags ~= nil)
end}

tests[#tests + 1] = {"rebuilds safely when the queue changes between refreshes", function()
    reset_fixture()
    set_queue({make_meta("old")})
    local anchor = make_anchor()
    gcqueue.populate(1, anchor)
    local old_row = row_at(anchor.table_queue, 1)
    t.assert_equal(old_row.children[4].children[1].name, "old")

    set_queue({make_meta("new")})
    gcqueue.populate(1, anchor)
    t.assert_equal(anchor.table_queue.clear_count, 2)
    local new_row = row_at(anchor.table_queue, 1)
    t.assert_true(new_row ~= old_row)
    t.assert_equal(new_row.children[4].children[1].name, "new")
end}

local passed = t.run("queue_component_spec", tests)
for _, name in ipairs(module_names) do
    package.preload[name] = original_preloads[name]
    package.loaded[name] = original_loaded[name]
end
_G.game = old_game
return passed
