package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local module_names = {
    "lib.const",
    "lib.util",
    "model.state",
    "model.tech",
    "model.queue",
    "model.research_policy",
    "model.lab",
    "lib.log",
    "view.gui.analyzer",
    "view.gui.gutil",
    "view.gui.components.tech"
}
local original_preloads = {}
for _, name in ipairs(module_names) do
    original_preloads[name] = package.preload[name]
    package.loaded[name] = nil
end

local force = {index = 1}
local player = {index = 1, force = force}
local master_enable = "right"
local order
local built_order
local tech_state = {}
local filtered = {}
local scores = {}
local tech_enabled = {}
local repeat_rules = {}
local build_order_calls = 0
local score_calls = {}
local last_average_cost

local const = {
    default_settings = {force = {master_enable = "right"}}
}

local state = {
    get_force_setting = function(force_index, key, default)
        if force_index == force.index and key == "master_enable" then
            return master_enable or default
        end
        return default
    end
}

local tech = {
    get_all_tech_state_ext = function(force_index)
        return force_index == force.index and tech_state or nil
    end
}

local queue = {
    get_tech_enabled = function(force_index, tech_name)
        return tech_enabled[tech_name] ~= false
    end,
    get_tech_order = function(force_index)
        return order
    end,
    build_tech_order = function(force_index)
        build_order_calls = build_order_calls + 1
        return built_order or order
    end,
    get_tech_ub = function(force_index, tech_name)
        return 1
    end,
    score_tech_detailed = function(xcur, level, ub, average_cost, force_index)
        last_average_cost = average_cost
        local total = scores[xcur.technology.name] or 0
        score_calls[#score_calls + 1] = xcur.technology.name
        return {
            importance = 1,
            level_boost = 2,
            user_boost = 3,
            science_priority = 4,
            strategy_boost = 5,
            total = total
        }
    end
}

local policy = {
    get_repeat_rule = function(force_index, tech_name)
        return repeat_rules[tech_name] or {mode = "always"}
    end
}

local analyzer = {
    get_filtered_technologies_player = function(player_index)
        return filtered
    end
}

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
        element.clear_count = element.clear_count + 1
        element.children = {}
    end
    return element
end

local gutil = {
    get_child = function(anchor, name)
        return anchor and anchor[name]
    end,
    get_tooltip_text = function(xcur, player_index)
        return {"test-tooltip", xcur.technology.name, player_index}
    end
}

local function prototype_map(prefix)
    return setmetatable({}, {
        __index = function(_, name)
            return {localised_name = prefix .. ":" .. name}
        end
    })
end

local function make_xcur(name, options)
    options = options or {}
    local trigger = options.trigger
    return {
        technology = {
            name = name,
            localised_name = "Technology " .. name,
            researched = options.researched == true,
            research_unit_count = options.cost or 100,
            level = options.level or 1
        },
        available = options.available ~= false,
        meta = {
            sciences = options.sciences or {},
            has_trigger = trigger ~= nil,
            is_infinite = options.is_infinite == true,
            prototype = {research_trigger = trigger}
        }
    }
end

local function reset_fixture()
    master_enable = "right"
    order = nil
    built_order = nil
    tech_state = {}
    filtered = {}
    scores = {}
    tech_enabled = {}
    repeat_rules = {}
    build_order_calls = 0
    score_calls = {}
    last_average_cost = nil
    _G.game = {
        get_player = function(player_index)
            return player_index == player.index and player or nil
        end
    }
    _G.prototypes = {
        item = prototype_map("item"),
        entity = prototype_map("entity"),
        fluid = prototype_map("fluid")
    }
end

local function make_anchor()
    return {available_technology_table = make_element("available_technology_table")}
end

local function row_tech_name(row)
    return row.children[1].name
end

local function row_title(row)
    return row.children[2].children[1].children[1]
end

local function row_science_flow(row)
    return row.children[2].children[1].children[2]
end

local function row_score_flow(row)
    return row.children[2].children[1].children[3]
end

local function icon_style_name(row)
    local icon = row.children[1]
    return type(icon.style) == "string" and icon.style or icon.requested_style
end

local function install_stubs()
    t.install_module("lib.const", const)
    t.install_module("lib.util", {})
    t.install_module("model.state", state)
    t.install_module("model.tech", tech)
    t.install_module("model.queue", queue)
    t.install_module("model.research_policy", policy)
    t.install_module("model.lab", {})
    t.install_module("lib.log", {debug = function() end})
    t.install_module("view.gui.analyzer", analyzer)
    t.install_module("view.gui.gutil", gutil)
end

reset_fixture()
install_stubs()
local gctech = require("view.gui.components.tech")
local tests = {}

tests[#tests + 1] = {"documents the missing-player precondition", function()
    reset_fixture()
    _G.game.get_player = function()
        return nil
    end
    local ok = pcall(function()
        gctech.populate(99, {})
    end)
    t.assert_false(ok, "populate requires a live player for the requested index")
end}

tests[#tests + 1] = {"returns without touching a missing technology table", function()
    reset_fixture()
    local anchor = {}
    gctech.populate(1, anchor)
    t.assert_nil(anchor.available_technology_table)
    t.assert_equal(build_order_calls, 0)
end}

tests[#tests + 1] = {"renders rows disabled when the master state is left", function()
    reset_fixture()
    master_enable = "left"
    local xcur = make_xcur("disabled-tech", {cost = 100})
    order = nil
    built_order = {"disabled-tech"}
    tech_state = {['disabled-tech'] = xcur}
    filtered = {xcur}
    scores["disabled-tech"] = 12
    local anchor = make_anchor()

    gctech.populate(1, anchor)

    local table_element = anchor.available_technology_table
    local row = table_element.children[1]
    t.assert_equal(table_element.clear_count, 1)
    t.assert_equal(build_order_calls, 1)
    t.assert_equal(#table_element.children, 1)
    t.assert_false(row.enabled)
    t.assert_false(row.children[1].enabled)
    t.assert_false(row_title(row).enabled)
    t.assert_false(row.children[3].enabled)
end}

tests[#tests + 1] = {"filters and sorts rows by detailed score", function()
    reset_fixture()
    order = {"low", "high", "researched", "filtered"}
    local low = make_xcur("low", {cost = 100})
    local high = make_xcur("high", {cost = 300})
    local researched = make_xcur("researched", {cost = 900, researched = true})
    local filtered_out = make_xcur("filtered", {cost = 700})
    tech_state = {
        low = low,
        high = high,
        researched = researched,
        filtered = filtered_out
    }
    filtered = {low, high}
    scores.low = 10
    scores.high = 90
    scores.researched = 1000
    scores.filtered = 800
    local anchor = make_anchor()

    gctech.populate(1, anchor)

    local rows = anchor.available_technology_table.children
    t.assert_equal(#rows, 2)
    t.assert_equal(row_tech_name(rows[1]), "high")
    t.assert_equal(row_tech_name(rows[2]), "low")
    t.assert_equal(last_average_cost, 200)
    t.assert_equal(score_calls[1], "low")
    t.assert_equal(score_calls[2], "high")
    t.assert_equal(row_score_flow(rows[1]).children[1].caption, "IW:1 LB:2 UB:3 SP:4 ST:5 = 90.0")
end}

tests[#tests + 1] = {"renders state-based icon and switch branches", function()
    reset_fixture()
    order = {"blocked", "unavailable", "enabled-off"}
    local blocked = make_xcur("blocked", {
        trigger = {type = "craft-item", item = "iron-plate", count = 2},
        sciences = {"a", "b"}
    })
    local unavailable = make_xcur("unavailable", {available = false})
    local enabled_off = make_xcur("enabled-off")
    tech_state = {blocked = blocked, unavailable = unavailable, ["enabled-off"] = enabled_off}
    filtered = {blocked, unavailable, enabled_off}
    scores.blocked = 30
    scores.unavailable = 20
    scores["enabled-off"] = 10
    tech_enabled["enabled-off"] = false
    local anchor = make_anchor()

    gctech.populate(1, anchor)

    local rows = anchor.available_technology_table.children
    t.assert_equal(icon_style_name(rows[1]), "lil_einstein_tech_btn_blocked")
    t.assert_equal(icon_style_name(rows[2]), "lil_einstein_tech_btn_unavailable")
    t.assert_equal(icon_style_name(rows[3]), "lil_einstein_tech_btn_available")
    local switch = row_title(rows[3]).children[1]
    local label = row_title(rows[3]).children[2]
    t.assert_equal(switch.sprite, "lil_einstein_mockup_enable_switch_off")
    t.assert_equal(label.style.font_color.r, 0.5)
end}

tests[#tests + 1] = {"renders trigger variants, science density, and repeat controls", function()
    reset_fixture()
    order = {
        "craft-one", "craft-many", "mine", "fluid", "capture", "capture-any",
        "build", "platform", "orbit", "scripted", "unknown", "plain"
    }
    local dense_sciences = {}
    for index = 1, 11 do
        dense_sciences[index] = "science-" .. index
    end
    local entries = {
        ["craft-one"] = make_xcur("craft-one", {
            trigger = {type = "craft-item", item = {name = "iron-plate"}, count = 1},
            sciences = dense_sciences,
            is_infinite = true
        }),
        ["craft-many"] = make_xcur("craft-many", {
            trigger = {type = "craft-item", item = "copper-plate", count = 2}
        }),
        mine = make_xcur("mine", {trigger = {type = "mine-entity", entity = {name = "iron-ore"}}}),
        fluid = make_xcur("fluid", {trigger = {type = "craft-fluid", fluid = "sulfuric-acid", amount = 50}}),
        capture = make_xcur("capture", {trigger = {type = "capture-spawner", entity = "biter-spawner"}}),
        ["capture-any"] = make_xcur("capture-any", {trigger = {type = "capture-spawner"}}),
        build = make_xcur("build", {trigger = {type = "build-entity", entity = "assembling-machine-1"}}),
        platform = make_xcur("platform", {trigger = {type = "create-space-platform"}}),
        orbit = make_xcur("orbit", {trigger = {type = "send-item-to-orbit", item = "rocket-part"}}),
        scripted = make_xcur("scripted", {trigger = {type = "scripted", trigger_description = {"scripted-description"}}}),
        unknown = make_xcur("unknown", {trigger = {type = "unrecognised"}}),
        plain = make_xcur("plain")
    }
    tech_state = entries
    filtered = {}
    scores = {}
    for index, name in ipairs(order) do
        filtered[index] = entries[name]
        scores[name] = #order - index + 1
    end
    repeat_rules["craft-one"] = {mode = "to_level", max_level = 3}
    local anchor = make_anchor()

    gctech.populate(1, anchor)

    local rows = anchor.available_technology_table.children
    t.assert_equal(#rows, #order)
    t.assert_equal(row_tech_name(rows[1]), "craft-one")
    local science_flow = row_science_flow(rows[1])
    t.assert_equal(#science_flow.children, 13)
    t.assert_true(science_flow.children[2].style.left_margin < 0)
    t.assert_equal(science_flow.children[12].sprite, "item/iron-plate")
    t.assert_equal(science_flow.children[12].tooltip[1], "technology-trigger.craft-item")
    t.assert_equal(row_score_flow(rows[1]).children[2].caption[1], "lil_einstein-repeat.to_level")
    t.assert_equal(row_score_flow(rows[1]).children[3].tags.delta, -1)
    t.assert_equal(row_score_flow(rows[1]).children[4].tags.delta, 1)

    local expected_sprites = {
        ["craft-many"] = "item/copper-plate",
        mine = "entity/iron-ore",
        fluid = "fluid/sulfuric-acid",
        capture = "entity/biter-spawner",
        ["capture-any"] = "entity/biter-spawner",
        build = "entity/assembling-machine-1",
        platform = "item/space-platform-starter-pack",
        orbit = "item/rocket-part",
        scripted = "utility/questionmark",
        unknown = "utility/danger_icon"
    }
    for row_index = 2, #rows do
        local row = rows[row_index]
        local name = row_tech_name(row)
        local science_children = row_science_flow(row).children
        if expected_sprites[name] then
            t.assert_equal(science_children[1].sprite, expected_sprites[name], "trigger sprite for " .. name)
        else
            t.assert_equal(#science_children, 0, "plain row has no trigger icon")
        end
    end
end}

tests[#tests + 1] = {"guards absent state and reports order key mismatches", function()
    reset_fixture()
    tech_state = nil
    gctech.populate(1, make_anchor())

    reset_fixture()
    local xcur = make_xcur("real-name", {cost = 100})
    order = {"alias"}
    tech_state = {alias = xcur}
    filtered = {xcur}
    scores["real-name"] = 10
    local anchor = make_anchor()
    gctech.populate(1, anchor)
    t.assert_equal(#anchor.available_technology_table.children, 1)
end}

local passed = t.run("tech_component_spec", tests)
for _, name in ipairs(module_names) do
    package.preload[name] = original_preloads[name]
    package.loaded[name] = nil
end
_G.game = nil
_G.prototypes = nil
return passed
