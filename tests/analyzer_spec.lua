package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local testlib = require("tests.testlib")
local original = {}
for _, name in ipairs({"lib.const", "lib.util", "model.state", "model.tech", "model.queue", "model.lab", "view.gui.analyzer"}) do
    original[name] = package.preload[name]
    package.loaded[name] = nil
end

local const = {
    default_settings = {
        player = {
            show_tech = {selected = "all"},
            hide_tech = {
                disabled_tech = false,
                suspended = false,
                manual_trigger_tech = false,
                infinite_tech = false,
                inherited_tech = false,
                unavailable_successors = false
            }
        }
    },
    categories = {}
}
local util
util = {
    array_has_value = function(array, value)
        for _, item in pairs(array or {}) do
            if item == value then return true end
        end
        return false
    end,
    array_has_all_values = function(needles, haystack)
        for _, needle in pairs(needles) do
            if not util.array_has_value(haystack, needle) then return false end
        end
        return true
    end,
    get_all_sciences = function() return {"automation-science"} end,
    fuzzy_search = function(needle, haystack)
        for _, value in pairs(haystack) do
            if value and string.find(string.lower(value), string.lower(needle), 1, true) then return true end
        end
        return false
    end
}
local settings = {}
local state = {
    get_player_setting = function(_, key, default) return settings[key] == nil and default or settings[key] end,
    get_translation = function(_, _, tech_name, field)
        if field == "localised_name" then
            return tech_name == "automation" and "Automation" or "Logistics"
        end
        return "science"
    end
}
local tech_state = {}
local tech = {get_all_tech_state_ext = function() return tech_state end}
local queue_state = {
    get_queue = function() return {"automation", "logistics"} end,
    get_tech_missing_science = function() return {automation = true} end,
    get_science_availability = function() return {} end,
    get_current_researching = function() return "automation" end,
    get_current_smart_researching = function() return "logistics" end,
    get_tech_enabled = function() return true end
}

testlib.install_module("lib.const", const)
testlib.install_module("lib.util", util)
testlib.install_module("model.state", state)
testlib.install_module("model.tech", tech)
testlib.install_module("model.queue", queue_state)
testlib.install_module("model.lab", {})
local analyzer = require("view.gui.analyzer")

local function find_private(function_value, wanted, seen)
    if type(function_value) ~= "function" then return nil end
    seen = seen or {}
    if seen[function_value] then return nil end
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

local function make_tech(name, options)
    options = options or {}
    return {
        meta = {
            has_prerequisites = options.has_prerequisites or false,
            has_trigger = options.has_trigger or false,
            hidden = options.hidden or false,
            is_infinite = options.is_infinite or false,
            all_successors = options.all_successors or {},
            all_prerequisites = options.all_prerequisites or {},
            sciences = options.sciences or {},
            prototype = {essential = options.essential or false}
        },
        available = options.available or false,
        suspended = options.suspended or false,
        inherited_by = options.inherited_by or {},
        queued = options.queued or false,
        blocked_by = options.blocked_by or {},
        disabled_by = options.disabled_by or {},
        technology = {
            name = name,
            researched = options.researched or false,
            enabled = options.enabled ~= false,
            successors = options.successors or {},
            prerequisites = options.prerequisites or {},
            prototype = {effects = options.effects or {}}
        }
    }
end

local tests = {
    {"returns nil for a missing or empty force queue", function()
        _G.game = {forces = {}}
        testlib.assert_nil(analyzer.get_queue_meta(1))
        game.forces[1] = {index = 1}
        queue_state.get_queue = function() return {} end
        testlib.assert_nil(analyzer.get_queue_meta(1))
        queue_state.get_queue = function() return {"automation", "logistics"} end
    end},
    {"annotates queue blocking, missing science, inheritance, and active state", function()
        tech_state = {
            automation = make_tech("automation", {
                available = true,
                has_prerequisites = true,
                all_prerequisites = {manual = true, clean = true, disabled_by = true, off = true},
                sciences = {"automation-science"}
            }),
            manual = make_tech("manual", {has_trigger = true, sciences = {"military-science"}}),
            clean = make_tech("clean"),
            disabled_by = make_tech("disabled_by", {blocked_by = {script = true}}),
            off = make_tech("off", {enabled = false}),
            logistics = make_tech("logistics", {
                enabled = false,
                hidden = true,
                all_successors = {automation = true}
            })
        }
        game.forces[1] = {index = 1}
        local result = analyzer.get_queue_meta(1)
        testlib.assert_equal(#result, 2)
        testlib.assert_true(result[1].is_researching)
        testlib.assert_true(result[1].misses_science)
        testlib.assert_true(result[1].missing_science["automation-science"])
        testlib.assert_true(result[1].missing_science["military-science"])
        testlib.assert_true(result[1].is_blocked)
        testlib.assert_has_value(result[1].inherit_blocked, "manual")
        testlib.assert_has_value(result[1].all_blocked, "manual")
        testlib.assert_has_value(result[1].inherit_unblocked, "clean")
        testlib.assert_has_value(result[1].inherit_blocked, "disabled_by")
        testlib.assert_true(result[1].blocking_reasons.tech_is_manual_trigger ~= nil)
        testlib.assert_true(result[1].blocking_reasons.tech_is_not_enabled ~= nil)
        testlib.assert_true(result[2].is_smart_researching)
        testlib.assert_true(result[2].is_inherited)
        testlib.assert_equal(result[2].inherit_by[1], "automation")
        testlib.assert_true(result[2].blocking_reasons.tech_is_not_enabled ~= nil)
    end},
    {"filters ordered technologies by science and search text", function()
        settings = {allowed_automation = true, search_text = "auto", show_tech_filter_category = "all"}
        tech_state = {
            automation = make_tech("automation", {
                available = true,
                sciences = {"automation-science"},
                effects = {{type = "unlock-recipe", recipe = "assembling-machine-1"}},
                successors = {logistics = true}
            }),
            logistics = make_tech("logistics", {
                prerequisites = {automation = true},
                sciences = {"automation-science"}
            })
        }
        game = {
            forces = {[1] = {
                index = 1,
                technologies = {
                    automation = tech_state.automation.technology,
                    logistics = tech_state.logistics.technology
                }
            }},
            get_player = function() return {index = 1, force = game.forces[1]} end
        }
        local result = analyzer.get_filtered_technologies_player(1)
        testlib.assert_equal(#result, 1)
        testlib.assert_equal(result[1].technology.name, "automation")
        settings.search_text = ""
        testlib.assert_true(#analyzer.get_filtered_technologies_player(1) >= 1)
        local matches_search = find_private(analyzer.get_filtered_technologies_player, "tech_matches_search_text")
        testlib.assert_true(type(matches_search) == "function")
        testlib.assert_true(matches_search(1, "automation"))
    end},
    {"supports category and hidden-technology filters", function()
        settings = {show_tech_filter_category = "essential", infinite_tech = true}
        tech_state = {
            essential = make_tech("essential", {available = true, essential = true}),
            infinite = make_tech("infinite", {available = true, is_infinite = true}),
            ordinary = make_tech("ordinary", {available = true})
        }
        game = {
            forces = {[1] = {index = 1, technologies = {
                essential = tech_state.essential.technology,
                infinite = tech_state.infinite.technology,
                ordinary = tech_state.ordinary.technology
            }}},
            get_player = function() return {index = 1, force = game.forces[1]} end
        }
        local result = analyzer.get_filtered_technologies_player(1)
        testlib.assert_equal(#result, 1)
        testlib.assert_equal(result[1].technology.name, "essential")
    end},
    {"applies search, science, blocking, and inheritance filters", function()
        local root = make_tech("root", {available = true, sciences = {"automation-science"},
            successors = {child = true}})
        local child = make_tech("child", {available = true, sciences = {"automation-science"},
            prerequisites = {root = true}})
        local suspended = make_tech("suspended", {available = true, suspended = true})
        local manual = make_tech("manual", {available = true, has_trigger = true})
        local infinite = make_tech("infinite", {available = true, is_infinite = true})
        local inherited = make_tech("inherited", {available = true, queued = true,
            inherited_by = {root = true}})
        local blocked = make_tech("blocked", {available = true, blocked_by = {root = true},
            disabled_by = {script = true}})
        local disabled = make_tech("disabled", {available = true, enabled = false})
        tech_state = {
            root = root, child = child, suspended = suspended, manual = manual,
            infinite = infinite, inherited = inherited, blocked = blocked, disabled = disabled
        }
        game = {
            forces = {[1] = {index = 1, technologies = {
                root = root.technology, child = child.technology, suspended = suspended.technology,
                manual = manual.technology, infinite = infinite.technology,
                inherited = inherited.technology, blocked = blocked.technology,
                disabled = disabled.technology
            }}},
            get_player = function() return {index = 1, force = game.forces[1]} end
        }
        settings = {show_tech_filter_category = "all"}
        local all = analyzer.get_filtered_technologies_player(1)
        testlib.assert_true(#all >= 8)

        settings.search_text = "does-not-exist"
        testlib.assert_equal(#analyzer.get_filtered_technologies_player(1), 0)

        settings.search_text = "assembly"
        state.get_translation = function(_, _, _, field)
            return field == "localised_name" and "Assembly" or "description"
        end
        root.technology.prototype.effects = {{type = "unlock-recipe", recipe = "assembling-machine-1"}}
        testlib.assert_true(#analyzer.get_filtered_technologies_player(1) >= 1)

        settings.search_text = nil
        settings.allowed_automation = true
        settings.suspended = true
        settings.manual_trigger_tech = true
        settings.infinite_tech = true
        settings.inherited_tech = true
        settings.unavailable_successors = true
        settings.disabled_tech = true
        local filtered = analyzer.get_filtered_technologies_player(1)
        testlib.assert_equal(#filtered, 2)
    end},
    {"keeps science-pack inspector state out of the technology list filter", function()
        const.categories.military = {research_effects = {"ammo-damage"}}
        local science = make_tech("science", {available = true, sciences = {"automation-science"}})
        local no_science = make_tech("no-science", {available = true, sciences = {"other-science"}})
        local infinite = make_tech("infinite", {available = true, is_infinite = true})
        local military = make_tech("military", {available = true})
        military.meta.research_effects = {['ammo-damage'] = true}
        tech_state = {science = science, no_science = no_science, infinite = infinite, military = military}
        game = {
            forces = {[1] = {index = 1, technologies = {
                science = science.technology, no_science = no_science.technology,
                infinite = infinite.technology, military = military.technology
            }}},
            get_player = function() return {index = 1, force = game.forces[1]} end
        }
        settings = {allowed_automation_science = true, ["allowed_automation-science"] = true,
            show_tech_filter_category = "all"}
        local science_filtered = analyzer.get_filtered_technologies_player(1)
        testlib.assert_equal(#science_filtered, 4)

        settings["allowed_automation-science"] = false
        settings.show_tech_filter_category = "infinite"
        local infinite_filtered = analyzer.get_filtered_technologies_player(1)
        testlib.assert_equal(#infinite_filtered, 1)
        testlib.assert_equal(infinite_filtered[1].technology.name, "infinite")

        settings.show_tech_filter_category = "military"
        local military_filtered = analyzer.get_filtered_technologies_player(1)
        testlib.assert_equal(#military_filtered, 1)
        testlib.assert_equal(military_filtered[1].technology.name, "military")
    end}
}

local passed = testlib.run("analyzer_spec", tests)
for name, value in pairs(original) do package.preload[name] = value end
for _, name in ipairs({"lib.const", "lib.util", "model.state", "model.tech", "model.queue", "model.lab", "view.gui.analyzer"}) do
    package.loaded[name] = nil
end
return passed
