local result = {
    status = "running",
    checks = {},
    tick = nil
}

local test_lab_name = "lil-einstein-test-lab"
local starved_technology_name = "lil-einstein-test-starved"
local supplied_technology_name = "lil-einstein-test-supplied"
local scenario_lab_count = 275
local scenario_working_lab_count = 5
local observe_before_switch_tick = 240
local observe_after_switch_tick = 900
local observe_before_recovery_tick = 1440
local verify_switch_tick = 2400

local function check(name, condition, detail)
    local item = {
        name = name,
        pass = condition == true
    }
    if not item.pass then
        item.detail = detail or "assertion returned false"
    end
    table.insert(result.checks, item)
    return item.pass
end

local function check_call(name, callback)
    local ok, value = pcall(callback)
    if not ok then
        check(name, false, tostring(value))
        return nil
    end
    check(name, true)
    return value
end

local function write_result()
    local failed = 0
    for _, item in ipairs(result.checks) do
        if not item.pass then
            failed = failed + 1
        end
    end
    result.status = failed == 0 and "passed" or "failed"
    result.failed = failed
    result.tick = game.tick
    helpers.write_file("lil_einstein_test_result.json", helpers.table_to_json(result), false)
    log("lil-einstein-test: " .. result.status .. " (" .. tostring(#result.checks) .. " checks)")
end

local function setup_switch_scenario()
    local force = game.forces.player
    local surface = game.surfaces[1]
    surface.request_to_generate_chunks({0, 0}, 5)
    surface.force_generate_chunk_requests()

    for technology_name, technology in pairs(force.technologies) do
        technology.enabled = technology_name == starved_technology_name or
            technology_name == supplied_technology_name
    end

    local created_labs = 0
    local working_labs = 0
    for index = 1, scenario_lab_count do
        local column = (index - 1) % 25
        local row = math.floor((index - 1) / 25)
        local wanted_position = {x = (column - 12) * 4, y = (row - 5) * 4}
        local position = surface.find_non_colliding_position(test_lab_name, wanted_position, 24, 0.5)
        if position then
            local lab_entity = surface.create_entity({
                name = test_lab_name,
                position = position,
                force = force,
                raise_built = true,
                create_build_effect_smoke = false
            })
            if lab_entity then
                local inventory = lab_entity.get_inventory(defines.inventory.lab_input)
                if inventory then
                    inventory.insert({name = "logistic-science-pack", count = 1000})
                    if index <= scenario_working_lab_count then
                        local inserted = inventory.insert({name = "automation-science-pack", count = 1000})
                        if inserted > 0 then
                            working_labs = working_labs + 1
                        end
                    end
                end
                created_labs = created_labs + 1
            end
        end
    end

    force.technologies[starved_technology_name].researched = false
    force.technologies[supplied_technology_name].researched = false
    storage.switch_scenario = {
        created_labs = created_labs,
        working_labs = working_labs,
        queue_started = false,
        initial_research = nil,
        initial_progress = nil,
        initial_queue_size = nil,
        initial_stored_queue = {},
        before_switch_research = nil,
        before_switch_progress = nil,
        after_switch_research = nil,
        before_recovery_snapshot = nil,
        timeline = {},
        completed = false
    }
end

local function record_research_state(scenario, tick)
    local force = game.forces.player
    local queue_names = {}
    for _, technology in ipairs(force.research_queue or {}) do
        table.insert(queue_names, technology.name)
    end
    table.insert(scenario.timeline,
        tostring(tick) .. ":" ..
        tostring(force.current_research and force.current_research.name or "nil") ..
        "[" .. table.concat(queue_names, ",") .. "]")
end

local function run_checks()
    local force = game.forces.player
    check("player force exists", force ~= nil)

    local runtime = check_call("production snapshot is available", function()
        return remote.call("lil_einstein_test", "snapshot", force.index)
    end)
    if runtime then
        check("production storage initialized", runtime.storage_initialized == true)
        check("player force initialized", runtime.force_initialized == true)
        check("queue storage initialized", runtime.queue_initialized == true)
        check("policy storage initialized", runtime.policy_initialized == true)
        check("lab storage initialized", runtime.lab_initialized == true)
        check("policy default strategy is balanced", runtime.strategy == "balanced")
        check("queue getter result shape", runtime.queue_type == "table")
        check("production stored queue remains the starved singleton",
            #runtime.stored_queue == 1 and runtime.stored_queue[1] == starved_technology_name,
            "stored queue was [" .. table.concat(runtime.stored_queue or {}, ",") .. "]")
        check("production snapshot observes the supplied live research",
            runtime.live_current_research == supplied_technology_name,
            "snapshot current research was " .. tostring(runtime.live_current_research))
        check("pinned technology starts empty", runtime.pinned_is_nil == true)
        check("research history getter returns a table", runtime.history_type == "table")
        check("environment sciences getter returns a table", runtime.sciences_type == "table")
        check("lab registry getter returns a table", runtime.labs_type == "table")
        check("policy export shape", runtime.policy_export_type == "table")
        check("policy sanitizer accepts its own export", runtime.policy_sanitized_type == "table")
        check("science counts getter is safe", runtime.science_counts_type == "table")
        check("science breakdown getter is safe", runtime.science_breakdown_type == "table")
        check("science clusters getter is safe", runtime.science_clusters_type == "table")
        check("science forecast getter is safe", runtime.science_forecast_type == "table")
        check("science availability getter is safe", runtime.science_availability_type == "table")
        check("research summary getter is safe", runtime.research_summary_type == "table")
        check("research diagnostic getter is safe", runtime.diagnostic_type == "table")
        check("upcoming research getter is safe", runtime.upcoming_type == "table")
        check("upcoming display getter is safe", runtime.upcoming_display_type == "table")
        check("queue budget getter is safe", runtime.queue_budget_type == "table")
        check("health snapshot tick getter is safe", runtime.health_snapshot_tick_type == "number")
        check("trigger objective getter is safe", runtime.trigger_objectives_type == "table")
        check("SI formatter runs in Factorio", runtime.si == "1.3K")

    end

    local scenario = storage.switch_scenario or {}
    local current_name = force.current_research and force.current_research.name or nil
    local timeline = table.concat(scenario.timeline or {}, "; ")
    check("created all 275 disposable labs", scenario.created_labs == scenario_lab_count,
        "created " .. tostring(scenario.created_labs) .. " labs")
    check("only 5 labs can consume the starved technology's pack",
        scenario.working_labs == scenario_working_lab_count,
        "supplied " .. tostring(scenario.working_labs) .. " labs")
    check("the explicit research queue contained only the starved technology",
        scenario.initial_queue_size == 1,
        "initial queue size was " .. tostring(scenario.initial_queue_size))
    check("LilEinstein's stored queue contained only the starved technology",
        #scenario.initial_stored_queue == 1 and
            scenario.initial_stored_queue[1] == starved_technology_name,
        "stored queue was [" .. table.concat(scenario.initial_stored_queue or {}, ",") .. "]")
    check("starved research started first", scenario.initial_research == starved_technology_name,
        "initial research was " .. tostring(scenario.initial_research))
    check("starved research remained active before the switch interval",
        scenario.before_switch_research == starved_technology_name,
        "research at tick " .. tostring(observe_before_switch_tick) .. " was " ..
            tostring(scenario.before_switch_research) .. "; timeline: " .. timeline)
    check("starved research made low but nonzero progress before switching",
        type(scenario.initial_progress) == "number" and
            type(scenario.before_switch_progress) == "number" and
            scenario.before_switch_progress > scenario.initial_progress,
        "progress changed from " .. tostring(scenario.initial_progress) .. " to " ..
            tostring(scenario.before_switch_progress))
    check("live research switched to the supplied alternate by tick 900",
        scenario.after_switch_research == supplied_technology_name,
        "research at tick " .. tostring(observe_after_switch_tick) .. " was " ..
            tostring(scenario.after_switch_research) .. "; timeline: " .. timeline)
    local recovery = scenario.before_recovery_snapshot or {}
    check("target remains insufficient before its first recovery check",
        recovery.test_target_science_sufficient == false,
        "target sufficient=" .. tostring(recovery.test_target_science_sufficient) ..
            ", stock=" .. tostring(recovery.test_target_pack_stock) ..
            ", production/min=" .. tostring(recovery.test_target_pack_production_per_minute) ..
            ", consumption/min=" .. tostring(recovery.test_target_pack_consumption_per_minute) ..
            ", demand/min=" .. tostring(recovery.test_target_demand_per_minute) ..
            ", capacity/min=" .. tostring(recovery.test_target_capacity_per_minute) ..
            ", horizon=" .. tostring(recovery.test_target_horizon_seconds) ..
            ", live=" .. tostring(recovery.live_current_research) ..
            ", target=" .. tostring(recovery.research_control and recovery.research_control.target_tech) ..
            ", temp=" .. tostring(recovery.research_control and recovery.research_control.temp_tech))
    check("live research stayed on the supplied alternate through target recovery checks",
        current_name == supplied_technology_name,
        "current research at tick " .. tostring(game.tick) .. " was " .. tostring(current_name) ..
            "; timeline: " .. timeline)

    write_result()
end

script.on_init(setup_switch_scenario)
script.on_event(defines.events.on_tick, function(event)
    local scenario = storage.switch_scenario
    if not scenario or scenario.completed then
        return
    end
    if not scenario.queue_started and event.tick >= 1 then
        local force = game.forces.player
        scenario.initial_stored_queue = remote.call(
            "lil_einstein_test",
            "configure_queue",
            force.index,
            {starved_technology_name}
        )
        force.research_queue = {starved_technology_name}
        scenario.initial_research = force.current_research and force.current_research.name or nil
        scenario.initial_progress = force.research_progress
        scenario.initial_queue_size = #(force.research_queue or {})
        scenario.queue_started = true
    end
    if event.tick == 1 or event.tick % 30 == 0 then
        record_research_state(scenario, event.tick)
    end
    if not scenario.before_switch_research and event.tick >= observe_before_switch_tick then
        local force = game.forces.player
        scenario.before_switch_research = force.current_research and force.current_research.name or nil
        scenario.before_switch_progress = force.research_progress
    end
    if not scenario.after_switch_research and event.tick >= observe_after_switch_tick then
        local force = game.forces.player
        scenario.after_switch_research = force.current_research and force.current_research.name or nil
    end
    if not scenario.before_recovery_snapshot and event.tick >= observe_before_recovery_tick then
        scenario.before_recovery_snapshot = remote.call(
            "lil_einstein_test",
            "snapshot",
            game.forces.player.index
        )
    end
    if event.tick >= verify_switch_tick then
        scenario.completed = true
        run_checks()
    end
end)
