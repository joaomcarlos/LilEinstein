package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local t = require("tests.testlib")

local names = {
    "lib.util", "lib.const", "model.state", "model.tech", "model.lab", "model.env",
    "lib.log", "model.research_weights", "model.research_policy", "model.queue"
}
local original = {}
for _, name in ipairs(names) do
    original[name] = package.preload[name]
    package.loaded[name] = nil
end

local labs = {}
local runtime = {}
local tech_state = {}
local policy_settings = {}
local science_states = {}
local cluster_states = {}
local repeat_rules = {}
local research_weights = {research_weights = {}, research_caps = {}}
local queued_updates = {}
local sanitize_valid = true
local flow_input = 10
local flow_output = 2

t.install_module("lib.util", {})
t.install_module("lib.const", {
    runtime_intervals = {science_pack_panel_ticks = 300},
    default_settings = {
        force = {settings = {auto_research = true, requeue_infinite_tech = true}}
    }
})
t.install_module("lib.log", {log = function() end, warn = function() end, error = function() end})
t.install_module("model.state", {
    get_force_setting = function(_, key, default)
        return policy_settings[key] == nil and default or policy_settings[key]
    end,
    request_next_research = function() end,
    request_gui_update = function() end
})
t.install_module("model.tech", {
    get_all_tech_state_ext = function() return tech_state end,
    get_single_tech_state_ext = function(_, name) return tech_state[name] end,
    update_queued = function(_, name, value) queued_updates[name] = value end
})
t.install_module("model.lab", {
    get_registered_labs = function() return labs end,
    get_runtime_lab_content = function() return runtime end,
    register = function() end
})
t.install_module("model.env", {
    get_all_sciences = function() return {"automation-science-pack", "logistic-science-pack"} end
})
t.install_module("model.research_weights", research_weights)
t.install_module("model.research_policy", {
    get_setting = function(_, key, default)
        return policy_settings[key] == nil and default or policy_settings[key]
    end,
    get_tech_science_priority = function(_, xcur)
        local name = xcur and xcur.technology and xcur.technology.name
        local priorities = policy_settings.science_priorities or {}
        return priorities[name] or 0
    end,
    get_strategy_adjustment = function() return 0 end,
    should_requeue = function() return false end,
    consume_repeat = function() end,
    parallel_mod_available = function() return policy_settings.parallel_mod == true end,
    get_science_policy = function() return {upper_threshold = 1, lower_threshold = 0.5} end,
    get_science_available_state = function(_, science, default)
        return science_states[science] == nil and default or science_states[science]
    end,
    set_science_available_state = function(_, science, value) science_states[science] = value end,
    get_cluster_science_available_state = function(_, cluster, science, default)
        local states = cluster_states[cluster] or {}
        return states[science] == nil and default or states[science]
    end,
    set_cluster_science_available_state = function(_, cluster, science, value)
        cluster_states[cluster] = cluster_states[cluster] or {}
        cluster_states[cluster][science] = value
    end,
    prune_cluster_science_states = function() end,
    get_repeat_rule = function(_, name) return repeat_rules[name] or {mode = "none"} end,
    copy_table = function(value)
        local copy = {}
        for key, item in pairs(value or {}) do copy[key] = item end
        return copy
    end,
    export_settings = function() return {} end,
    sanitize_settings = function(value) return sanitize_valid and (value or {}) or nil end,
    import_settings = function() end,
    get_presets = function() return {} end,
    set_preset = function() return true end,
    delete_preset = function() end
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

local original_globals = {
    game = _G.game,
    storage = _G.storage,
    defines = _G.defines,
    prototypes = _G.prototypes
}

local statuses = {
    working = 1,
    missing_science_packs = 2,
    no_power = 3,
    low_power = 4,
    no_fuel = 5,
    not_plugged_in_electric_network = 6,
    frozen = 7,
    disabled_by_control_behavior = 8,
    disabled_by_script = 9,
    disabled = 10,
    closed_by_circuit_network = 11,
    marked_for_deconstruction = 12,
    no_research_in_progress = 13
}

local function make_network(id, counts)
    return {
        valid = true,
        network_id = id,
        get_item_count = function(name) return counts[name] or 0 end
    }
end

local function make_lab(unit_number, options)
    options = options or {}
    local network = options.network
    local entity = {
        valid = options.valid ~= false,
        unit_number = unit_number,
        status = options.status or statuses.working,
        frozen = options.frozen or false,
        speed_bonus = options.speed_bonus or 0,
        productivity_bonus = options.productivity_bonus or 0,
        quality = options.quality,
        position = {x = unit_number, y = unit_number + 1},
        surface = {valid = true, index = 1, name = "nauvis"},
        prototype = {
            name = options.prototype_name or ("lab-" .. tostring(unit_number)),
            lab_inputs = options.lab_inputs or {"automation-science-pack", "logistic-science-pack"},
            science_pack_drain_rate_percent = options.drain_rate,
            uses_quality_drain_modifier = options.uses_quality_drain_modifier or false,
            get_researching_speed = function() return options.research_speed or 1 end
        }
    }
    entity.force = {
        find_logistic_network_by_position = function() return network end
    }
    entity.get_inventory = function()
        return {get_contents = function() return options.inventory_contents or {} end}
    end
    return entity
end

local function make_current(options)
    options = options or {}
    return {
        name = options.name or "research",
        research_unit_count = options.research_unit_count or 100,
        research_unit_energy = options.research_unit_energy == nil and 1 or options.research_unit_energy,
        research_unit_ingredients = options.ingredients or {
            {name = "automation-science-pack", amount = 1},
            {name = "logistic-science-pack", amount = 1}
        }
    }
end

local function reset(options)
    options = options or {}
    labs = options.labs or {}
    runtime = options.runtime or {}
    tech_state = options.tech_state or {}
    policy_settings = options.policy_settings or {}
    science_states = {}
    cluster_states = {}
    repeat_rules = {}
    queued_updates = {}
    sanitize_valid = true
    flow_input = options.flow_input == nil and 10 or options.flow_input
    flow_output = options.flow_output == nil and 2 or options.flow_output

    local current = options.current
    local stats = {
        valid = options.stats_valid ~= false,
        get_flow_count = function(request)
            if options.flow_error then error("flow unavailable") end
            return request.category == "input" and flow_input or flow_output
        end
    }
    local force = {
        index = 1,
        current_research = current,
        research_progress = options.research_progress or 0,
        technologies = options.technologies or {},
        research_queue = {},
        get_item_production_statistics = function()
            if options.stats_error then error("stats unavailable") end
            return stats
        end
    }
    storage = {forces = {[1] = {queue = {}}}}
    game = {
        tick = options.tick or 100,
        forces = {[1] = force},
        surfaces = {[1] = {valid = true, index = 1, name = "nauvis"}}
    }
    defines = {
        inventory = {lab_input = 1},
        entity_status = statuses,
        flow_precision_index = {one_minute = 1}
    }
    prototypes = {item = {}}
    queue.invalidate_science_cache(1)
    return force
end

local function finish_health_snapshot()
    queue.request_research_health_snapshot(1)
    local complete = false
    for _ = 1, 100 do
        complete = queue.tick_research_health_snapshot(1)
        if complete then return true end
    end
    return false
end

local tests = {
    {"counts lab and network science, caches, and reports breakdowns", function()
        local network = make_network(7, {
            ["automation-science-pack"] = 30,
            ["logistic-science-pack"] = 4
        })
        local first = make_lab(1, {
            network = network,
            inventory_contents = {{name = "automation-science-pack", count = 2}}
        })
        local second = make_lab(2, {
            network = network,
            inventory_contents = {{name = "logistic-science-pack", count = 3}}
        })
        reset({labs = {first, second}, runtime = {
            [1] = {latest_tick = 100, latest_contents = {{name = "automation-science-pack", count = 2}}},
            [2] = {latest_tick = 100, latest_contents = {{name = "logistic-science-pack", count = 3}}}
        }})
        local counts = queue.get_science_counts(1)
        t.assert_equal(counts["automation-science-pack"], 32)
        t.assert_equal(counts["logistic-science-pack"], 7)
        t.assert_equal(queue.get_science_counts(1), counts)
        local clusters = queue.get_science_clusters(1)
        local cluster = clusters["1:network:7"]
        t.assert_equal(cluster.lab_count, 2)
        t.assert_equal(cluster.lab_input_counts["automation-science-pack"], 2)
        local breakdown = queue.get_science_count_breakdown(1, "automation-science-pack")
        t.assert_equal(breakdown.lab_entity_count, 1)
        t.assert_equal(breakdown.network_total, 30)
        t.assert_equal(#breakdown.networks, 1)
        local unknown = queue.get_science_count_breakdown(1, "missing-pack")
        t.assert_equal(unknown.lab_count, 0)
        second.valid = false
        game.tick = game.tick + 1
        queue.get_science_counts(1)
        queue.invalidate_science_cache(1)
        t.assert_equal(queue.get_science_counts(1)["automation-science-pack"], 32)
    end},
    {"computes plain and cluster availability plus positive and negative forecasts", function()
        local network = make_network(9, {['automation-science-pack'] = 50, ['logistic-science-pack'] = 0})
        local entity = make_lab(3, {network = network, inventory_contents = {}})
        reset({labs = {entity}, runtime = {[3] = {latest_tick = 100, latest_contents = {}}}})
        local availability = queue.get_science_availability(1)
        t.assert_true(availability["automation-science-pack"])
        t.assert_false(availability["logistic-science-pack"])
        t.assert_false(availability.__cluster_mode)
        local forecast = queue.get_science_forecast(1)
        t.assert_equal(forecast["automation-science-pack"].net_per_minute, 8)
        t.assert_true(forecast["logistic-science-pack"].recovery_seconds ~= nil)
        t.assert_equal(forecast["automation-science-pack"].depletion_seconds, math.huge)
        game.tick = game.tick + 1
        queue.get_science_counts(1)
        runtime[3].latest_tick = -1000
        entity.get_inventory = function()
            return {get_contents = function()
                return {{name = "automation-science-pack", count = 3}}
            end}
        end
        game.tick = game.tick + 1
        queue.get_science_counts(1)
        reset({
            labs = {make_lab(4, {inventory_contents = {{name = "automation-science-pack", count = 20}}})},
            runtime = {[4] = {latest_tick = 100, latest_contents = {{name = "automation-science-pack", count = 20}}}},
            flow_input = 0,
            flow_output = 5
        })
        local negative = queue.get_science_forecast(1)["automation-science-pack"]
        t.assert_equal(negative.net_per_minute, -5)
        t.assert_true(negative.depletion_seconds ~= nil)
        t.assert_nil(negative.recovery_seconds)
        reset({stats_valid = false})
        t.assert_equal(queue.get_science_forecast(1)["automation-science-pack"].production_per_minute, 0)
        reset({flow_error = true})
        t.assert_equal(queue.get_science_forecast(1)["automation-science-pack"].consumption_per_minute, 0)
        policy_settings.cluster_mode = true
        local clustered = queue.get_science_availability(1)
        t.assert_true(clustered.__cluster_mode)
        t.assert_true(clustered.__clusters ~= nil)
    end},
    {"caches cargo-pod transit totals across science forecast entries", function()
        local current = make_current()
        local cargo_scans = 0
        local pod = {
            valid = true,
            get_inventory = function(index)
                t.assert_equal(index, defines.inventory.cargo_unit)
                return {
                    get_contents = function()
                        return {
                            {name = "automation-science-pack", count = 11},
                            {name = "logistic-science-pack", count = 13}
                        }
                    end
                }
            end
        }

        reset({current = current, labs = {make_lab(80)}})
        defines.inventory.cargo_unit = 2
        game.surfaces = {
            [1] = {
                valid = true,
                index = 1,
                name = "nauvis",
                find_entities_filtered = function(filters)
                    if filters and filters.type == "cargo-pod" then
                        cargo_scans = cargo_scans + 1
                        return {pod}
                    end
                    return {}
                end
            }
        }

        local forecast = queue.get_science_forecast(1)
        t.assert_equal(forecast["automation-science-pack"].in_transit, 11)
        t.assert_equal(forecast["logistic-science-pack"].in_transit, 13)
        t.assert_equal(cargo_scans, 1)

        game.tick = game.tick + 1
        queue.get_science_forecast(1)
        t.assert_equal(cargo_scans, 1)
    end},
    {"orders science networks and direct clusters deterministically on ties", function()
        local first_network = make_network(21, {['automation-science-pack'] = 1})
        local second_network = make_network(22, {['automation-science-pack'] = 1})
        local first = make_lab(101, {network = first_network})
        local second = make_lab(102, {network = second_network})
        reset({labs = {second, first}, runtime = {
            [101] = {latest_tick = 100, latest_contents = {}},
            [102] = {latest_tick = 100, latest_contents = {}}
        }})
        local clusters = queue.get_science_clusters(1)
        t.assert_true(clusters["1:network:21"] ~= nil)
        t.assert_true(clusters["1:network:22"] ~= nil)
        local breakdown = queue.get_science_count_breakdown(1, "automation-science-pack")
        t.assert_equal(#breakdown.networks, 2)

        local direct_one = make_lab(103)
        local direct_two = make_lab(104)
        direct_two.surface = {valid = true, index = 2, name = "Fulgora"}
        direct_one.force.find_logistic_network_by_position = function() return nil end
        direct_two.force.find_logistic_network_by_position = function() return nil end
        reset({current = make_current(), labs = {direct_two, direct_one}, runtime = {
            [103] = {latest_tick = 100, latest_contents = {}},
            [104] = {latest_tick = 100, latest_contents = {}}
        }})
        local direct_clusters = queue.get_science_clusters(1)
        t.assert_true(direct_clusters["1:lab:103"] ~= nil)
        t.assert_true(direct_clusters["2:lab:104"] ~= nil)
        local diagnostic = queue.get_research_diagnostic(1)
        t.assert_equal(#diagnostic.clusters, 2)
    end},
    {"reports science packs that cannot be supplied together", function()
        local automation_network = make_network(31, {['automation-science-pack'] = 50})
        local logistic_network = make_network(32, {['logistic-science-pack'] = 50})
        local automation_lab = make_lab(111, {network = automation_network,
            lab_inputs = {"automation-science-pack"}})
        local logistic_lab = make_lab(112, {network = logistic_network,
            lab_inputs = {"logistic-science-pack"}})
        reset({policy_settings = {cluster_mode = true}, labs = {automation_lab, logistic_lab}, runtime = {
            [111] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}},
            [112] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }})
        t.assert_true(finish_health_snapshot())
        local xcur = {
            available = true,
            queued = false,
            blocked_by = {},
            disabled_by = {},
            meta = {sciences = {"automation-science-pack", "logistic-science-pack"},
                all_prerequisites = {}, hidden = false, has_trigger = false, is_infinite = false,
                prototype = {}},
            technology = {name = "split-science", researched = false, enabled = true, level = 1,
                research_unit_count = 100, research_unit_ingredients = {}}
        }
        tech_state = {['split-science'] = xcur}
        storage.forces[1].queue.queue = {"split-science"}
        local entries = queue.get_upcoming_research_display(1, 1)
        t.assert_equal(entries[1].availability_reason, "science_not_together")
    end},
    {"classifies diagnostic causes and caches the result", function()
        reset()
        t.assert_equal(queue.get_research_diagnostic(1).state, "idle")
        t.assert_equal(queue.get_research_diagnostic(99).state, "idle")
        t.assert_equal(#queue.get_science_forecast(99), 0)
        t.assert_equal(queue.get_research_display_diagnostic(1).state, "idle")
        t.assert_equal(queue.get_research_display_diagnostic(99).state, "idle")
        local current = make_current()
        local missing = make_lab(5, {status = statuses.missing_science_packs, inventory_contents = {}})
        local power = make_lab(6, {status = statuses.no_power, drain_rate = 50,
            uses_quality_drain_modifier = true, quality = {science_pack_drain_multiplier = 0.5}, inventory_contents = {
            {name = "automation-science-pack", count = 1},
            {name = "logistic-science-pack", count = 1}
        }})
        local incompatible = make_lab(7, {
            prototype_name = "incompatible",
            lab_inputs = {"automation-science-pack"},
            inventory_contents = {}
        })
        reset({
            current = current,
            labs = {missing, power, incompatible},
            runtime = {
                [5] = {latest_tick = 100, latest_status = statuses.missing_science_packs, latest_contents = {}},
                [6] = {latest_tick = 100, latest_status = statuses.no_power, latest_contents = {
                    {name = "automation-science-pack", count = 1},
                    {name = "logistic-science-pack", count = 1}
                }},
                [7] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
            }
        })
        local diagnostic = queue.get_research_diagnostic(1)
        t.assert_equal(diagnostic.current_technology, "research")
        t.assert_equal(diagnostic.total_labs, 3)
        t.assert_equal(diagnostic.compatible_labs, 2)
        t.assert_equal(diagnostic.incompatible_labs, 1)
        t.assert_equal(diagnostic.state, "pack_bound")
        t.assert_equal(diagnostic.dominant_cause.kind, "missing_science")
        t.assert_equal(diagnostic.dominant_missing_science.science, "automation-science-pack")
        t.assert_true(diagnostic.dominant_cluster_key ~= nil)
        local missing_descriptor
        local incompatible_descriptor
        for _, cluster in ipairs(diagnostic.clusters) do
            for _, descriptor in ipairs(cluster.lab_descriptors or {}) do
                if descriptor.unit_number == 5 then
                    missing_descriptor = descriptor
                elseif descriptor.unit_number == 7 then
                    incompatible_descriptor = descriptor
                end
            end
        end
        t.assert_true(missing_descriptor ~= nil)
        t.assert_equal(missing_descriptor.status_key, "missing_science")
        t.assert_equal(missing_descriptor.missing_sciences[1], "automation-science-pack")
        t.assert_true(incompatible_descriptor ~= nil)
        t.assert_equal(incompatible_descriptor.status_key, "incompatible")
        t.assert_equal(queue.get_research_diagnostic(1), diagnostic)
        game.tick = game.tick + 1
        reset({current = current, labs = {}, runtime = {}, tick = game.tick})
        local no_labs = queue.get_research_diagnostic(1)
        t.assert_equal(no_labs.state, "operational_fault")
        t.assert_equal(no_labs.dominant_cause.kind, "no_labs")

        local incompatible_only = make_lab(9, {
            prototype_name = "incompatible-only",
            lab_inputs = {"automation-science-pack"}
        })
        reset({current = current, labs = {incompatible_only}, runtime = {
            [9] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }, tick = game.tick + 1})
        local no_compatible = queue.get_research_diagnostic(1)
        t.assert_equal(no_compatible.dominant_cause.kind, "no_compatible_labs")
    end},
    {"handles no capacity, status causes, and healthy diagnostic states", function()
        local current = make_current()
        local zero = make_lab(8, {status = statuses.working})
        reset({current = make_current({research_unit_energy = 0}), labs = {zero}, runtime = {
            [8] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }})
        local no_capacity = queue.get_research_diagnostic(1)
        t.assert_equal(no_capacity.state, "operational_fault")
        t.assert_equal(no_capacity.dominant_cause.kind, "no_capacity")

        for _, status in ipairs({statuses.frozen, statuses.disabled, statuses.no_research_in_progress, 99}) do
            local entity = make_lab(20 + status, {status = status, frozen = status == statuses.frozen,
                inventory_contents = {{name = "automation-science-pack", count = 1},
                    {name = "logistic-science-pack", count = 1}}})
            reset({current = current, labs = {entity}, runtime = {
                [entity.unit_number] = {latest_tick = 100, latest_status = status,
                    latest_contents = {{name = "automation-science-pack", count = 1},
                        {name = "logistic-science-pack", count = 1}}}
            }, tick = 100 + status})
            local diagnostic = queue.get_research_diagnostic(1)
            t.assert_equal(diagnostic.state, "operational_fault")
            t.assert_equal(#diagnostic.causes, 1)
        end

        local healthy = make_lab(40, {status = statuses.working, inventory_contents = {
            {name = "automation-science-pack", count = 1},
            {name = "logistic-science-pack", count = 1}
        }})
        reset({current = current, labs = {healthy}, runtime = {
            [40] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {
                {name = "automation-science-pack", count = 1},
                {name = "logistic-science-pack", count = 1}
            }}
        }, tick = 200})
        local measuring = queue.get_research_diagnostic(1)
        t.assert_equal(measuring.state, "measuring")
        storage.forces[1].queue.speed_samples = {}
        for i = 1, 20 do
            storage.forces[1].queue.speed_samples[i] = {tick = 200 - (i - 1) * 180, tech_name = "research", speed = 60,
                valid_speed = true}
        end
        game.tick = 201
        queue.invalidate_science_cache(1)
        local at_capacity = queue.get_research_diagnostic(1)
        t.assert_true(at_capacity.sampling_ready)
        t.assert_equal(at_capacity.state, "at_capacity")

        local degraded_lab = make_lab(41, {status = statuses.working})
        reset({current = current, labs = {degraded_lab}, runtime = {
            [41] = {latest_tick = 100, latest_status = statuses.working,
                latest_contents = {{name = "automation-science-pack", count = 1},
                    {name = "logistic-science-pack", count = 1}}}
        }, tick = 300})
        storage.forces[1].queue.speed_samples = {}
        for i = 1, 20 do
            storage.forces[1].queue.speed_samples[i] = {
                tick = 300 - (i - 1) * 180, tech_name = "research", speed = 0.1, valid_speed = true
            }
        end
        game.tick = 301
        local degraded = queue.get_research_diagnostic(1)
        t.assert_equal(degraded.state, "degraded_unexplained")

        local tie_network_a = make_network(91, {})
        local tie_network_b = make_network(92, {})
        local tie_lab_a = make_lab(42, {network = tie_network_a, status = statuses.no_power,
            inventory_contents = {{name = "automation-science-pack", count = 1},
                {name = "logistic-science-pack", count = 0}}})
        local tie_lab_b = make_lab(43, {network = tie_network_b, status = statuses.no_power,
            inventory_contents = {{name = "automation-science-pack", count = 0},
                {name = "logistic-science-pack", count = 1}}})
        reset({current = current, labs = {tie_lab_b, tie_lab_a}, runtime = {
            [42] = {latest_tick = 100, latest_status = statuses.no_power,
                latest_contents = {{name = "automation-science-pack", count = 1}}},
            [43] = {latest_tick = 100, latest_status = statuses.no_power,
                latest_contents = {{name = "logistic-science-pack", count = 1}}}
        }, tick = 400})
        local tied_clusters = queue.get_research_diagnostic(1)
        t.assert_equal(#tied_clusters.clusters, 2)
        t.assert_true(tied_clusters.dominant_cluster_key ~= nil)

        tie_lab_b.speed_bonus = 1
        game.tick = 401
        queue.invalidate_science_cache(1)
        local ordered_clusters = queue.get_research_diagnostic(1)
        t.assert_equal(#ordered_clusters.clusters, 2)
    end},
    {"runs the staged health snapshot through labs, networks, availability, forecast, and display APIs", function()
        local network = make_network(11, {['automation-science-pack'] = 50, ['logistic-science-pack'] = 50})
        local entity = make_lab(50, {network = network, status = statuses.working,
            inventory_contents = {{name = "automation-science-pack", count = 2},
                {name = "logistic-science-pack", count = 2}}})
        reset({current = make_current(), labs = {entity}, runtime = {
            [50] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {
                {name = "automation-science-pack", count = 2},
                {name = "logistic-science-pack", count = 2}
            }}
        }})
        storage.forces[1].queue.speed_samples = {}
        for index = 1, 20 do
            storage.forces[1].queue.speed_samples[index] = {
                tick = 100 - index,
                tech_name = "research",
                speed = index <= 5 and 0.5 or 1,
                valid_speed = true
            }
        end
        t.assert_true(finish_health_snapshot())
        local counts = queue.get_science_display_counts(1)
        t.assert_equal(counts["automation-science-pack"], 52)
        t.assert_equal(queue.get_research_health_snapshot_tick(1), game.tick)
        t.assert_equal(queue.get_science_display_breakdown(1, "automation-science-pack").network_total, 50)
        t.assert_equal(queue.get_science_display_breakdown(1, "not-present").lab_count, 0)
        t.assert_true(queue.get_science_display_forecast(1)["automation-science-pack"] ~= nil)
        local first_health = queue.get_research_display_diagnostic(1)
        t.assert_equal(first_health.current_technology, "research")
        t.assert_equal(first_health.state, "degraded_unexplained")
        t.assert_true(first_health.recent_spm ~= nil)
        t.assert_true(first_health.previous_spm ~= nil)
        local depletion_lab = make_lab(53, {inventory_contents = {
            {name = "automation-science-pack", count = 20},
            {name = "logistic-science-pack", count = 20}
        }})
        reset({current = make_current(), labs = {depletion_lab}, runtime = {
            [53] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {
                {name = "automation-science-pack", count = 20},
                {name = "logistic-science-pack", count = 20}
            }}
        }, flow_input = 0, flow_output = 5, tick = 300})
        t.assert_true(finish_health_snapshot())
        t.assert_true(queue.get_science_display_forecast(1)["automation-science-pack"].depletion_seconds ~= nil)
        local recovery_lab = make_lab(54, {inventory_contents = {}})
        reset({current = make_current(), labs = {recovery_lab}, runtime = {
            [54] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }, flow_input = 5, flow_output = 0, tick = 400})
        t.assert_true(finish_health_snapshot())
        t.assert_true(queue.get_science_display_forecast(1)["automation-science-pack"].recovery_seconds ~= nil)
        local missing = make_lab(51, {status = statuses.missing_science_packs, inventory_contents = {}})
        local incompatible = make_lab(52, {prototype_name = "health-incompatible",
            lab_inputs = {"automation-science-pack"}, inventory_contents = {}})
        reset({current = make_current(), labs = {missing, incompatible}, runtime = {
            [51] = {latest_tick = 100, latest_status = statuses.missing_science_packs, latest_contents = {}},
            [52] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }, policy_settings = {cluster_mode = true}, tick = 200})
        t.assert_true(finish_health_snapshot())
        local health_diagnostic = queue.get_research_display_diagnostic(1)
        t.assert_equal(health_diagnostic.total_labs, 2)
        t.assert_true(health_diagnostic.dominant_cause ~= nil)
        queue.request_research_health_snapshot(1)
        t.assert_false(queue.tick_research_health_snapshot(99))
        t.assert_equal(queue.get_research_health_snapshot_tick(99), -1)
    end},
    {"detects an active missing-science bottleneck only after a complete sample", function()
        local entity = make_lab(60, {status = statuses.missing_science_packs})
        local current = make_current()
        reset({current = current, labs = {entity}, runtime = {
            [60] = {lab = entity, latest_tick = 100, latest_status = statuses.missing_science_packs, latest_contents = {}}
        }})
        local xcur = {technology = {name = "research"}}
        t.assert_nil(queue.get_active_missing_science_bottleneck(1, {technology = {name = "other"}})["automation-science-pack"])
        local bottleneck = queue.get_active_missing_science_bottleneck(1, xcur)
        t.assert_true(bottleneck["automation-science-pack"])
        t.assert_true(bottleneck["logistic-science-pack"])
        t.assert_equal(queue.get_active_missing_science_bottleneck(1, xcur), bottleneck)
        local saved_speed = queue.get_research_speed
        queue.get_research_speed = function() return 0.1, true end
        runtime[60].latest_status = statuses.working
        runtime[60].latest_contents = {
            {name = "automation-science-pack", count = 1},
            {name = "logistic-science-pack", count = 1}
        }
        game.tick = game.tick + 1
        queue.invalidate_science_cache(1)
        t.assert_equal(next(queue.get_active_missing_science_bottleneck(1, xcur)), nil)
        queue.get_research_speed = saved_speed
        runtime[60].latest_tick = -1000
        game.tick = game.tick + 1
        queue.invalidate_science_cache(1)
        t.assert_nil(queue.get_active_missing_science_bottleneck(1, xcur)["automation-science-pack"])
        t.assert_false(queue.science_is_sufficient(nil, 1))
        t.assert_true(queue.science_is_sufficient({meta = {sciences = {}}}, 1))
    end},
    {"classifies staged health faults when no compatible capacity exists", function()
        local current = make_current()
        reset({current = current, labs = {}, runtime = {}})
        t.assert_true(finish_health_snapshot())
        t.assert_equal(queue.get_research_display_diagnostic(1).dominant_cause.kind, "no_labs")

        local incompatible = make_lab(80, {prototype_name = "only-automation",
            lab_inputs = {"automation-science-pack"}})
        reset({current = current, labs = {incompatible}, runtime = {
            [80] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }})
        t.assert_true(finish_health_snapshot())
        t.assert_equal(queue.get_research_display_diagnostic(1).dominant_cause.kind, "no_compatible_labs")

        local no_capacity = make_lab(81)
        reset({current = make_current({research_unit_energy = 0}), labs = {no_capacity}, runtime = {
            [81] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }})
        t.assert_true(finish_health_snapshot())
        t.assert_equal(queue.get_research_display_diagnostic(1).dominant_cause.kind, "no_capacity")
    end},
    {"builds a bounded upcoming display with prerequisites and current research first", function()
        local current = make_current({name = "research"})
        local network = make_network(12, {
            ["automation-science-pack"] = 100,
            ["logistic-science-pack"] = 100
        })
        local entity = make_lab(70, {network = network, inventory_contents = {}})
        reset({current = current, labs = {entity}, runtime = {
            [70] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }})
        local function candidate(name, options)
            options = options or {}
            return {
                available = true,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {
                    sciences = {"automation-science-pack"},
                    all_prerequisites = options.prerequisites or {},
                    hidden = false,
                    has_trigger = false,
                    is_infinite = options.infinite or false,
                    prototype = {effects = options.effects or {}}
                },
                technology = {
                    name = name,
                    researched = false,
                    enabled = true,
                    level = options.level or 1,
                    research_unit_count = options.cost or 100,
                    research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
                }
            }
        end
        tech_state = {
            research = candidate("research", {cost = 100}),
            prerequisite = candidate("prerequisite", {cost = 50}),
            goal = candidate("goal", {cost = 200, prerequisites = {prerequisite = true}})
        }
        storage.forces[1].queue.queue = {"goal", "prerequisite"}
        storage.forces[1].queue.pinned_tech = "goal"
        storage.forces[1].queue.speed_samples = {{speed = 1, valid_speed = true, tech_name = "research"}}
        t.assert_true(finish_health_snapshot())
        queue.request_upcoming_research_display(1, 5)
        local done, entries
        for _ = 1, 30 do
            done, entries = queue.tick_upcoming_research_display(1, 1)
            if done then break end
        end
        t.assert_true(done)
        t.assert_equal(entries[1].tech_name, "research")
        t.assert_equal(entries[2].tech_name, "prerequisite")
        t.assert_equal(entries[3].tech_name, "goal")
        t.assert_true(entries[1].duration ~= nil)
        t.assert_equal(entries[1].wait_time, 0)
        t.assert_true(queue.get_upcoming_research(1, 2)[1] ~= nil)
        t.assert_true(queue.get_upcoming_research_display(1, 5)[1] ~= nil)
        t.assert_equal(queue.tick_upcoming_research_display(1, 1), true)

        -- A one-row request completes directly from the finalize phase, while
        -- the multi-entry request above exercises the available-candidate break
        -- in the incremental entries phase.
        queue.request_upcoming_research_display(1, 1)
        local one_done, one_entries
        for _ = 1, 20 do
            one_done, one_entries = queue.tick_upcoming_research_display(1, 1)
            if one_done then break end
        end
        t.assert_true(one_done)
        t.assert_equal(#one_entries, 1)
    end},
    {"covers virtual preview guards and every repeat-budget mode", function()
        local network = make_network(13, {
            ["automation-science-pack"] = 100,
            ["logistic-science-pack"] = 100
        })
        local entity = make_lab(90, {network = network, inventory_contents = {}})
        local current = make_current({name = "active"})
        reset({current = current, labs = {entity}, runtime = {
            [90] = {latest_tick = 100, latest_status = statuses.working, latest_contents = {}}
        }, research_progress = 0.25})
        local function candidate(name, options)
            options = options or {}
            return {
                available = options.available ~= false,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {
                    sciences = options.sciences or {"automation-science-pack"},
                    all_prerequisites = options.prerequisites or {},
                    hidden = options.hidden or false,
                    has_trigger = options.trigger or false,
                    is_infinite = options.infinite or false,
                    prototype = {
                        effects = options.effects or {},
                        research_unit_count_formula = options.formula
                    }
                },
                technology = {
                    name = name,
                    researched = options.researched or false,
                    enabled = options.enabled ~= false,
                    level = options.level or 1,
                    research_unit_count = options.cost or 100,
                    research_unit_ingredients = options.ingredients or {
                        {name = "automation-science-pack", amount = 1}
                    }
                }
            }
        end
        tech_state = {
            active = candidate("active", {cost = 120}),
            base = candidate("base", {cost = 20}),
            prerequisite = candidate("prerequisite", {cost = 40, prerequisites = {base = true}}),
            goal = candidate("goal", {cost = 180, prerequisites = {prerequisite = true}}),
            blocked = candidate("blocked", {sciences = {"missing-science"}}),
            researched = candidate("researched", {researched = true}),
            hidden = candidate("hidden", {hidden = true}),
            disabled = candidate("disabled", {enabled = false}),
            triggered = candidate("triggered", {trigger = true})
        }
        storage.forces[1].queue.queue = {"goal", "blocked", "hidden", "disabled", "triggered", "prerequisite", "base"}
        storage.forces[1].queue.speed_samples = {{speed = 2, valid_speed = true, tech_name = "active"}}
        local entries = queue.get_upcoming_research(1, 5)
        t.assert_equal(entries[1].tech_name, "active")
        t.assert_true(entries[1].duration ~= nil)
        t.assert_true(#entries >= 3)

        storage.forces[1].queue.speed_samples = nil
        game.tick = game.tick + 1
        queue.invalidate_science_cache(1)
        local no_speed = queue.get_upcoming_research(1, 1)
        t.assert_true(no_speed[1] ~= nil)
        t.assert_nil(no_speed[1].duration)

        reset()
        t.assert_equal(#queue.get_upcoming_research(99, 2), 0)
        tech_state = nil
        t.assert_equal(#queue.get_upcoming_research(1, 2), 0)

        local infinite = candidate("infinite", {
            infinite = true,
            level = 2,
            cost = 200,
            formula = "100(L-1)+50",
            ingredients = {"malformed", {name = "automation-science-pack", amount = 2}}
        })
        tech_state = {infinite = infinite}
        storage.forces[1].queue.queue = {"infinite"}
        repeat_rules.infinite = {mode = "continuous"}
        t.assert_true(queue.get_queue_budget(1, 4).repeat_unbounded)
        repeat_rules.infinite = {mode = "default"}
        t.assert_true(queue.get_queue_budget(1, 4).repeat_unbounded)
        repeat_rules.infinite = {mode = "once", remaining = 2}
        local once = queue.get_queue_budget(1, 4)
        t.assert_equal(once.technology_count, 3)
        repeat_rules.infinite = {mode = "to_level", max_level = 5}
        local to_level = queue.get_queue_budget(1, 4)
        t.assert_equal(to_level.technology_count, 4)
        repeat_rules.infinite = {mode = "once", remaining = 20}
        t.assert_true(queue.get_queue_budget(1, 2).repeat_truncated)

        reset()
        tech_state = {
            researched = candidate("researched", {researched = true}),
            automatic = candidate("automatic", {sciences = {}}),
            ready = candidate("ready", {sciences = {}, prerequisites = {researched = true}})
        }
        storage.forces[1].queue.queue = {}
        policy_settings.strategy = "throughput"
        local automatic = queue.get_upcoming_research(1, 2)
        t.assert_true(automatic[1] ~= nil)
        t.assert_nil(automatic[1].duration)
        storage.forces[1].queue.queue = {"ready", "automatic"}
        local ready = queue.get_upcoming_research(1, 2)
        t.assert_true(#ready >= 1)
        queue.reorder_queue_by_score(1)
        queue.reorder_queue_by_score(1)
        storage.forces[1].queue.queue = {}
        policy_settings.strategy = "focused"
        t.assert_equal(#queue.get_upcoming_research(1, 2), 0)
        policy_settings.strategy = "throughput"
        policy_settings.auto_research = false
        t.assert_equal(#queue.get_upcoming_research(1, 2), 0)
    end},
    {"waits for a health snapshot before finalizing blocked upcoming entries", function()
        reset({current = make_current({name = "research"})})
        local force_two = {
            index = 2,
            current_research = make_current({name = "research"}),
            research_progress = 0,
            technologies = {},
            research_queue = {},
            get_item_production_statistics = function()
                return {
                    valid = true,
                    get_flow_count = function() return 0 end
                }
            end
        }
        game.forces[2] = force_two
        storage.forces[2] = {queue = {}}
        local function candidate(name)
            return {
                available = true,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {
                    sciences = {"automation-science-pack"},
                    all_prerequisites = {},
                    hidden = false,
                    has_trigger = false,
                    is_infinite = false,
                    prototype = {effects = {}}
                },
                technology = {
                    name = name,
                    researched = false,
                    enabled = true,
                    level = 1,
                    research_unit_count = 100,
                    research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
                }
            }
        end
        tech_state = {blocked = candidate("blocked")}
        storage.forces[2].queue.queue = {"blocked"}
        queue.request_upcoming_research_display(2, 1)
        queue.tick_upcoming_research_display(2, 1)
        queue.tick_upcoming_research_display(2, 1)
        queue.tick_upcoming_research_display(2, 1)
        queue.tick_upcoming_research_display(2, 1)
        local waiting = queue.tick_upcoming_research_display(2, 1)
        t.assert_false(waiting)
        queue.request_research_health_snapshot(2)
        local health_done = false
        for _ = 1, 20 do
            health_done = queue.tick_research_health_snapshot(2)
            if health_done then break end
        end
        t.assert_true(health_done)
        local done, entries
        for _ = 1, 10 do
            done, entries = queue.tick_upcoming_research_display(2, 1)
            if done then break end
        end
        t.assert_true(done)
        t.assert_equal(entries[1].tech_name, "blocked")
        t.assert_false(entries[1].has_science)
    end},
    {"walks upcoming display prerequisites, invalid requests, and blocked candidates", function()
        local function candidate(name, options)
            options = options or {}
            return {
                available = options.available ~= false,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {
                    sciences = options.sciences or {},
                    all_prerequisites = options.prerequisites or {},
                    hidden = false,
                    has_trigger = false,
                    is_infinite = false,
                    prototype = {effects = {}}
                },
                technology = {
                    name = name,
                    researched = false,
                    enabled = true,
                    level = 1,
                    research_unit_count = options.cost or 100,
                    research_unit_ingredients = {}
                }
            }
        end

        reset({current = make_current({name = "current"})})
        tech_state = {
            current = candidate("current"),
            base = candidate("base"),
            middle = candidate("middle", {prerequisites = {base = true}}),
            goal = candidate("goal", {prerequisites = {middle = true}}),
            blocked = candidate("blocked", {sciences = {"missing-science"}}),
            orphan = candidate("orphan", {prerequisites = {absent = true}})
        }
        storage.forces[1].queue.queue = {"missing-name", "blocked", "goal", "orphan", "middle", "base"}
        storage.forces[1].queue.speed_samples = {{speed = 1, valid_speed = true, tech_name = "current"}}
        t.assert_true(finish_health_snapshot())
        queue.request_upcoming_research_display(1, 6)

        local done, entries
        for _ = 1, 40 do
            done, entries = queue.tick_upcoming_research_display(1, 1)
            if done then break end
        end
        t.assert_true(done)
        t.assert_equal(entries[1].tech_name, "current")
        t.assert_true(#entries >= 3)
        t.assert_equal(entries[2].tech_name, "base")
        t.assert_equal(entries[3].tech_name, "middle")
        t.assert_true(entries[#entries].availability_reason == "missing_science" or
            entries[#entries].tech_name == "goal" or entries[#entries].tech_name == "orphan")
    end},
    {"switches temporary research for low supply and higher priority candidates", function()
        local function candidate(name, options)
            options = options or {}
            return {
                available = options.available ~= false,
                queued = options.queued ~= false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {
                    sciences = {"automation-science-pack"},
                    all_prerequisites = {},
                    hidden = false,
                    has_trigger = false,
                    is_infinite = false,
                    prototype = {effects = {}}
                },
                technology = {
                    name = name,
                    researched = false,
                    enabled = true,
                    level = 1,
                    research_unit_count = options.cost or 100,
                    research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
                }
            }
        end
        local original_sufficient = queue.science_is_sufficient
        local original_bottleneck = queue.get_active_missing_science_bottleneck
        local original_availability = queue.get_science_availability
        local sufficient = false
        queue.science_is_sufficient = function() return sufficient end
        queue.get_active_missing_science_bottleneck = function() return {} end
        queue.get_science_availability = function()
            return {['automation-science-pack'] = true}
        end

        local force = reset({current = make_current({name = "current"})})
        local current = candidate("current")
        local alternate = candidate("alternate", {cost = 50})
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"alternate"}
        force.current_research = make_current({name = "current"})
        queue.set_pinned_tech(1, "alternate")
        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, "alternate")
        t.assert_equal(storage.forces[1].queue.target_tech, "current")

        reset({current = make_current({name = "current"})})
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"alternate"}
        force = game.forces[1]
        force.current_research = make_current({name = "current"})
        sufficient = true
        policy_settings.science_priorities = {current = 0, alternate = 3}
        queue.check_and_switch_temp_research(force)
        t.assert_equal(storage.forces[1].queue.temp_tech, "alternate")

        reset({current = make_current({name = "current"})})
        tech_state = {current = current, alternate = alternate}
        storage.forces[1].queue.queue = {"alternate"}
        force = game.forces[1]
        force.current_research = make_current({name = "current"})
        storage.forces[1].queue.target_tech = "current"
        storage.forces[1].queue.temp_tech = "alternate"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        policy_settings.science_priorities = {current = 3, alternate = 0}
        queue.check_and_switch_temp_research(force)
        t.assert_nil(storage.forces[1].queue.temp_tech)
        t.assert_nil(storage.forces[1].queue.temp_tech_timeout)

        storage.forces[1].queue.temp_tech = "alternate"
        storage.forces[1].queue.temp_tech_timeout = game.tick - 1
        storage.forces[1].queue.target_tech = nil
        storage.forces[1].queue.last_switch_tick = nil
        queue.check_and_switch_temp_research(force)
        t.assert_nil(storage.forces[1].queue.temp_tech)

        queue.science_is_sufficient = original_sufficient
        queue.get_active_missing_science_bottleneck = original_bottleneck
        queue.get_science_availability = original_availability
    end},
    {"estimates queue budget costs, unlocks, deficits, and repeat truncation", function()
        local function candidate(name, options)
            options = options or {}
            return {
                available = true,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {
                    sciences = {"automation-science-pack"},
                    all_prerequisites = {},
                    hidden = false,
                    has_trigger = false,
                    is_infinite = options.infinite or false,
                    prototype = {
                        effects = options.effects or {},
                        research_unit_count_formula = options.formula
                    }
                },
                technology = {
                    name = name,
                    researched = false,
                    enabled = true,
                    level = options.level or 1,
                    research_unit_count = options.cost or 100,
                    research_unit_ingredients = {{name = "automation-science-pack", amount = 2}}
                }
            }
        end
        reset({current = make_current({name = "finite"}), research_progress = 0.25,
            flow_input = 4, flow_output = 1})
        tech_state = {
            finite = candidate("finite", {cost = 100, effects = {
                {type = "unlock-recipe"}, {type = "unlock-quality"}
            }}),
            infinite = candidate("infinite", {cost = 200, infinite = true, level = 2, formula = "100(L-1)+50",
                effects = {{type = "unlock-space-location"}}})
        }
        storage.forces[1].queue.queue = {"finite", "infinite"}
        storage.forces[1].queue.speed_samples = {{speed = 1, valid_speed = true}}
        repeat_rules.infinite = {mode = "once", remaining = 2}
        local budget = queue.get_queue_budget(1, 5)
        t.assert_equal(budget.technology_count, 4)
        t.assert_true(budget.total_seconds ~= nil)
        t.assert_equal(budget.unlock_count, 3)
        t.assert_true(budget.sciences["automation-science-pack"].deficit > 0)
        t.assert_equal(budget.limiting_science, "automation-science-pack")
        t.assert_false(budget.repeat_unbounded)
        t.assert_false(budget.repeat_truncated)
        local truncated = queue.get_queue_budget(1, 2)
        t.assert_true(truncated.repeat_truncated)
    end},
    {"builds available and blocked queues while honoring caps, formulas, and strategy guards", function()
        local function candidate(name, options)
            options = options or {}
            return {
                available = options.available ~= false,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {
                    sciences = options.sciences or {},
                    hidden = options.hidden or false,
                    has_trigger = false,
                    is_infinite = options.infinite or false,
                    research_effects = {},
                    prototype = {research_unit_count_formula = options.formula, effects = {}}
                },
                technology = {
                    name = name,
                    researched = options.researched or false,
                    enabled = options.enabled ~= false,
                    level = options.level or 1,
                    research_unit_count = options.cost or 100,
                    research_unit_ingredients = {{name = "automation-science-pack", amount = 1}}
                }
            }
        end
        reset()
        research_weights.research_caps.capped = 1
        tech_state = {
            available = candidate("available", {cost = 100}),
            blocked = candidate("blocked", {sciences = {"automation-science-pack"}}),
            researched = candidate("researched", {researched = true}),
            disabled = candidate("disabled", {enabled = false}),
            hidden = candidate("hidden", {hidden = true}),
            capped = candidate("capped", {infinite = true, level = 1}),
            formula = candidate("formula", {infinite = true, level = 2, formula = "100(L-1)+50"})
        }
        storage.forces[1].queue.tech_enabled = {disabled = false}
        queue.build_queue_from_available(1)
        t.assert_equal(queue.get_queue(1)[1], "available")
        t.assert_equal(queue.get_queue(1)[2], "formula")
        t.assert_equal(queue.get_queue(1)[3], "blocked")
        t.assert_true(queued_updates.available)
        t.assert_true(queued_updates.formula)
        t.assert_true(queued_updates.blocked)
        queue.init_force(1)
        t.assert_true(queued_updates.available)
        policy_settings.strategy = "focused"
        storage.forces[1].queue.queue = {"keep"}
        queue.build_queue_from_available(1)
        t.assert_equal(queue.get_queue(1)[1], "keep")
        queue.build_queue_from_available(99)
    end},
    {"rotates parallel candidates and honors pause, master, and integration guards", function()
        local function candidate(name)
            return {
                available = true,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {sciences = {}, all_prerequisites = {}, hidden = false, has_trigger = false,
                    prototype = {}, research_effects = {}},
                technology = {name = name, researched = false, enabled = true, level = 1,
                    research_unit_count = 100, research_unit_ingredients = {}}
            }
        end
        local force = reset({policy_settings = {parallel_research = true, parallel_slots = 2}})
        tech_state = {a = candidate("a"), b = candidate("b")}
        storage.forces[1].queue.queue = {"a", "b"}
        queue.rotate_parallel_research(force)
        t.assert_equal(storage.forces[1].queue.current_tech, "a")
        t.assert_equal(force.research_queue[1], "a")
        queue.rotate_parallel_research(force)
        t.assert_equal(storage.forces[1].queue.current_tech, "b")
        t.assert_equal(force.research_queue[1], "b")
        policy_settings.parallel_mod = true
        queue.rotate_parallel_research(force)
        t.assert_equal(force.research_queue[1], "a")
        policy_settings.parallel_mod = false
        queue.reorder_queue_by_score(1)
        t.assert_true(force.research_queue[1] ~= nil)
        policy_settings.planning_paused = true
        local before = force.research_queue[1]
        queue.rotate_parallel_research(force)
        t.assert_equal(force.research_queue[1], before)
        policy_settings.planning_paused = false
        policy_settings.master_enable = "left"
        queue.rotate_parallel_research(force)
        t.assert_equal(force.research_queue[1], before)
        policy_settings.master_enable = "right"
        policy_settings.parallel_research = false
        queue.rotate_parallel_research(force)
        t.assert_equal(force.research_queue[1], before)
    end},
    {"covers upcoming job guards, auto-source collection, and invalid candidates", function()
        reset()
        t.assert_equal(queue.tick_upcoming_research_display(1, 1), true)
        queue.request_upcoming_research_display(99, 1)
        t.assert_equal(queue.tick_upcoming_research_display(99, 1), true)
        queue.request_upcoming_research_display(1, 1)
        tech_state = nil
        t.assert_equal(queue.tick_upcoming_research_display(1, 1), true)

        reset({policy_settings = {strategy = "focused"}})
        queue.request_upcoming_research_display(1, 1)
        t.assert_false(queue.tick_upcoming_research_display(1, 1))
        reset()
        local function candidate(name, researched)
            return {
                available = true,
                queued = false,
                inherited_by = {},
                blocked_by = {},
                disabled_by = {},
                meta = {sciences = {}, all_prerequisites = {}, hidden = false, has_trigger = false,
                    prototype = {}, research_effects = {}},
                technology = {name = name, researched = researched or false, enabled = true, level = 1,
                    research_unit_count = 100, research_unit_ingredients = {}}
            }
        end
        tech_state = {researched = candidate("researched", true), live = candidate("live")}
        storage.forces[1].queue.queue = {}
        queue.request_upcoming_research_display(1, 2)
        t.assert_false(queue.tick_upcoming_research_display(1, 1))
        t.assert_false(queue.tick_upcoming_research_display(1, 1))
        queue.request_upcoming_research_display(1, 1)
        storage.forces[1].queue.queue = {"live", "live", "missing"}
        t.assert_false(queue.tick_upcoming_research_display(1, 1))
        t.assert_false(queue.tick_upcoming_research_display(1, 1))
        t.assert_false(queue.tick_upcoming_research_display(1, 1))
    end},
    {"rejects malformed plan fields and handles missing runtime queue state", function()
        reset({technologies = {a = {valid = true, researched = false}}})
        helpers = {
            decode_string = function() return "json" end,
            json_to_table = function() return {version = 1, queue = {}, tech_enabled = "bad", tech_ub = {}, policy = {}} end
        }
        local _, enabled_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(enabled_reason, "invalid-tech-enabled")
        helpers.json_to_table = function() return {version = 1, queue = {}, tech_enabled = {}, tech_ub = "bad", policy = {}} end
        local _, priority_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(priority_reason, "invalid-tech-priority")
        helpers.json_to_table = function() return {version = 1, queue = {}, tech_enabled = {}, tech_ub = {}, policy = {}} end
        sanitize_valid = false
        local _, policy_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(policy_reason, "invalid-policy")
        sanitize_valid = true
        storage.forces[1].queue = nil
        local _, force_reason = queue.import_plan(1, "LE1:encoded")
        t.assert_equal(force_reason, "invalid-force")
        helpers = nil
        storage.forces[1].queue = {}
        t.assert_nil(queue.get_tech_order(1))
        queue.move_tech_up(1, "a")
        queue.move_tech_down(1, "a")
        t.assert_true(queue.get_tech_enabled(1, "a"))
        t.assert_equal(queue.get_tech_ub(1, "a"), 0)
        queue.set_tech_enabled(1, "a", false)
        queue.adjust_tech_ub(1, "a", 2)
        t.assert_equal(queue.get_tech_enabled(1, "a"), false)
        t.assert_equal(queue.get_tech_ub(1, "a"), 2)
        storage.forces[1].queue.tech_custom_order = {"a", "b"}
        queue.move_tech_down(1, "a")
        queue.move_tech_up(1, "a")
        t.assert_equal(storage.forces[1].queue.tech_custom_order[1], "a")
        storage.forces[1].queue = nil
        queue.set_tech_enabled(1, "a", true)
        queue.adjust_tech_ub(1, "a", 1)
    end},
    {"stages availability across more clusters than one scheduler slice", function()
        local many_labs = {}
        local many_runtime = {}
        for index = 1, 33 do
            local entity = make_lab(200 + index, {
                network = make_network(200 + index, {['automation-science-pack'] = 0,
                    ['logistic-science-pack'] = 0}),
                inventory_contents = {}
            })
            if index == 33 then
                entity.surface = {valid = true, index = 2, name = "fulgora"}
            end
            table.insert(many_labs, entity)
            many_runtime[entity.unit_number] = {
                latest_tick = 100, latest_status = statuses.working, latest_contents = {}
            }
        end
        reset({current = make_current(), labs = many_labs, runtime = many_runtime,
            policy_settings = {cluster_mode = true}})
        t.assert_true(finish_health_snapshot())
        local snapshot = queue.get_science_display_counts(1)
        t.assert_true(snapshot ~= nil)
    end},
    {"covers every staged display diagnostic state and cluster tie-breaker", function()
        reset({current = make_current()})
        local new_display = find_private(queue.tick_research_health_snapshot, "new_display_diagnostic")
        local finish_display = find_private(queue.tick_research_health_snapshot, "finish_display_diagnostic")
        t.assert_true(type(new_display) == "function")
        t.assert_true(type(finish_display) == "function")

        local idle = new_display(1, nil)
        t.assert_equal(finish_display(idle).state, "idle")

        local function context_with(result)
            local context = new_display(1, make_current())
            for key, value in pairs(result) do
                context.result[key] = value
            end
            return context
        end

        local no_labs = context_with({expected_spm = 0, total_labs = 0, compatible_labs = 0})
        t.assert_equal(finish_display(no_labs).dominant_cause.kind, "no_labs")
        local no_compatible = context_with({expected_spm = 0, total_labs = 1, compatible_labs = 0})
        t.assert_equal(finish_display(no_compatible).dominant_cause.kind, "no_compatible_labs")
        local no_capacity = context_with({expected_spm = 0, total_labs = 1, compatible_labs = 1})
        t.assert_equal(finish_display(no_capacity).dominant_cause.kind, "no_capacity")

        local missing = context_with({expected_spm = 100, total_labs = 1, compatible_labs = 1,
            actual_spm = 0, sampling_ready = true})
        missing.cause_data = {missing_science = {kind = "missing_science", labs = 1, lost_spm = 100}}
        missing.missing_sciences = {
            automation = {science = "automation-science-pack", labs = 1, missing_per_minute = 2, lost_spm = 100}
        }
        missing.clusters = {
            one = {key = "one", lost_spm = 100, surface_name = "nauvis",
                causes = {{kind = "missing_science", lost_spm = 100}},
                missing_sciences = {{science = "automation-science-pack", lost_spm = 100}}}
        }
        t.assert_equal(finish_display(missing).state, "pack_bound")

        local operational = context_with({expected_spm = 100, total_labs = 1, compatible_labs = 1,
            actual_spm = 0, sampling_ready = true})
        operational.cause_data = {power = {kind = "power", labs = 1, lost_spm = 100}}
        operational.clusters = {
            first = {key = "first", lost_spm = 100, surface_name = "nauvis",
                causes = {{kind = "power", lost_spm = 100}}, missing_sciences = {}}
        }
        t.assert_equal(finish_display(operational).state, "operational_fault")

        local measuring = context_with({expected_spm = 100, total_labs = 1, compatible_labs = 1,
            actual_spm = 10, sampling_ready = false})
        t.assert_equal(finish_display(measuring).state, "measuring")
        local capacity = context_with({expected_spm = 100, total_labs = 1, compatible_labs = 1,
            actual_spm = 100, sampling_ready = true})
        t.assert_equal(finish_display(capacity).state, "at_capacity")
        local degraded = context_with({expected_spm = 100, total_labs = 1, compatible_labs = 1,
            actual_spm = 10, sampling_ready = true})
        t.assert_equal(finish_display(degraded).state, "degraded_unexplained")

        local ties = context_with({expected_spm = 100, total_labs = 2, compatible_labs = 2,
            actual_spm = 0, sampling_ready = true})
        ties.clusters = {
            first = {key = "first", lost_spm = 20, surface_name = "nauvis", causes = {}, missing_sciences = {}},
            second = {key = "second", lost_spm = 20, surface_name = "nauvis", causes = {}, missing_sciences = {}},
            other = {key = "other", lost_spm = 10, surface_name = "fulgora", causes = {}, missing_sciences = {}}
        }
        t.assert_equal(#finish_display(ties).clusters, 3)
    end},
    {"covers defensive guards in staged health workers", function()
        local current = make_current()
        reset({current = current})
        local process_display = find_private(queue.tick_research_health_snapshot,
            "process_display_diagnostic_observation")
        local process_lab = find_private(queue.tick_research_health_snapshot, "process_research_health_lab")
        local process_network = find_private(queue.tick_research_health_snapshot, "process_research_health_network")
        local process_forecast = find_private(queue.tick_research_health_snapshot, "process_research_health_forecast")
        local process_availability = find_private(queue.tick_research_health_snapshot,
            "process_research_health_availability")
        local new_job = find_private(queue.tick_research_health_snapshot, "new_research_health_job")
        local sort_loss = find_private(queue.get_research_diagnostic, "sort_loss_evidence")
        t.assert_true(type(process_display) == "function")
        t.assert_true(type(process_lab) == "function")
        t.assert_true(type(process_network) == "function")
        t.assert_true(type(process_forecast) == "function")
        t.assert_true(type(process_availability) == "function")
        t.assert_true(type(sort_loss) == "function")
        local loss_items = {{kind = "small", lost_spm = 1}, {kind = "large", lost_spm = 2}}
        sort_loss(loss_items, "kind")
        t.assert_equal(loss_items[1].kind, "large")

        local context = find_private(queue.tick_research_health_snapshot, "new_display_diagnostic")(1, current)
        process_display(context, current, {entity = nil}, nil)
        process_lab({force_index = 1}, {entity = nil})
        process_network({all_sciences = {}}, {network = nil})
        process_forecast({force_index = 99, lab_input_counts = {}, counts = {}, forecast = {}}, "pack")
        process_availability({force_index = 1, all_sciences = {}, availability_index = 1,
            cluster_mode = true, active_science_cluster_keys = {}})

        t.assert_true(finish_health_snapshot())
        t.assert_false(queue.tick_research_health_snapshot(1))
        local display_context = new_job(1)
        t.assert_true(display_context ~= nil)
    end},
    {"builds a lazy science-pack insight with Nauvis labs, planet stock, and transit", function()
        local current = make_current()
        local scan_counts = {nauvis = 0, vulcanus = 0}
        local make_surface = function(index, name, stock)
            return {
                valid = true,
                index = index,
                name = name,
                planet = {name = name},
                find_entities_filtered = function(filters)
                    scan_counts[name] = scan_counts[name] + 1
                    if filters and filters.type == "cargo-pod" then
                        return {}
                    end
                    if stock <= 0 then
                        return {}
                    end
                    return {{
                        valid = true,
                        get_item_count = function() return stock end
                    }}
                end
            }
        end

        reset({current = current, tick = 100, labs = {make_lab(70)}})
        local nauvis = make_surface(1, "nauvis", 37)
        local vulcanus = make_surface(2, "vulcanus", 0)
        game.surfaces = {[1] = nauvis, [2] = vulcanus}
        game.planets = {
            nauvis = {name = "nauvis", surface = nauvis},
            vulcanus = {name = "vulcanus", surface = vulcanus}
        }
        local force = game.forces[1]
        force.platforms = {
            platform_1 = {
                valid = true,
                name = "platform-1",
                hub = {
                    valid = true,
                    get_item_count = function() return 12 end
                },
                space_connection = {
                    from = {name = "nauvis"},
                    to = {name = "vulcanus"}
                },
                distance = 0.25,
                speed = 1
            }
        }

        t.assert_true(finish_health_snapshot())
        t.assert_equal(scan_counts.nauvis, 1)
        t.assert_equal(scan_counts.vulcanus, 1)

        local insight = queue.get_science_pack_insight(1, "automation-science-pack")
        t.assert_equal(insight.labs.surface_name, "nauvis")
        t.assert_true(#insight.labs.clusters >= 1)
        for _, cluster in ipairs(insight.labs.clusters) do
            t.assert_equal(cluster.surface_name, "nauvis")
        end
        t.assert_equal(insight.planet_stock.nauvis, 37)
        t.assert_equal(insight.planet_stock.vulcanus, 0)
        t.assert_equal(#insight.planet_stock_rows, 1,
                       "planet stock rows must omit zero-stock planets")
        t.assert_equal(insight.planet_stock_rows[1].name, "nauvis")
        t.assert_equal(insight.in_transit.total, 12)
        t.assert_equal(insight.in_transit.routes[1].platform, "platform-1")
        t.assert_equal(insight.next_refresh_tick, 400)
        t.assert_true(scan_counts.nauvis > 0)
        t.assert_true(scan_counts.vulcanus > 0)

        local scans_after_first = scan_counts.nauvis
        local cached = queue.get_science_pack_insight(1, "automation-science-pack")
        t.assert_equal(cached, insight)
        t.assert_equal(scan_counts.nauvis, scans_after_first)
        game.tick = 400
        local refreshed = queue.get_science_pack_insight(1, "automation-science-pack")
        t.assert_true(refreshed ~= insight)
        t.assert_true(scan_counts.nauvis > 1)
    end},
    {"excludes drawing-board and cargo-flow pseudo planets from planet stock", function()
        local current = make_current()
        local make_surface = function(index, name, stock)
            return {
                valid = true,
                index = index,
                name = name,
                planet = {name = name},
                find_entities_filtered = function(filters)
                    if filters and filters.type == "cargo-pod" then
                        return {}
                    end
                    if stock <= 0 then
                        return {}
                    end
                    return {{
                        valid = true,
                        get_item_count = function() return stock end
                    }}
                end
            }
        end

        reset({current = current, tick = 100, labs = {make_lab(70)}})
        local nauvis = make_surface(1, "nauvis", 50)
        local drawing_board = make_surface(2, "drawing-board_player", 99)
        local graveyard = make_surface(3, "space-platform-graveyard", 99)
        local cargo_flow = make_surface(4, "cargo-flow-12345", 99)
        local unresolved = make_surface(5, "surface-without-planet", 99)
        unresolved.planet = nil
        game.surfaces = {
            [1] = nauvis, [2] = drawing_board, [3] = graveyard, [4] = cargo_flow,
            [5] = unresolved
        }
        game.planets = {
            nauvis = {name = "nauvis", surface = nauvis},
            ["drawing-board_player"] = {name = "drawing-board_player", surface = drawing_board},
            ["space-platform-graveyard"] = {name = "space-platform-graveyard", surface = graveyard},
            ["cargo-flow-12345"] = {name = "cargo-flow-12345", surface = cargo_flow}
        }

        t.assert_true(finish_health_snapshot())
        local insight = queue.get_science_pack_insight(1, "automation-science-pack")
        local names = {}
        for _, row in ipairs(insight.planet_stock_rows) do
            table.insert(names, row.name)
        end
        t.assert_equal(#names, 1, "only Nauvis must appear; pseudo planets must be excluded")
        t.assert_equal(names[1], "nauvis")
        t.assert_equal(insight.planet_stock.nauvis, 50)
        t.assert_nil(insight.planet_stock["drawing-board_player"],
                     "drawing-board_player must not appear in planet stock")
        t.assert_nil(insight.planet_stock["space-platform-graveyard"],
                     "space-platform-graveyard must not appear in planet stock")
        t.assert_nil(insight.planet_stock["cargo-flow-12345"],
                     "cargo-flow-* must not appear in planet stock")
        t.assert_nil(insight.planet_stock["surface-without-planet"],
                     "surfaces without a real planet must not appear in planet stock")
    end},
    {"omits transit routes with unresolved destinations", function()
        local current = make_current()
        reset({current = current, tick = 100, labs = {make_lab(70)}})
        game.surfaces = {[1] = {valid = true, index = 1, name = "nauvis",
            find_entities_filtered = function() return {} end}}
        game.planets = {nauvis = {name = "nauvis", surface = game.surfaces[1]}}
        local force = game.forces[1]
        force.platforms = {
            platform_good = {
                valid = true,
                name = "platform-good",
                hub = {valid = true, get_item_count = function() return 10 end},
                space_connection = {
                    from = {name = "nauvis"},
                    to = {name = "vulcanus"}
                },
                distance = 0.5
            },
            platform_unknown_from = {
                valid = true,
                name = "platform-unknown-from",
                hub = {valid = true, get_item_count = function() return 20 end},
                space_connection = {
                    from = {},
                    to = {name = "vulcanus"}
                },
                distance = 0.3
            },
            platform_unknown_to = {
                valid = true,
                name = "platform-unknown-to",
                hub = {valid = true, get_item_count = function() return 30 end},
                space_connection = {
                    from = {name = "nauvis"},
                    to = {}
                },
                distance = 0.7
            },
            platform_named_unknown = {
                valid = true,
                name = "platform-named-unknown",
                hub = {valid = true, get_item_count = function() return 40 end},
                space_connection = {
                    from = {name = "unknown"},
                    to = {name = "vulcanus"}
                },
                distance = 0.8
            }
        }

        t.assert_true(finish_health_snapshot())
        local insight = queue.get_science_pack_insight(1, "automation-science-pack")
        t.assert_equal(insight.in_transit.total, 10,
                       "only the resolved route must contribute to transit total")
        t.assert_equal(#insight.in_transit.routes, 1,
                       "unresolved routes must be omitted")
        t.assert_equal(insight.in_transit.routes[1].platform, "platform-good")
        t.assert_equal(insight.in_transit.routes[1].from, "nauvis")
        t.assert_equal(insight.in_transit.routes[1].to, "vulcanus")
    end}
}

local passed = t.run("queue_diagnostic_spec", tests)
for _, name in ipairs(names) do
    package.preload[name] = original[name]
    package.loaded[name] = nil
end
_G.game = original_globals.game
_G.storage = original_globals.storage
_G.defines = original_globals.defines
_G.prototypes = original_globals.prototypes
return passed
