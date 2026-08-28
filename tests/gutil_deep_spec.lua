package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local old_state_preload = package.preload["model.state"]
local old_state_loaded = package.loaded["model.state"]
local old_gutil_loaded = package.loaded["view.gui.gutil"]

local translations = {}
local function translation_key(player_index, kind, name, field)
    return tostring(player_index) .. ":" .. kind .. ":" .. name .. ":" .. field
end

t.install_module("model.state", {
    get_translation = function(player_index, kind, name, field)
        return translations[translation_key(player_index, kind, name, field)]
    end
})
t.reset_modules({"view.gui.gutil"})

local gutil = require("view.gui.gutil")
local tests = {}

local function assert_contains(text, fragment, message)
    t.assert_true(string.find(text, fragment, 1, true) ~= nil, message or ("missing " .. fragment))
end

local function deep_contains(value, expected)
    if value == expected then
        return true
    end
    if type(value) ~= "table" then
        return false
    end
    for _, child in pairs(value) do
        if deep_contains(child, expected) then
            return true
        end
    end
    return false
end

local function deep_find(value, fragment)
    if type(value) == "string" then
        return string.find(value, fragment, 1, true) ~= nil
    end
    if type(value) ~= "table" then
        return false
    end
    for _, child in pairs(value) do
        if deep_find(child, fragment) then
            return true
        end
    end
    return false
end

tests[#tests + 1] = {"formats cost, time, boundaries, and safe numeric fallbacks", function()
    t.assert_equal(gutil.format_cost, gutil.format_si)
    t.assert_equal(gutil.format_cost(1250), "1.3K")
    t.assert_equal(gutil.format_si("not a number"), "0")
    t.assert_equal(gutil.format_si(-0.5), "-0.5")
    t.assert_equal(gutil.format_si(999950), "1M")
    t.assert_equal(gutil.format_si(-math.huge), tostring(-math.huge))
    t.assert_equal(gutil.format_si(0 / 0), tostring(0 / 0))
end}

tests[#tests + 1] = {"recursively changes enabled state while honoring both ignore tags", function()
    local nested = {valid = true, enabled = false, children = {}}
    local ignored_force = {
        valid = true,
        tags = {ignore_force_enable = true},
        enabled = false,
        children = {nested}
    }
    local ordinary = {valid = true, enabled = false, children = {}}
    local root = {
        valid = true,
        tags = {},
        enabled = false,
        children = {ignored_force, ordinary}
    }

    gutil.disenable_recursive(root, true)
    t.assert_true(root.enabled)
    t.assert_false(ignored_force.enabled)
    t.assert_true(nested.enabled)
    t.assert_true(ordinary.enabled)

    local blocked_parent = {
        valid = true,
        tags = {ignore_enable = true},
        enabled = true,
        children = {{valid = true, enabled = true, children = {}}}
    }
    gutil.disenable_recursive(blocked_parent, false)
    t.assert_false(blocked_parent.enabled)
    t.assert_true(blocked_parent.children[1].enabled)
    gutil.disenable_recursive(nil, true)
end}

tests[#tests + 1] = {"finds children through invalid branches and refreshes cached references", function()
    local leaf = {valid = true, name = "leaf", children = {}}
    local invalid_branch = {valid = false, name = "branch", children = {leaf}}
    local anchor = {
        valid = true,
        index = 21,
        name = "anchor",
        children = {invalid_branch}
    }

    t.assert_nil(gutil.get_child(anchor, "leaf"))
    invalid_branch.valid = true
    t.assert_equal(gutil.get_child(anchor, "leaf"), leaf)
    local cached_leaf = gutil.get_child(anchor, "leaf")
    t.assert_equal(cached_leaf, leaf)

    leaf.valid = false
    t.assert_nil(gutil.get_child(anchor, "leaf"))
    leaf.valid = true
    gutil.clear_child_cache()
    t.assert_equal(gutil.get_child(anchor, "anchor"), anchor)
    t.assert_equal(gutil.get_child(anchor, "leaf"), leaf)

    local replacement = {valid = true, index = 21, name = "replacement", children = {leaf}}
    t.assert_equal(gutil.get_child(replacement, "leaf"), leaf)
    anchor.valid = false
    t.assert_nil(gutil.get_child(anchor, "leaf"))
    t.assert_nil(gutil.get_child(nil, "leaf"))
end}

tests[#tests + 1] = {"uses translated names, fallback names, and level overrides", function()
    translations[translation_key(3, "technology", "worker-robots-speed-7", "localised_name")] =
        "Worker robot speed 7 (infinite)"
    translations[translation_key(3, "technology", "mining-productivity", "localised_name")] =
        "Mining productivity 2"

    local infinite = {
        technology = {name = "worker-robots-speed-7", level = 7},
        meta = {is_infinite = true}
    }
    t.assert_equal(gutil.get_tech_name(3, infinite), "Worker robot speed 7 (infinite)")
    t.assert_equal(gutil.get_tech_name(3, infinite, 8), "Worker robot speed 8 (infinite)")

    local finite = {
        technology = {name = "mining-productivity", level = 2},
        meta = {is_infinite = false}
    }
    t.assert_equal(gutil.get_tech_name(3, finite, 1), "Mining productivity")
    t.assert_equal(gutil.get_tech_name(3, finite, 4), "Mining productivity 4")

    local fallback = {
        technology = {name = "automation", level = 1},
        meta = {is_infinite = false}
    }
    t.assert_equal(gutil.get_tech_name(3, fallback), "automation")
    fallback.technology.level = nil
    t.assert_equal(gutil.get_tech_name(3, fallback), "automation")
end}

tests[#tests + 1] = {"builds trigger and empty-effect tooltips with safe fallbacks", function()
    local trigger = {
        technology = {name = "rocket-silo", level = 1},
        meta = {is_infinite = false, has_trigger = true, prototype = {effects = {}}}
    }
    local tooltip = gutil.get_tooltip_text(trigger, 4)
    t.assert_equal(tooltip[1], "")
    t.assert_true(deep_find(tooltip, "[font=heading-2]rocket-silo[/font]"))
    t.assert_true(deep_find(tooltip, "Unlocked by trigger"))

    local empty = {
        technology = {name = "empty-tech", level = 2, research_unit_count = nil, research_unit_energy = nil},
        meta = {is_infinite = false, has_trigger = false, sciences = nil, prototype = {effects = {}}}
    }
    local empty_tooltip = gutil.get_tooltip_text(empty, 4)
    t.assert_true(deep_find(empty_tooltip, "[font=heading-2]empty-tech 2[/font]"))
    t.assert_true(deep_find(empty_tooltip, "0x"))
    t.assert_true(deep_find(empty_tooltip, "[img=virtual-signal.signal-clock]0"))
end}

tests[#tests + 1] = {"builds cost, science, time, recipe, item, and modifier tooltip effects", function()
    translations[translation_key(5, "recipe", "rocket-part", "localised_name")] = "Rocket part"
    translations[translation_key(5, "space_location", "vulcanus", "localised_name")] = "Vulcanus"

    local xcur = {
        technology = {
            name = "rocket-silo",
            level = 3,
            research_unit_count = 120,
            research_unit_energy = 120
        },
        meta = {
            is_infinite = false,
            has_trigger = false,
            sciences = {"automation-science-pack", "logistic-science-pack"},
            prototype = {
                effects = {
                    {type = "unlock-recipe", recipe = "rocket-part"},
                    {type = "give-item", item = "space-science-pack", count = 3, quality = "epic"},
                    {type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.125},
                    {type = "ammo-damage", ammo_category = "bullet", modifier = 0.25},
                    {type = "gun-speed", ammo_category = "laser", modifier = 0.5},
                    {type = "turret-attack", turret_id = "gun-turret", modifier = 0.1},
                    {type = "nothing", effect_description = {"", "No effect"}},
                    {type = "unlock-space-location", space_location = "vulcanus"},
                    {type = "unlock-quality"},
                    {type = "unlock-circuit-network", modifier = 0.2}
                }
            }
        }
    }

    local tooltip = gutil.get_tooltip_text(xcur, 5, nil, 150)
    t.assert_true(deep_find(tooltip, "[font=heading-2]rocket-silo 3[/font]"))
    t.assert_true(deep_find(tooltip, "[font=default-bold]Cost[/font]"))
    t.assert_true(deep_find(tooltip, "150x"))
    t.assert_true(deep_find(tooltip, "[img=item.automation-science-pack]"))
    t.assert_true(deep_find(tooltip, "[img=item.logistic-science-pack]"))
    t.assert_true(deep_find(tooltip, "[img=virtual-signal.signal-clock]2"))
    t.assert_true(deep_find(tooltip, "[img=recipe.rocket-part] Rocket part (Recipe)"))
    t.assert_true(deep_find(tooltip, "3x [item=space-science-pack,quality=epic] space-science-pack"))
    t.assert_true(deep_contains(tooltip, "modifier-description.change-recipe-productivity"))
    t.assert_true(deep_contains(tooltip, "modifier-description.bullet-damage-bonus"))
    t.assert_true(deep_contains(tooltip, "modifier-description.laser-shooting-speed-bonus"))
    t.assert_true(deep_contains(tooltip, "modifier-description.gun-turret-attack-bonus"))
    t.assert_true(deep_contains(tooltip, "No effect"))
    t.assert_true(deep_contains(tooltip, "modifier-description.space-location-discovery"))
    t.assert_true(deep_contains(tooltip, "[space-location=vulcanus] Vulcanus"))
    t.assert_true(deep_contains(tooltip, "modifier-description.unlock-quality"))
    t.assert_true(deep_contains(tooltip, "modifier-description.unlock-circuit-network"))
end}

tests[#tests + 1] = {"limits very large modifier tooltip lists with a remainder marker", function()
    local effects = {}
    for index = 1, 19 do
        effects[index] = {type = "unlisted-effect-" .. index}
    end
    local xcur = {
        technology = {name = "large-tech", level = 1, research_unit_count = 1, research_unit_energy = 60},
        meta = {
            is_infinite = false,
            has_trigger = false,
            prototype = {effects = effects}
        }
    }

    local tooltip = gutil.get_tooltip_text(xcur, 6)
    t.assert_true(deep_contains(tooltip, "+1"))
    t.assert_true(deep_contains(tooltip, "modifier-description.unlisted-effect-1"))
    t.assert_true(deep_contains(tooltip, "modifier-description.unlisted-effect-18"))
    t.assert_false(deep_contains(tooltip, "modifier-description.unlisted-effect-19"))
end}

tests[#tests + 1] = {"includes localised_description between heading and cost", function()
    translations[translation_key(7, "technology", "oil-processing", "localised_description")] =
        "Refinery allows processing crude oil."
    local xcur = {
        technology = {name = "oil-processing", level = 1, research_unit_count = 30, research_unit_energy = 30},
        meta = {
            is_infinite = false,
            has_trigger = false,
            sciences = {"automation-science-pack"},
            prototype = {
                effects = {},
                localised_description = {"technology-description.oil-processing"}
            }
        }
    }
    local tooltip = gutil.get_tooltip_text(xcur, 7)
    t.assert_equal(tooltip[1], "")
    t.assert_true(deep_find(tooltip, "[font=heading-2]oil-processing[/font]"))
    t.assert_true(deep_contains(tooltip, "technology-description.oil-processing"))
    t.assert_true(deep_find(tooltip, "[font=default-bold]Cost[/font]"))
    -- Description must appear before the cost section in the array
    local desc_idx
    local cost_idx
    for i, v in ipairs(tooltip) do
        if type(v) == "table" and deep_contains(v, "technology-description.oil-processing") then
            desc_idx = i
        end
        if type(v) == "string" and string.find(v, "Cost", 1, true) then
            cost_idx = i
        end
    end
    t.assert_true(desc_idx ~= nil and cost_idx ~= nil and desc_idx < cost_idx)
end}

tests[#tests + 1] = {"skips description when translation is missing", function()
    local xcur = {
        technology = {name = "no-desc-tech", level = 1, research_unit_count = 10, research_unit_energy = 30},
        meta = {
            is_infinite = false,
            has_trigger = false,
            sciences = {"automation-science-pack"},
            prototype = {effects = {}, localised_description = {"technology-description.no-desc-tech"}}
        }
    }
    local tooltip = gutil.get_tooltip_text(xcur, 8)
    t.assert_equal(tooltip[1], "")
    t.assert_true(deep_find(tooltip, "[font=heading-2]no-desc-tech[/font]"))
    t.assert_true(deep_find(tooltip, "[font=default-bold]Cost[/font]"))
    -- With no translation, the description LocalisedString must not be inserted
    t.assert_false(deep_contains(tooltip, "technology-description.no-desc-tech"))
    -- tooltip[2] is heading and tooltip[3] is the body (no description in between)
    t.assert_equal(tooltip[2], "[font=heading-2]no-desc-tech[/font]\n")
end}

local passed, err = pcall(function()
    return t.run("gutil_deep_spec", tests)
end)

if old_state_preload then
    package.preload["model.state"] = old_state_preload
else
    package.preload["model.state"] = nil
end
package.loaded["model.state"] = old_state_loaded
package.loaded["view.gui.gutil"] = old_gutil_loaded

if not passed then
    error(err, 0)
end
return err
