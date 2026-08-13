local util = require("lib.util")
local tech = require("model.tech")
local queue = require("model.queue")
local analyzer = require("view.gui.analyzer")
local gutil = require("view.gui.gutil")

local debug_report = {}

local max_upcoming_entries = 100
local max_available_technologies = 250
local graph_sample_seconds = 3
local graph_sample_count = 40

local append = function(lines, ...)
    table.insert(lines, string.format(...))
end

local safe_string = function(value)
    local result = tostring(value or "-")
    return (result:gsub("[\r\n\t]", " "))
end

local number = function(value)
    return tonumber(value) or 0
end

local exact_number = function(value)
    if value == nil then
        return "-"
    end
    return string.format("%.3f", number(value))
end

local compact_number = function(value)
    return gutil.format_si(number(value))
end

local compact_optional = function(value)
    if value == nil then
        return "-"
    end
    return compact_number(value)
end

local yes_no = function(value)
    return value and "YES" or "NO"
end

local format_seconds = function(value)
    if value == nil then
        return "-"
    end
    local seconds = math.max(0, math.floor(number(value) + 0.5))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    if hours > 0 then
        return string.format("%dh %02dm %02ds", hours, minutes, remainder)
    end
    if minutes > 0 then
        return string.format("%dm %02ds", minutes, remainder)
    end
    return string.format("%ds", remainder)
end

local sorted_copy = function(values)
    local res = {}
    for _, value in pairs(values or {}) do
        table.insert(res, value)
    end
    table.sort(res, function(a, b) return tostring(a) < tostring(b) end)
    return res
end

local format_list = function(values)
    local res = {}
    for _, value in ipairs(values or {}) do
        table.insert(res, safe_string(value))
    end
    return #res > 0 and table.concat(res, ",") or "-"
end

local get_sciences = function(xcur)
    return sorted_copy(xcur and xcur.meta and xcur.meta.sciences or {})
end

local get_missing_sciences = function(xcur, availability)
    local missing = {}
    for _, science in ipairs(get_sciences(xcur)) do
        if not availability or availability[science] ~= true then
            table.insert(missing, science)
        end
    end
    return missing
end

local get_current_progress = function(force, technology_name)
    if force and force.current_research and force.current_research.name == technology_name then
        return math.max(0, math.min(1, number(force.research_progress)))
    end
    local t = force and force.technologies and force.technologies[technology_name]
    return math.max(0, math.min(1, number(t and t.saved_progress)))
end

local get_scored_available_technologies = function(player_index, force_index, availability)
    local filtered = analyzer.get_filtered_technologies_player(player_index) or {}
    local allowed = {}
    for _, xcur in ipairs(filtered) do
        if xcur and xcur.technology then
            allowed[xcur.technology.name] = true
        end
    end

    local order = queue.get_tech_order(force_index)
    if not order then
        order = queue.build_tech_order(force_index) or {}
    end
    local ordered_names = {}
    local seen = {}
    for _, tech_name in ipairs(order or {}) do
        table.insert(ordered_names, tech_name)
        seen[tech_name] = true
    end
    for _, xcur in ipairs(filtered) do
        local tech_name = xcur and xcur.technology and xcur.technology.name
        if tech_name and not seen[tech_name] then
            table.insert(ordered_names, tech_name)
            seen[tech_name] = true
        end
    end

    local tsx = tech.get_all_tech_state_ext(force_index) or {}
    local total_cost = 0
    local cost_count = 0
    for _, tech_name in ipairs(ordered_names) do
        local xcur = tsx[tech_name]
        if xcur and xcur.technology and not xcur.technology.researched and allowed[tech_name] then
            total_cost = total_cost + number(xcur.technology.research_unit_count or 1)
            cost_count = cost_count + 1
        end
    end
    local average_cost = cost_count > 0 and total_cost / cost_count or nil

    local res = {}
    for _, tech_name in ipairs(ordered_names) do
        local xcur = tsx[tech_name]
        if xcur and xcur.technology and not xcur.technology.researched and allowed[tech_name] then
            local score = queue.score_tech_detailed(
                xcur,
                xcur.technology.level,
                queue.get_tech_ub(force_index, tech_name),
                average_cost,
                force_index
            ) or {}
            table.insert(res, {
                tech_name = tech_name,
                xcur = xcur,
                score = score,
                packs_ok = queue.science_is_available(xcur, availability) == true
            })
        end
    end
    table.sort(res, function(a, b)
        local a_total = number(a.score.total)
        local b_total = number(b.score.total)
        if a_total == b_total then
            return tostring(a.tech_name) < tostring(b.tech_name)
        end
        return a_total > b_total
    end)
    return res
end

local add_control_state = function(lines, control)
    append(lines, "CONTROL STATE")
    append(lines, "live_current=%s | cached_current=%s | cached_smart=%s", safe_string(control.live_current_tech),
        safe_string(control.cached_current_tech), safe_string(control.cached_smart_tech))
    append(lines, "target=%s | temporary=%s | temporary_timeout_tick=%s | last_switch_tick=%s | stuck=%s",
        safe_string(control.target_tech), safe_string(control.temp_tech), safe_string(control.temp_tech_timeout_tick),
        safe_string(control.last_switch_tick), yes_no(control.is_stuck))
    append(lines, "stored_queue=%s", format_list(control.stored_queue))
    append(lines, "runtime_queue=%s", format_list(control.runtime_queue))
    table.insert(lines, "")
end

local add_upcoming = function(lines, force, force_index, availability, entries)
    entries = entries or queue.get_upcoming_research_display(force_index, max_upcoming_entries) or {}
    append(lines, "UPCOMING RESEARCH (%d entries returned)", #entries)
    table.insert(lines, "rank|technology|level|progress|time_left|wait|packs_sufficient|reason|missing_packs|cost")
    for rank, entry in ipairs(entries) do
        local progress = get_current_progress(force, entry.tech_name)
        local missing = entry.missing_sciences or get_missing_sciences(entry.xcur, availability)
        append(lines, "%d|%s|%s|%.2f%%|%s|%s|%s|%s|%s|%s", rank, safe_string(entry.tech_name),
            safe_string(entry.level), progress * 100, format_seconds(entry.duration), format_seconds(entry.wait_time),
            yes_no(entry.has_science), safe_string(entry.availability_reason), format_list(missing),
            compact_number(entry.cost))
    end
    table.insert(lines, "")
end

local add_available_technologies = function(lines, player_index, force_index, availability)
    local entries = get_scored_available_technologies(player_index, force_index, availability)
    local count = #entries
    append(lines, "AVAILABLE TECHNOLOGIES (%d entries%s)", count,
        count > max_available_technologies and ", report truncated" or "")
    table.insert(lines, "rank|technology|level|available|enabled|packs_sufficient|missing_packs|cost|IW|LB|UB|SP|ST|total|sciences|infinite|suspended|queued")
    for rank = 1, math.min(count, max_available_technologies) do
        local entry = entries[rank]
        local xcur = entry.xcur
        local score = entry.score or {}
        local technology_name = entry.tech_name
        append(lines, "%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s", rank,
            safe_string(technology_name), safe_string(xcur.technology.level), yes_no(xcur.available),
            yes_no(queue.get_tech_enabled(force_index, technology_name)), yes_no(entry.packs_ok),
            format_list(get_missing_sciences(xcur, availability)), compact_number(xcur.technology.research_unit_count),
            exact_number(score.importance), exact_number(score.level_boost), exact_number(score.user_boost),
            exact_number(score.science_priority), exact_number(score.strategy_boost), exact_number(score.total),
            format_list(get_sciences(xcur)), yes_no(xcur.meta.is_infinite), yes_no(xcur.suspended), yes_no(xcur.queued))
    end
    table.insert(lines, "")
end

local add_graph = function(lines, force_index, summary)
    local history = queue.get_research_history(force_index, graph_sample_count) or {}
    append(lines, "RESEARCH GRAPH (newest sample is age 0; %ds samples)", graph_sample_seconds)
    table.insert(lines, "age_seconds|spm")
    for index, value in ipairs(history) do
        append(lines, "%d|%s", (#history - index) * graph_sample_seconds, exact_number(value))
    end
    append(lines, "graph_samples=%d | current_spm=%s | summary_spm=%s", #history,
        exact_number(history[#history] or 0), exact_number(summary.spm))
    table.insert(lines, "")
end

local get_flow_value = function(flow_history, index, science)
    local sample = flow_history and flow_history[index]
    local value = sample and sample.values and sample.values[science]
    return value and value.consumption_per_minute or nil
end

local add_science = function(lines, force_index, sciences, counts, forecast, availability)
    local flow_history = queue.get_science_flow_history(force_index) or {}
    append(lines, "SCIENCE PACKS (quantity now; drain/min is the rolling one-minute flow sampled over the last 2 minutes; samples=%d)",
        #flow_history)
    table.insert(lines, "science_pack|quantity|drain_per_min_now|drain_per_min_oldest|drain_per_min_middle|production_per_min|net_per_min|depletion|availability")
    for _, science in ipairs(sciences) do
        local item = forecast[science] or {}
        append(lines, "%s|%s|%s|%s|%s|%s|%s|%s|%s", safe_string(science), compact_number(counts[science] or item.stock),
            compact_number(item.consumption_per_minute), compact_optional(get_flow_value(flow_history, 1, science)),
            compact_optional(get_flow_value(flow_history, 2, science)), compact_number(item.production_per_minute),
            compact_number(item.net_per_minute), format_seconds(item.depletion_seconds),
            yes_no(availability[science]))
    end
    table.insert(lines, "")
end

local add_warnings = function(lines, force_index, force, diagnostic, upcoming, availability, control, sciences, flow_history)
    local warnings = {}
    local add_warning = function(message)
        table.insert(warnings, message)
    end

    if not force.current_research then
        add_warning("idle: no active research")
    elseif diagnostic.state and diagnostic.state ~= "at_capacity" then
        add_warning("research_health: state=" .. safe_string(diagnostic.state))
    end
    if diagnostic.dominant_cause then
        local cause = diagnostic.dominant_cause
        add_warning(string.format("dominant_cause: %s lost_spm=%s labs=%s material=%s", safe_string(cause.kind),
            exact_number(cause.lost_spm), safe_string(cause.labs), yes_no(cause.material)))
    end
    for _, cause in ipairs(diagnostic.causes or {}) do
        add_warning(string.format("cause: %s lost_spm=%s labs=%s material=%s", safe_string(cause.kind),
            exact_number(cause.lost_spm), safe_string(cause.labs), yes_no(cause.material)))
    end
    for _, missing in ipairs(diagnostic.missing_sciences or {}) do
        add_warning(string.format("pack_bound: %s missing_per_min=%s lost_spm=%s labs=%s", safe_string(missing.science),
            exact_number(missing.missing_per_minute), exact_number(missing.lost_spm), safe_string(missing.labs)))
    end
    for _, entry in ipairs(upcoming or {}) do
        if entry.has_science == false then
            add_warning("upcoming_not_selectable: " .. safe_string(entry.tech_name) .. " reason=" ..
                safe_string(entry.availability_reason) .. " missing=" .. format_list(entry.missing_sciences))
        end
    end
    local queue_missing = queue.get_tech_missing_science(force_index) or {}
    for tech_name, missing in pairs(queue_missing) do
        if missing then
            add_warning("queue_missing_science: " .. safe_string(tech_name))
        end
    end
    for _, science in ipairs(sciences) do
        if availability[science] ~= true then
            add_warning("science_unavailable: " .. safe_string(science))
        end
    end
    if control.live_current_tech ~= control.cached_current_tech then
        add_warning("current_cache_mismatch: live=" .. safe_string(control.live_current_tech) ..
            " cached=" .. safe_string(control.cached_current_tech))
    end
    if diagnostic.current_technology ~= control.live_current_tech then
        add_warning("health_snapshot_mismatch: snapshot=" .. safe_string(diagnostic.current_technology) ..
            " live=" .. safe_string(control.live_current_tech))
    end
    if control.is_stuck then
        add_warning("queue_marked_stuck")
    end
    if #flow_history < 3 then
        add_warning(string.format("science_flow_history_incomplete: %d/3 samples", #flow_history))
    end
    if diagnostic.sampling_ready == false and force.current_research then
        add_warning(string.format("research_sampling_incomplete: %d samples", number(diagnostic.sample_count)))
    end

    append(lines, "WARNINGS (%d)", #warnings)
    if #warnings == 0 then
        table.insert(lines, "none")
    else
        for index, warning in ipairs(warnings) do
            append(lines, "%d|%s", index, warning)
        end
    end
    table.insert(lines, "")
end

debug_report.generate = function(player_index)
    local player = game.get_player(player_index)
    if not player or not player.force then
        return "LilEinstein debug report\nerror=player or force unavailable\n"
    end
    local force = player.force
    local force_index = force.index
    local summary = queue.get_research_summary(force_index) or {}
    local diagnostic = queue.get_research_display_diagnostic(force_index) or
        queue.get_research_diagnostic(force_index) or {}
    local display_counts = queue.get_science_display_counts(force_index) or {}
    local counts = next(display_counts) and display_counts or (queue.get_science_counts(force_index) or {})
    local display_forecast = queue.get_science_display_forecast(force_index) or {}
    local forecast = next(display_forecast) and display_forecast or (queue.get_science_forecast(force_index) or {})
    local availability = queue.get_science_availability(force_index) or {}
    local sciences = sorted_copy(util.get_all_sciences() or {})
    local control = queue.get_research_control_state and queue.get_research_control_state(force_index) or {
        live_current_tech = force.current_research and force.current_research.name,
        cached_current_tech = queue.get_current_researching(force_index),
        stored_queue = queue.get_queue(force_index) or {},
        runtime_queue = {}
    }
    local upcoming = queue.get_upcoming_research_display(force_index, max_upcoming_entries) or {}
    local flow_history = queue.get_science_flow_history and queue.get_science_flow_history(force_index) or {}
    local speed = queue.get_research_speed(force_index)
    local lines = {
        "LilEinstein debug report",
        "schema=2 | generated_tick=" .. safe_string(game.tick) .. " | force_index=" .. safe_string(force_index) ..
            " | force_name=" .. safe_string(force.name),
        "note=This report is generated from the live force/model state. The in-game report box selects all text; press Ctrl+C.",
        ""
    }

    append(lines, "CURRENT RESEARCH")
    append(lines, "technology=%s | progress=%.2f%% | units=%s/%s | speed_units_per_second=%s | spm=%s | time_left=%s",
        safe_string(force.current_research and force.current_research.name), number(summary.progress) * 100,
        compact_number(summary.done), compact_number(summary.total), exact_number(speed), exact_number(summary.spm),
        format_seconds(summary.remaining_seconds))
    append(lines, "health_state=%s | health_snapshot_technology=%s | actual_spm=%s | expected_spm=%s | working_spm=%s | utilization=%.2f%% | labs=%s/%s compatible | working_labs=%s | incompatible_labs=%s | health_snapshot_tick=%s",
        safe_string(diagnostic.state), safe_string(diagnostic.current_technology), exact_number(diagnostic.actual_spm),
        exact_number(diagnostic.expected_spm),
        exact_number(diagnostic.working_spm), number(diagnostic.utilization) * 100, safe_string(diagnostic.total_labs),
        safe_string(diagnostic.compatible_labs), safe_string(diagnostic.working_labs), safe_string(diagnostic.incompatible_labs),
        safe_string(queue.get_research_health_snapshot_tick(force_index)))
    table.insert(lines, "")

    add_control_state(lines, control)
    add_upcoming(lines, force, force_index, availability, upcoming)
    add_available_technologies(lines, player_index, force_index, availability)
    add_graph(lines, force_index, summary)
    add_science(lines, force_index, sciences, counts, forecast, availability)
    add_warnings(lines, force_index, force, diagnostic, upcoming, availability, control, sciences, flow_history)
    return table.concat(lines, "\n") .. "\n"
end

return debug_report
