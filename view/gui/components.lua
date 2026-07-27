local const = require("lib.const")
local logger = require("lib.log")
local util = require("lib.util")
local state = require("model.state")
local tech = require("model.tech")
local queue = require("model.queue")
local policy = require("model.research_policy")
local analyzer = require("view.gui.analyzer")

local gutil = require("view.gui.gutil")
local gctech = require("view.gui.components.tech")
local gcupcoming = require("view.gui.components.upcoming")

local content = {}
local ordered_force_settings = {"requeue_infinite_tech", "auto_research"}
local research_graph_column_count = 200
local research_graph_sample_seconds = 3
local research_graph_plot_width = 456
local research_graph_plot_height = 118
local research_graph_hover_dot_height = 3
local research_graph_hover_column_setting = "research_graph_hover_column"

local get_science_tooltip = function(player_index, force_index, science, total_count)
    local item_name = state.get_translation(player_index, "item", science, "localised_name") or science
    local detail = queue.get_science_count_breakdown(force_index, science)
    local science_policy = policy.get_science_policy(force_index, science)
    local forecast = queue.get_science_forecast(force_index)[science] or {}
    local networks = {}
    for _, item in pairs(detail.networks or {}) do
        table.insert(networks, item)
    end
    table.sort(networks, function(a, b)
        if a.count == b.count then
            return a.label < b.label
        end
        return a.count > b.count
    end)

    local tt = "[font=heading-2]" .. tostring(item_name) .. "[/font]\n" ..
                   "Total: " .. gutil.format_cost(total_count or 0) .. "\n" ..
                   "In labs: " .. gutil.format_cost(detail.lab_count or 0) .. " in " ..
                   tostring(detail.lab_entity_count or 0) .. " labs\n" ..
                   "In networks: " .. gutil.format_cost(detail.network_total or 0) .. "\n" ..
                   "Priority: " .. tostring(science_policy.priority) .. "\n" ..
                   string.format("Production / consumption: %.1f / %.1f per minute", forecast.production_per_minute or 0,
                       forecast.consumption_per_minute or 0)

    if forecast.depletion_seconds then
        tt = tt .. "\nEstimated depletion: " .. tostring(math.floor(forecast.depletion_seconds + 0.5)) .. "s"
    elseif forecast.recovery_seconds then
        tt = tt .. "\nEstimated recovery: " .. tostring(math.floor(forecast.recovery_seconds + 0.5)) .. "s"
    end
    tt = tt .. "\nLeft-click: filter technology\nRight-click: cycle automation priority"

    if #networks > 0 then
        tt = tt .. "\n\n"
        for i, item in ipairs(networks) do
            tt = tt .. item.label .. ": " .. gutil.format_cost(item.count or 0)
            if i < #networks then
                tt = tt .. "\n"
            end
        end
    else
        tt = tt .. "\n\nNo detected robot networks"
    end

    return tt
end

local refresh_science_counts = function(player_index, anchor)
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local force_index = p.force.index
    local science_counts = queue.get_science_counts(force_index)

    for _, science in pairs(util.get_all_sciences()) do
        local count = science_counts[science] or 0
        local btn = gutil.get_child(anchor, "allowed_science_btn_" .. science)
        if btn then
            btn.tooltip = get_science_tooltip(player_index, force_index, science, count)
        end

        local label_name = "allowed_science_count_" .. science
        local count_label = gutil.get_child(anchor, label_name)
        if count > 0 then
            local caption = gutil.format_cost(count)
            if count_label then
                count_label.caption = caption
            elseif btn and btn.parent then
                count_label = btn.parent.add({
                    type = "label",
                    name = label_name,
                    caption = caption,
                    ignored_by_interaction = true
                })
                count_label.style.width = 44
                count_label.style.horizontal_align = "center"
                count_label.style.top_margin = -6
                count_label.style.font = "default-small"
                count_label.style.font_color = {r = 1, g = 1, b = 1}
            end
        elseif count_label then
            count_label.destroy()
        end
    end
end

local format_spaced_number = function(value)
    local str = tostring(math.floor((value or 0) + 0.5))
    local res = str:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", "")
    return res
end

local format_time = function(seconds)
    if not seconds then
        return "--"
    end
    seconds = math.max(0, math.floor(seconds + 0.5))
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    if minutes > 0 then
        return tostring(minutes) .. "m" .. string.format("%02ds", secs)
    end
    return tostring(secs) .. "s"
end

local format_axis_value = function(value)
    value = math.max(0, value or 0)
    if value <= 0 then
        return "0"
    end
    if value < 1000 then
        return tostring(math.floor(value + 0.5))
    end
    if value < 1000000 then
        return tostring(math.floor((value / 1000) + 0.5)) .. "k"
    end
    local label = gutil.format_cost(math.floor((value / 1000) + 0.5) * 1000)
    return label:gsub("K", "k")
end

local get_axis_max = function(history, spm)
    local max_value = spm or 0
    for _, value in ipairs(history or {}) do
        if value and value > max_value then
            max_value = value
        end
    end
    if max_value <= 0 then
        return 1000
    end
    if max_value < 1000 then
        return math.floor(max_value) + 1
    end
    return (math.floor(max_value / 1000) + 1) * 1000
end

local get_research_graph_ratio = function(value, axis_max)
    if not axis_max or axis_max <= 0 then
        return 0
    end

    local ratio = (value or 0) / axis_max
    if ratio > 1 then
        return 1
    elseif ratio < 0 then
        return 0
    end
    return ratio
end

local get_research_graph_y = function(value, axis_max)
    return math.ceil((1 - get_research_graph_ratio(value, axis_max)) * (research_graph_plot_height - 1))
end

local get_research_graph_hover_tooltip = function(value, column_index)
    local seconds_ago = (research_graph_column_count - column_index) * research_graph_sample_seconds
    return {"", "[font=default-bold]SPM:[/font] ", format_spaced_number(value), "\n",
            "[font=default-bold]Time:[/font] ", format_time(seconds_ago), " ago"}
end

local get_research_graph_column_width = function(i)
    local left = math.floor(((i - 1) * research_graph_plot_width) / research_graph_column_count)
    local right = math.floor((i * research_graph_plot_width) / research_graph_column_count)
    return math.max(1, right - left)
end

local ensure_research_graph_columns = function(plot)
    if not plot then
        return
    end
    if #plot.children == research_graph_column_count then
        local col = plot["research_graph_column_1"]
        if col and col["research_graph_vertical_before_1"] and col["research_graph_horizontal_1"] and
            col["research_graph_vertical_after_1"] and col["research_graph_horizontal_1"].type == "progressbar" then
            return
        end
    end

    plot.clear()
    for i = 1, research_graph_column_count do
        local column_width = get_research_graph_column_width(i)
        local col = plot.add({
            type = "flow",
            name = "research_graph_column_" .. i,
            direction = "vertical",
            style = "lil_einstein_research_graph_column"
        })
        col.style.width = column_width
        col.add({
            type = "empty-widget",
            name = "research_graph_spacer_" .. i,
            style = "lil_einstein_research_graph_line_spacer"
        })
        local vertical_before = col.add({
            type = "progressbar",
            name = "research_graph_vertical_before_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_data_segment",
            ignored_by_interaction = true
        })
        vertical_before.visible = false
        vertical_before.style.width = 1
        local horizontal = col.add({
            type = "progressbar",
            name = "research_graph_horizontal_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_data_segment",
            ignored_by_interaction = true
        })
        horizontal.style.width = column_width
        horizontal.style.height = 1
        local vertical_after = col.add({
            type = "progressbar",
            name = "research_graph_vertical_after_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_data_segment",
            ignored_by_interaction = true
        })
        vertical_after.visible = false
        vertical_after.style.width = 1
    end
end

local ensure_research_graph_hover_columns = function(overlay)
    if not overlay then
        return
    end
    if #overlay.children == research_graph_column_count then
        local col = overlay["research_graph_hover_column_1"]
        if col and col["research_graph_hover_line_before_1"] and col["research_graph_hover_dot_1"] and
            col["research_graph_hover_line_after_1"] then
            return
        end
    end

    overlay.clear()
    for i = 1, research_graph_column_count do
        local column_width = get_research_graph_column_width(i)
        local col = overlay.add({
            type = "flow",
            name = "research_graph_hover_column_" .. i,
            direction = "vertical",
            style = "lil_einstein_research_graph_hover_column",
            tags = {
                lil_einstein_on_hover = true,
                handler = "research_graph_hover",
                column_index = i
            },
            tooltip = get_research_graph_hover_tooltip(0, i),
            raise_hover_events = true
        })
        col.style.width = column_width

        local line_before = col.add({
            type = "progressbar",
            name = "research_graph_hover_line_before_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_hover_line",
            ignored_by_interaction = true
        })
        line_before.visible = false

        local dot = col.add({
            type = "progressbar",
            name = "research_graph_hover_dot_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_hover_dot",
            ignored_by_interaction = true
        })
        dot.visible = false

        local line_after = col.add({
            type = "progressbar",
            name = "research_graph_hover_line_after_" .. i,
            value = 1,
            style = "lil_einstein_research_graph_hover_line",
            ignored_by_interaction = true
        })
        line_after.visible = false
    end
end

local set_research_graph_spacer = function(spacer, height)
    if not spacer then
        return
    end
    height = math.max(0, math.floor(height or 0))
    if height > 0 then
        spacer.style.height = height
        spacer.visible = true
    else
        spacer.visible = false
    end
end

local set_research_graph_segment = function(segment, width, height)
    if not segment then
        return
    end
    width = math.max(1, math.floor(width or 1))
    height = math.max(0, math.floor(height or 0))
    if height > 0 then
        segment.value = 1
        segment.style.width = width
        segment.style.height = height
        segment.style.bar_width = height
        segment.visible = true
    else
        segment.visible = false
    end
end

local hide_research_graph_hover_column = function(col, i)
    if not col then
        return
    end

    local line_before = col["research_graph_hover_line_before_" .. i]
    local dot = col["research_graph_hover_dot_" .. i]
    local line_after = col["research_graph_hover_line_after_" .. i]
    if line_before then
        line_before.visible = false
    end
    if dot then
        dot.visible = false
    end
    if line_after then
        line_after.visible = false
    end
end

local clear_research_graph_hover_columns = function(anchor)
    local overlay = gutil.get_child(anchor, "research_graph_hover_overlay")
    if not overlay then
        return
    end

    for i = 1, research_graph_column_count do
        hide_research_graph_hover_column(overlay["research_graph_hover_column_" .. i], i)
    end
end

local set_research_graph_hover_marker = function(col, column_index, value, axis_max)
    if not col then
        return
    end

    local line_before = col["research_graph_hover_line_before_" .. column_index]
    local dot = col["research_graph_hover_dot_" .. column_index]
    local line_after = col["research_graph_hover_line_after_" .. column_index]
    if not line_before or not dot or not line_after then
        return
    end

    local y = get_research_graph_y(value, axis_max)
    local dot_top = y - math.floor(research_graph_hover_dot_height / 2)
    dot_top = math.max(0, math.min(research_graph_plot_height - research_graph_hover_dot_height, dot_top))

    set_research_graph_segment(line_before, 1, dot_top)
    set_research_graph_segment(dot, get_research_graph_column_width(column_index), research_graph_hover_dot_height)
    set_research_graph_segment(line_after, 1, research_graph_plot_height - dot_top - research_graph_hover_dot_height)
end

local get_research_context = function(player_index, anchor)
    local p = game.get_player(player_index)
    if not p or not anchor then
        return nil, nil
    end

    local summary = queue.get_research_summary(p.force.index)
    return p, summary
end

local refresh_research_progress = function(player_index, anchor)
    local _, summary = get_research_context(player_index, anchor)
    if not summary then
        return
    end

    gcupcoming.refresh_progress(player_index, anchor)

    local progress_value = gutil.get_child(anchor, "research_graph_progress_value")
    if progress_value then
        progress_value.caption = format_spaced_number(summary.done) .. " / " .. format_spaced_number(summary.total)
    end
end

local throughput_prefix = "lil_einstein-throughput."
local research_details_columns = {
    location = 220,
    labs = 140,
    capacity = 160,
    lost = 120,
    cause = 230,
    pack = 260,
    action = 250
}
local research_details_column_order = {"location", "labs", "capacity", "lost", "cause", "pack", "action"}
local diagnostic_state_colors = {
    idle = {0.70, 0.69, 0.64},
    measuring = {0.48, 0.78, 1.00},
    pack_bound = {1.00, 0.35, 0.20},
    operational_fault = {1.00, 0.45, 0.20},
    at_capacity = {0.20, 1.00, 0.20},
    degraded_unexplained = {1.00, 0.80, 0.20}
}

local item_caption = function(science)
    if not science then
        return {"lil_einstein-throughput.no-pack"}
    end
    return {"", "[item=", science, "] ", {"item-name." .. science}}
end

local cause_caption = function(kind)
    return {throughput_prefix .. "cause-" .. tostring(kind or "other"):gsub("_", "-")}
end

local cluster_location_caption = function(cluster)
    if not cluster then
        return {"lil_einstein-throughput.all-locations"}
    elseif cluster.scope == "network" and cluster.network_id then
        return {"lil_einstein-throughput.location-network", cluster.surface_name, cluster.network_id}
    end
    return {"lil_einstein-throughput.location-direct", cluster.surface_name}
end

local find_diagnostic_cluster = function(diagnostic, key)
    for _, cluster in ipairs((diagnostic and diagnostic.clusters) or {}) do
        if cluster.key == key then
            return cluster
        end
    end
    return nil
end

local get_diagnostic_action = function(diagnostic, cluster)
    local cause = cluster and cluster.dominant_cause or diagnostic and diagnostic.dominant_cause
    if cause then
        if cause.kind == "missing_science" then
            return {"lil_einstein-throughput.action-restock"}
        elseif cause.kind == "power" then
            return {"lil_einstein-throughput.action-power"}
        elseif cause.kind == "disabled" then
            return {"lil_einstein-throughput.action-enable"}
        elseif cause.kind == "frozen" then
            return {"lil_einstein-throughput.action-frozen"}
        elseif cause.kind == "no_labs" then
            return {"lil_einstein-throughput.action-build-labs"}
        elseif cause.kind == "no_compatible_labs" then
            return {"lil_einstein-throughput.action-build-compatible"}
        elseif cause.kind == "no_capacity" then
            return {"lil_einstein-throughput.action-capacity"}
        end
        return {"lil_einstein-throughput.action-inspect-status"}
    elseif cluster and (cluster.incompatible_labs or 0) > 0 and (cluster.compatible_labs or 0) == 0 then
        return {"lil_einstein-throughput.action-build-compatible"}
    elseif diagnostic and diagnostic.state == "at_capacity" then
        return {"lil_einstein-throughput.raise-ceiling"}
    end
    return {"lil_einstein-throughput.action-watch"}
end

local get_research_health_summary = function(diagnostic)
    local state_name = diagnostic and diagnostic.state or "idle"
    local state_label = {throughput_prefix .. "state-" .. state_name:gsub("_", "-")}
    local color = diagnostic_state_colors[state_name] or diagnostic_state_colors.idle
    local headline = state_label
    local evidence = {"lil_einstein-throughput.idle-evidence"}
    local action = {"lil_einstein-throughput.idle-action"}

    if state_name == "measuring" then
        headline = {"lil_einstein-throughput.headline-ceiling", state_label,
                    format_spaced_number(diagnostic.expected_spm)}
        evidence = {"lil_einstein-throughput.measuring-evidence"}
        action = {"lil_einstein-throughput.measuring-action"}
    elseif state_name == "at_capacity" then
        headline = {"lil_einstein-throughput.headline-output", state_label,
                    format_spaced_number(diagnostic.actual_spm), format_spaced_number(diagnostic.expected_spm)}
        evidence = {"lil_einstein-throughput.at-capacity-evidence", diagnostic.working_labs or 0,
                    diagnostic.compatible_labs or 0}
        action = {"lil_einstein-throughput.raise-ceiling"}
    elseif state_name == "pack_bound" then
        local missing = diagnostic.dominant_missing_science
        headline = {"lil_einstein-throughput.headline-lost", state_label,
                    format_spaced_number(diagnostic.material_loss_spm)}
        evidence = {"lil_einstein-throughput.pack-bound-evidence", item_caption(missing and missing.science),
                    missing and missing.labs or 0}
        action = {"lil_einstein-throughput.inspect-location",
                  cluster_location_caption(find_diagnostic_cluster(diagnostic, diagnostic.dominant_cluster_key))}
    elseif state_name == "operational_fault" then
        local cause = diagnostic.dominant_cause
        if cause and (cause.kind == "no_labs" or cause.kind == "no_compatible_labs" or
                      cause.kind == "no_capacity") then
            headline = state_label
        else
            headline = {"lil_einstein-throughput.headline-lost", state_label,
                        format_spaced_number(diagnostic.material_loss_spm)}
        end
        evidence = {"lil_einstein-throughput.fault-evidence", cause_caption(cause and cause.kind),
                    cause and cause.labs or 0}
        local cluster = find_diagnostic_cluster(diagnostic, diagnostic.dominant_cluster_key)
        action = cluster and {"lil_einstein-throughput.inspect-location", cluster_location_caption(cluster)} or
                     get_diagnostic_action(diagnostic)
    elseif state_name == "degraded_unexplained" then
        headline = {"lil_einstein-throughput.headline-output", state_label,
                    format_spaced_number(diagnostic.actual_spm), format_spaced_number(diagnostic.expected_spm)}
        evidence = {"lil_einstein-throughput.degraded-evidence"}
        action = {"lil_einstein-throughput.action-watch"}
    end

    return headline, {"", evidence, "\n", action}, color
end

local format_research_diagnostic = function(diagnostic)
    local headline, evidence = get_research_health_summary(diagnostic)
    local tt = {"", "[font=heading-2]", {"lil_einstein-throughput.tooltip-title"}, "[/font]\n",
                headline, "\n", evidence}
    if not diagnostic or not diagnostic.available then
        return tt
    end

    table.insert(tt, "\n\n")
    table.insert(tt, {"lil_einstein-throughput.tooltip-measured", format_spaced_number(diagnostic.actual_spm),
                      diagnostic.sample_count or 0})
    table.insert(tt, "\n")
    table.insert(tt, {"lil_einstein-throughput.tooltip-capacity", format_spaced_number(diagnostic.expected_spm),
                      format_spaced_number(diagnostic.working_spm)})
    table.insert(tt, "\n")
    table.insert(tt, {"lil_einstein-throughput.tooltip-labs", diagnostic.working_labs or 0,
                      diagnostic.compatible_labs or 0, diagnostic.incompatible_labs or 0})

    if diagnostic.causes and #diagnostic.causes > 0 then
        table.insert(tt, "\n\n[font=default-bold]")
        table.insert(tt, {"lil_einstein-throughput.current-losses"})
        table.insert(tt, "[/font]")
        for _, cause in ipairs(diagnostic.causes) do
            table.insert(tt, "\n")
            table.insert(tt, {"lil_einstein-throughput.cause-evidence", cause_caption(cause.kind),
                              cause.labs or 0, format_spaced_number(cause.lost_spm)})
        end
    end

    if diagnostic.missing_sciences and #diagnostic.missing_sciences > 0 then
        table.insert(tt, "\n\n[font=default-bold]")
        table.insert(tt, {"lil_einstein-throughput.missing-pack-detail"})
        table.insert(tt, "[/font]")
        local max_sciences = math.min(8, #diagnostic.missing_sciences)
        for i = 1, max_sciences do
            local item = diagnostic.missing_sciences[i]
            table.insert(tt, "\n")
            table.insert(tt, {"lil_einstein-throughput.pack-evidence", item_caption(item.science),
                              item.labs or 0, format_spaced_number(item.lost_spm)})
        end
    end

    table.insert(tt, "\n\n")
    table.insert(tt, {"lil_einstein-throughput.capacity-method"})
    return tt
end

local get_cluster_causes_caption = function(cluster)
    if not cluster.causes or #cluster.causes == 0 then
        if (cluster.incompatible_labs or 0) > 0 and (cluster.compatible_labs or 0) == 0 then
            return cause_caption("no_compatible_labs")
        end
        return {"lil_einstein-throughput.no-live-loss"}
    end

    local res = {""}
    for index, cause in ipairs(cluster.causes) do
        if index > 1 then
            table.insert(res, "\n")
        end
        table.insert(res, {"lil_einstein-throughput.cause-evidence", cause_caption(cause.kind),
                           cause.labs or 0, format_spaced_number(cause.lost_spm)})
    end
    return res
end

local get_cluster_pack_caption = function(cluster)
    local item = cluster.dominant_missing_science
    if not item then
        return {"lil_einstein-throughput.no-pack-loss"}
    end
    return {"lil_einstein-throughput.cluster-pack-evidence", item_caption(item.science), item.labs or 0,
            format_spaced_number(item.lost_spm), format_spaced_number(item.local_stock)}
end

local set_details_cell_width = function(element, width)
    if not element then
        return
    end
    element.style.width = width
    element.style.single_line = false
end

local create_research_details_row = function(rows, index, cluster)
    local row = rows.add({
        type = "frame",
        name = "research_details_row_" .. index,
        style = "inside_shallow_frame",
        direction = "vertical",
        tags = {cluster_key = cluster.key}
    })
    row.style.horizontally_stretchable = true
    local cells = row.add({
        type = "table",
        name = "research_details_cells_" .. index,
        column_count = #research_details_column_order
    })
    for _, column in ipairs(research_details_column_order) do
        local label = cells.add({
            type = "label",
            name = "research_details_" .. column .. "_" .. index,
            caption = ""
        })
        set_details_cell_width(label, research_details_columns[column])
    end
    return row
end

local research_details_rows_match = function(rows, clusters)
    if #rows.children ~= #clusters then
        return false
    end
    for index, cluster in ipairs(clusters) do
        local row = rows.children[index]
        if not row or not row.valid or not row.tags or row.tags.cluster_key ~= cluster.key then
            return false
        end
    end
    return true
end

local refresh_research_details = function(player_index, anchor, diagnostic)
    local panel = gutil.get_child(anchor, "research_details_panel")
    if not panel or not panel.visible then
        return
    end

    local p = game.get_player(player_index)
    if not p then
        return
    end
    diagnostic = diagnostic or queue.get_research_diagnostic(p.force.index)
    local headline_caption, evidence_caption, state_color = get_research_health_summary(diagnostic)
    local headline = gutil.get_child(panel, "research_details_headline")
    local evidence = gutil.get_child(panel, "research_details_evidence")
    local ceiling_hint = gutil.get_child(panel, "research_details_ceiling_hint")
    if headline then
        headline.caption = headline_caption
        headline.style.font_color = state_color
    end
    if evidence then
        evidence.caption = evidence_caption
    end
    if ceiling_hint then
        ceiling_hint.visible = diagnostic and diagnostic.state == "at_capacity"
    end

    local header = gutil.get_child(panel, "research_details_header")
    if header then
        for _, column in ipairs(research_details_column_order) do
            set_details_cell_width(gutil.get_child(header, "research_details_header_" .. column),
                                   research_details_columns[column])
        end
    end
    local pane = gutil.get_child(panel, "research_details_scroll_pane")
    if pane then
        pane.style.width = 1510
        pane.style.height = 545
        pane.horizontal_scroll_policy = "never"
        pane.vertical_scroll_policy = "auto"
    end

    local rows = gutil.get_child(panel, "research_details_rows")
    if not rows then
        return
    end
    local clusters = (diagnostic and diagnostic.clusters) or {}
    if #clusters == 0 then
        if #rows.children ~= 1 or rows.children[1].name ~= "research_details_empty" then
            rows.clear()
            rows.add({
                type = "label",
                name = "research_details_empty",
                caption = {"lil_einstein-throughput.no-clusters"}
            })
        end
        return
    elseif not research_details_rows_match(rows, clusters) then
        rows.clear()
        for index, cluster in ipairs(clusters) do
            create_research_details_row(rows, index, cluster)
        end
    end

    for index, cluster in ipairs(clusters) do
        local row = rows.children[index]
        local location = gutil.get_child(row, "research_details_location_" .. index)
        local labs = gutil.get_child(row, "research_details_labs_" .. index)
        local capacity = gutil.get_child(row, "research_details_capacity_" .. index)
        local lost = gutil.get_child(row, "research_details_lost_" .. index)
        local cause = gutil.get_child(row, "research_details_cause_" .. index)
        local pack = gutil.get_child(row, "research_details_pack_" .. index)
        local action = gutil.get_child(row, "research_details_action_" .. index)
        if location then
            location.caption = cluster_location_caption(cluster)
            if cluster.representative_position then
                location.tooltip = {"lil_einstein-throughput.position-tooltip",
                                    math.floor(cluster.representative_position.x + 0.5),
                                    math.floor(cluster.representative_position.y + 0.5)}
            else
                location.tooltip = nil
            end
        end
        if labs then
            labs.caption = {"lil_einstein-throughput.labs-cell", cluster.working_labs or 0,
                            cluster.compatible_labs or 0, cluster.incompatible_labs or 0}
        end
        if capacity then
            capacity.caption = {"lil_einstein-throughput.capacity-cell",
                                format_spaced_number(cluster.working_spm), format_spaced_number(cluster.expected_spm)}
        end
        if lost then
            lost.caption = {"lil_einstein-throughput.lost-cell", format_spaced_number(cluster.lost_spm)}
        end
        if cause then
            cause.caption = get_cluster_causes_caption(cluster)
        end
        if pack then
            pack.caption = get_cluster_pack_caption(cluster)
        end
        if action then
            action.caption = get_diagnostic_action(diagnostic, cluster)
        end
    end
end

local refresh_research_metrics = function(player_index, anchor)
    local p, summary = get_research_context(player_index, anchor)
    if not p or not summary then
        return
    end

    local diagnostic = queue.get_research_diagnostic(p.force.index)
    local diagnostic_tooltip = format_research_diagnostic(diagnostic)
    local spm_value = gutil.get_child(anchor, "research_graph_spm_value")
    if spm_value then
        spm_value.caption = format_spaced_number(summary.spm)
    end

    local health_panel = gutil.get_child(anchor, "research_health_panel")
    local health_state = gutil.get_child(anchor, "research_health_state")
    local health_reason = gutil.get_child(anchor, "research_health_reason")
    local state_caption, reason_caption, state_color = get_research_health_summary(diagnostic)
    if health_panel then
        health_panel.tooltip = diagnostic_tooltip
    end
    if health_state then
        health_state.caption = state_caption
        health_state.tooltip = diagnostic_tooltip
        health_state.style.font_color = state_color
    end
    if health_reason then
        health_reason.caption = reason_caption
        health_reason.tooltip = diagnostic_tooltip
    end
    refresh_research_details(player_index, anchor, diagnostic)

    local remaining_value = gutil.get_child(anchor, "research_graph_remaining_value")
    if remaining_value then
        remaining_value.caption = format_time(summary.remaining_seconds)
    end
end

local refresh_research_graph_hover = function(player_index, anchor, history, axis_max)
    clear_research_graph_hover_columns(anchor)

    local column_index = state.get_player_setting(player_index, research_graph_hover_column_setting)
    column_index = math.floor(tonumber(column_index) or 0)
    if column_index < 1 or column_index > research_graph_column_count then
        state.clear_player_setting(player_index, research_graph_hover_column_setting)
        return
    end

    if not history or not axis_max then
        local p, summary = get_research_context(player_index, anchor)
        if not p or not summary then
            return
        end
        history = queue.get_research_history(p.force.index, research_graph_column_count)
        axis_max = get_axis_max(history, summary.spm)
    end

    local overlay = gutil.get_child(anchor, "research_graph_hover_overlay")
    ensure_research_graph_hover_columns(overlay)
    if not overlay then
        return
    end

    local col = overlay["research_graph_hover_column_" .. column_index]
    local value = history[column_index] or 0
    if col then
        col.tooltip = get_research_graph_hover_tooltip(value, column_index)
        set_research_graph_hover_marker(col, column_index, value, axis_max)
    end
end

local show_research_graph_hover = function(player_index, anchor, column_index)
    column_index = math.floor(tonumber(column_index) or 0)
    if column_index < 1 or column_index > research_graph_column_count then
        return
    end

    state.set_player_setting(player_index, research_graph_hover_column_setting, column_index)
    refresh_research_graph_hover(player_index, anchor)
end

local hide_research_graph_hover = function(player_index, anchor)
    state.clear_player_setting(player_index, research_graph_hover_column_setting)
    clear_research_graph_hover_columns(anchor)
end

local refresh_research_graph = function(player_index, anchor)
    local p, summary = get_research_context(player_index, anchor)
    if not p or not summary then
        return
    end

    local history, has_history = queue.get_research_history(p.force.index, research_graph_column_count)
    local axis_max = get_axis_max(history, summary.spm)
    for i = 1, 8 do
        local label = gutil.get_child(anchor, "research_graph_axis_" .. i)
        if label then
            label.caption = format_axis_value(axis_max * (8 - i) / 7)
        end
    end

    local plot = gutil.get_child(anchor, "research_graph_plot")
    ensure_research_graph_columns(plot)
    local overlay = gutil.get_child(anchor, "research_graph_hover_overlay")
    ensure_research_graph_hover_columns(overlay)
    if not plot then
        return
    end

    for i = 1, research_graph_column_count do
        local col = plot["research_graph_column_" .. i]
        local hover_col = overlay and overlay["research_graph_hover_column_" .. i]
        local value = history[i] or 0
        if hover_col then
            hover_col.tooltip = get_research_graph_hover_tooltip(value, i)
        end
        if col then
            local spacer = col["research_graph_spacer_" .. i]
            local vertical_before = col["research_graph_vertical_before_" .. i]
            local horizontal = col["research_graph_horizontal_" .. i]
            local vertical_after = col["research_graph_vertical_after_" .. i]
            if spacer and vertical_before and horizontal and vertical_after then
                local column_width = get_research_graph_column_width(i)
                local previous_value = history[i - 1] or value

                local y = get_research_graph_y(value, axis_max)
                local previous_y = get_research_graph_y(previous_value, axis_max)
                local vertical_before_height = 0
                local vertical_after_height = 0
                if previous_y < y then
                    set_research_graph_spacer(spacer, previous_y)
                    vertical_before_height = y - previous_y
                else
                    set_research_graph_spacer(spacer, y)
                    vertical_after_height = previous_y - y
                end

                if has_history or value > 0 or previous_value > 0 then
                    set_research_graph_segment(vertical_before, 1, vertical_before_height)
                    set_research_graph_segment(horizontal, column_width, 1)
                    set_research_graph_segment(vertical_after, 1, vertical_after_height)
                else
                    vertical_before.visible = false
                    horizontal.visible = false
                    vertical_after.visible = false
                end
            end
        end
    end

    refresh_research_graph_hover(player_index, anchor, history, axis_max)
end

local refresh_research_status = function(player_index, anchor)
    refresh_research_progress(player_index, anchor)
    refresh_research_metrics(player_index, anchor)
    refresh_research_graph(player_index, anchor)
end

local add_force_setting_row = function(flow, force_index, setting_name, top_margin)
    local st = state.get_force_setting(force_index, setting_name, const.default_settings.force.settings[setting_name])
    local row = flow.add({
        type = "flow",
        name = setting_name .. "_row",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_nospacing"
    })
    row.style.height = 21
    row.style.top_margin = top_margin or 0
    row.style.vertical_align = "center"

    row.add({
        type = "button",
        name = setting_name,
        style = st and "lil_einstein_settings_checkbox_on" or "lil_einstein_settings_checkbox_off",
        tags = {
            lil_einstein_on_click = true,
            handler = "toggle_checkbox_force_click",
            setting_name = setting_name
        },
        tooltip = {"lil_einstein-force-settings." .. setting_name}
    })

    local label = row.add({
        type = "label",
        name = setting_name .. "_label",
        caption = {"lil_einstein-force-settings." .. setting_name},
        tags = {
            lil_einstein_on_click = true,
            handler = "toggle_checkbox_force_click",
            setting_name = setting_name
        },
        tooltip = {"lil_einstein-force-settings." .. setting_name}
    })
    label.style.left_margin = 7
    label.style.top_margin = -1
    label.style.font_color = {0.92, 0.92, 0.92}
end

local populate_force_settings = function(player_index, anchor)
    -- Dropdown
    -- local name = "announcement_level"
    -- local dl
    -- for i, v in ipairs(const.announcements) do
    --     if v == const.default_settings.force.announcement_level then
    --         dl = i
    --     end
    -- end
    -- local elm = gutil.get_child(anchor, name)
    -- local lvl = state.get_force_setting(player_index, name, dl)
    -- elm.selected_index = lvl

    -- Checkboxes
    local flow = gutil.get_child(anchor, "force_settings_flow")
    if not flow then
        -- For some reason when an equipment grid is opened and we try to open the queue
        -- The game crashes because we can't find the flow
        -- As containment we just exit here
        return
    end
    flow.clear()

    -- player_index may differ from force_index; state functions need force_index
    local p = game.get_player(player_index)
    local force_index = p and p.force.index or player_index

    for i, setting_name in ipairs(ordered_force_settings) do
        add_force_setting_row(flow, force_index, setting_name, i == 1 and 0 or 5)
    end

    if const.default_settings.force.global_settings then
        for k, v in pairs(const.default_settings.force.global_settings) do
            local tt = {"",
                        "[font=default-bold]This is a global mod setting, which is located under\nsettings > mod settings > map[/font]\n",
                        "", {"mod-setting-description." .. v}, ""}
            local state = settings.global[v].value
            local ifl = flow.add({
                type = "flow",
                direction = "horizontal",
                tooltip = tt
            })
            ifl.add({
                type = "checkbox",
                name = v,
                caption = {"", {"mod-setting-name." .. v}},
                state = state,
                enabled = false,
                tooltip = tt
            })
            ifl.add({
                type = "sprite",
                sprite = "info",
                tooltip = tt
            })
        end
    end

    -- Consecutive tech cap with +/- buttons
    local cap_val = state.get_force_setting(force_index, "consecutive_tech_cap", const.default_settings.force.settings.consecutive_tech_cap)
    local cap_fl = flow.add({
        type = "flow",
        name = "consecutive_tech_cap_row",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_nospacing"
    })
    cap_fl.style.top_margin = 8
    cap_fl.style.vertical_align = "center"
    cap_fl.add({
        type = "label",
        caption = {"lil_einstein-force-settings.consecutive_tech_cap"}
    })
    local right = cap_fl.add({
        type = "flow",
        name = "consecutive_tech_cap_controls",
        direction = "horizontal",
        style = "lil_einstein_horizontal_flow_nospacing"
    })
    right.style.horizontally_stretchable = true
    right.style.horizontal_align = "right"
    right.style.left_margin = 11

    local value_frame = right.add({
        type = "frame",
        name = "consecutive_tech_cap_value_frame",
        style = "lil_einstein_number_input_frame",
        direction = "horizontal"
    })
    local value_lbl = value_frame.add({
        type = "label",
        name = "consecutive_tech_cap_value",
        caption = tostring(cap_val)
    })
    value_lbl.style.width = 43
    value_lbl.style.horizontal_align = "center"
    value_lbl.style.font_color = {0.92, 0.92, 0.92}

    right.add({
        type = "button",
        style = "lil_einstein_settings_stepper_left",
        tags = {
            lil_einstein_on_click = true,
            handler = "consecutive_tech_cap_dec"
        },
        tooltip = "-1"
    })
    right.add({
        type = "button",
        style = "lil_einstein_settings_stepper_right",
        tags = {
            lil_einstein_on_click = true,
            handler = "consecutive_tech_cap_inc"
        },
        tooltip = "+1"
    })
end

local populate_science_filters = function(player_index, anchor)
    local scitbl = gutil.get_child(anchor, "allowed_science_table")
    if not scitbl then
        logger.error(nil, "Did not find allowed science table, please open a bug report on the mod portal")
        return
    end
    scitbl.clear()
    scitbl.style.height = 64

    local sci = util.get_all_sciences()

    local p = game.get_player(player_index)
    local force_index = p and p.force.index or player_index
    local science_counts = queue.get_science_counts(force_index)

    -- Add all the sciences as icons to the table
    for _, s in pairs(sci) do
        local container = scitbl.add({
            type = "flow",
            direction = "vertical"
        })
        container.style.width = 46
        container.style.horizontal_align = "center"

        local count = science_counts[s] or 0
        local sprop = {
            type = "sprite-button",
            name = "allowed_science_btn_" .. s,
            style = "lil_einstein_science_pack_button",
            sprite = "item/" .. s,
            hovered_sprite = "item/" .. s,
            clicked_sprite = "item/" .. s,
            toggled = state.get_player_setting(player_index, "allowed_" .. s, false),
            tooltip = get_science_tooltip(player_index, force_index, s, count),
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_allowed_science",
                science = s
            }
        }
        local btn = container.add(sprop)
        btn.style.width = 46
        btn.style.height = 55

        if count > 0 then
            local count_label = container.add({
                type = "label",
                name = "allowed_science_count_" .. s,
                caption = gutil.format_cost(count),
                ignored_by_interaction = true
            })
            count_label.style.width = 44
            count_label.style.horizontal_align = "center"
            count_label.style.top_margin = -6
            count_label.style.font = "default-small"
            count_label.style.font_color = {r = 1, g = 1, b = 1}
        end
    end

end

local populate_hide_categories = function(player_index, anchor)
    local flow = gutil.get_child(anchor, "hide_tech_flow")
    if not flow then
        logger.error(nil, "Did not find hide tech flow, skipping hide categories")
        return
    end
    flow.clear()
    for k, v in pairs(const.default_settings.player.hide_tech) do
        local state = state.get_player_setting(player_index, k, v)
        local prop = {
            type = "checkbox",
            name = k,
            caption = {"lil_einstein-hide-tech." .. k},
            state = state,
            tags = {
                lil_einstein_on_state_change = true,
                handler = "toggle_checkbox_player",
                setting_name = k
            }
        }
        flow.add(prop)
    end
end

local populate_show_categories = function(player_index, anchor)
    local flow = gutil.get_child(anchor, "show_tech_flow")
    if not flow then
        logger.error(nil, "Did not find show tech flow, skipping show categories")
        return
    end
    flow.clear()
    local setting = "show_tech_filter_category"
    local selected = state.get_player_setting(player_index, setting, const.default_settings.player.show_tech.selected)
    for k, v in pairs(const.categories) do
        local row = flow.add({
            type = "flow",
            direction = "horizontal",
            style = "lil_einstein_horizontal_flow_nospacing"
        })
        row.style.height = 23
        local prop = {
            type = "button",
            name = k,
            style = k == selected and "lil_einstein_radio_button_on" or "lil_einstein_radio_button_off",
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_radiobutton_player",
                setting_name = setting,
                value = k
            }
        }
        row.add(prop)
        local label = row.add({
            type = "label",
            caption = {"lil_einstein-filter-category." .. k},
            tags = {
                lil_einstein_on_click = true,
                handler = "toggle_radiobutton_player",
                setting_name = setting,
                value = k
            }
        })
        label.style.left_margin = 6
    end
end

local set_master_enable = function(player_index, anchor)
    -- Get player and force
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local f = p.force

    -- Get the master switch
    local sw = gutil.get_child(anchor, "master_enable")
    if not sw then
        return
    end

    -- Get the state from storage or default settings
    local st = state.get_force_setting(f.index, "master_enable")
    if st == nil then
        st = const.default_settings.force.master_enable
    end

    -- Set the state
    if sw.type == "switch" then
        sw.switch_state = st
    else
        if st == "left" then
            sw.sprite = "lil_einstein_mockup_enable_switch_off"
            sw.hovered_sprite = "lil_einstein_mockup_enable_switch_off"
            sw.clicked_sprite = "lil_einstein_mockup_enable_switch_off"
            sw.toggled = false
        else
            sw.sprite = "lil_einstein_mockup_enable_switch_on"
            sw.hovered_sprite = "lil_einstein_mockup_enable_switch_on"
            sw.clicked_sprite = "lil_einstein_mockup_enable_switch_on"
            sw.toggled = true
        end
    end

    -- Disable/enable the rest of the content based on the state
    -- Forward delcare recursive function

    -- The new enabled state for the elements
    local enbl = true
    local lbl = gutil.get_child(anchor, "master_enable_label")
    if lbl then
        lbl.style = "bold_label"
        lbl.style.left_margin = 9
        lbl.style.top_margin = 1
        lbl.style.font_color = {0.945, 0.745, 0.392}
    end
    if st == "left" then
        enbl = false
        if lbl then
            lbl.style = "label"
            lbl.style.left_margin = 9
            lbl.style.top_margin = 1
        end
    end

    -- Loop through entry point elements
    for _, c in pairs({"queue_pane", "frame_upcoming", "right"}) do
        -- Get the child element, then call recursive function for that element
        gutil.disenable_recursive(gutil.get_child(anchor, c), enbl)
    end
end

local update_styles = function(player_index, anchor)
    local lbl
    lbl = gutil.get_child(anchor, "available_tech_lbl")
    if lbl then
        lbl.style.bottom_margin = 4
    end

    local row = gutil.get_child(anchor, "enable_row")
    if row then
        row.style.height = 24
        row.style.top_margin = 1
    end

    row = gutil.get_child(anchor, "subsettings")
    if row then
        row.style.top_margin = 16
    end

    row = gutil.get_child(anchor, "force_settings_flow")
    if row then
        row.style.vertical_spacing = 0
    end
end

local add_policy_toggle = function(flow, force_index, setting_name, caption, tooltip, enabled)
    local value = policy.get_setting(force_index, setting_name)
    local row = flow.add({type = "flow", direction = "horizontal", style = "lil_einstein_horizontal_flow_nospacing"})
    row.style.height = 25
    row.style.vertical_align = "center"
    local button = row.add({
        type = "button",
        style = value and "lil_einstein_settings_checkbox_on" or "lil_einstein_settings_checkbox_off",
        enabled = enabled ~= false,
        tags = {
            lil_einstein_on_click = true,
            handler = "toggle_policy_setting",
            setting_name = setting_name
        },
        tooltip = tooltip
    })
    button.style.right_margin = 7
    row.add({type = "label", caption = caption, tooltip = tooltip})
end

local add_policy_number = function(flow, force_index, setting_name, caption, step, suffix)
    local row = flow.add({type = "flow", direction = "horizontal"})
    row.style.vertical_align = "center"
    local label = row.add({type = "label", caption = caption})
    label.style.width = 265
    row.add({
        type = "button",
        caption = "-",
        tags = {
            lil_einstein_on_click = true,
            handler = "adjust_policy_setting",
            setting_name = setting_name,
            delta = -step
        }
    })
    local value = policy.get_setting(force_index, setting_name)
    local formatted = value
    if setting_name == "finish_current_threshold" then
        formatted = tostring(math.floor((value or 0) * 100 + 0.5)) .. "%"
    else
        formatted = tostring(value) .. (suffix or "")
    end
    local value_label = row.add({type = "label", caption = formatted})
    value_label.style.width = 75
    value_label.style.horizontal_align = "center"
    row.add({
        type = "button",
        caption = "+",
        tags = {
            lil_einstein_on_click = true,
            handler = "adjust_policy_setting",
            setting_name = setting_name,
            delta = step
        }
    })
end

local populate_policy_general = function(player_index, anchor)
    local p = game.get_player(player_index)
    local flow = gutil.get_child(anchor, "policy_general_flow")
    if not p or not flow then
        return
    end
    flow.clear()
    flow.style.width = 690
    flow.style.padding = 8
    flow.style.vertical_spacing = 5

    local strategy_row = flow.add({type = "flow", direction = "horizontal"})
    local strategy_label = strategy_row.add({type = "label", caption = {"lil_einstein-policy.strategy"}})
    strategy_label.style.width = 265
    local items = {}
    local selected = 1
    local current = policy.get_setting(p.force.index, "strategy")
    for index, strategy in ipairs(policy.strategy_order) do
        table.insert(items, {"lil_einstein-strategy." .. strategy})
        if current == strategy then
            selected = index
        end
    end
    strategy_row.add({
        type = "drop-down",
        items = items,
        selected_index = selected,
        tags = {lil_einstein_on_state_change = true, handler = "policy_strategy"}
    })

    add_policy_toggle(flow, p.force.index, "planning_paused", {"lil_einstein-policy.planning-paused"},
        {"lil_einstein-policy.planning-paused-description"})
    add_policy_toggle(flow, p.force.index, "parallel_research", {"lil_einstein-policy.parallel-research"},
        policy.parallel_mod_available() and {"lil_einstein-policy.parallel-research-integration"} or
            {"lil_einstein-policy.parallel-research-description"})
    add_policy_toggle(flow, p.force.index, "cluster_mode", {"lil_einstein-policy.cluster-mode"},
        {"lil_einstein-policy.cluster-mode-description"})
    add_policy_toggle(flow, p.force.index, "performance_mode", {"lil_einstein-policy.performance-mode"},
        {"lil_einstein-policy.performance-mode-description"})
    add_policy_number(flow, p.force.index, "min_switch_seconds", {"lil_einstein-policy.minimum-switch-time"}, 5, "s")
    add_policy_number(flow, p.force.index, "finish_current_threshold", {"lil_einstein-policy.finish-threshold"}, 0.05)
    add_policy_number(flow, p.force.index, "forecast_seconds", {"lil_einstein-policy.forecast-horizon"}, 30, "s")
    add_policy_number(flow, p.force.index, "parallel_slots", {"lil_einstein-policy.parallel-slots"}, 1)
end

local format_policy_time = function(seconds)
    if not seconds then
        return "--"
    end
    if seconds == math.huge then
        return "never"
    end
    if seconds >= 3600 then
        return string.format("%.1fh", seconds / 3600)
    end
    if seconds >= 60 then
        return string.format("%.1fm", seconds / 60)
    end
    return tostring(math.floor(seconds + 0.5)) .. "s"
end

local populate_policy_science = function(player_index, anchor)
    local p = game.get_player(player_index)
    local flow = gutil.get_child(anchor, "policy_science_flow")
    if not p or not flow then
        return
    end
    flow.clear()
    flow.style.width = 690
    flow.style.padding = 8
    local forecast = queue.get_science_forecast(p.force.index)

    for _, science in ipairs(util.get_all_sciences()) do
        local item = policy.get_science_policy(p.force.index, science)
        local data = forecast[science] or {}
        local row = flow.add({type = "flow", direction = "horizontal"})
        row.style.height = 34
        row.style.vertical_align = "center"
        local icon = row.add({type = "sprite", sprite = "item/" .. science, tooltip = {"item-name." .. science}})
        icon.style.size = 28
        local priority = row.add({
            type = "button",
            caption = {"lil_einstein-science-priority." .. item.priority},
            tags = {lil_einstein_on_click = true, handler = "cycle_science_priority", science = science},
            tooltip = {"lil_einstein-policy.priority-cycle"}
        })
        priority.style.width = 92

        local low = row.add({type = "label", caption = "L " .. tostring(math.floor(item.lower_threshold * 100 + 0.5)) .. "%"})
        low.style.width = 52
        row.add({
            type = "button",
            caption = "-",
            tags = {
                lil_einstein_on_click = true,
                handler = "adjust_science_threshold",
                science = science,
                threshold_name = "lower",
                delta = -0.05
            }
        })
        row.add({
            type = "button",
            caption = "+",
            tags = {
                lil_einstein_on_click = true,
                handler = "adjust_science_threshold",
                science = science,
                threshold_name = "lower",
                delta = 0.05
            }
        })
        local high = row.add({type = "label", caption = "H " .. tostring(math.floor(item.upper_threshold * 100 + 0.5)) .. "%"})
        high.style.width = 54
        row.add({
            type = "button",
            caption = "-",
            tags = {
                lil_einstein_on_click = true,
                handler = "adjust_science_threshold",
                science = science,
                threshold_name = "upper",
                delta = -0.05
            }
        })
        row.add({
            type = "button",
            caption = "+",
            tags = {
                lil_einstein_on_click = true,
                handler = "adjust_science_threshold",
                science = science,
                threshold_name = "upper",
                delta = 0.05
            }
        })
        local rates = row.add({
            type = "label",
            caption = string.format("%s  +%.1f/−%.1f min  empty %s", gutil.format_cost(data.stock or 0),
                data.production_per_minute or 0, data.consumption_per_minute or 0,
                format_policy_time(data.depletion_seconds))
        })
        rates.style.left_margin = 8
    end
end

local populate_policy_budget = function(player_index, anchor)
    local p = game.get_player(player_index)
    local flow = gutil.get_child(anchor, "policy_budget_flow")
    if not p or not flow then
        return
    end
    flow.clear()
    flow.style.width = 690
    flow.style.padding = 8
    local budget_limit = policy.get_setting(p.force.index, "performance_mode") and 100 or 250
    local budget = queue.get_queue_budget(p.force.index, budget_limit)
    flow.add({
        type = "label",
        caption = {"lil_einstein-policy.budget-summary", budget.technology_count, format_policy_time(budget.total_seconds),
                   budget.unlock_count}
    })
    if budget.repeat_unbounded then
        flow.add({type = "label", caption = {"lil_einstein-policy.budget-repeat-unbounded"}})
    elseif budget.repeat_truncated then
        flow.add({type = "label", caption = {"lil_einstein-policy.budget-repeat-truncated", budget_limit}})
    end
    if budget.limiting_science then
        flow.add({
            type = "label",
            caption = {"", {"lil_einstein-policy.limiting-science"}, " [img=item/", budget.limiting_science, "] ",
                       {"item-name." .. budget.limiting_science}}
        })
    end
    for _, science in ipairs(util.get_all_sciences()) do
        local item = budget.sciences[science]
        if item then
            local row = flow.add({type = "flow", direction = "horizontal"})
            local icon = row.add({type = "sprite", sprite = "item/" .. science})
            icon.style.size = 24
            local label = row.add({
                type = "label",
                caption = {"lil_einstein-policy.budget-science-row", gutil.format_cost(math.ceil(item.required)),
                           gutil.format_cost(item.available), gutil.format_cost(math.ceil(item.deficit)),
                           string.format("%.1f", item.production_per_minute)}
            })
            label.style.left_margin = 5
        end
    end
end

local get_trigger_action = function(trigger)
    if not trigger then
        return {"lil_einstein-trigger.unknown"}
    end
    local trigger_type = trigger.type
    if trigger_type == "craft-item" and trigger.item then
        local name = trigger.item.name or trigger.item
        local item = prototypes.item[name]
        local tagged = {"", "[item=" .. name .. "] ", item and item.localised_name or name}
        if (trigger.count or 1) == 1 then
            return {"technology-trigger.craft-item", tagged}
        end
        return {"technology-trigger.craft-items", trigger.count, tagged}
    elseif trigger_type == "mine-entity" and trigger.entity then
        local name = trigger.entity.name or trigger.entity
        local entity = prototypes.entity[name]
        return {"technology-trigger.mine-entity", {"", "[entity=" .. name .. "] ", entity and entity.localised_name or name}}
    elseif trigger_type == "craft-fluid" and trigger.fluid then
        local name = trigger.fluid.name or trigger.fluid
        local fluid = prototypes.fluid[name]
        return {"lil_einstein-trigger-action.craft-fluid", trigger.amount or 0,
                {"", "[fluid=" .. name .. "] ", fluid and fluid.localised_name or name}}
    elseif trigger_type == "build-entity" and trigger.entity then
        local name = trigger.entity.name or trigger.entity
        local entity = prototypes.entity[name]
        return {"technology-trigger.build-entity", {"", "[entity=" .. name .. "] ", entity and entity.localised_name or name}}
    elseif trigger_type == "send-item-to-orbit" and trigger.item then
        local name = trigger.item.name or trigger.item
        local item = prototypes.item[name]
        return {"technology-trigger.send-item-to-orbit", {"", "[item=" .. name .. "] ", item and item.localised_name or name}}
    elseif trigger_type == "capture-spawner" then
        if trigger.entity then
            local entity = prototypes.entity[trigger.entity]
            return {"technology-trigger.capture-spawner",
                    {"", "[entity=" .. trigger.entity .. "] ", entity and entity.localised_name or trigger.entity}}
        end
        return {"technology-trigger.capture-any-spawner"}
    elseif trigger_type == "create-space-platform" then
        return {"technology-trigger.create-space-platform-specific", {"item-name.space-platform-starter-pack"}}
    elseif trigger_type == "scripted" and trigger.trigger_description then
        return trigger.trigger_description
    end
    return {"lil_einstein-trigger." .. tostring(trigger_type or "unknown")}
end

local populate_policy_triggers = function(player_index, anchor)
    local p = game.get_player(player_index)
    local flow = gutil.get_child(anchor, "policy_trigger_flow")
    if not p or not flow then
        return
    end
    flow.clear()
    flow.style.width = 690
    flow.style.padding = 8
    local objectives = queue.get_trigger_objectives(p.force.index)
    if #objectives == 0 then
        flow.add({type = "label", caption = {"lil_einstein-policy.no-manual-objectives"}})
        return
    end
    for index = 1, math.min(12, #objectives) do
        local item = objectives[index]
        local row = flow.add({type = "flow", direction = "horizontal"})
        local icon = row.add({type = "sprite", sprite = "technology/" .. item.tech_name})
        icon.style.size = 28
        local button = row.add({
            type = "button",
            caption = {"", item.xcur.technology.localised_name, " — ",
                       {"lil_einstein-trigger." .. item.trigger_type}},
            tags = {lil_einstein_on_click = true, handler = "show_trigger_technology", technology = item.tech_name},
            tooltip = {"", item.ready and {"lil_einstein-policy.trigger-ready"} or
                {"lil_einstein-policy.trigger-blocked"}, "\n", get_trigger_action(item.xcur.meta.prototype.research_trigger)}
        })
        button.style.width = 610
    end
end

local populate_policy_presets = function(player_index, anchor)
    local p = game.get_player(player_index)
    local flow = gutil.get_child(anchor, "policy_preset_flow")
    if not p or not flow then
        return
    end
    flow.clear()
    flow.style.width = 690
    flow.style.padding = 8
    local name_row = flow.add({type = "flow", direction = "horizontal"})
    local name_field = name_row.add({
        type = "textfield",
        name = "policy_preset_name",
        text = state.get_player_setting(player_index, "plan_preset_name", ""),
        tags = {lil_einstein_on_change = true, handler = "policy_preset_name"}
    })
    name_field.style.width = 330
    name_row.add({
        type = "button",
        caption = {"lil_einstein-policy.save-preset"},
        tags = {lil_einstein_on_click = true, handler = "save_plan_preset"}
    })

    local names = queue.get_preset_names(p.force.index)
    local selected_name = state.get_player_setting(player_index, "selected_plan_preset")
    local selected_index = 0
    for index, name in ipairs(names) do
        if name == selected_name then
            selected_index = index
            break
        end
    end
    if #names > 0 then
        if selected_index == 0 then
            selected_index = 1
            state.set_player_setting(player_index, "selected_plan_preset", names[1])
        end
        local preset_row = flow.add({type = "flow", direction = "horizontal"})
        local dropdown = preset_row.add({
            type = "drop-down",
            items = names,
            selected_index = selected_index,
            tags = {lil_einstein_on_state_change = true, handler = "policy_preset_selection"}
        })
        dropdown.style.width = 330
        preset_row.add({
            type = "button",
            caption = {"lil_einstein-policy.load-preset"},
            tags = {lil_einstein_on_click = true, handler = "load_plan_preset"}
        })
        preset_row.add({
            type = "button",
            caption = {"lil_einstein-policy.delete-preset"},
            tags = {lil_einstein_on_click = true, handler = "delete_plan_preset"}
        })
    end

    local exchange = flow.add({
        type = "textfield",
        name = "policy_exchange_string",
        text = state.get_player_setting(player_index, "plan_exchange_string", ""),
        tags = {lil_einstein_on_change = true, handler = "policy_exchange_string"}
    })
    exchange.style.width = 650
    local exchange_row = flow.add({type = "flow", direction = "horizontal"})
    exchange_row.add({
        type = "button",
        caption = {"lil_einstein-policy.export-plan"},
        tags = {lil_einstein_on_click = true, handler = "export_plan"}
    })
    exchange_row.add({
        type = "button",
        caption = {"lil_einstein-policy.import-plan"},
        tags = {lil_einstein_on_click = true, handler = "import_plan"}
    })
end

local populate_policy_history = function(player_index, anchor)
    local p = game.get_player(player_index)
    local flow = gutil.get_child(anchor, "policy_history_flow")
    if not p or not flow then
        return
    end
    flow.clear()
    flow.style.width = 690
    flow.style.padding = 8
    add_policy_toggle(flow, p.force.index, "multiplayer_lock", {"lil_einstein-policy.multiplayer-lock"},
        {"lil_einstein-policy.multiplayer-lock-description"}, p.admin)
    local history = policy.get_history(p.force.index)
    if #history == 0 then
        flow.add({type = "label", caption = {"lil_einstein-policy.no-history"}})
        return
    end
    for index = 1, math.min(10, #history) do
        local item = history[index]
        local seconds_ago = math.max(0, math.floor((game.tick - (item.tick or game.tick)) / 60))
        flow.add({
            type = "label",
            caption = {"lil_einstein-policy.history-row", format_policy_time(seconds_ago), item.player, item.action,
                       item.detail}
        })
    end
end

local populate_policy_panel = function(player_index, anchor)
    local pane = gutil.get_child(anchor, "policy_scroll_pane")
    if pane then
        pane.style.height = 640
        pane.style.width = 1510
    end
    local sections = gutil.get_child(anchor, "policy_sections_table")
    if sections then
        sections.style.horizontal_spacing = 10
        sections.style.vertical_spacing = 10
    end
    populate_policy_general(player_index, anchor)
    populate_policy_budget(player_index, anchor)
    populate_policy_science(player_index, anchor)
    populate_policy_triggers(player_index, anchor)
    populate_policy_presets(player_index, anchor)
    populate_policy_history(player_index, anchor)
end

local policy_panel_is_visible = function(anchor)
    local panel = gutil.get_child(anchor, "policy_panel")
    return panel and panel.visible == true
end

local research_details_panel_is_visible = function(anchor)
    local panel = gutil.get_child(anchor, "research_details_panel")
    return panel and panel.visible == true
end

content.repopulate_static = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        populate_policy_panel(player_index, anchor)
        return
    elseif research_details_panel_is_visible(anchor) then
        refresh_research_details(player_index, anchor)
        return
    end
    populate_force_settings(player_index, anchor)
    populate_science_filters(player_index, anchor)
    populate_hide_categories(player_index, anchor)
    populate_show_categories(player_index, anchor)
    update_styles(player_index, anchor)
end

content.repopulate_dynamic = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    elseif research_details_panel_is_visible(anchor) then
        refresh_research_details(player_index, anchor)
        return
    end
    gctech.populate(player_index, anchor)
    gcupcoming.populate(player_index, anchor)
    refresh_research_status(player_index, anchor)
    set_master_enable(player_index, anchor)
end

content.repopulate_all = function(player_index, anchor)
    content.repopulate_static(player_index, anchor)
    content.repopulate_dynamic(player_index, anchor)
end

content.repopulate_tech = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    gctech.populate(player_index, anchor)
end

content.refresh_upcoming = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    gcupcoming.populate(player_index, anchor)
end

content.refresh_upcoming_times = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    gcupcoming.refresh_times(player_index, anchor)
end

content.refresh_science_counts = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    refresh_science_counts(player_index, anchor)
end

content.refresh_research_status = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    refresh_research_status(player_index, anchor)
end

content.refresh_research_progress = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    refresh_research_progress(player_index, anchor)
end

content.refresh_research_metrics = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    refresh_research_metrics(player_index, anchor)
end

content.refresh_research_details = function(player_index, anchor)
    refresh_research_details(player_index, anchor)
end

content.refresh_research_graph = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    refresh_research_graph(player_index, anchor)
end

content.show_research_graph_hover = function(player_index, anchor, column_index)
    show_research_graph_hover(player_index, anchor, column_index)
end

content.hide_research_graph_hover = function(player_index, anchor)
    hide_research_graph_hover(player_index, anchor)
end

content.repopulate_policy = function(player_index, anchor)
    populate_policy_panel(player_index, anchor)
end

return content
