local result = {
    status = "running",
    checks = {},
    tick = nil
}

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

    write_result()
end

script.on_init(run_checks)
