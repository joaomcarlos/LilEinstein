package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")
local names = {
    "lib.util", "lib.const", "model.state", "model.tech", "model.lab", "model.env",
    "lib.log", "model.research_weights", "model.research_policy", "model.auto_switch",
    "model.queue"
}
local original = {}
for _, name in ipairs(names) do
    original[name] = package.preload[name]
    package.loaded[name] = nil
end

local requests = 0
local queued_updates = {}
local tech_state = {}
local presets = {}
local force_settings = {}
local policy_settings = {}
local science_priorities = {}
local science_names = {}
local registered_labs = {}
local runtime_lab_content = {}

t.install_module("lib.util", {})
t.install_module("lib.const", {
    default_settings = {force = {settings = {auto_research = true, requeue_infinite_tech = true}}}
})
t.install_module("lib.log", {log = function() end, warn = function() end, error = function() end})
t.install_module("model.state", {
    get_force_setting = function(_, key, default) return force_settings[key] == nil and default or force_settings[key] end,
    request_next_research = function() requests = requests + 1 end,
    request_gui_update = function() requests = requests + 1 end
})
t.install_module("model.tech", {
    get_all_tech_state_ext = function() return tech_state end,
    get_single_tech_state_ext = function(_, name) return tech_state[name] end,
    update_queued = function(_, name, value) queued_updates[name] = value end
})
t.install_module("model.lab", {
    get_registered_labs = function() return registered_labs end,
    get_runtime_lab_content = function() return runtime_lab_content end,
    register = function() end
})
t.install_module("model.env", {
    get_all_sciences = function() return science_names end
})
t.install_module("model.research_weights", {research_weights = {}, research_caps = {}, pack_difficulty = {}})
t.install_module("model.research_policy", {
    get_setting = function(_, key, default) return policy_settings[key] == nil and default or policy_settings[key] end,
    get_tech_science_priority = function(_, xcur_value)
        local name = xcur_value and xcur_value.technology and xcur_value.technology.name
        if name and science_priorities[name] ~= nil then
            return science_priorities[name]
        end
        return policy_settings.science_priority == nil and 0 or policy_settings.science_priority
    end,
    get_strategy_adjustment = function() return 0 end,
    should_requeue = function() return false end,
    consume_repeat = function() end,
    parallel_mod_available = function() return policy_settings.parallel_mod == true end,
    get_science_policy = function() return {upper_threshold = 1, lower_threshold = 0.5} end,
    get_science_available_state = function() return false end,
    set_science_available_state = function() end,
    get_cluster_science_available_state = function() return false end,
    set_cluster_science_available_state = function() end,
    prune_cluster_science_states = function() end,
    copy_table = function(value)
        local copy = {}
        for key, item in pairs(value or {}) do copy[key] = item end
        return copy
    end,
    export_settings = function() return {} end,
    sanitize_settings = function(value) return value or {} end,
    import_settings = function() end,
    set_preset = function(_, name, snapshot) presets[name] = snapshot; return true end,
    get_presets = function() return presets end,
    delete_preset = function(_, name) presets[name] = nil end
})

local queue = require("model.queue")

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

local function find_private_slot(function_value, wanted, seen)
    if type(function_value) ~= "function" then return nil end
    seen = seen or {}
    if seen[function_value] then return nil end
    seen[function_value] = true
    for index = 1, 64 do
        local name, value = debug.getupvalue(function_value, index)
        if not name then break end
        if name == wanted then
            return function_value, index, value
        end
        local owner, nested_index, original = find_private_slot(value, wanted, seen)
        if owner then
            return owner, nested_index, original
        end
    end
    return nil
end

local function swap_private(function_value, wanted, replacement)
    local owner, index, original = find_private_slot(function_value, wanted)
    if not owner then return nil end
    debug.setupvalue(owner, index, replacement)
    return function()
        debug.setupvalue(owner, index, original)
    end
end

local function make_tech(name, options)
    options = options or {}
    return {
        name = name,
        valid = options.valid ~= false,
        enabled = options.enabled ~= false,
        researched = options.researched or false,
        level = options.level,
        localised_name = {"technology-name", name},
        research_unit_count = options.research_unit_count or 100,
        research_unit_ingredients = options.research_unit_ingredients or {{name = "automation-science-pack"}},
        prototype = {effects = options.effects or {}}
    }
end

local function reset_runtime()
    requests = 0
    queued_updates = {}
    presets = {}
    force_settings = {}
    policy_settings = {}
    science_priorities = {}
    tech_state = {}
    science_names = {}
    registered_labs = {}
    runtime_lab_content = {}
    local technologies = {
        a = make_tech("a"),
        b = make_tech("b"),
        c = make_tech("c"),
        d = make_tech("d")
    }
    storage = {forces = {[1] = {queue = {queue = {"a", "b", "c"}}}}}
    game = {tick = 10, forces = {[1] = {index = 1, technologies = technologies, research_queue = {}}}, surfaces = {}}
    prototypes = {item = {}}
    return game.forces[1]
end

local function xcur(name, options)
    options = options or {}
    return {
        available = options.available ~= false,
        suspended = false,
        queued = false,
        inherited_by = {},
        blocked_by = {},
        disabled_by = {},
        meta = {
            sciences = options.sciences or {},
            hidden = options.hidden or false,
            has_trigger = options.has_trigger or false,
            is_infinite = options.is_infinite or false,
            prototype = options.prototype or {},
            research_effects = options.research_effects or {}
        },
        technology = make_tech(name, options)
    }
end

local tests = {
    {"stores basic queue state and internal cancellation windows", function()
        local force = reset_runtime()
        queue.set_pinned_tech(1, "b")
        t.assert_equal(queue.get_pinned_tech(1), "b")
        t.assert_equal(queue.get_queue(1)[2], "b")
        t.assert_false(queue.is_internal_research_queue_update(force))
        storage.forces[1].queue.internal_queue_update_until = game.tick + 2
        storage.forces[1].queue.internal_cancelled_techs = {b = game.tick + 2}
        t.assert_true(queue.is_internal_research_queue_update(force))
        t.assert_true(queue.consume_internal_research_cancel(force, "b"))
        t.assert_false(queue.consume_internal_research_cancel(force, "b"))
        game.tick = game.tick + 3
        t.assert_false(queue.is_internal_research_queue_update(force))
    end},
    {"checks plain and cluster science availability", function()
        reset_runtime()
        local item = xcur("a", {sciences = {"automation-science-pack"}})
        t.assert_false(queue.science_is_available(nil, {}))
        t.assert_true(queue.science_is_available({meta = {}}, {}))
        t.assert_false(queue.science_is_available(item, {}))
        t.assert_true(queue.science_is_available(item, {['automation-science-pack'] = true}))
        local cluster = {
            available_sciences = {['automation-science-pack'] = true},
            lab_input_sets = {{['automation-science-pack'] = true}}
        }
        local clustered = {['automation-science-pack'] = true, __cluster_mode = true, __clusters = {cluster}}
        t.assert_true(queue.science_is_available(item, clustered))
        cluster.lab_input_sets = {{['logistic-science-pack'] = true}}
        t.assert_false(queue.science_is_available(item, clustered))
        cluster.available_sciences = {}
        t.assert_false(queue.science_is_available(item, clustered))
    end},
    {"counts lab and logistic-network stock with cached breakdowns", function()
        local force = reset_runtime()
        science_names = {"automation-science-pack", "logistic-science-pack"}
        defines = {inventory = {lab_input = 1}}

        local direct_force = {
            find_logistic_network_by_position = function() return nil end
        }
        local network = {
            valid = true,
            network_id = 7,
            get_item_count = function(science)
                return science == "automation-science-pack" and 5 or 3
            end
        }
        local network_force = {
            find_logistic_network_by_position = function() return network end
        }
        local surface = {valid = true, index = 1, name = "Nauvis"}
        local direct = {
            valid = true,
            unit_number = 1,
            force = direct_force,
            surface = surface,
            position = {x = 0, y = 0},
            prototype = {name = "direct-lab", lab_inputs = science_names},
            get_inventory = function()
                return {get_contents = function()
                    return {{name = "automation-science-pack", count = 2}}
                end}
            end
        }
        local network_lab = {
            valid = true,
            unit_number = 2,
            force = network_force,
            surface = surface,
            position = {x = 1, y = 1},
            prototype = {name = "network-lab", lab_inputs = science_names},
            get_inventory = function()
                return {get_contents = function() return {} end}
            end
        }
        registered_labs = {direct, network_lab, {valid = false}}
        queue.invalidate_science_cache(1)
        local counts = queue.get_science_counts(1)
        t.assert_equal(counts["automation-science-pack"], 7, "automation count " .. tostring(counts["automation-science-pack"]))
        t.assert_equal(counts["logistic-science-pack"], 3, "logistic count " .. tostring(counts["logistic-science-pack"]))
        local breakdown = queue.get_science_count_breakdown(1, "automation-science-pack")
        t.assert_equal(breakdown.lab_count, 2)
        t.assert_equal(breakdown.lab_entity_count, 1)
        t.assert_equal(breakdown.network_total, 5)
        local clusters = queue.get_science_clusters(1)
        local cluster_count = 0
        for _ in pairs(clusters) do cluster_count = cluster_count + 1 end
        t.assert_equal(cluster_count, 2)
        t.assert_equal(queue.get_science_count_breakdown(1, "missing").lab_count, 0)
        t.assert_equal(queue.get_science_counts(1), counts)
        _G.defines = nil
    end},
    {"computes force-wide availability and production forecasts", function()
        local force = reset_runtime()
        science_names = {"automation-science-pack"}
        defines = {flow_precision_index = {one_minute = 1}, inventory = {lab_input = 1}}
        local surface = {valid = true, index = 1, name = "Nauvis"}
        local network = {
            valid = true,
            network_id = 9,
            get_item_count = function() return 20 end
        }
        local lab_force = {find_logistic_network_by_position = function() return network end}
        registered_labs = {{
            valid = true,
            unit_number = 9,
            force = lab_force,
            surface = surface,
            position = {x = 2, y = 2},
            prototype = {name = "forecast-lab", lab_inputs = science_names},
            get_inventory = function() return {get_contents = function() return {} end} end
        }}
        force.get_item_production_statistics = function()
            return {
                valid = true,
                get_flow_count = function(options)
                    return options.category == "input" and 5 or 2
                end
            }
        end
        game.surfaces = {surface}
        queue.invalidate_science_cache(1)
        local availability = queue.get_science_availability(1)
        t.assert_true(availability["automation-science-pack"])
        local forecast = queue.get_science_forecast(1)
        t.assert_equal(forecast["automation-science-pack"].production_per_minute, 5)
        t.assert_equal(forecast["automation-science-pack"].consumption_per_minute, 2)
        t.assert_equal(forecast["automation-science-pack"].depletion_seconds, math.huge)
        policy_settings.cluster_mode = true
        game.tick = game.tick + 1
        queue.invalidate_science_cache(1)
        local clustered = queue.get_science_availability(1)
        t.assert_true(clustered.__cluster_mode)
        t.assert_true(clustered["automation-science-pack"])
        _G.defines = nil
    end},
    {"distinguishes attributable and shared cluster depletion", function()
        reset_runtime()
        policy_settings.forecast_seconds = 60
        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        queue.get_research_speed = function() return 1, true end
        queue.get_science_forecast = function()
            return {pack = {depletion_seconds = 1}}
        end
        queue.get_science_availability = function()
            return {
                pack = true,
                __cluster_mode = true,
                __clusters = {{
                    lab_input_counts = {pack = 1},
                    available_sciences = {pack = true},
                    lab_input_sets = {{pack = true}}
                }}
            }
        end
        local candidate = xcur("candidate", {
            sciences = {"pack"},
            research_unit_count = 100,
            research_unit_ingredients = {{name = "pack", amount = 1}}
        })
        t.assert_false(queue.science_is_sufficient(candidate, 1))
        queue.get_science_availability = function()
            return {
                pack = true,
                __cluster_mode = true,
                __clusters = {
                    {
                        lab_input_counts = {pack = 1},
                        available_sciences = {pack = true},
                        lab_input_sets = {{pack = true}}
                    },
                    {
                        lab_input_counts = {pack = 1},
                        available_sciences = {pack = true},
                        lab_input_sets = {{pack = true}}
                    }
                }
            }
        end
        t.assert_true(queue.science_is_sufficient(candidate, 1))
        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed
    end},
    {"scores technology effects, caps, unavailable candidates, and formulas", function()
        reset_runtime()
        local recipe = xcur("recipe", {research_effects = {['unlock-recipe'] = true}})
        local score = queue.score_tech_detailed(recipe, 1, 2, 200, 1)
        t.assert_equal(score.importance, 3)
        t.assert_equal(score.user_boost, 2)
        t.assert_true(score.total > 0)
        local infinite = xcur("infinite", {
            is_infinite = true,
            level = 2,
            prototype = {research_unit_count_formula = "100(L-1)+50"}
        })
        local infinite_score = queue.score_tech_detailed(infinite, 3, 0, 1000, 1)
        t.assert_true(infinite_score.level_boost > 0)
        local invalid_formula = xcur("invalid-formula", {
            is_infinite = true,
            level = 2,
            prototype = {research_unit_count_formula = "not a formula"}
        })
        t.assert_true(queue.score_tech_detailed(invalid_formula, 3, 0, 1000, 1).total ~= nil)
        local unavailable = xcur("unavailable", {available = false})
        local unavailable_score = queue.score_tech_detailed(unavailable, 1, 0, nil, 1)
        local available = queue.score_tech_detailed(xcur("available"), 1, 0, nil, 1)
        t.assert_true(unavailable_score.total < available.total)
        policy_settings.science_priority = -1000
        t.assert_equal(queue.score_tech_detailed(xcur("blocked-score"), 1, 0, nil, 1).total, -10000)
        policy_settings.science_priority = nil
    end},
    {"rejects unavailable and forecast-depleting science supplies", function()
        local force = reset_runtime()
        defines = {inventory = {lab_input = 1}}
        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_bottleneck = queue.get_active_missing_science_bottleneck
        local xscience = xcur("science-tech", {sciences = {"automation-science-pack"}, research_unit_count = 100})
        storage.forces[1].queue.speed_samples = {{speed = 1, valid_speed = true, tech_name = "science-tech"}}
        queue.get_science_forecast = function()
            return {['automation-science-pack'] = {depletion_seconds = 1}}
        end

        queue.get_science_availability = function()
            return {['automation-science-pack'] = false}
        end
        t.assert_false(queue.science_is_sufficient(xscience, 1))

        queue.get_science_availability = function()
            return {
                ['automation-science-pack'] = true,
                __cluster_mode = true,
                __clusters = {{available_sciences = {['automation-science-pack'] = true},
                    lab_input_sets = {{['automation-science-pack'] = true}},
                    lab_input_counts = {['automation-science-pack'] = 1}}}
            }
        end
        queue.get_science_forecast = function()
            return {['automation-science-pack'] = {depletion_seconds = 1}}
        end
        policy_settings.forecast_seconds = 100
        t.assert_false(queue.science_is_sufficient(xscience, 1))

        queue.get_science_availability = function()
            return {
                ['automation-science-pack'] = true,
                __cluster_mode = true,
                __clusters = {
                    {available_sciences = {['automation-science-pack'] = true},
                        lab_input_sets = {{['automation-science-pack'] = true}},
                        lab_input_counts = {['automation-science-pack'] = 1}},
                    {available_sciences = {['automation-science-pack'] = true},
                        lab_input_sets = {{['automation-science-pack'] = true}},
                        lab_input_counts = {['automation-science-pack'] = 1}}
                }
            }
        end
        t.assert_true(queue.science_is_sufficient(xscience, 1))

        force.current_research = make_tech("science-tech")
        queue.get_active_missing_science_bottleneck = function() return {['automation-science-pack'] = true} end
        t.assert_false(queue.science_is_sufficient(xscience, 1))

        queue.get_active_missing_science_bottleneck = function() return {} end
        t.assert_true(queue.science_is_sufficient(xscience, 1))
        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_active_missing_science_bottleneck = old_bottleneck
    end},
    {"switches when a material pack-bound loss leaves an alternate supplied", function()
        local force = reset_runtime()
        science_names = {"starved-pack", "available-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_speed = queue.get_research_speed
        queue.get_science_availability = function()
            return {['starved-pack'] = true, ['available-pack'] = true}
        end
        queue.get_research_speed = function() return 16 / 60, true end

        local make_lab = function(unit_number, status, speed)
            return {
                valid = true,
                unit_number = unit_number,
                speed_bonus = speed - 1,
                productivity_bonus = 0,
                prototype = {
                    name = "switch-lab-" .. tostring(unit_number),
                    lab_inputs = {"starved-pack", "available-pack"},
                    get_researching_speed = function() return 1 end
                }
            }, {
                lab = nil,
                latest_tick = game.tick,
                latest_status = status,
                latest_contents = {{name = "available-pack", count = 1}}
            }
        end

        local missing_lab, missing_content = make_lab(1, defines.entity_status.missing_science_packs, 1)
        missing_content.lab = missing_lab
        runtime_lab_content[1] = missing_content
        for unit_number = 2, 5 do
            local working_lab, working_content = make_lab(
                unit_number, defines.entity_status.working, 4.75
            )
            working_content.lab = working_lab
            runtime_lab_content[unit_number] = working_content
        end

        tech_state = {
            current = xcur("current", {sciences = {"starved-pack"}}),
            alternate = xcur("alternate", {sciences = {"available-pack"}})
        }
        storage.forces[1].queue.queue = {"current", "alternate"}
        force.current_research = {
            name = "current",
            research_unit_energy = 100,
            research_unit_ingredients = {{name = "starved-pack", amount = 1}}
        }

        t.assert_equal(queue.get_active_missing_science_bottleneck(1, tech_state.current)["starved-pack"], true)
        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, "alternate",
            "a material pack-bound loss must switch to a supplied alternate research")
        t.assert_equal(requests, 1, "switching must request active research reselection")

        queue.get_science_availability = old_availability
        queue.get_research_speed = old_speed
    end},
    {"uses the completed pack-bound diagnostic when staggered samples are stale", function()
        local force = reset_runtime()
        game.tick = 2000
        science_names = {"starved-pack", "available-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_diagnostic = queue.get_research_display_diagnostic
        local old_snapshot_tick = queue.get_research_health_snapshot_tick
        local old_forecast = queue.get_science_forecast
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {['starved-pack'] = true, ['available-pack'] = true}
        end
        queue.get_science_forecast = function()
            return {}
        end
        queue.get_research_health_snapshot_tick = function()
            return game.tick
        end
        queue.get_research_display_diagnostic = function()
            return {
                state = "pack_bound",
                current_technology = "current",
                missing_sciences = {
                    {science = "starved-pack", lost_spm = 100}
                }
            }
        end

        local current = xcur("current", {
            sciences = {"starved-pack"},
            research_unit_ingredients = {{name = "starved-pack", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        force.current_research = current.technology
        local alternate = xcur("alternate", {
            sciences = {"available-pack"},
            research_unit_ingredients = {{name = "available-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60

        local stale_lab = {
            valid = true,
            unit_number = 1,
            speed_bonus = 0,
            productivity_bonus = 0,
            prototype = {
                name = "stale-diagnostic-lab",
                lab_inputs = {"starved-pack"},
                get_researching_speed = function() return 1 end
            }
        }
        runtime_lab_content[1] = {
            lab = stale_lab,
            latest_tick = game.tick - 1000,
            latest_status = defines.entity_status.missing_science_packs,
            latest_contents = {}
        }

        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"current"}

        local bottleneck = queue.get_active_missing_science_bottleneck(1, current)
        t.assert_equal(bottleneck["starved-pack"], true,
            "the switcher must honor a fresh completed PACK-BOUND diagnostic even when its lab samples are stale")
        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, "alternate",
            "a player-visible PACK-BOUND result must trigger the alternate research switch")

        queue.get_science_availability = old_availability
        queue.get_research_display_diagnostic = old_diagnostic
        queue.get_research_health_snapshot_tick = old_snapshot_tick
        queue.get_science_forecast = old_forecast
    end},
    {"uses a supplied unqueued fallback when the only queued technology is pack-bound", function()
        local force = reset_runtime()
        game.tick = 31000
        science_names = {"unique-starved-pack", "available-pack", "thin-pack", "short-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        local availability_calls = 0
        policy_settings.forecast_seconds = 120
        queue.get_science_availability = function()
            availability_calls = availability_calls + 1
            return {
                ['unique-starved-pack'] = true,
                ['available-pack'] = true,
                ['thin-pack'] = true,
                ['short-pack'] = true
            }
        end
        queue.get_science_forecast = function()
            return {
                ['unique-starved-pack'] = {
                    stock = 1,
                    production_per_minute = 0,
                    consumption_per_minute = 0,
                    net_per_minute = 0
                },
                ['available-pack'] = {
                    stock = 100000,
                    production_per_minute = 100000,
                    consumption_per_minute = 0,
                    net_per_minute = 100000
                },
                ['thin-pack'] = {
                    stock = 500,
                    production_per_minute = 0,
                    consumption_per_minute = 0,
                    net_per_minute = 0
                },
                ['short-pack'] = {
                    stock = 100,
                    production_per_minute = 0,
                    consumption_per_minute = 0,
                    net_per_minute = 0
                }
            }
        end
        queue.get_research_speed = function() return 1 end

        local current = xcur("current", {
            sciences = {"unique-starved-pack"},
            research_unit_ingredients = {{name = "unique-starved-pack", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local alternate = xcur("alternate", {
            sciences = {"available-pack"},
            research_unit_ingredients = {{name = "available-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        local thin_alternate = xcur("thin-alternate", {
            sciences = {"thin-pack"},
            research_unit_count = 100000,
            research_unit_ingredients = {{name = "thin-pack", amount = 1}}
        })
        thin_alternate.technology.research_unit_energy = 60
        science_priorities["thin-alternate"] = 100
        local short_alternate = xcur("short-alternate", {
            sciences = {"short-pack"},
            research_unit_count = 100,
            research_unit_ingredients = {{name = "short-pack", amount = 1}}
        })
        short_alternate.technology.research_unit_energy = 60
        science_priorities["short-alternate"] = 90
        tech_state = {
            current = current,
            alternate = alternate,
            ["thin-alternate"] = thin_alternate,
            ["short-alternate"] = short_alternate
        }
        for index = 1, 200 do
            local name = string.format("disabled-filler-%03d", index)
            local filler = xcur(name, {
                enabled = false,
                sciences = {"available-pack"},
                research_unit_ingredients = {{name = "available-pack", amount = 1}}
            })
            tech_state[name] = filler
            force.technologies[name] = filler.technology
        end
        storage.forces[1].queue.queue = {"current"}
        force.current_research = current.technology

        local function add_lab(unit_number, speed, status, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                speed_bonus = speed - 1,
                productivity_bonus = 0,
                prototype = {
                    name = "fallback-lab-" .. tostring(unit_number),
                    lab_inputs = {"unique-starved-pack", "available-pack"},
                    get_researching_speed = function() return 1 end
                }
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = status,
                latest_contents = contents
            }
        end
        add_lab(1, 49, defines.entity_status.missing_science_packs,
            {{name = "available-pack", count = 100000}})
        add_lab(2, 1, defines.entity_status.working, {
            {name = "unique-starved-pack", count = 100000},
            {name = "available-pack", count = 100000}
        })

        local bottleneck = queue.get_active_missing_science_bottleneck(1, current)
        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech
        local requested = requests
        local availability_calls_after_switch = availability_calls
        queue.start_next_research(force, true)
        local runtime_first = force.research_queue[1]
        runtime_first = runtime_first and runtime_first.name or runtime_first
        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_equal(bottleneck["unique-starved-pack"], true,
            "the low-but-nonzero current research must expose its unique missing pack")
        t.assert_equal(selected, "short-alternate",
            "hard starvation must skip a forecast-starved alternate and accept one stocked to completion")
        t.assert_equal(requested, 1, "the emergency fallback must request active reselection")
        t.assert_true(availability_calls_after_switch <= 2,
            "one emergency slice must reuse science availability; calls=" ..
                tostring(availability_calls_after_switch))
        t.assert_equal(runtime_first, "short-alternate",
            "forced reselection must put the emergency fallback first in Factorio's queue")
    end},
    {"bounds the emergency fallback candidate scan", function()
        local force = reset_runtime()
        game.tick = 31500
        science_names = {"unique-starved-pack", "blocked-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_get_tech_enabled = queue.get_tech_enabled
        local enabled_checks = 0
        queue.get_science_availability = function()
            return {['unique-starved-pack'] = true, ['blocked-pack'] = false}
        end
        queue.get_tech_enabled = function(force_index, technology_name)
            enabled_checks = enabled_checks + 1
            return old_get_tech_enabled(force_index, technology_name)
        end

        local current = xcur("current", {
            sciences = {"unique-starved-pack"},
            research_unit_ingredients = {{name = "unique-starved-pack", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        tech_state = {current = current}
        for index = 1, 200 do
            local name = string.format("blocked-%03d", index)
            local candidate = xcur(name, {
                sciences = {"blocked-pack"},
                research_unit_ingredients = {{name = "blocked-pack", amount = 1}}
            })
            candidate.technology.research_unit_energy = 60
            tech_state[name] = candidate
            force.technologies[name] = candidate.technology
        end
        storage.forces[1].queue.queue = {"current"}
        force.current_research = current.technology

        local function add_lab(unit_number, speed, status, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                speed_bonus = speed - 1,
                productivity_bonus = 0,
                prototype = {
                    name = "bounded-fallback-lab-" .. tostring(unit_number),
                    lab_inputs = {"unique-starved-pack", "blocked-pack"},
                    get_researching_speed = function() return 1 end
                }
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = status,
                latest_contents = contents
            }
        end
        add_lab(1, 49, defines.entity_status.missing_science_packs, {})
        add_lab(2, 1, defines.entity_status.working,
            {{name = "unique-starved-pack", count = 100000}})

        queue.check_and_switch_temp_research(force)
        queue.get_science_availability = old_availability
        queue.get_tech_enabled = old_get_tech_enabled

        t.assert_true(enabled_checks <= 150,
            "one starvation check must inspect only a bounded technology slice; checks=" ..
                tostring(enabled_checks))
        t.assert_equal(storage.forces[1].queue.temp_tech, nil,
            "blocked technologies must not become emergency research")
    end},
    {"does not restore a high-demand target for a tiny idle stock buffer", function()
        local force = reset_runtime()
        game.tick = 32000
        science_names = {"target-pack", "alternate-pack"}
        policy_settings.forecast_seconds = 120
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        queue.get_science_availability = function()
            return {['target-pack'] = true, ['alternate-pack'] = true}
        end
        queue.get_science_forecast = function()
            return {
                ['target-pack'] = {
                    stock = 10,
                    production_per_minute = 0,
                    consumption_per_minute = 0,
                    net_per_minute = 0
                },
                ['alternate-pack'] = {
                    stock = 100000,
                    production_per_minute = 100000,
                    consumption_per_minute = 0,
                    net_per_minute = 100000
                }
            }
        end
        queue.get_research_speed = function() return 100 end

        local target = xcur("target", {
            sciences = {"target-pack"},
            research_unit_count = 100000,
            research_unit_ingredients = {{name = "target-pack", amount = 1}}
        })
        target.technology.research_unit_energy = 60
        target.queued = true
        local alternate = xcur("alternate", {
            sciences = {"alternate-pack"},
            research_unit_count = 100000,
            research_unit_ingredients = {{name = "alternate-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        tech_state = {target = target, alternate = alternate}
        storage.forces[1].queue.queue = {"target"}
        storage.forces[1].queue.target_tech = "target"
        storage.forces[1].queue.temp_tech = "alternate"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        storage.forces[1].queue.last_switch_tick = game.tick - 2000
        force.current_research = alternate.technology

        local lab_entity = {
            valid = true,
            unit_number = 1,
            speed_bonus = 99,
            productivity_bonus = 0,
            prototype = {
                name = "high-demand-lab",
                lab_inputs = {"target-pack", "alternate-pack"},
                science_pack_drain_rate_percent = 100,
                get_researching_speed = function() return 1 end
            }
        }
        runtime_lab_content[1] = {
            lab = lab_entity,
            latest_tick = game.tick,
            latest_status = defines.entity_status.working,
            latest_contents = {{name = "alternate-pack", count = 100000}}
        }

        local target_is_sufficient = queue.science_is_sufficient(target, 1)
        queue.check_and_switch_temp_research(force)
        local retained_temp = storage.forces[1].queue.temp_tech
        local extended_timeout = storage.forces[1].queue.temp_tech_timeout
        local requested = requests
        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_false(target_is_sufficient,
            "an idle target must be evaluated against its own projected pack demand")
        t.assert_equal(retained_temp, "alternate",
            "a tiny delivery must not restore the high-demand pack-bound target")
        t.assert_true(extended_timeout > game.tick,
            "the supplied alternate must receive another recovery window")
        t.assert_equal(requested, 0,
            "retaining the already-active alternate must not request redundant reselection")
    end},
    {"uses the target's own capacity for its recovery horizon", function()
        local force = reset_runtime()
        game.tick = 32500
        science_names = {"target-pack", "alternate-pack"}
        policy_settings.forecast_seconds = 120
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        queue.get_science_availability = function()
            return {['target-pack'] = true, ['alternate-pack'] = true}
        end
        queue.get_science_forecast = function()
            return {
                ['target-pack'] = {
                    stock = 500,
                    production_per_minute = 0,
                    consumption_per_minute = 0,
                    net_per_minute = 0
                },
                ['alternate-pack'] = {
                    stock = 100000,
                    production_per_minute = 100000,
                    consumption_per_minute = 0,
                    net_per_minute = 100000
                }
            }
        end
        queue.get_research_speed = function() return 100 end

        local target = xcur("target", {
            sciences = {"target-pack"},
            research_unit_count = 1000,
            research_unit_ingredients = {{name = "target-pack", amount = 1}}
        })
        target.technology.research_unit_energy = 600
        target.queued = true
        local alternate = xcur("alternate", {
            sciences = {"alternate-pack"},
            research_unit_count = 100000,
            research_unit_ingredients = {{name = "alternate-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        tech_state = {target = target, alternate = alternate}
        storage.forces[1].queue.queue = {"target"}

        local lab_entity = {
            valid = true,
            unit_number = 1,
            speed_bonus = 99,
            productivity_bonus = 0,
            prototype = {
                name = "different-energy-lab",
                lab_inputs = {"target-pack", "alternate-pack"},
                science_pack_drain_rate_percent = 100,
                get_researching_speed = function() return 1 end
            }
        }
        runtime_lab_content[1] = {
            lab = lab_entity,
            latest_tick = game.tick,
            latest_status = defines.entity_status.missing_science_packs,
            latest_contents = {}
        }
        force.current_research = target.technology
        queue.get_active_missing_science_bottleneck(1, target)

        storage.forces[1].queue.target_tech = "target"
        storage.forces[1].queue.temp_tech = "alternate"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        storage.forces[1].queue.last_switch_tick = game.tick - 2000
        force.current_research = alternate.technology
        runtime_lab_content[1].latest_status = defines.entity_status.working
        runtime_lab_content[1].latest_contents = {{name = "alternate-pack", count = 100000}}

        local target_is_sufficient = queue.science_is_sufficient(target, 1)
        queue.check_and_switch_temp_research(force)
        local retained_temp = storage.forces[1].queue.temp_tech
        local requested = requests
        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_false(target_is_sufficient,
            "the fast temporary technology must not shorten the slower target's recovery horizon")
        t.assert_equal(retained_temp, "alternate",
            "the slower target must remain deferred until its own demand can be sustained")
        t.assert_equal(requested, 0,
            "retaining the temporary technology must not request redundant reselection")
    end},
    {"does not apply force-wide demand projection across isolated lab clusters", function()
        local force = reset_runtime()
        game.tick = 32700
        science_names = {"target-pack", "alternate-pack"}
        policy_settings.forecast_seconds = 120
        defines = {inventory = {lab_input = 1}}

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        local cluster_availability = {
            ['target-pack'] = true,
            ['alternate-pack'] = true,
            __cluster_mode = true,
            __clusters = {
                {
                    key = "1:network:1",
                    lab_input_counts = {['target-pack'] = 1},
                    lab_input_sets = {{['target-pack'] = true}},
                    available_sciences = {['target-pack'] = true},
                    counts = {['target-pack'] = 5}
                },
                {
                    key = "2:network:2",
                    lab_input_counts = {['target-pack'] = 1},
                    lab_input_sets = {{['target-pack'] = true}},
                    available_sciences = {},
                    counts = {['target-pack'] = 5}
                },
                {
                    key = "3:network:3",
                    lab_input_counts = {['alternate-pack'] = 1},
                    lab_input_sets = {{['alternate-pack'] = true}},
                    available_sciences = {['alternate-pack'] = true},
                    counts = {['target-pack'] = 100000}
                }
            }
        }
        local target_forecast = {
            stock = 100010,
            production_per_minute = 0,
            consumption_per_minute = 0,
            net_per_minute = 0
        }
        queue.get_science_availability = function()
            return cluster_availability
        end
        queue.get_science_forecast = function()
            return {['target-pack'] = target_forecast}
        end
        queue.get_research_speed = function() return 100 end

        local target = xcur("cluster-target", {
            sciences = {"target-pack"},
            research_unit_count = 100000,
            research_unit_ingredients = {{name = "target-pack", amount = 1}}
        })
        target.technology.research_unit_energy = 60
        local alternate = xcur("alternate", {sciences = {"alternate-pack"}})
        alternate.technology.research_unit_energy = 60
        tech_state = {["cluster-target"] = target, alternate = alternate}
        force.current_research = alternate.technology

        local sufficient = queue.science_is_sufficient(target, 1)
        cluster_availability.__clusters[1].key = "1:lab:1"
        cluster_availability.__clusters[2].key = "1:lab:2"
        target_forecast.production_per_minute = 100000
        local direct_surface_sufficient = queue.science_is_sufficient(target, 1)
        game.tick = game.tick + 600
        cluster_availability.__clusters[1].counts['target-pack'] = 500
        cluster_availability.__clusters[2].counts['target-pack'] = 500
        target_forecast.stock = 101000
        local burst_supply_sufficient = queue.science_is_sufficient(target, 1)
        local burst_evidence = queue.get_research_recovery_evidence(1, "cluster-target")
        game.tick = game.tick + 600
        cluster_availability.__clusters[1].counts['target-pack'] = 50005
        cluster_availability.__clusters[2].counts['target-pack'] = 50005
        target_forecast.stock = 200010
        local arrived_supply_sufficient = queue.science_is_sufficient(target, 1)
        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_true(sufficient,
            "force-wide flow cannot reject a candidate when multiple isolated clusters consume its pack")
        t.assert_false(direct_surface_sufficient,
            "remote force production must not satisfy direct-fed recovery until reachable stock grows")
        t.assert_false(burst_supply_sufficient,
            "one partial delivery must not be extrapolated as sustained target supply; demand=" ..
                tostring(burst_evidence.physical_demand_per_minute["target-pack"]) ..
                ", horizon=" .. tostring(burst_evidence.horizon_seconds))
        t.assert_true(arrived_supply_sufficient,
            "enough stock already reachable by the labs must permit target recovery")
    end},
    {"restores a supplied target when the temporary research becomes pack-bound", function()
        local force = reset_runtime()
        science_names = {"available-pack"}
        game.tick = 2000

        local old_availability = queue.get_science_availability
        local old_sufficient = queue.science_is_sufficient
        queue.get_science_availability = function()
            return {['available-pack'] = true}
        end
        queue.science_is_sufficient = function(xcur)
            return xcur and xcur.technology and xcur.technology.name == "target"
        end

        local target = xcur("target", {sciences = {"available-pack"}})
        local temporary = xcur("temporary", {sciences = {"starved-pack"}})
        target.queued = true
        temporary.queued = true
        tech_state = {target = target, temporary = temporary}
        storage.forces[1].queue.queue = {"target", "temporary"}
        storage.forces[1].queue.target_tech = "target"
        storage.forces[1].queue.temp_tech = "temporary"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        storage.forces[1].queue.last_switch_tick = game.tick - 2000
        force.current_research = {name = "temporary"}

        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, nil,
            "a pack-bound temporary research must stop holding the supplied target")
        t.assert_equal(storage.forces[1].queue.temp_tech_timeout, nil,
            "restoring the target must clear the temporary timeout")
        t.assert_equal(requests, 1, "restoring the target must request active research reselection")

        queue.get_science_availability = old_availability
        queue.science_is_sufficient = old_sufficient
    end},
    {"replaces pack-bound Research productivity 62 with a supplied third technology", function()
        local force = reset_runtime()
        game.tick = 4000
        science_names = {"target-starved-pack", "agricultural-science-pack", "available-pack"}
        defines = {
            entity_status = {missing_science_packs = "missing-science-packs"},
            inventory = {lab_input = 1},
            flow_precision_index = {one_minute = 1}
        }

        local old_availability = queue.get_science_availability
        queue.get_science_availability = function()
            return {
                ["target-starved-pack"] = false,
                ["agricultural-science-pack"] = true,
                ["available-pack"] = true
            }
        end

        local original_target = xcur("original-target", {sciences = {"target-starved-pack"}})
        local research_productivity = xcur("research-productivity", {
            level = 62,
            sciences = {"agricultural-science-pack"},
            research_unit_ingredients = {{name = "agricultural-science-pack", amount = 1}}
        })
        research_productivity.technology.research_unit_energy = 100
        local supplied_alternate = xcur("supplied-alternate", {sciences = {"available-pack"}})
        original_target.queued = true
        research_productivity.queued = true
        supplied_alternate.queued = true
        tech_state = {
            ["original-target"] = original_target,
            ["research-productivity"] = research_productivity,
            ["supplied-alternate"] = supplied_alternate
        }
        storage.forces[1].queue.queue = {
            "original-target", "research-productivity", "supplied-alternate"
        }
        storage.forces[1].queue.target_tech = "original-target"
        storage.forces[1].queue.temp_tech = "research-productivity"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        storage.forces[1].queue.last_switch_tick = game.tick - 2000
        force.current_research = research_productivity.technology

        local lab_entity = {
            valid = true,
            unit_number = 62,
            speed_bonus = 0,
            productivity_bonus = 0,
            prototype = {
                name = "research-productivity-lab",
                lab_inputs = {
                    "target-starved-pack", "agricultural-science-pack", "available-pack"
                },
                get_researching_speed = function() return 1 end
            }
        }
        runtime_lab_content[lab_entity.unit_number] = {
            lab = lab_entity,
            latest_tick = game.tick,
            latest_status = defines.entity_status.missing_science_packs,
            latest_contents = {{name = "available-pack", count = 1}}
        }

        t.assert_equal(
            queue.get_active_missing_science_bottleneck(1, research_productivity)["agricultural-science-pack"],
            true,
            "the active level-62 research fixture must be materially pack-bound"
        )
        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.target_tech, "original-target",
            "replacing a starved temporary technology must preserve its original target")
        t.assert_equal(storage.forces[1].queue.temp_tech, "supplied-alternate",
            "a starved temporary technology must yield to a supplied third candidate")
        t.assert_equal(requests, 1, "the replacement must request active research reselection")

        queue.get_science_availability = old_availability
    end},
    {"does not protect near-finished research from a higher-priority switch", function()
        local force = reset_runtime()
        science_names = {"available-pack"}
        science_priorities.current = 0
        science_priorities.alternate = 1
        force.research_progress = 0.99

        local old_availability = queue.get_science_availability
        local old_sufficient = queue.science_is_sufficient
        queue.get_science_availability = function()
            return {['available-pack'] = true}
        end
        queue.science_is_sufficient = function() return true end

        local current = xcur("current", {sciences = {"available-pack"}})
        local alternate = xcur("alternate", {sciences = {"available-pack"}})
        current.queued = true
        alternate.queued = true
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"current", "alternate"}
        force.current_research = {name = "current"}

        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, "alternate",
            "near-finished research must still yield to a higher-priority alternate")
        t.assert_equal(requests, 1, "a higher-priority switch must request active research reselection")

        queue.get_science_availability = old_availability
        queue.science_is_sufficient = old_sufficient
    end},
    {"adds, removes, reorders, and clears queue entries", function()
        local force = reset_runtime()
        queue.add(force, "d", 2, false)
        t.assert_equal(queue.get_queue(1)[2], "d")
        t.assert_true(queued_updates.d)
        queue.add(force, "d", nil, false)
        t.assert_equal(#queue.get_queue(1), 4)
        queue.remove(force, "d", false)
        t.assert_equal(#queue.get_queue(1), 3)
        queue.promote(force, "c", 2)
        t.assert_equal(queue.get_queue(1)[1], "c")
        queue.demote(force, "c", 2)
        t.assert_equal(queue.get_queue(1)[3], "c")
        queue.clear(force)
        t.assert_equal(#queue.get_queue(1), 0)
        t.assert_equal(force.research_queue[1], nil)
    end},
    {"handles enabled states, user boosts, custom order, and initialization", function()
        local force = reset_runtime()
        queue.set_tech_enabled(1, "a", false)
        t.assert_false(queue.get_tech_enabled(1, "a"))
        t.assert_true(queue.get_tech_enabled(1, "missing"))
        queue.adjust_tech_ub(1, "a", 4)
        queue.adjust_tech_ub(1, "a", -1)
        t.assert_equal(queue.get_tech_ub(1, "a"), 3)
        tech_state = {
            a = xcur("a"),
            b = xcur("b"),
            hidden = xcur("hidden", {hidden = true}),
            researched = xcur("researched", {researched = true})
        }
        local order = queue.build_tech_order(1)
        t.assert_equal(#order, 2)
        queue.move_tech_down(1, order[1])
        queue.move_tech_up(1, order[1])
        t.assert_equal(queue.get_tech_order(1), order)
        storage.forces[1].queue = nil
        queue.init_force(1)
        t.assert_true(type(storage.forces[1].queue.queue) == "table")
        t.assert_true(type(storage.forces[1].queue.tech_enabled) == "table")
        storage.forces[1].queue.current_tech = "a"
        storage.forces[1].queue.current_tech_smart = "b"
        storage.forces[1].queue.misses_science = {a = true}
        t.assert_equal(queue.get_current_researching(1), "a")
        t.assert_equal(queue.get_current_smart_researching(1), "b")
        t.assert_true(queue.get_tech_missing_science(1).a)
    end},
    {"records speed samples and summarizes active research", function()
        local force = reset_runtime()
        force.current_research = make_tech("a", {research_unit_count = 100})
        force.research_progress = 0.1
        game.tick = 10
        queue.record_research_progress(1)
        force.research_progress = 0.2
        game.tick = 70
        queue.record_research_progress(1)
        local speed, valid = queue.get_research_speed(1)
        t.assert_true(valid)
        t.assert_equal(speed, 10)
        local history, history_valid = queue.get_research_history(1, 3)
        t.assert_true(history_valid)
        t.assert_equal(history[3], 600)
        local summary = queue.get_research_summary(1)
        t.assert_equal(summary.done, 20)
        t.assert_equal(summary.total, 100)
        t.assert_equal(summary.remaining_seconds, 8)
        force.current_research = nil
        t.assert_false(queue.get_research_summary(1).is_researching)
    end},
    {"saves, lists, loads, deletes, exports, and imports plans", function()
        reset_runtime()
        local missing_ok, missing_reason = queue.load_preset(1, "missing")
        t.assert_false(missing_ok)
        t.assert_equal(missing_reason, "missing-preset")
        t.assert_false(queue.save_preset(99))
        t.assert_nil(queue.export_plan(99))
        queue.set_tech_enabled(1, "a", false)
        queue.adjust_tech_ub(1, "b", 7)
        t.assert_true(queue.save_preset(1, "baseline"))
        t.assert_equal(queue.get_preset_names(1)[1], "baseline")
        storage.forces[1].queue.queue = {"d"}
        t.assert_true(queue.load_preset(1, "baseline"))
        t.assert_equal(queue.get_queue(1)[1], "a")
        t.assert_false(queue.get_tech_enabled(1, "a"))
        t.assert_equal(queue.get_tech_ub(1, "b"), 7)
        helpers = {
            table_to_json = function() return "json" end,
            encode_string = function(value) return value .. "-encoded" end,
            decode_string = function(value) return value:gsub("-encoded$", "") end,
            json_to_table = function()
                return {
                    version = 1,
                    queue = {"b"},
                    tech_enabled = {},
                    tech_ub = {},
                    policy = {}
                }
            end
        }
        t.assert_equal(queue.export_plan(1), "LE1:json-encoded")
        local _, reason = queue.import_plan(1, "bad")
        t.assert_equal(reason, "invalid-prefix")
        helpers.decode_string = function() error("decode failed") end
        local _, encoding_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(encoding_reason, "invalid-encoding")
        helpers.decode_string = function() return "json" end
        helpers.json_to_table = function() error("json failed") end
        local _, json_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(json_reason, "invalid-json")
        helpers.json_to_table = function() return {version = 2, queue = {}} end
        local _, plan_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(plan_reason, "invalid-plan")
        helpers.json_to_table = function() return {
            version = 1, queue = {[0] = "a"}, tech_enabled = {}, tech_ub = {}, policy = {}
        } end
        local _, queue_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(queue_reason, "invalid-queue")
        helpers.json_to_table = function() return {
            version = 1, queue = {[1] = "a", [3] = "b"}, tech_enabled = {}, tech_ub = {}, policy = {}
        } end
        local _, sparse_queue_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(sparse_queue_reason, "invalid-queue")
        helpers.json_to_table = function() return {
            version = 1, queue = {}, tech_enabled = {[1] = true}, tech_ub = {}, policy = {}
        } end
        local _, enabled_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(enabled_reason, "invalid-tech-enabled")
        helpers.json_to_table = function() return {
            version = 1, queue = {}, tech_enabled = {}, tech_ub = {a = math.huge}, policy = {}
        } end
        local _, priority_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(priority_reason, "invalid-tech-priority")
        local _, force_reason = queue.import_plan(99, "LE1:encoded")
        t.assert_equal(force_reason, "invalid-force")
        helpers.json_to_table = function()
            return {version = 1, queue = {"b"}, tech_enabled = {}, tech_ub = {}, policy = {}}
        end
        t.assert_true(queue.import_plan(1, "LE1:json-encoded"))
        t.assert_equal(queue.get_queue(1)[1], "b")
        queue.delete_preset(1, "baseline")
        t.assert_equal(#queue.get_preset_names(1), 0)
        helpers = nil
    end},
    {"orders manual trigger objectives by readiness and name", function()
        reset_runtime()
        tech_state = {
            zed = xcur("zed", {has_trigger = true, available = false}),
            ready = xcur("ready", {has_trigger = true, available = true}),
            ready_two = xcur("ready_two", {has_trigger = true, available = true}),
            ordinary = xcur("ordinary")
        }
        tech_state.zed.meta.prototype.research_trigger = {type = "craft-item"}
        tech_state.ready.meta.prototype.research_trigger = {type = "research-item"}
        tech_state.zed.blocked_by = {prerequisite = true}
        local objectives = queue.get_trigger_objectives(1)
        t.assert_equal(#objectives, 3)
        t.assert_equal(objectives[1].tech_name, "ready")
        t.assert_true(objectives[1].ready)
        t.assert_equal(objectives[1].trigger_type, "research-item")
        t.assert_true(objectives[2].ready)
        t.assert_false(objectives[3].ready)
    end},
    {"handles research history migration and invalid samples", function()
        local force = reset_runtime()
        local sfq = storage.forces[1].queue
        sfq.speed_samples = {
            {tick = 1, speed = 2, valid_speed = true},
            {tick = 2, speed = 0, valid_speed = false},
            {tick = 3, speed = 4}
        }
        local speed, valid = queue.get_research_speed(1)
        t.assert_true(valid)
        t.assert_equal(speed, 3)
        local history, history_valid = queue.get_research_history(1, 3)
        t.assert_true(history_valid)
        t.assert_equal(history[3], 180)

        sfq.research_spm_history = {
            size = 32,
            values = {[1] = 12},
            head = 0,
            count = -4
        }
        local migrated = queue.get_research_history(1, 2)
        t.assert_true(type(migrated) == "table")
        t.assert_equal(migrated[2], 180)
        sfq.research_spm_history = {size = 32, values = {}, head = 99, count = 99}
        local normalized = queue.get_research_history(1, 1)
        t.assert_true(type(normalized) == "table")

        local no_speed, no_valid = queue.get_research_speed(99)
        t.assert_nil(no_speed)
        t.assert_false(no_valid)
        queue.record_research_progress(99)
        queue.get_research_summary(99)
        force.current_research = nil
        queue.record_research_progress(1)
        t.assert_equal(#sfq.speed_samples, 4)
    end},
    {"guards queue operations and runtime synchronization edge cases", function()
        local force = reset_runtime()
        _G.serpent = {line = function(value) return tostring(value) end}
        queue.add(force, nil)
        queue.add(force, "missing")
        force.technologies.b.valid = false
        queue.add(force, "b")
        force.technologies.b.valid = true
        force.technologies.b.enabled = false
        queue.add(force, "b")
        force.technologies.b.enabled = true
        queue.add(force, "a")
        queue.add(force, "a")
        queue.remove(force, "missing")
        queue.promote(force, "missing")
        queue.promote(force, "a")
        queue.promote(force, "a", 2)
        queue.demote(force, "missing")
        queue.demote(force, "c")
        queue.demote(force, "a", 20)

        force.research_queue = {}
        queue.sync_ingame_queue(force)
        force.research_queue = {{name = "b"}}
        queue.sync_ingame_queue(force)
        storage.forces[1].queue.queue = {}
        force.research_queue = {{name = "a"}, {name = "b"}}
        queue.sync_ingame_queue(force)
        queue.clean_ingame_queue_timeout(force)
        force.research_queue = {}
        queue.clean_ingame_queue_timeout(force)

        local old_remove = queue.remove
        local old_add = queue.add
        queue.remove = function() end
        queue.add = function() end
        storage.forces[1].queue.queue = {}
        force.research_queue = {{name = "a"}}
        queue.sync_ingame_queue(force)
        queue.remove = old_remove
        queue.add = old_add

        queue.requeue_finished(force, {name = "unknown"})
        queue.apply_planning_pause(nil)
        force.current_research = make_tech("a")
        queue.apply_planning_pause(force)
        force.current_research = nil
        storage.forces[1].queue = nil
        queue.clear(force)
        queue.clean_ingame_queue_timeout(force)
        queue.sync_ingame_queue(force)

        queue.start_next_research(nil)
        policy_settings.strategy = "focused"
        storage.forces[1].queue = {queue = {}}
        queue.start_next_research(force)
        t.assert_equal(#force.research_queue, 0)
        policy_settings.strategy = nil
        force_settings.auto_research = false
        queue.start_next_research(force)
        t.assert_equal(#force.research_queue, 0)
        force_settings.auto_research = true
        storage.forces[1].queue = {queue = {}}
        local old_build = queue.build_queue_from_available
        queue.build_queue_from_available = function() storage.forces[1].queue.queue = {} end
        queue.start_next_research(force)
        queue.build_queue_from_available = old_build
    end},
    {"detects stuck research and honors start guards", function()
        local force = reset_runtime()
        tech_state = {a = xcur("a", {sciences = {"automation-science-pack"}})}
        storage.forces[1].queue.queue = {"a"}
        storage.forces[1].queue.current_tech = "a"
        queue.get_science_availability = function() return {['automation-science-pack'] = false} end
        storage.forces[1].queue.current_tech = nil
        t.assert_true(queue.research_is_stuck(force))
        storage.forces[1].queue.queue = {}
        storage.forces[1].queue.current_tech = nil
        storage.forces[1].queue.current_tech_smart = "missing"
        t.assert_false(queue.research_is_stuck(force))
        storage.forces[1].queue.queue = {"a"}
        storage.forces[1].queue.current_tech_smart = nil
        t.assert_true(queue.research_is_stuck(force))
        t.assert_true(queue.research_is_stuck(force))
        queue.get_science_availability = function() return {['automation-science-pack'] = true} end
        storage.forces[1].queue.current_tech = "a"
        t.assert_false(queue.research_is_stuck(force))
        force_settings.auto_research = false
        storage.forces[1].queue.queue = {}
        storage.forces[1].queue.current_tech = nil
        queue.start_next_research(force)
        force_settings.auto_research = true

        force_settings.master_enable = "left"
        queue.start_next_research(force)
        queue.check_and_switch_temp_research(nil)
        force_settings.master_enable = nil
        policy_settings.planning_paused = true
        queue.start_next_research(force)
        queue.check_and_switch_temp_research(force)
        policy_settings.planning_paused = false
        policy_settings.parallel_research = true
        queue.check_and_switch_temp_research(force)
        queue.rotate_parallel_research(force)
    end},
    {"selects temporary and restored targets across stale switch states", function()
        local force = reset_runtime()
        local old_sufficient = queue.science_is_sufficient
        local old_availability = queue.get_science_availability
        local old_score = queue.score_tech_detailed
        queue.science_is_sufficient = function() return true end
        queue.get_science_availability = function() return {} end

        local current = xcur("current")
        local target = xcur("target")
        local temporary = xcur("temporary")
        current.queued = true
        target.queued = true
        temporary.queued = true
        tech_state = {current = current, target = target, temporary = temporary}
        storage.forces[1].queue.queue = {"target", "temporary"}

        storage.forces[1].queue.temp_tech = "temporary"
        queue.reorder_queue_by_score(1)
        t.assert_equal(storage.forces[1].queue.current_tech, "temporary")

        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.target_tech = "target"
        queue.reorder_queue_by_score(1)
        t.assert_equal(storage.forces[1].queue.current_tech, "target")

        policy_settings.parallel_research = false
        force.current_research = make_tech("current")
        storage.forces[1].queue.target_tech = "target"
        storage.forces[1].queue.temp_tech = "temporary"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.score_tech_detailed = function(xcur_value)
            return {total = xcur_value.technology.name == "temporary" and 100 or 1}
        end
        queue.check_and_switch_temp_research(force)
        t.assert_true(storage.forces[1].queue.temp_tech_timeout > game.tick)

        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.score_tech_detailed = function() return {total = 1} end
        queue.check_and_switch_temp_research(force)
        t.assert_nil(storage.forces[1].queue.temp_tech)
        t.assert_equal(storage.forces[1].queue.target_tech, "target")

        storage.forces[1].queue.last_switch_tick = nil
        storage.forces[1].queue.target_tech = "missing"
        storage.forces[1].queue.temp_tech = "temporary"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.check_and_switch_temp_research(force)
        t.assert_nil(storage.forces[1].queue.target_tech)

        storage.forces[1].queue.target_tech = nil
        storage.forces[1].queue.temp_tech = "missing"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.check_and_switch_temp_research(force)
        t.assert_nil(storage.forces[1].queue.temp_tech)

        queue.score_tech_detailed = old_score
        local old_bottleneck = queue.get_active_missing_science_bottleneck
        queue.science_is_sufficient = function() return false end
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.temp_tech_timeout = nil
        storage.forces[1].queue.target_tech = nil
        force.current_research = make_tech("current")
        storage.forces[1].queue.queue = {"target"}
        queue.set_pinned_tech(1, "target")
        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, "target")

        queue.set_pinned_tech(1, nil)
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.target_tech = nil
        storage.forces[1].queue.last_switch_tick = nil
        queue.get_active_missing_science_bottleneck = function() return {pack = true} end
        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, "target")

        queue.get_active_missing_science_bottleneck = old_bottleneck
        queue.score_tech_detailed = old_score
        queue.science_is_sufficient = old_sufficient
        queue.get_science_availability = old_availability
    end},
    {"requeues finished infinite technologies", function()
        local force = reset_runtime()
        local finite = xcur("finite", {level = 1})
        tech_state = {finite = finite}
        force.technologies.finite = finite.technology
        storage.forces[1].queue.temp_tech = "finite"
        storage.forces[1].queue.temp_tech_timeout = game.tick
        queue.requeue_finished(force, {name = "finite"})
        t.assert_nil(storage.forces[1].queue.temp_tech)
        local infinite = xcur("infinite", {is_infinite = true, level = 2})
        infinite.meta.is_infinite = true
        infinite.technology.level = 2
        tech_state = {infinite = infinite}
        force.technologies.infinite = infinite.technology
        storage.forces[1].queue.queue = {"infinite"}
        storage.forces[1].queue.pinned_tech = "infinite"
        local policy_module = require("model.research_policy")
        local old_should_requeue = policy_module.should_requeue
        policy_module.should_requeue = function() return true end
        queue.requeue_finished(force, {name = "infinite"})
        t.assert_nil(queue.get_pinned_tech(1))
        t.assert_equal(queue.get_queue(1)[1], "infinite")
        policy_module.should_requeue = old_should_requeue
    end},
    {"covers warning alerts, inferred score weights, and candidate guards", function()
        local force = reset_runtime()
        local alerts = 0
        local lab_entity = {valid = true}
        storage.settings = {showWarnings = true, notifySwitches = true, warnEveryNTicks = 1}
        storage.forces[1].lab = {all_labs = {1}, lab_content = {[1] = {lab = lab_entity}}}
        force.connected_players = {{valid = true, add_custom_alert = function() alerts = alerts + 1 end}}
        game.surfaces = {}

        tech_state = {
            a = xcur("a", {sciences = {}, research_unit_count = 100}),
            b = xcur("b", {sciences = {}, research_unit_count = 1})
        }
        force.current_research = force.technologies.a
        storage.forces[1].queue.queue = {"b"}
        queue.check_and_switch_temp_research(force)
        t.assert_true(alerts > 0)

        local old_availability = queue.get_science_availability
        prototypes.item["spoilable-pack"] = {get_spoil_ticks = function() return 60 end}
        queue.get_science_availability = function() return {['spoilable-pack'] = true} end
        tech_state = {
            a = xcur("a", {sciences = {}}),
            b = xcur("b", {sciences = {"spoilable-pack"}, is_infinite = true, level = 3,
                research_unit_count = 1})
        }
        storage.forces[1].queue.queue = {"b"}
        storage.forces[1].queue.target_tech = nil
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.temp_tech_timeout = nil
        storage.forces[1].queue.last_switch_tick = nil
        force.current_research = force.technologies.a
        queue.check_and_switch_temp_research(force)
        t.assert_true(alerts > 1)

        queue.get_science_availability = function() return {} end
        local old_bottleneck = queue.get_active_missing_science_bottleneck
        queue.get_active_missing_science_bottleneck = function() return {['missing-pack'] = true} end
        tech_state.a = xcur("a", {sciences = {"missing-pack"}})
        tech_state.b = xcur("b", {sciences = {}})
        storage.forces[1].queue.queue = {"b"}
        storage.forces[1].queue.target_tech = nil
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.temp_tech_timeout = nil
        storage.forces[1].queue.last_switch_tick = nil
        queue.check_and_switch_temp_research(force)
        t.assert_true(alerts > 2)
        queue.get_active_missing_science_bottleneck = old_bottleneck
        queue.get_science_availability = old_availability

        local effects = {
            {key = "unlock-space-location", expected = 5},
            {key = "unlock-recipe", expected = 3},
            {key = "laboratory-speed", expected = 4},
            {key = "mining-drill-productivity-bonus", expected = 6},
            {key = "turret-attack", expected = 2},
            {key = "character-health-bonus", expected = 1}
        }
        for _, item in ipairs(effects) do
            local scored = queue.score_tech_detailed(xcur("effect", {
                research_effects = {[item.key] = true}
            }), 1, 0, 100, 1)
            t.assert_equal(scored.importance, item.expected)
        end
        local rw = require("model.research_weights")
        rw.research_caps.capped = 2
        t.assert_equal(queue.score_tech_detailed(xcur("capped", {level = 2}), 2, 0, 100, 1).total, -1000)
        rw.research_weights.weighted = 7
        t.assert_equal(queue.score_tech_detailed(xcur("weighted"), 1, 0, 100, 1).importance, 7)
        local invalid_formula = queue.score_tech_detailed(xcur("infinite", {
            is_infinite = true, level = 2, formula = "not a formula"
        }), 3, 0, 100, 1)
        t.assert_true(invalid_formula.total ~= nil)
        rw.research_caps.capped = nil
        rw.research_weights.weighted = nil

        tech_state = {blocked = xcur("blocked", {available = false})}
        storage.forces[1].queue.queue = {"blocked"}
        force.current_research = nil
        queue.start_next_research(force)
        t.assert_true(alerts > 1)

        storage.forces[1].lab = nil
        game.surfaces = {{find_entities_filtered = function()
            return {{valid = true}}
        end}}
        storage.forces[1].lab = {all_labs = {}, lab_content = {}}
        queue.start_next_research(force)
        t.assert_true(alerts > 2)
    end},
    {"selects prerequisites, pinned candidates, and builds a scored queue", function()
        local force = reset_runtime()
        tech_state = {
            blocked = xcur("blocked", {available = false}),
            prerequisite = xcur("prerequisite"),
            available = xcur("available")
        }
        tech_state.blocked.meta.all_prerequisites = {prerequisite = true}
        storage.forces[1].queue.queue = {"blocked", "available"}
        queue.set_pinned_tech(1, "blocked")
        queue.reorder_queue_by_score(1)
        t.assert_equal(queue.get_current_researching(1), "prerequisite")
        t.assert_equal(force.research_queue[1], "prerequisite")

        force.research_queue = nil
        setmetatable(force, {
            __newindex = function(element, key, value)
                if key ~= "research_queue" then
                    rawset(element, key, value)
                end
            end
        })
        queue.reorder_queue_by_score(1)
        setmetatable(force, nil)
        force.research_queue = {}

        queue.set_pinned_tech(1, nil)
        queue.build_queue_from_available(1)
        t.assert_equal(#queue.get_queue(1), 3)
        t.assert_true(queued_updates.blocked)
        t.assert_true(queued_updates.available)
    end},
    {"covers runtime candidate fallbacks, warning paths, and queue guards", function()
        local force = reset_runtime()

        -- The storage setters/getters and event guards must tolerate a force that
        -- was removed while a queued callback is still pending.
        queue.set_pinned_tech(99, "missing-force")
        storage.forces[1] = nil
        queue.set_pinned_tech(1, "missing-force")
        t.assert_nil(queue.get_pinned_tech(1))
        t.assert_false(queue.is_internal_research_queue_update(force))
        t.assert_false(queue.consume_internal_research_cancel(force, "a"))
        storage.forces[1] = {queue = {queue = {"a"}}}

        -- Exercise both the no-lab warning lookup and the surface fallback.
        storage.settings = {showWarnings = true, warnEveryNTicks = 1}
        force.connected_players = {{valid = true, add_custom_alert = function() end}}
        force_settings.auto_research = false
        tech_state = {blocked = xcur("blocked", {available = false})}
        storage.forces[1].queue.queue = {"blocked"}
        game.surfaces = {}
        queue.start_next_research(force)
        game.tick = game.tick + 2
        game.surfaces = {{find_entities_filtered = function()
            return {{valid = true}}
        end}}
        queue.start_next_research(force)

        -- A spoilable candidate uses the switch notification branch.
        local old_availability = queue.get_science_availability
        storage.settings.notifySwitches = true
        prototypes.item.spoilable = {get_spoil_ticks = function() return 60 end}
        force_settings.auto_research = true
        tech_state = {
            current = xcur("current", {research_unit_count = 100}),
            candidate = xcur("candidate", {sciences = {"spoilable"}, research_unit_count = 1})
        }
        tech_state.candidate.meta.has_spoilable_science = true
        queue.get_science_availability = function() return {spoilable = true} end
        storage.forces[1].queue.queue = {"candidate"}
        force.current_research = make_tech("current")
        queue.check_and_switch_temp_research(force)
        queue.get_science_availability = old_availability

        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        policy_settings.forecast_seconds = 200
        queue.get_research_speed = function() return 1, true end
        queue.get_science_forecast = function()
            return {pack = {depletion_seconds = 1}}
        end
        queue.get_science_availability = function() return {pack = true} end
        local forecast_candidate = xcur("forecast", {sciences = {"pack"}, research_unit_count = 100})
        force.current_research = make_tech("other")
        t.assert_false(queue.science_is_sufficient(forecast_candidate, 1))
        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed
        policy_settings.forecast_seconds = nil

        -- Exercise the expired temporary-tech decisions: pinned target,
        -- pinned temporary, insufficient temporary packs, priority changes,
        -- and equal-priority score comparison.
        local old_sufficient = queue.science_is_sufficient
        local old_score = queue.score_tech_detailed
        queue.science_is_sufficient = function() return true end
        tech_state = {
            current = xcur("current"),
            target = xcur("target"),
            temporary = xcur("temporary")
        }
        tech_state.target.queued = true
        tech_state.temporary.queued = true
        storage.forces[1].queue.queue = {"target", "temporary"}
        force.current_research = make_tech("current")
        storage.forces[1].queue.target_tech = "target"
        storage.forces[1].queue.temp_tech = "temporary"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.set_pinned_tech(1, "temporary")
        queue.check_and_switch_temp_research(force)
        queue.set_pinned_tech(1, "target")
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.check_and_switch_temp_research(force)
        queue.set_pinned_tech(1, nil)
        queue.science_is_sufficient = function(_, index)
            return index == 1
        end
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.check_and_switch_temp_research(force)
        queue.science_is_sufficient = old_sufficient
        science_priorities.temporary = 2
        science_priorities.target = 0
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.check_and_switch_temp_research(force)
        science_priorities.temporary = nil
        science_priorities.target = nil
        queue.score_tech_detailed = function(value)
            return {total = value.technology.name == "temporary" and 10 or 1}
        end
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.check_and_switch_temp_research(force)
        queue.score_tech_detailed = old_score

        -- Normal checks cover cooldown, finished-current cleanup, stale target
        -- cleanup, and the active missing-science availability projection.
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.temp_tech_timeout = nil
        storage.forces[1].queue.target_tech = "target"
        storage.forces[1].queue.last_switch_tick = game.tick
        queue.check_and_switch_temp_research(force)
        storage.forces[1].queue.last_switch_tick = nil
        force.research_progress = 1
        queue.science_is_sufficient = function() return true end
        queue.check_and_switch_temp_research(force)
        force.research_progress = 0
        force.current_research = make_tech("target")
        queue.check_and_switch_temp_research(force)
        storage.forces[1].queue.target_tech = "unexpected"
        storage.forces[1].queue.temp_tech = "temporary"
        queue.check_and_switch_temp_research(force)
        force.current_research = make_tech("current")
        queue.science_is_sufficient = function() return false end
        local old_bottleneck_block = queue.get_active_missing_science_bottleneck
        queue.get_active_missing_science_bottleneck = function() return {pack = true} end
        queue.get_science_availability = function() return {pack = true} end
        storage.forces[1].queue.target_tech = nil
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.temp_tech_timeout = nil
        storage.forces[1].queue.last_switch_tick = nil
        queue.set_pinned_tech(1, nil)
        queue.check_and_switch_temp_research(force)
        queue.science_is_sufficient = old_sufficient
        queue.get_active_missing_science_bottleneck = old_bottleneck_block
        queue.get_science_availability = old_availability

        -- Explicitly exercise the unstarted and unknown-current stuck states.
        storage.forces[1].queue.queue = {}
        storage.forces[1].queue.current_tech = nil
        storage.forces[1].queue.current_tech_smart = nil
        force.current_research = nil
        t.assert_false(queue.research_is_stuck(force))
        force.current_research = make_tech("unknown")
        t.assert_false(queue.research_is_stuck(force))

        -- An available candidate with missing packs is recorded, while an
        -- unavailable candidate can fall back to a prerequisite that also lacks
        -- packs.
        local old_science_available = queue.get_science_availability
        queue.get_science_availability = function() return {} end
        tech_state = {
            missing = xcur("missing", {sciences = {"pack"}}),
            target = xcur("target", {available = false}),
            prerequisite = xcur("prerequisite", {sciences = {"pack"}})
        }
        tech_state.target.meta.all_prerequisites = {prerequisite = true}
        storage.forces[1].queue.queue = {"missing"}
        queue.reorder_queue_by_score(1)
        t.assert_true(queue.get_tech_missing_science(1).missing)
        storage.forces[1].queue.queue = {"target"}
        queue.set_pinned_tech(1, "target")
        queue.reorder_queue_by_score(1)
        t.assert_equal(queue.get_current_researching(1), "prerequisite")
        t.assert_true(queue.get_tech_missing_science(1).target)

        -- Candidate filters cover researched, disabled, hidden, triggered,
        -- user-disabled, science-prioritized-out, and capped technologies.
        local rw = require("model.research_weights")
        rw.research_caps.capped = 1
        queue.set_tech_enabled(1, "user-disabled", false)
        policy_settings.science_priority = -1000
        tech_state = {
            researched = xcur("researched", {researched = true}),
            disabled = xcur("disabled", {enabled = false}),
            hidden = xcur("hidden", {hidden = true}),
            triggered = xcur("triggered", {has_trigger = true}),
            user_disabled = xcur("user-disabled"),
            priority_blocked = xcur("priority-blocked"),
            capped = xcur("capped", {level = 1})
        }
        storage.forces[1].queue.queue = {
            "unknown", "researched", "disabled", "hidden", "triggered",
            "user-disabled", "priority_blocked", "capped"
        }
        queue.get_upcoming_research(1, 1)
        rw.research_caps.capped = nil
        policy_settings.science_priority = nil
        queue.get_science_availability = old_science_available

        queue.get_science_availability = function() return {pack = true} end
        tech_state = {ready = xcur("ready", {sciences = {"pack"}})}
        storage.forces[1].queue.queue = {"ready"}
        local ready_entries = queue.get_upcoming_research(1, 1)
        t.assert_equal(ready_entries[1].tech_name, "ready")

        tech_state = {
            goal = xcur("goal"),
            middle = xcur("middle"),
            unmet = xcur("unmet", {available = false})
        }
        tech_state.goal.meta.all_prerequisites = {middle = true}
        tech_state.middle.meta.all_prerequisites = {unmet = true}
        storage.forces[1].queue.queue = {"unknown", "goal"}
        queue.get_upcoming_research(1, 2)
        queue.get_science_availability = old_science_available

        policy_settings.parallel_research = true
        force_settings.auto_research = false
        storage.forces[1].queue = {queue = {}}
        queue.rotate_parallel_research(force)
        tech_state = {a = xcur("a"), b = xcur("b")}
        force_settings.auto_research = true
        storage.forces[1] = {}
        queue.rotate_parallel_research(force)
        storage.forces[1] = {queue = {queue = {}}}
        policy_settings.parallel_research = false

        -- Empty queue policy branches and a missing technology-state snapshot.
        storage.forces[1].queue.queue = {}
        policy_settings.strategy = "focused"
        t.assert_equal(#queue.get_upcoming_research(1, 1), 0)
        policy_settings.strategy = nil
        force_settings.auto_research = false
        t.assert_equal(#queue.get_upcoming_research(1, 1), 0)
        force_settings.auto_research = true
        tech_state = nil
        t.assert_equal(#queue.get_upcoming_research(1, 1), 0)
        policy_settings.parallel_research = true
        queue.rotate_parallel_research(force)
        policy_settings.parallel_research = false
        tech_state = {}

        -- The one-item sync path is a no-op when Factorio already accepted the
        -- same next technology, and the internal marker records live research.
        force.current_research = nil
        tech_state = {a = xcur("a")}
        storage.forces[1].queue.queue = {"a"}
        force.research_queue = {{name = "a"}}
        queue.sync_ingame_queue(force)
        force.current_research = make_tech("a")
        queue.reorder_queue_by_score(1)

        -- History APIs normalize empty, mismatched, and oversized samples.
        storage.forces[1].queue.speed_samples = {}
        t.assert_nil(queue.get_research_speed(1))
        queue.get_research_diagnostic(1)
        storage.forces[1].queue.speed_samples = {{tick = 1, speed = 1, valid_speed = true, tech_name = "other"}}
        queue.get_research_diagnostic(1)
        t.assert_equal(queue.get_research_history(99, 2)[1], 0)
        local many_samples = {}
        for i = 1, 25 do
            many_samples[i] = {tick = i, progress = 0, speed = 1, valid_speed = true, tech_name = "a"}
        end
        storage.forces[1].queue.speed_samples = many_samples
        queue.get_research_history(1, 2)
        for i = 26, 205 do
            storage.forces[1].queue.speed_samples[i] = {
                tick = i, progress = 0, speed = 1, valid_speed = true, tech_name = "a"
            }
        end
        game.tick = 205
        queue.record_research_progress(1)

        -- Private helpers still get contract tests for defensive branches that
        -- public queue operations intentionally guard before reaching.
        local candidate_guard = find_private(queue.reorder_queue_by_score, "tech_can_be_runtime_candidate")
        local horizon = find_private(queue.science_is_sufficient, "get_depletion_horizon_seconds")
        local attributable = find_private(queue.science_is_sufficient, "science_depletion_is_attributable")
        local move = find_private(queue.promote, "move_research")
        local position = find_private(queue.promote, "get_queue_position")
        local average = find_private(queue.get_research_speed, "get_average_research_speed")
        local window = find_private(queue.get_research_diagnostic, "get_research_speed_window")
        local ensure_history = find_private(queue.get_research_history, "ensure_research_spm_history")
        local write_history = find_private(queue.record_research_progress, "write_research_spm_history")
        local any_lab = find_private(queue.start_next_research, "get_any_lab")
        local block_details = find_private(queue.get_upcoming_research, "get_science_block_details")
        local temp_persist = find_private(queue.check_and_switch_temp_research, "temp_should_persist")
        local mark_internal = find_private(queue.reorder_queue_by_score, "mark_internal_research_queue_update")
        local get_network = find_private(queue.get_science_counts, "get_lab_network")
        local get_input_set = find_private(queue.get_science_counts, "get_lab_input_set")
        local observation_contents = find_private(queue.get_research_diagnostic, "get_observation_contents")
        local missing_lab_sciences = find_private(queue.get_research_diagnostic, "get_missing_lab_sciences")
        local find_runtime = find_private(queue.reorder_queue_by_score, "find_runtime_candidate")
        local build_runtime_names = find_private(queue.reorder_queue_by_score, "build_runtime_queue_names")
        local display_candidate = find_private(queue.tick_upcoming_research_display,
            "get_upcoming_display_candidate")
        t.assert_true(type(candidate_guard) == "function")
        t.assert_true(type(horizon) == "function")
        t.assert_true(type(attributable) == "function")
        t.assert_true(type(find_runtime) == "function")
        t.assert_true(type(build_runtime_names) == "function")
        t.assert_true(type(display_candidate) == "function")
        t.assert_false(candidate_guard(1, nil))
        t.assert_false(candidate_guard(1, xcur("disabled", {enabled = false})))
        queue.set_tech_enabled(1, "user-guard", false)
        t.assert_false(candidate_guard(1, xcur("user-guard")))
        policy_settings.science_priority = -1000
        t.assert_false(candidate_guard(1, xcur("priority-guard")))
        policy_settings.science_priority = nil
        local rw = require("model.research_weights")
        rw.research_caps.guard = 1
        t.assert_false(candidate_guard(1, xcur("guard", {level = 1})))
        rw.research_caps.guard = nil

        force.current_research = make_tech("other")
        force.research_progress = 0.5
        queue.get_research_speed = function() return 1, true end
        local horizon_value = horizon(xcur("horizon", {research_unit_count = 100}), 1, 200)
        t.assert_equal(horizon_value, 100)
        force.current_research = make_tech("horizon")
        force.research_progress = 0.5
        t.assert_equal(horizon(xcur("horizon", {research_unit_count = 100}), 1, 200), 50)
        t.assert_true(attributable({__cluster_mode = false}, "pack"))
        local no_candidate = {find_runtime(1, "missing", {}, {}, {})}
        t.assert_nil(no_candidate[1])

        t.assert_equal(block_details(xcur("no-pack", {sciences = {"pack"}}), {}), "missing_science")
        t.assert_equal(block_details(nil, {}), "missing_science")
        t.assert_nil(display_candidate({force_index = 1, tech_states = {}, virtually_researched = {}}, "missing"))

        -- The public source builder filters invalid entries before the preview
        -- candidate guard. Replace that source narrowly to exercise the guard's
        -- defensive contract without weakening the normal queue invariant.
        tech_state = {a = xcur("a")}
        storage.forces[1].queue = {queue = {}}
        force.current_research = nil
        local restore_virtual_source = swap_private(queue.get_upcoming_research, "get_virtual_queue_source",
            function() return {"missing"} end)
        t.assert_true(type(restore_virtual_source) == "function")
        t.assert_equal(#queue.get_upcoming_research(1, 1), 0)
        restore_virtual_source()

        -- An invalid active name falls back to the first candidate in the runtime
        -- queue builder, including its insertion and de-duplication paths.
        storage.forces[1].queue = {queue = {"a"}}
        local runtime_names, runtime_active = build_runtime_names(1, "missing")
        t.assert_equal(runtime_names[1], "a")
        t.assert_equal(runtime_active, "a")

        -- Reorder bookkeeping also handles a candidate appearing after the
        -- active-research lookup returns no technology.
        local restore_first_next = swap_private(queue.reorder_queue_by_score, "get_first_next_tech",
            function() return nil end)
        local restore_runtime_names = swap_private(queue.reorder_queue_by_score, "build_runtime_queue_names",
            function() return {"a"}, "a" end)
        t.assert_true(type(restore_first_next) == "function")
        t.assert_true(type(restore_runtime_names) == "function")
        storage.forces[1].queue = {queue = {}}
        queue.reorder_queue_by_score(1)
        t.assert_equal(storage.forces[1].queue.current_tech, "a")
        restore_runtime_names()
        restore_first_next()

        -- Count and history APIs retain safe empty fallbacks when their internal
        -- providers return an invalid shape.
        queue.invalidate_science_cache(1)
        local restore_counts = swap_private(queue.get_science_count_breakdown, "get_science_counts",
            function() return nil end)
        t.assert_true(type(restore_counts) == "function")
        t.assert_equal(queue.get_science_count_breakdown(1, "pack").lab_count, 0)
        restore_counts()

        t.assert_false(temp_persist(nil, xcur("temporary"), xcur("target"), 100))
        queue.set_pinned_tech(1, "target")
        t.assert_false(temp_persist(1, xcur("temporary"), xcur("target"), 100))
        queue.set_pinned_tech(1, "temporary")
        t.assert_true(temp_persist(1, xcur("temporary"), xcur("target"), 100))
        queue.set_pinned_tech(1, nil)
        local old_sufficient_for_private = queue.science_is_sufficient
        queue.science_is_sufficient = function() return false end
        t.assert_false(temp_persist(1, xcur("temporary"), xcur("target"), 100))
        queue.science_is_sufficient = old_sufficient_for_private
        science_priorities.temporary = 2
        science_priorities.target = 0
        t.assert_true(temp_persist(1, xcur("temporary"), xcur("target"), 100))
        science_priorities.temporary = 0
        science_priorities.target = 2
        t.assert_false(temp_persist(1, xcur("temporary"), xcur("target"), 100))
        science_priorities.temporary = nil
        science_priorities.target = nil
        t.assert_false(temp_persist(1, nil, xcur("target"), 100))

        local old_check_sufficient = queue.science_is_sufficient
        local old_check_availability = queue.get_science_availability
        queue.science_is_sufficient = function(xcur_value)
            return xcur_value and xcur_value.technology.name == "current"
        end
        queue.get_science_availability = function() return {pack = true} end
        tech_state = {
            current = xcur("current"),
            target = xcur("target"),
            temporary = xcur("temporary")
        }
        force.current_research = make_tech("current")
        storage.forces[1].queue = {
            queue = {"target", "temporary"},
            target_tech = "target",
            temp_tech = "missing",
            temp_tech_timeout = game.tick - 1
        }
        queue.check_and_switch_temp_research(force)
        storage.forces[1].queue.temp_tech = "temporary"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        queue.check_and_switch_temp_research(force)
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.temp_tech_timeout = nil
        force.current_research = nil
        queue.check_and_switch_temp_research(force)
        force.current_research = make_tech("unknown")
        queue.check_and_switch_temp_research(force)
        force.current_research = make_tech("current")
        force.research_progress = 1
        storage.forces[1].queue.target_tech = nil
        queue.science_is_sufficient = function() return true end
        queue.check_and_switch_temp_research(force)
        force.research_progress = 0
        storage.forces[1].queue.target_tech = "target"
        queue.science_is_sufficient = old_check_sufficient
        queue.check_and_switch_temp_research(force)
        queue.science_is_sufficient = old_check_sufficient
        queue.get_science_availability = old_check_availability

        storage.forces[1] = nil
        mark_internal(1, {})
        storage.forces[1] = {queue = {queue = {}}}
        t.assert_nil(any_lab(nil))
        game.surfaces = {{find_entities_filtered = function() return {} end}}
        t.assert_nil(any_lab(1))
        local surface_lab = {valid = true, unit_number = 7, surface = {valid = true, name = "surface"},
            prototype = {name = "surface-lab"}}
        game.surfaces = {{find_entities_filtered = function() return {surface_lab} end}}
        storage.forces[1].lab = {all_labs = {}, lab_content = {}}
        t.assert_equal(any_lab(1), surface_lab)
        t.assert_nil(get_network(1, nil))
        t.assert_equal(next(get_input_set({valid = true, prototype = {}})), nil)
        t.assert_equal(#observation_contents({entity = {valid = false}}), 0)
        local missing_science = missing_lab_sciences({research_unit_ingredients = {{name = "pack", amount = 2}}},
            {{name = "pack", count = 1}})
        t.assert_equal(missing_science[1], "pack")

        t.assert_nil(position(force, "missing"))
        move(force, "a", 1, 1)
        storage.forces[1].queue.queue = nil
        move(force, "a", 1, 2)
        local empty_average = {average({}, 3)}
        t.assert_nil(empty_average[1])
        local empty_window = {window({{speed = 0, valid_speed = false, tech_name = "other"}}, 0, 1, "a")}
        t.assert_equal(empty_window[2], 0)
        local invalid_window = {window({{speed = 0, valid_speed = false, tech_name = "a"}}, 0, 1, "a")}
        t.assert_equal(invalid_window[2], 0)
        storage.forces[1].queue = {}
        queue.get_research_history(1, 1)
        storage.forces[1].queue = {queue = {"a", "b", "d"}}
        queue.promote(force, "d", 20)
        queue.demote(force, "d")
        queue.demote(force, "c")
        storage.forces[1].queue.research_spm_history = {size = 200, values = {}, head = 5, count = 0}
        queue.get_research_history(1, 1)
        t.assert_nil(ensure_history(nil))
        write_history(nil, 1, 1)
        local restore_history = swap_private(queue.get_research_history, "ensure_research_spm_history",
            function() return {} end)
        t.assert_true(type(restore_history) == "function")
        queue.get_research_history(1, 1)
        restore_history()

        tech_state = {a = xcur("a", {sciences = {"pack"}}), current = xcur("current")}
        storage.forces[1].queue = {queue = {}, current_tech = "a"}
        force.current_research = nil
        queue.get_science_availability = function() return {} end
        t.assert_true(queue.research_is_stuck(force))
        storage.forces[1].queue = nil
        queue.check_and_switch_temp_research(force)
        storage.forces[1].queue = {
            queue = {}, temp_tech = "temporary", temp_tech_timeout = game.tick + 1
        }
        tech_state.temporary = xcur("temporary")
        force.current_research = make_tech("current")
        queue.check_and_switch_temp_research(force)
        tech_state = nil
        storage.forces[1].queue = {queue = {}}
        queue.check_and_switch_temp_research(force)

        force_settings.master_enable = "left"
        queue.check_and_switch_temp_research(force)
        force_settings.master_enable = nil
        tech_state = {current = xcur("current"), temporary = xcur("temporary")}
        force.current_research = make_tech("current")
        storage.forces[1].queue = {
            queue = {"temporary"}, temp_tech = "temporary", temp_tech_timeout = game.tick - 1
        }
        queue.check_and_switch_temp_research(force)

        local old_reorder = queue.reorder_queue_by_score
        local old_build_queue = queue.build_queue_from_available
        local reorder_calls = 0
        queue.reorder_queue_by_score = function()
            reorder_calls = reorder_calls + 1
            if reorder_calls == 2 then
                storage.forces[1].queue.current_tech = "current"
            end
        end
        queue.build_queue_from_available = function() end
        storage.forces[1].queue = {queue = {"current"}}
        force.current_research = nil
        force_settings.auto_research = true
        queue.start_next_research(force)
        queue.reorder_queue_by_score = old_reorder
        queue.build_queue_from_available = old_build_queue

        local network_a = {valid = true, network_id = 41,
            get_item_count = function() return 1 end}
        local network_b = {valid = true, network_id = 42,
            get_item_count = function() return 1 end}
        local surface_a = {valid = true, index = 1, name = "a"}
        local surface_b = {valid = true, index = 2, name = "b"}
        local function science_lab(unit, network, surface)
            return {
                valid = true, unit_number = unit, force = {
                    find_logistic_network_by_position = function() return network end
                }, surface = surface, position = {x = unit, y = unit},
                prototype = {name = "science-lab-" .. unit, lab_inputs = {"pack"}},
                get_inventory = function() return {get_contents = function() return {} end} end
            }
        end
        science_names = {"pack"}
        defines = {inventory = {lab_input = 1}}
        registered_labs = {science_lab(41, network_a, surface_a), science_lab(42, network_b, surface_b)}
        queue.invalidate_science_cache(1)
        queue.get_science_counts(1)
        _G.defines = nil
    end},
    {"auto_switch fallback switches a singleton queued pack-bound tech to a supplied unqueued alternate", function()
        local force = reset_runtime()
        game.tick = 33000
        science_names = {"starved-pack", "available-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_bottleneck = queue.get_active_missing_science_bottleneck
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {['starved-pack'] = true, ['available-pack'] = true}
        end
        queue.get_science_forecast = function() return {} end
        queue.get_research_speed = function() return 1 end
        -- Simulate the staggered sampler/display being temporarily unavailable:
        -- the existing bottleneck path finds nothing, so the auto_switch
        -- direct-inventory fallback must confirm the pack-bound state.
        queue.get_active_missing_science_bottleneck = function() return {} end

        local current = xcur("current", {
            sciences = {"starved-pack"},
            research_unit_ingredients = {{name = "starved-pack", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local alternate = xcur("alternate", {
            sciences = {"available-pack"},
            research_unit_ingredients = {{name = "available-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"current"}
        force.current_research = current.technology

        -- Labs accept both packs but only hold available-pack; starved-pack is
        -- present in zero accepting labs, so auto_switch must flag it missing.
        local function add_lab(unit_number, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                frozen = false,
                electric_buffer_size = 0,
                energy = 100,
                disabled_by_script = false,
                disabled_by_control_behavior = false,
                prototype = {
                    name = "auto-switch-lab-" .. tostring(unit_number),
                    lab_inputs = {"starved-pack", "available-pack"}
                },
                get_inventory = function()
                    return {
                        is_empty = function() return #contents == 0 end,
                        get_contents = function() return contents end
                    }
                end
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = defines.entity_status.working,
                latest_contents = contents
            }
        end
        add_lab(1, {{name = "available-pack", count = 100}})
        add_lab(2, {{name = "available-pack", count = 100}})

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech
        local requested = requests

        queue.get_science_availability = old_availability
        queue.get_active_missing_science_bottleneck = old_bottleneck
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_equal(selected, "alternate",
            "the auto_switch fallback must switch a pack-bound current tech to a supplied unqueued alternate")
        t.assert_equal(requested, 1,
            "the emergency switch must request active reselection")
    end},
    {"auto_switch fallback rejects an alternate that fails existing sufficiency", function()
        local force = reset_runtime()
        game.tick = 33500
        science_names = {"starved-pack", "unavailable-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_bottleneck = queue.get_active_missing_science_bottleneck
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {['starved-pack'] = true, ['unavailable-pack'] = false}
        end
        queue.get_science_forecast = function() return {} end
        queue.get_research_speed = function() return 1 end
        queue.get_active_missing_science_bottleneck = function() return {} end

        local current = xcur("current", {
            sciences = {"starved-pack"},
            research_unit_ingredients = {{name = "starved-pack", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local alternate = xcur("alternate", {
            sciences = {"unavailable-pack"},
            research_unit_ingredients = {{name = "unavailable-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"current"}
        force.current_research = current.technology

        local function add_lab(unit_number, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                frozen = false,
                electric_buffer_size = 0,
                energy = 100,
                disabled_by_script = false,
                disabled_by_control_behavior = false,
                prototype = {
                    name = "reject-lab-" .. tostring(unit_number),
                    lab_inputs = {"starved-pack", "unavailable-pack"}
                },
                get_inventory = function()
                    return {
                        is_empty = function() return #contents == 0 end,
                        get_contents = function() return contents end
                    }
                end
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = defines.entity_status.working,
                latest_contents = contents
            }
        end
        -- Labs hold unavailable-pack but NOT starved-pack, so auto_switch flags
        -- starved-pack as missing. The alternate requires unavailable-pack which
        -- is not available in queue.get_science_availability, so it must be rejected.
        add_lab(1, {{name = "unavailable-pack", count = 100}})
        add_lab(2, {{name = "unavailable-pack", count = 100}})

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech

        queue.get_science_availability = old_availability
        queue.get_active_missing_science_bottleneck = old_bottleneck
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_equal(selected, nil,
            "an alternate that fails existing sufficiency must not be selected by the auto_switch fallback")
    end},
    {"rotates parallel candidates and honors the dedicated-mod handoff", function()
        local force = reset_runtime()
        tech_state = {a = xcur("a"), b = xcur("b"), c = xcur("c")}
        storage.forces[1].queue.queue = {"a", "b", "c"}
        policy_settings.parallel_research = true
        policy_settings.parallel_slots = 2
        queue.rotate_parallel_research(force)
        t.assert_equal(#force.research_queue, 2)
        t.assert_equal(queue.get_current_researching(1), force.research_queue[1])

        policy_settings.parallel_mod = true
        queue.rotate_parallel_research(force)
        t.assert_equal(#force.research_queue, 2)
        policy_settings.parallel_research = false
        queue.rotate_parallel_research(force)
    end},
    {"auto_switch fallback switches when sampler and display are both stale with multiple missing sciences", function()
        local force = reset_runtime()
        game.tick = 34000
        science_names = {"starved-pack-a", "starved-pack-b", "available-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_bottleneck = queue.get_active_missing_science_bottleneck
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        local old_snapshot_tick = queue.get_research_health_snapshot_tick
        local old_diagnostic = queue.get_research_display_diagnostic
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {['starved-pack-a'] = true, ['starved-pack-b'] = true, ['available-pack'] = true}
        end
        queue.get_science_forecast = function() return {} end
        queue.get_research_speed = function() return 1 end
        -- Simulate BOTH the staggered sampler AND the display diagnostic being
        -- stale/unavailable for a massive factory: the bottleneck path finds
        -- nothing, and the display snapshot is too old. The auto_switch
        -- direct-inventory fallback must confirm the pack-bound state.
        queue.get_active_missing_science_bottleneck = function() return {} end
        queue.get_research_health_snapshot_tick = function() return -1 end
        queue.get_research_display_diagnostic = function() return nil end

        local current = xcur("current", {
            sciences = {"starved-pack-a", "starved-pack-b", "available-pack"},
            research_unit_ingredients = {
                {name = "starved-pack-a", amount = 1},
                {name = "starved-pack-b", amount = 1},
                {name = "available-pack", amount = 1}
            }
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local alternate = xcur("alternate", {
            sciences = {"available-pack"},
            research_unit_ingredients = {{name = "available-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"current"}
        force.current_research = current.technology

        -- Labs accept all three packs but only hold available-pack; both
        -- starved packs are present in zero accepting labs, so auto_switch
        -- must flag them missing.
        local function add_lab(unit_number, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                frozen = false,
                electric_buffer_size = 0,
                energy = 100,
                disabled_by_script = false,
                disabled_by_control_behavior = false,
                prototype = {
                    name = "multi-starve-lab-" .. tostring(unit_number),
                    lab_inputs = {"starved-pack-a", "starved-pack-b", "available-pack"}
                },
                get_inventory = function()
                    return {
                        is_empty = function() return #contents == 0 end,
                        get_contents = function() return contents end
                    }
                end
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = defines.entity_status.working,
                latest_contents = contents
            }
        end
        add_lab(1, {{name = "available-pack", count = 100}})
        add_lab(2, {{name = "available-pack", count = 100}})

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech
        local requested = requests

        queue.get_science_availability = old_availability
        queue.get_active_missing_science_bottleneck = old_bottleneck
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed
        queue.get_research_health_snapshot_tick = old_snapshot_tick
        queue.get_research_display_diagnostic = old_diagnostic

        t.assert_equal(selected, "alternate",
            "the auto_switch fallback must switch a multi-pack-bound current tech to a supplied unqueued alternate when both sampler and display are stale")
        t.assert_equal(requested, 1,
            "the emergency switch must request active reselection")
    end},
    {"uses a stale pack_bound display snapshot when the technology still matches", function()
        local force = reset_runtime()
        game.tick = 50000
        science_names = {"starved-pack", "available-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_bottleneck = queue.get_active_missing_science_bottleneck
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        local old_snapshot_tick = queue.get_research_health_snapshot_tick
        local old_diagnostic = queue.get_research_display_diagnostic
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {['starved-pack'] = true, ['available-pack'] = true}
        end
        queue.get_science_forecast = function() return {} end
        queue.get_research_speed = function() return 1 end
        -- Simulate a massive factory: the staggered sampler has <80% coverage
        -- (all lab latest_tick values are stale), and the display snapshot is
        -- very old (2000 ticks = 33 s) but still says pack_bound for the same
        -- technology. The switcher must honor the stale snapshot.
        queue.get_research_health_snapshot_tick = function()
            return game.tick - 2000
        end
        queue.get_research_display_diagnostic = function()
            return {
                state = "pack_bound",
                current_technology = "current",
                missing_sciences = {
                    {science = "starved-pack", lost_spm = 100}
                }
            }
        end

        local current = xcur("current", {
            sciences = {"starved-pack"},
            research_unit_ingredients = {{name = "starved-pack", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local alternate = xcur("alternate", {
            sciences = {"available-pack"},
            research_unit_ingredients = {{name = "available-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"current"}
        force.current_research = current.technology

        -- All labs have stale latest_tick (sampled >900 ticks ago), so the
        -- live sampler has 0% coverage. The display snapshot is 2000 ticks
        -- old but matches the current technology and says pack_bound.
        local function add_stale_lab(unit_number)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                frozen = false,
                electric_buffer_size = 0,
                energy = 100,
                disabled_by_script = false,
                disabled_by_control_behavior = false,
                prototype = {
                    name = "stale-snapshot-lab-" .. tostring(unit_number),
                    lab_inputs = {"starved-pack", "available-pack"},
                    get_researching_speed = function() return 1 end
                },
                get_inventory = function()
                    return {
                        is_empty = function() return false end,
                        get_contents = function()
                            return {{name = "available-pack", count = 100}}
                        end
                    }
                end
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick - 1000,
                latest_status = defines.entity_status.working,
                latest_contents = {{name = "available-pack", count = 100}}
            }
        end
        add_stale_lab(1)
        add_stale_lab(2)

        -- Verify the bottleneck is detected from the stale display snapshot
        local bottleneck = queue.get_active_missing_science_bottleneck(1, current)
        t.assert_equal(bottleneck["starved-pack"], true,
            "a stale pack_bound display snapshot for the same technology must still inform the bottleneck")

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech
        local requested = requests

        queue.get_science_availability = old_availability
        queue.get_active_missing_science_bottleneck = old_bottleneck
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed
        queue.get_research_health_snapshot_tick = old_snapshot_tick
        queue.get_research_display_diagnostic = old_diagnostic

        t.assert_equal(selected, "alternate",
            "a stale pack_bound display snapshot must still trigger the alternate research switch")
        t.assert_equal(requested, 1,
            "the switch must request active research reselection")
    end},
    {"trivial per-science loss does not block switching to a candidate using that science", function()
        local force = reset_runtime()
        game.tick = 60000
        science_names = {"heavy-starved-pack", "trivial-starved-pack", "available-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        local old_snapshot_tick = queue.get_research_health_snapshot_tick
        local old_diagnostic = queue.get_research_display_diagnostic
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {
                ['heavy-starved-pack'] = true,
                ['trivial-starved-pack'] = true,
                ['available-pack'] = true
            }
        end
        queue.get_science_forecast = function() return {} end
        queue.get_research_speed = function() return 1 end
        queue.get_research_health_snapshot_tick = function() return -1 end
        queue.get_research_display_diagnostic = function() return nil end

        local current = xcur("current", {
            sciences = {"heavy-starved-pack", "trivial-starved-pack", "available-pack"},
            research_unit_ingredients = {
                {name = "heavy-starved-pack", amount = 1},
                {name = "trivial-starved-pack", amount = 1},
                {name = "available-pack", amount = 1}
            }
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        -- The alternate requires trivial-starved-pack (which is only missing
        -- from 1 lab) and available-pack. It must NOT be blocked just because
        -- trivial-starved-pack appears in the current tech's bottleneck.
        local alternate = xcur("alternate", {
            sciences = {"trivial-starved-pack", "available-pack"},
            research_unit_ingredients = {
                {name = "trivial-starved-pack", amount = 1},
                {name = "available-pack", amount = 1}
            }
        })
        alternate.technology.research_unit_energy = 60
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"current"}
        force.current_research = current.technology

        -- 10 labs total. 9 labs are missing heavy-starved-pack (material loss).
        -- Only 1 lab is missing trivial-starved-pack (trivial loss).
        -- The material threshold is max(1, expected_spm * 0.05).
        -- With 10 labs at 1 SPM each, expected_spm = 10, threshold = max(1, 0.5) = 1.
        -- heavy-starved-pack lost_spm = 9 (>= 1, included).
        -- trivial-starved-pack lost_spm = 1 (>= 1, included... but we need
        -- to make it below threshold). Let's use 20 labs instead.
        local function add_lab(unit_number, missing_heavy, missing_trivial)
            local contents = {}
            if not missing_heavy then
                table.insert(contents, {name = "heavy-starved-pack", count = 100})
            end
            if not missing_trivial then
                table.insert(contents, {name = "trivial-starved-pack", count = 100})
            end
            table.insert(contents, {name = "available-pack", count = 100})
            local status = (missing_heavy or missing_trivial)
                and defines.entity_status.missing_science_packs
                or defines.entity_status.working
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                frozen = false,
                electric_buffer_size = 0,
                energy = 100,
                disabled_by_script = false,
                disabled_by_control_behavior = false,
                speed_bonus = 0,
                productivity_bonus = 0,
                prototype = {
                    name = "per-science-lab-" .. tostring(unit_number),
                    lab_inputs = {"heavy-starved-pack", "trivial-starved-pack", "available-pack"},
                    get_researching_speed = function() return 1 end
                },
                get_inventory = function()
                    return {
                        is_empty = function() return #contents == 0 end,
                        get_contents = function() return contents end
                    }
                end
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = status,
                latest_contents = contents
            }
        end
        -- 20 labs: 19 missing heavy (material), 1 missing trivial (below threshold)
        -- expected_spm = 20 * 1 * 3600/60 = 1200
        -- threshold = max(1, 1200 * 0.05) = 60
        -- heavy lost_spm = 19 * 60 = 1140 (>= 60, included)
        -- trivial lost_spm = 1 * 60 = 60 (>= 60, included... hmm)
        -- Need trivial to be below 60. Use 19 missing heavy, 1 missing trivial.
        -- trivial lost_spm = 1 * 60 = 60. That's exactly the threshold.
        -- Let's use 20 labs where 18 missing heavy, 1 missing trivial, 1 working.
        -- expected_spm = 20 * 60 = 1200, threshold = 60
        -- heavy lost = 18 * 60 = 1080 (>= 60, included)
        -- trivial lost = 1 * 60 = 60 (>= 60, still included!)
        -- Need more labs. 100 labs: 90 missing heavy, 1 missing trivial, 9 working.
        -- expected_spm = 100 * 60 = 6000, threshold = max(1, 300) = 300
        -- heavy lost = 90 * 60 = 5400 (>= 300, included)
        -- trivial lost = 1 * 60 = 60 (< 300, excluded!)
        for i = 1, 90 do
            add_lab(i, true, false)
        end
        add_lab(91, false, true)  -- 1 lab missing only trivial
        for i = 92, 100 do
            add_lab(i, false, false)  -- 9 working labs
        end

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech
        local requested = requests

        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed
        queue.get_research_health_snapshot_tick = old_snapshot_tick
        queue.get_research_display_diagnostic = old_diagnostic

        t.assert_equal(selected, "alternate",
            "a candidate using a trivially-starved science must not be blocked from switching when that science's per-pack loss is below the material threshold")
        t.assert_equal(requested, 1,
            "the switch must request active research reselection")
    end},
    {"stale target from a previous switch is replaced by the current starving tech", function()
        local force = reset_runtime()
        game.tick = 70000
        science_names = {"starved-pack", "available-pack", "unavailable-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        local old_snapshot_tick = queue.get_research_health_snapshot_tick
        local old_diagnostic = queue.get_research_display_diagnostic
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {['starved-pack'] = true, ['available-pack'] = true, ['unavailable-pack'] = false}
        end
        queue.get_science_forecast = function() return {} end
        queue.get_research_speed = function() return 1 end
        queue.get_research_health_snapshot_tick = function() return -1 end
        queue.get_research_display_diagnostic = function() return nil end

        local current = xcur("current", {
            sciences = {"starved-pack"},
            research_unit_ingredients = {{name = "starved-pack", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local alternate = xcur("alternate", {
            sciences = {"available-pack"},
            research_unit_ingredients = {{name = "available-pack", amount = 1}}
        })
        alternate.technology.research_unit_energy = 60
        -- old_target is a tech from a previous switch cycle; it is queued but
        -- requires a fully unavailable pack, so it cannot be restored.
        local old_target = xcur("old-target", {
            sciences = {"unavailable-pack"},
            research_unit_ingredients = {{name = "unavailable-pack", amount = 1}}
        })
        old_target.technology.research_unit_energy = 60
        old_target.queued = true
        tech_state = {current = current, alternate = alternate, ["old-target"] = old_target}
        storage.forces[1].queue.queue = {"old-target", "current"}
        force.current_research = current.technology

        -- Simulate stale state from a previous switch: target is old-target,
        -- no temp is active. The current tech (current) is pack-bound.
        storage.forces[1].queue.target_tech = "old-target"
        storage.forces[1].queue.temp_tech = nil
        storage.forces[1].queue.temp_tech_timeout = nil
        storage.forces[1].queue.last_switch_tick = nil

        local function add_lab(unit_number, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                frozen = false,
                electric_buffer_size = 0,
                energy = 100,
                disabled_by_script = false,
                disabled_by_control_behavior = false,
                speed_bonus = 0,
                productivity_bonus = 0,
                prototype = {
                    name = "stale-target-lab-" .. tostring(unit_number),
                    lab_inputs = {"starved-pack", "available-pack"},
                    get_researching_speed = function() return 1 end
                },
                get_inventory = function()
                    return {
                        is_empty = function() return #contents == 0 end,
                        get_contents = function() return contents end
                    }
                end
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = defines.entity_status.missing_science_packs,
                latest_contents = contents
            }
        end
        -- 10 labs all missing starved-pack, holding only available-pack
        for i = 1, 10 do
            add_lab(i, {{name = "available-pack", count = 100}})
        end

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech
        local new_target = storage.forces[1].queue.target_tech

        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed
        queue.get_research_health_snapshot_tick = old_snapshot_tick
        queue.get_research_display_diagnostic = old_diagnostic

        t.assert_equal(selected, "alternate",
            "the switch must select the supplied alternate")
        t.assert_equal(new_target, "current",
            "the target must be the current starving tech, not a stale target from a previous switch cycle")
    end},
    {"preserves the original target when the current tech is itself the temp tech", function()
        local force = reset_runtime()
        game.tick = 80000
        science_names = {"starved-pack", "available-pack", "unavailable-pack"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        local old_snapshot_tick = queue.get_research_health_snapshot_tick
        local old_diagnostic = queue.get_research_display_diagnostic
        policy_settings.forecast_seconds = 0
        queue.get_science_availability = function()
            return {['starved-pack'] = true, ['available-pack'] = true, ['unavailable-pack'] = false}
        end
        queue.get_science_forecast = function() return {} end
        queue.get_research_speed = function() return 1 end
        queue.get_research_health_snapshot_tick = function() return -1 end
        queue.get_research_display_diagnostic = function() return nil end

        local original_target = xcur("original-target", {
            sciences = {"unavailable-pack"},
            research_unit_ingredients = {{name = "unavailable-pack", amount = 1}}
        })
        original_target.technology.research_unit_energy = 60
        original_target.queued = true
        local old_temp = xcur("old-temp", {
            sciences = {"starved-pack"},
            research_unit_ingredients = {{name = "starved-pack", amount = 1}}
        })
        old_temp.technology.research_unit_energy = 60
        old_temp.queued = true
        local replacement = xcur("replacement", {
            sciences = {"available-pack"},
            research_unit_ingredients = {{name = "available-pack", amount = 1}}
        })
        replacement.technology.research_unit_energy = 60
        tech_state = {["original-target"] = original_target, ["old-temp"] = old_temp, replacement = replacement}
        storage.forces[1].queue.queue = {"original-target", "old-temp"}
        -- The current research is the old temp tech, which is now also pack-bound
        force.current_research = old_temp.technology

        -- Stale state from a previous switch: target is original-target, temp is old-temp
        storage.forces[1].queue.target_tech = "original-target"
        storage.forces[1].queue.temp_tech = "old-temp"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1  -- expired
        storage.forces[1].queue.last_switch_tick = nil

        local function add_lab(unit_number, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                frozen = false,
                electric_buffer_size = 0,
                energy = 100,
                disabled_by_script = false,
                disabled_by_control_behavior = false,
                speed_bonus = 0,
                productivity_bonus = 0,
                prototype = {
                    name = "preserve-target-lab-" .. tostring(unit_number),
                    lab_inputs = {"starved-pack", "available-pack"},
                    get_researching_speed = function() return 1 end
                },
                get_inventory = function()
                    return {
                        is_empty = function() return #contents == 0 end,
                        get_contents = function() return contents end
                    }
                end
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = defines.entity_status.missing_science_packs,
                latest_contents = contents
            }
        end
        for i = 1, 10 do
            add_lab(i, {{name = "available-pack", count = 100}})
        end

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech
        local new_target = storage.forces[1].queue.target_tech

        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed
        queue.get_research_health_snapshot_tick = old_snapshot_tick
        queue.get_research_display_diagnostic = old_diagnostic

        t.assert_equal(selected, "replacement",
            "the switch must select the replacement temp")
        t.assert_equal(new_target, "original-target",
            "the original target must be preserved when the current tech is itself the expired temp tech")
    end},
    {"switches to a partial-supply candidate with fewer bottleneck sciences", function()
        local force = reset_runtime()
        game.tick = 32000
        queue.invalidate_science_cache(1)
        science_names = {"pack-a", "pack-b", "pack-c"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        policy_settings.forecast_seconds = 120
        queue.get_science_availability = function()
            return {['pack-a'] = true, ['pack-b'] = true, ['pack-c'] = true}
        end
        queue.get_science_forecast = function()
            return {
                ['pack-a'] = {stock = 100000, production_per_minute = 0, consumption_per_minute = 0, net_per_minute = 0},
                ['pack-b'] = {stock = 100000, production_per_minute = 0, consumption_per_minute = 0, net_per_minute = 0},
                ['pack-c'] = {stock = 100000, production_per_minute = 0, consumption_per_minute = 0, net_per_minute = 0}
            }
        end
        queue.get_research_speed = function() return 1 end

        local current = xcur("current", {
            sciences = {"pack-a", "pack-b"},
            research_unit_ingredients = {{name = "pack-a", amount = 1}, {name = "pack-b", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local partial = xcur("partial", {
            sciences = {"pack-a"},
            research_unit_ingredients = {{name = "pack-a", amount = 1}}
        })
        partial.technology.research_unit_energy = 60
        tech_state = {current = current, partial = partial}
        storage.forces[1].queue.queue = {"current", "partial"}
        force.current_research = current.technology

        local function add_lab(unit_number, speed, status, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                speed_bonus = speed - 1,
                productivity_bonus = 0,
                prototype = {
                    name = "partial-lab-" .. tostring(unit_number),
                    lab_inputs = {"pack-a", "pack-b"},
                    get_researching_speed = function() return 1 end
                }
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = status,
                latest_contents = contents
            }
        end
        add_lab(1, 49, defines.entity_status.missing_science_packs, {{name = "pack-a", count = 100000}})
        add_lab(2, 1, defines.entity_status.working,
            {{name = "pack-a", count = 100000}, {name = "pack-b", count = 100000}})

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech

        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_equal(selected, "partial",
            "a partial-supply candidate with fewer bottleneck sciences must be selected when no fully-sufficient candidate exists")
    end},
    {"does not switch to a partial-supply candidate with the same bottleneck count", function()
        local force = reset_runtime()
        game.tick = 32000
        queue.invalidate_science_cache(1)
        science_names = {"pack-a", "pack-b"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_forecast = queue.get_science_forecast
        local old_speed = queue.get_research_speed
        policy_settings.forecast_seconds = 120
        queue.get_science_availability = function()
            return {['pack-a'] = true, ['pack-b'] = true}
        end
        queue.get_science_forecast = function()
            return {
                ['pack-a'] = {stock = 100000, production_per_minute = 0, consumption_per_minute = 0, net_per_minute = 0},
                ['pack-b'] = {stock = 100000, production_per_minute = 0, consumption_per_minute = 0, net_per_minute = 0}
            }
        end
        queue.get_research_speed = function() return 1 end

        local current = xcur("current", {
            sciences = {"pack-a"},
            research_unit_ingredients = {{name = "pack-a", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local same_bottleneck = xcur("same-bottleneck", {
            sciences = {"pack-a"},
            research_unit_ingredients = {{name = "pack-a", amount = 1}}
        })
        same_bottleneck.technology.research_unit_energy = 60
        tech_state = {current = current, ["same-bottleneck"] = same_bottleneck}
        storage.forces[1].queue.queue = {"current", "same-bottleneck"}
        force.current_research = current.technology

        local function add_lab(unit_number, speed, status, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                speed_bonus = speed - 1,
                productivity_bonus = 0,
                prototype = {
                    name = "same-bn-lab-" .. tostring(unit_number),
                    lab_inputs = {"pack-a"},
                    get_researching_speed = function() return 1 end
                }
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = status,
                latest_contents = contents
            }
        end
        add_lab(1, 49, defines.entity_status.missing_science_packs, {})
        add_lab(2, 1, defines.entity_status.working, {{name = "pack-a", count = 100000}})

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech

        queue.get_science_availability = old_availability
        queue.get_science_forecast = old_forecast
        queue.get_research_speed = old_speed

        t.assert_equal(selected, nil,
            "a candidate with the same bottleneck count must not be selected as a partial-supply fallback")
    end},
    {"score_interrupt_margin allows score-based switching for a clearly better candidate", function()
        local force = reset_runtime()
        game.tick = 31000
        queue.invalidate_science_cache(1)
        science_names = {"pack-a"}
        defines = {
            entity_status = {
                working = "working",
                missing_science_packs = "missing-science-packs"
            },
            inventory = {lab_input = 1}
        }

        local old_availability = queue.get_science_availability
        local old_sufficient = queue.science_is_sufficient
        queue.get_science_availability = function() return {['pack-a'] = true} end
        queue.science_is_sufficient = function() return true end

        local current = xcur("current", {
            sciences = {"pack-a"},
            research_unit_ingredients = {{name = "pack-a", amount = 1}}
        })
        current.technology.research_unit_energy = 60
        current.queued = true
        local better = xcur("better", {
            sciences = {"pack-a"},
            research_unit_ingredients = {{name = "pack-a", amount = 1}}
        })
        better.technology.research_unit_energy = 60
        science_priorities["better"] = 200
        tech_state = {current = current, better = better}
        storage.forces[1].queue.queue = {"current", "better"}
        force.current_research = current.technology
        force.research_progress = 0.5

        local function add_lab(unit_number, speed, status, contents)
            local lab_entity = {
                valid = true,
                unit_number = unit_number,
                speed_bonus = speed - 1,
                productivity_bonus = 0,
                prototype = {
                    name = "margin-lab-" .. tostring(unit_number),
                    lab_inputs = {"pack-a"},
                    get_researching_speed = function() return 1 end
                }
            }
            runtime_lab_content[unit_number] = {
                lab = lab_entity,
                latest_tick = game.tick,
                latest_status = status,
                latest_contents = contents
            }
        end
        add_lab(1, 10, defines.entity_status.working, {{name = "pack-a", count = 100000}})

        queue.check_and_switch_temp_research(force)
        local selected = storage.forces[1].queue.temp_tech

        queue.get_science_availability = old_availability
        queue.science_is_sufficient = old_sufficient
        science_priorities["better"] = nil

        t.assert_equal(selected, "better",
            "a candidate with a much higher score must be able to interrupt a sufficient current research with the lower margin")
    end},
    {"upcoming wait_time does not accumulate blocked tech durations", function()
        local force = reset_runtime()
        science_names = {"pack-a", "pack-b"}
        local old_availability = queue.get_science_availability
        local old_speed = queue.get_research_speed
        queue.get_science_availability = function()
            return {['pack-a'] = true, ['pack-b'] = false}
        end
        queue.get_research_speed = function() return 1 end

        local first = xcur("first", {
            sciences = {"pack-a"},
            research_unit_count = 60,
            research_unit_ingredients = {{name = "pack-a", amount = 1}}
        })
        first.technology.research_unit_energy = 60
        local blocked = xcur("blocked", {
            sciences = {"pack-b"},
            research_unit_count = 120,
            research_unit_ingredients = {{name = "pack-b", amount = 1}}
        })
        blocked.technology.research_unit_energy = 60
        local third = xcur("third", {
            sciences = {"pack-a"},
            research_unit_count = 30,
            research_unit_ingredients = {{name = "pack-a", amount = 1}}
        })
        third.technology.research_unit_energy = 60
        tech_state = {first = first, blocked = blocked, third = third}
        storage.forces[1].queue.queue = {"first", "blocked", "third"}
        force.current_research = first.technology

        local entries = queue.get_upcoming_research(1, 3)
        queue.get_science_availability = old_availability
        queue.get_research_speed = old_speed

        local by_name = {}
        for _, entry in ipairs(entries) do
            by_name[entry.tech_name] = entry
        end

        t.assert_equal(#entries, 3, "three entries must be returned")
        t.assert_equal(by_name["first"].wait_time, 0,
            "first tech (current) must have zero wait_time")
        t.assert_true(by_name["blocked"].wait_time ~= nil,
            "blocked tech must have a wait_time value")
        t.assert_true(by_name["third"].wait_time ~= nil,
            "third tech must have a wait_time value")
        t.assert_equal(by_name["third"].wait_time, 60,
            "third tech must wait only for the first tech's duration; the blocked tech must not add to cumulative time")
        t.assert_equal(by_name["blocked"].wait_time, 90,
            "blocked tech must wait for first + third durations; its own duration must not accumulate")
    end},
}

local passed = t.run("queue_core_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original[name]
    package.loaded[name] = nil
end
return passed
