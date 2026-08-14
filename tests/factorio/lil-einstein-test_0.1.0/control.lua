local result = {
    status = "running",
    checks = {},
    tick = nil
}

local test_lab_name = "lil-einstein-test-lab"
local starved_technology_name = "lil-einstein-test-starved"
local supplied_technology_name = "lil-einstein-test-supplied"
local scenario_lab_count = 275
local observe_before_switch_tick = 240
local verify_switch_tick = 900

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

    local created_labs = 0
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
                    inventory.insert({name = "logistic-science-pack", count = 100})
                end
                created_labs = created_labs + 1
            end
        end
    end

    force.technologies[starved_technology_name].researched = false
    force.technologies[supplied_technology_name].researched = false
    storage.switch_scenario = {
        created_labs = created_labs,
        queue_started = false,
        initial_research = nil,
        before_switch_research = nil,
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
    check("starved research started first", scenario.initial_research == starved_technology_name,
        "initial research was " .. tostring(scenario.initial_research))
    check("starved research remained active before the switch interval",
        scenario.before_switch_research == starved_technology_name,
        "research at tick " .. tostring(observe_before_switch_tick) .. " was " ..
            tostring(scenario.before_switch_research) .. "; timeline: " .. timeline)
    check("live research switched to the supplied alternate",
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
        force.research_queue = {starved_technology_name, supplied_technology_name}
        scenario.initial_research = force.current_research and force.current_research.name or nil
        scenario.queue_started = true
    end
    if event.tick == 1 or event.tick % 30 == 0 then
        record_research_state(scenario, event.tick)
    end
    if not scenario.before_switch_research and event.tick >= observe_before_switch_tick then
        local force = game.forces.player
        scenario.before_switch_research = force.current_research and force.current_research.name or nil
    end
    if event.tick >= verify_switch_tick then
        scenario.completed = true
        run_checks()
    end
end)
