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
local policy_tabs = {
    {name = "automation", section = "policy_general_flow", button = "policy_tab_automation"},
    {name = "budget", section = "policy_budget_flow", button = "policy_tab_budget"},
    {name = "science", section = "policy_science_flow", button = "policy_tab_science"},
    {name = "objectives", section = "policy_trigger_flow", button = "policy_tab_objectives"},
    {name = "presets", section = "policy_preset_flow", button = "policy_tab_presets"},
    {name = "history", section = "policy_history_flow", button = "policy_tab_history"}
}
local policy_history_filters = {"all", "switch", "strategy", "policy", "queue", "setting"}
local ordered_force_settings = {"requeue_infinite_tech", "auto_research"}
local research_graph_column_count = 200
local research_graph_sample_seconds = 3
local research_graph_plot_width = 456
local research_graph_plot_height = 118
local research_graph_hover_dot_height = 3
local research_graph_hover_column_setting = "research_graph_hover_column"
local graph_render_cache = {}
local science_render_cache = {}
local science_pack_panel_render_cache = {}
local graph_render_jobs = {}
local graph_hover_cache = {}
local research_status_cache = {}
local research_graph_render_budget = 40

local get_graph_render_state = function(element)
    local index = element.index
    local rendered = graph_render_cache[index]
    if not rendered or not rendered.element.valid or rendered.element ~= element then
        rendered = {element = element}
        graph_render_cache[index] = rendered
    end
    return rendered
end

local get_science_tooltip = function(player_index, force_index, science, total_count)
    local item_name = state.get_translation(player_index, "item", science, "localised_name") or science
    local detail = queue.get_science_display_breakdown(force_index, science)
    local science_policy = policy.get_science_policy(force_index, science)
    local forecast = queue.get_science_display_forecast(force_index)[science] or {}
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
                   "Production / consumption: " .. gutil.format_si(forecast.production_per_minute or 0) .. " / " ..
                   gutil.format_si(forecast.consumption_per_minute or 0) .. " per minute"

    if forecast.depletion_seconds then
        local depletion = forecast.depletion_seconds
        if depletion == math.huge then
            tt = tt .. "\nEstimated depletion: ∞"
        else
            tt = tt .. "\nEstimated depletion: " .. tostring(math.floor(depletion + 0.5)) .. "s"
        end
    elseif forecast.recovery_seconds then
        tt = tt .. "\nEstimated recovery: " .. tostring(math.floor(forecast.recovery_seconds + 0.5)) .. "s"
    end
    tt = tt .. "\nLeft-click: inspect science pack\nRight-click: cycle automation priority"

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

local refresh_science_counts = function(player_index, anchor, budget)
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local force_index = p.force.index
    local science_counts = queue.get_science_display_counts(force_index)
    local sciences = util.get_all_sciences()
    local anchor_index = anchor.index
    local rendered = science_render_cache[anchor_index]
    if not rendered or not rendered.element.valid or rendered.element ~= anchor then
        rendered = {
            element = anchor,
            force_index = force_index,
            revision = nil,
            next_index = 1,
            sciences = {}
        }
        science_render_cache[anchor_index] = rendered
    end
    local revision = queue.get_research_health_snapshot_tick(force_index)
    if rendered.force_index ~= force_index or rendered.revision ~= revision then
        rendered.force_index = force_index
        rendered.revision = revision
        rendered.next_index = 1
    end
    if not rendered.next_index then
        return
    end

    local last = math.min(#sciences, rendered.next_index + (budget or 1) - 1)
    for index = rendered.next_index, last do
        local science = sciences[index]
        local count = science_counts[science] or 0
        local btn = gutil.get_child(anchor, "allowed_science_btn_" .. science)
        local science_rendered = rendered.sciences[science] or {}
        local tooltip = get_science_tooltip(player_index, force_index, science, count)
        if btn and science_rendered.tooltip ~= tooltip then
            btn.tooltip = tooltip
            science_rendered.tooltip = tooltip
        end
        local selected = state.get_player_setting(player_index, "science_pack_panel_science") == science
        if btn and btn.toggled ~= selected then
            btn.toggled = selected
        end

        local label_name = "allowed_science_count_" .. science
        local count_label = gutil.get_child(anchor, label_name)
        if count > 0 then
            local caption = gutil.format_cost(count)
            if count_label then
                if science_rendered.caption ~= caption then
                    count_label.caption = caption
                end
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
            science_rendered.caption = caption
        elseif count_label then
            count_label.destroy()
            science_rendered.caption = nil
        end
        rendered.sciences[science] = science_rendered
    end
    rendered.next_index = last < #sciences and last + 1 or nil
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

local set_caption = function(element, caption)
    if element then
        element.caption = caption
    end
end

local set_table_rows = function(table_element, rows, rendered, column_count, key_fn, caption_fn)
    if not table_element then
        return
    end
    local signature_parts = {}
    for _, row in ipairs(rows or {}) do
        table.insert(signature_parts, tostring(key_fn(row)))
    end
    local signature = table.concat(signature_parts, "\31")
    if rendered.signature ~= signature then
        table_element.clear()
        for _ = 1, (#rows or 0) * column_count do
            table_element.add({type = "label", caption = "", ignored_by_interaction = true})
        end
        rendered.signature = signature
    end

    for row_index, row in ipairs(rows or {}) do
        local captions = caption_fn(row)
        local offset = (row_index - 1) * column_count
        for column = 1, column_count do
            local cell = table_element.children[offset + column]
            if cell then
                cell.caption = captions[column] or ""
            end
        end
    end
end

local get_science_pack_status = function(insight)
    local labs = insight.labs or {}
    if (insight.current_stock or 0) <= 0 or
        ((labs.compatible_labs or 0) > 0 and (labs.starved_labs or 0) >= (labs.compatible_labs or 0)) then
        return "starved"
    end
    if (insight.net_per_minute or 0) < 0 then
        return "at-risk"
    end
    return "healthy"
end

local get_transit_progress_caption = function(progress)
    if type(progress) ~= "number" then
        return ""
    end
    return tostring(math.floor(math.max(0, math.min(1, progress)) * 100 + 0.5)) .. "%"
end

local refresh_science_pack_panel = function(player_index, anchor)
    local panel = gutil.get_child(anchor, "science_pack_panel")
    if not panel or not panel.visible then
        return
    end
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local science = state.get_player_setting(player_index, "science_pack_panel_science")
    if type(science) ~= "string" then
        return
    end

    -- This is the only view path that asks for the world-scanning insight. The
    -- model keeps the result cached until the next open-panel refresh boundary.
    local insight = queue.get_science_pack_insight(p.force.index, science)
    if not insight then
        return
    end
    local rendered = science_pack_panel_render_cache[anchor.index]
    if not rendered or not rendered.element.valid or rendered.element ~= anchor then
        rendered = {element = anchor, generated_tick = nil, labs = {}, planets = {}, transit = {}}
        science_pack_panel_render_cache[anchor.index] = rendered
    end

    local item_name = state.get_translation(player_index, "item", science, "localised_name") or science
    local status = get_science_pack_status(insight)
    local status_caption = {"lil_einstein-science-pack.status-" .. status}
    local status_label = gutil.get_child(panel, "science_pack_panel_state")
    local icon = gutil.get_child(panel, "science_pack_panel_icon")
    set_caption(gutil.get_child(panel, "science_pack_panel_name"), item_name)
    set_caption(status_label, status_caption)
    if icon then
        icon.sprite = "item/" .. science
    end
    if status_label then
        status_label.style.font_color = status == "starved" and {1.0, 0.35, 0.25} or
            (status == "at-risk" and {1.0, 0.75, 0.25} or {0.45, 1.0, 0.55})
    end

    local seconds = math.max(0, math.ceil(((insight.next_refresh_tick or game.tick) - game.tick) / 60))
    set_caption(gutil.get_child(panel, "science_pack_panel_timer"),
        {"lil_einstein-science-pack.refreshes-in", seconds})

    local generated_tick = insight.generated_tick
    if generated_tick == nil or rendered.generated_tick ~= generated_tick then
        rendered.generated_tick = generated_tick
        set_caption(gutil.get_child(panel, "science_pack_panel_current_stock"),
            {"lil_einstein-science-pack.current-stock", gutil.format_cost(insight.current_stock or 0)})
        set_caption(gutil.get_child(panel, "science_pack_panel_flow_summary"),
            {"lil_einstein-science-pack.flow-summary", gutil.format_si(insight.production_per_minute or 0),
             gutil.format_si(insight.consumption_per_minute or 0), gutil.format_si(insight.net_per_minute or 0)})

        local labs = insight.labs or {}
        set_caption(gutil.get_child(panel, "science_pack_panel_labs_summary"),
            {"lil_einstein-science-pack.labs-summary", labs.compatible_labs or 0,
             labs.supplied_labs or 0, labs.starved_labs or 0})
        local lab_rows = labs.clusters or {}
        set_caption(gutil.get_child(panel, "science_pack_panel_labs_empty"),
            {"lil_einstein-science-pack.no-labs"})
        local lab_empty = gutil.get_child(panel, "science_pack_panel_labs_empty")
        if lab_empty then lab_empty.visible = #lab_rows == 0 end
        set_table_rows(gutil.get_child(panel, "science_pack_panel_labs_rows"), lab_rows, rendered.labs, 4,
            function(row) return row.key or row.label end,
            function(row)
                return {row.label or row.surface_name or "Nauvis", row.supplied_labs or 0,
                    row.starved_labs or 0, gutil.format_si(row.maximum_per_minute or 0)}
            end)

        local planet_rows = insight.planet_stock_rows or {}
        set_caption(gutil.get_child(panel, "science_pack_panel_planet_stock_summary"),
            {"lil_einstein-science-pack.planet-stock-summary", #planet_rows})
        local planet_empty = gutil.get_child(panel, "science_pack_panel_planet_stock_empty")
        if planet_empty then planet_empty.visible = #planet_rows == 0 end
        set_table_rows(gutil.get_child(panel, "science_pack_panel_planet_stock_rows"), planet_rows,
            rendered.planets, 2, function(row) return row.name end,
            function(row)
                return {row.name, (row.stock or 0) > 0 and gutil.format_cost(row.stock) or
                    {"lil_einstein-science-pack.no-stock"}}
            end)

        local transit = insight.in_transit or {}
        local transit_rows = transit.routes or {}
        set_caption(gutil.get_child(panel, "science_pack_panel_transit_summary"),
            {"lil_einstein-science-pack.transit-summary", gutil.format_cost(transit.total or 0),
             #transit_rows})
        local transit_empty = gutil.get_child(panel, "science_pack_panel_transit_empty")
        if transit_empty then transit_empty.visible = #transit_rows == 0 end
        set_table_rows(gutil.get_child(panel, "science_pack_panel_transit_rows"), transit_rows,
            rendered.transit, 4, function(row) return tostring(row.platform) .. ":" .. tostring(row.to) end,
            function(row)
                return {(row.from or "?") .. " → " .. (row.to or "?"), gutil.format_cost(row.stock or 0),
                    {"lil_einstein-science-pack.moving"}, get_transit_progress_caption(row.progress)}
            end)

        local flow = gutil.get_child(panel, "science_pack_panel_flow_balance")
        set_caption(gutil.get_child(flow, "science_pack_panel_flow_production"),
            {"lil_einstein-science-pack.flow-production", gutil.format_si(insight.production_per_minute or 0)})
        set_caption(gutil.get_child(flow, "science_pack_panel_flow_transit"),
            {"lil_einstein-science-pack.flow-transit", gutil.format_cost((insight.in_transit or {}).total or 0)})
        set_caption(gutil.get_child(flow, "science_pack_panel_flow_consumption"),
            {"lil_einstein-science-pack.flow-consumption", gutil.format_si(insight.consumption_per_minute or 0)})
        set_caption(gutil.get_child(flow, "science_pack_panel_flow_net"),
            {"lil_einstein-science-pack.flow-net", gutil.format_si(insight.net_per_minute or 0)})
    end
end

local format_status_si = function(value)
    return gutil.format_si(value or 0):gsub("K", "k")
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
        local rendered = get_graph_render_state(spacer)
        if rendered.height ~= height then
            spacer.style.height = height
            rendered.height = height
        end
        if not spacer.visible then
            spacer.visible = true
        end
    elseif spacer.visible then
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
        local rendered = get_graph_render_state(segment)
        if segment.value ~= 1 then
            segment.value = 1
        end
        if not rendered or rendered.width ~= width then
            segment.style.width = width
        end
        if not rendered or rendered.height ~= height then
            segment.style.height = height
        end
        if not rendered or rendered.bar_width ~= height then
            segment.style.bar_width = height
        end
        rendered.width = width
        rendered.height = height
        rendered.bar_width = height
        if not segment.visible then
            segment.visible = true
        end
    elseif segment.visible then
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
    if line_before and line_before.visible then
        line_before.visible = false
    end
    if dot and dot.visible then
        dot.visible = false
    end
    if line_after and line_after.visible then
        line_after.visible = false
    end
end

local clear_research_graph_hover_columns = function(anchor)
    local overlay = gutil.get_child(anchor, "research_graph_hover_overlay")
    if not overlay then
        return
    end

    local overlay_index = overlay.index
    local rendered = graph_hover_cache[overlay_index]
    if not rendered or not rendered.element.valid or rendered.element ~= overlay then
        rendered = {element = overlay}
        graph_hover_cache[overlay_index] = rendered
        for i = 1, research_graph_column_count do
            hide_research_graph_hover_column(overlay["research_graph_hover_column_" .. i], i)
        end
    elseif rendered.column_index then
        local i = rendered.column_index
        hide_research_graph_hover_column(overlay["research_graph_hover_column_" .. i], i)
    end
    rendered.column_index = nil
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
local research_details_content_width = 1510
local research_details_columns = {
    location = 180,
    missing = 220,
    labs = 190,
    capacity = 205,
    cause = 300,
    action = 415
}
local research_details_column_order = {"location", "missing", "labs", "capacity", "cause", "action"}
local research_details_pack_columns = {
    science = 165,
    stock = 55,
    maximum = 65,
    working = 65,
    missing = 65
}
local research_details_pack_column_order = {"science", "stock", "maximum", "working", "missing"}
local research_details_demand_columns = {
    science = 400,
    maximum = 370,
    working = 370,
    produced = 370
}
local research_details_demand_column_order = {"science", "maximum", "working", "produced"}
local research_details_throughput_columns = {
    science = 350,
    need = 190,
    used = 190,
    produced = 210,
    gap = 275,
    status = 335
}
local research_details_throughput_column_order = {"science", "need", "used", "produced", "gap", "status"}
local research_details_throughput_status_rank = {
    bottleneck = 1,
    starving = 2,
    balanced = 3,
    overproducing = 4
}
local research_details_throughput_status_colors = {
    bottleneck = {r = 1.00, g = 0.72, b = 0.18},
    starving = {r = 1.00, g = 0.20, b = 0.16},
    balanced = {r = 0.72, g = 0.72, b = 0.72},
    overproducing = {r = 0.46, g = 1.00, b = 0.20}
}
local research_details_throughput_status_sprites = {
    bottleneck = "utility/status_yellow",
    starving = "utility/status_not_working",
    balanced = "utility/status_inactive",
    overproducing = "utility/status_working"
}
local research_lab_inspection_columns = {
    name = 385,
    location = 380,
    status = 380,
    missing = 365
}
local research_lab_inspection_column_order = {"name", "location", "status", "missing"}
local diagnostic_state_colors = {
    idle = {0.70, 0.69, 0.64},
    measuring = {0.48, 0.78, 1.00},
    pack_bound = {1.00, 0.35, 0.20},
    operational_fault = {1.00, 0.45, 0.20},
    at_capacity = {0.20, 1.00, 0.20},
    degraded_unexplained = {1.00, 0.80, 0.20}
}

local localised_parameter_limit = 20
local concat_localised_parts
concat_localised_parts = function(parts)
    if #parts <= localised_parameter_limit then
        local res = {""}
        for _, part in ipairs(parts) do
            table.insert(res, part)
        end
        return res
    end

    local groups = {}
    local index = 1
    while index <= #parts do
        local group = {""}
        local group_end = math.min(index + localised_parameter_limit - 1, #parts)
        for group_index = index, group_end do
            table.insert(group, parts[group_index])
        end
        table.insert(groups, group)
        index = group_end + 1
    end
    return concat_localised_parts(groups)
end

local item_caption = function(science)
    if not science then
        return {"lil_einstein-throughput.no-pack"}
    end
    return {"", "[item=", science, "] ", {"item-name." .. science}}
end

local cause_caption = function(kind)
    return {throughput_prefix .. "cause-" .. tostring(kind or "other"):gsub("_", "-")}
end

local technology_caption = function(technology_name)
    if not technology_name then
        return {"lil_einstein-status.unknown-research"}
    end
    return {"", "[technology=", technology_name, "] ", {"technology-name." .. technology_name}}
end

local format_status_percent = function(value)
    return string.format("%.2f", math.max(0, math.min(100, (value or 0) * 100)))
end

local copy_sorted_missing_sciences = function(missing_sciences)
    local result = {}
    for _, missing in ipairs(missing_sciences or {}) do
        table.insert(result, missing)
    end
    table.sort(result, function(a, b)
        if (a.lost_spm or 0) == (b.lost_spm or 0) then
            return tostring(a.science or "") < tostring(b.science or "")
        end
        return (a.lost_spm or 0) > (b.lost_spm or 0)
    end)
    return result
end

local build_research_status_insights = function(diagnostic, summary, control_state, forecast)
    local insights = {}
    diagnostic = diagnostic or {}
    summary = summary or {}
    control_state = control_state or {}
    forecast = forecast or {}

    if diagnostic.state == "pack_bound" then
        local missing = copy_sorted_missing_sciences(diagnostic.missing_sciences)
        local pack_names = {}
        for index = 1, math.min(2, #missing) do
            if index > 1 then
                table.insert(pack_names, " + ")
            end
            table.insert(pack_names, item_caption(missing[index].science))
        end
        local labs = math.max(0, (diagnostic.compatible_labs or 0) - (diagnostic.working_labs or 0))
        table.insert(insights, {
            kind = "pack_bound",
            key = "pack_bound:" .. tostring(diagnostic.material_loss_spm or 0) .. ":" .. tostring(labs),
            loss_spm = diagnostic.material_loss_spm or 0,
            labs = labs,
            caption = {"lil_einstein-status.pack-bound", format_status_si(diagnostic.material_loss_spm or 0),
                       concat_localised_parts(pack_names), labs},
            tooltip = {"lil_einstein-status.pack-bound-tooltip", format_status_si(diagnostic.material_loss_spm or 0),
                       concat_localised_parts(pack_names), labs}
        })
        for _, missing_pack in ipairs(missing) do
            table.insert(insights, {
                kind = "missing_pack",
                key = "missing_pack:" .. tostring(missing_pack.science or "") .. ":" ..
                    tostring(missing_pack.labs or 0) .. ":" .. tostring(missing_pack.lost_spm or 0),
                science = missing_pack.science,
                caption = {"lil_einstein-status.missing-pack", item_caption(missing_pack.science),
                           missing_pack.labs or 0, format_status_si(missing_pack.lost_spm or 0)},
                tooltip = {"lil_einstein-status.missing-pack-tooltip", item_caption(missing_pack.science),
                           missing_pack.labs or 0, format_status_si(missing_pack.lost_spm or 0)}
            })
        end
    elseif diagnostic.state == "operational_fault" and diagnostic.dominant_cause then
        local cause = diagnostic.dominant_cause
        table.insert(insights, {
            kind = "operational_fault",
            key = "operational_fault:" .. tostring(cause.kind or "") .. ":" .. tostring(cause.labs or 0) .. ":" ..
                tostring(cause.lost_spm or 0),
            caption = {"lil_einstein-status.operational-fault", cause_caption(cause.kind), cause.labs or 0},
            tooltip = {"lil_einstein-status.operational-fault-tooltip", cause_caption(cause.kind),
                       cause.labs or 0, format_status_si(cause.lost_spm or 0)}
        })
    end

    if control_state.temp_tech and control_state.target_tech then
        table.insert(insights, {
            kind = "temporary",
            key = "temporary:" .. tostring(control_state.temp_tech) .. ":" .. tostring(control_state.target_tech),
            caption = {"lil_einstein-status.temporary", technology_caption(control_state.temp_tech),
                       technology_caption(control_state.target_tech)},
            tooltip = {"lil_einstein-status.temporary-tooltip", technology_caption(control_state.temp_tech),
                       technology_caption(control_state.target_tech)}
        })
    elseif control_state.target_tech then
        table.insert(insights, {
            kind = "switch_ready",
            key = "switch_ready:" .. tostring(control_state.target_tech),
            caption = {"lil_einstein-status.switch-ready", technology_caption(control_state.target_tech)},
            tooltip = {"lil_einstein-status.switch-ready-tooltip", technology_caption(control_state.target_tech)}
        })
    end

    local depletion
    for science, item in pairs(forecast) do
        if item and item.depletion_seconds and item.depletion_seconds > 0 and
            (not depletion or item.depletion_seconds < depletion.seconds) then
            depletion = {science = science, seconds = item.depletion_seconds}
        end
    end
    if depletion then
        table.insert(insights, {
            kind = "science_risk",
            key = "science_risk:" .. tostring(depletion.science) .. ":" .. tostring(depletion.seconds),
            science = depletion.science,
            caption = {"lil_einstein-status.science-risk", item_caption(depletion.science),
                       format_time(depletion.seconds)},
            tooltip = {"lil_einstein-status.science-risk-tooltip", item_caption(depletion.science),
                       format_time(depletion.seconds)}
        })
    end

    if summary.is_researching then
        table.insert(insights, {
            kind = "progress",
            key = "progress:" .. tostring(control_state.live_current_tech) .. ":" .. tostring(summary.progress or 0) .. ":" ..
                tostring(summary.remaining_seconds or ""),
            caption = {"lil_einstein-status.progress", technology_caption(control_state.live_current_tech),
                       format_status_percent(summary.progress), format_time(summary.remaining_seconds)},
            tooltip = {"lil_einstein-status.progress-tooltip", technology_caption(control_state.live_current_tech),
                       format_status_percent(summary.progress), format_time(summary.remaining_seconds),
                       format_status_si(summary.spm or 0)}
        })
    end

    if #insights == 0 then
        table.insert(insights, {
            kind = "idle",
            key = "idle",
            caption = {"lil_einstein-status.idle"},
            tooltip = {"lil_einstein-status.idle-tooltip"}
        })
    end
    return insights
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

local get_dominant_missing_pack = function(source)
    if source and source.dominant_missing_science then
        return source.dominant_missing_science
    end
    return source and source.missing_sciences and source.missing_sciences[1] or nil
end

local format_missing_pack_summary = function(missing, fallback_lost_spm)
    if not missing then
        return {"lil_einstein-throughput.lost-cell", format_spaced_number(fallback_lost_spm)}
    end
    local lost_spm = format_spaced_number(-(missing.lost_spm or fallback_lost_spm or 0))
    return {"lil_einstein-throughput.missing-pack-summary", lost_spm,
            format_spaced_number(missing.missing_per_minute or 0), lost_spm}
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
        headline = {"lil_einstein-throughput.headline-missing-pack", state_label,
                    format_spaced_number(missing and missing.missing_per_minute or 0),
                    format_spaced_number(-(diagnostic.material_loss_spm or
                                           missing and missing.lost_spm or 0))}
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
    local tt = {
        "",
        {"", "[font=heading-2]", {"lil_einstein-throughput.tooltip-title"}, "[/font]\n"},
        {"", headline, "\n", evidence}
    }
    if not diagnostic or not diagnostic.available then
        return tt
    end

    table.insert(tt, {
        "",
        "\n\n",
        {"lil_einstein-throughput.tooltip-measured", format_spaced_number(diagnostic.actual_spm),
         diagnostic.sample_count or 0},
        "\n",
        {"lil_einstein-throughput.tooltip-capacity", format_spaced_number(diagnostic.expected_spm),
         format_spaced_number(diagnostic.working_spm)},
        "\n",
        {"lil_einstein-throughput.tooltip-labs", diagnostic.working_labs or 0,
         diagnostic.compatible_labs or 0, diagnostic.incompatible_labs or 0}
    })

    if diagnostic.causes and #diagnostic.causes > 0 then
        local causes = {
            "",
            "\n\n[font=default-bold]",
            {"lil_einstein-throughput.current-losses"},
            "[/font]"
        }
        for _, cause in ipairs(diagnostic.causes) do
            table.insert(causes, {
                "",
                "\n",
                cause.kind == "missing_science" and {
                    "lil_einstein-throughput.missing-pack-cause",
                    format_spaced_number((get_dominant_missing_pack(diagnostic) or {}).missing_per_minute or 0),
                    format_spaced_number(-(cause.lost_spm or 0)), cause.labs or 0
                } or {"lil_einstein-throughput.cause-evidence", cause_caption(cause.kind),
                      cause.labs or 0, format_spaced_number(cause.lost_spm)}
            })
        end
        table.insert(tt, concat_localised_parts(causes))
    end

    if diagnostic.missing_sciences and #diagnostic.missing_sciences > 0 then
        local packs = {
            "",
            "\n\n[font=default-bold]",
            {"lil_einstein-throughput.missing-pack-detail"},
            "[/font]"
        }
        local max_sciences = math.min(8, #diagnostic.missing_sciences)
        for i = 1, max_sciences do
            local item = diagnostic.missing_sciences[i]
            table.insert(packs, {
                "",
                "\n",
                {"lil_einstein-throughput.pack-evidence", item_caption(item.science),
                 format_spaced_number(item.missing_per_minute or 0),
                 format_spaced_number(-(item.lost_spm or 0)), item.labs or 0}
            })
        end
        table.insert(tt, packs)
    end

    table.insert(tt, {"", "\n\n", {"lil_einstein-throughput.capacity-method"}})
    return tt
end

local get_cluster_causes_caption = function(cluster)
    if not cluster.causes or #cluster.causes == 0 then
        if (cluster.incompatible_labs or 0) > 0 and (cluster.compatible_labs or 0) == 0 then
            return cause_caption("no_compatible_labs")
        end
        return {"lil_einstein-throughput.no-live-loss"}
    end

    local parts = {}
    for index, cause in ipairs(cluster.causes) do
        if index > 1 then
            table.insert(parts, "\n")
        end
        if cause.kind == "missing_science" then
            local missing = get_dominant_missing_pack(cluster)
            table.insert(parts, {"lil_einstein-throughput.missing-pack-cause",
                                 format_spaced_number(missing and missing.missing_per_minute or 0),
                                 format_spaced_number(-(cause.lost_spm or 0)), cause.labs or 0})
        else
            table.insert(parts, {"lil_einstein-throughput.cause-evidence", cause_caption(cause.kind),
                                 cause.labs or 0, format_spaced_number(cause.lost_spm)})
        end
    end
    return concat_localised_parts(parts)
end

local set_details_cell_width = function(element, width)
    if not element then
        return
    end
    element.style.width = width
    element.style.single_line = false
end

local get_cluster_missing_pack = function(cluster, science)
    for _, missing in ipairs(cluster and cluster.missing_sciences or {}) do
        if missing.science == science then
            return missing
        end
    end
    return nil
end

local get_cluster_affected_labs = function(cluster)
    local missing = get_dominant_missing_pack(cluster)
    if not missing then
        return {}
    end

    local affected = {}
    for _, descriptor in ipairs(cluster.lab_descriptors or {}) do
        for _, science in ipairs(descriptor.missing_sciences or {}) do
            if science == missing.science then
                table.insert(affected, descriptor)
                break
            end
        end
    end
    return affected
end

local lab_status_caption = function(status_key)
    local key = tostring(status_key or "other"):gsub("_", "-")
    return {throughput_prefix .. "lab-status-" .. key}
end

local lab_identity_caption = function(descriptor)
    local prototype_name = descriptor.prototype_name or "lab"
    return {throughput_prefix .. "lab-identity",
            {"", "[entity=", prototype_name, "]"}, descriptor.unit_number or 0}
end

local lab_location_caption = function(descriptor)
    if not descriptor.position then
        return {throughput_prefix .. "lab-location-unknown", descriptor.surface_name or "unknown"}
    end
    return {throughput_prefix .. "lab-location", descriptor.surface_name or "unknown",
            math.floor(descriptor.position.x + 0.5), math.floor(descriptor.position.y + 0.5)}
end

local lab_missing_caption = function(descriptor)
    local parts = {}
    for index, science in ipairs(descriptor.missing_sciences or {}) do
        if index > 1 then
            table.insert(parts, ", ")
        end
        table.insert(parts, item_caption(science))
    end
    if #parts == 0 then
        return {throughput_prefix .. "lab-missing-none"}
    end
    return concat_localised_parts(parts)
end

local add_details_table_cell = function(parent, name, caption, width, is_header, style_name)
    local label = parent.add({
        type = "label",
        name = name,
        style = style_name or (is_header and "bold_label" or nil),
        caption = caption
    })
    set_details_cell_width(label, width)
    return label
end

local get_research_details_pack_rate = function(rates, science)
    for _, item in ipairs(rates or {}) do
        if item.science == science then
            return item
        end
    end
    return nil
end

local get_science_throughput_status = function(need, used, produced)
    if need <= 0.001 then
        return produced > 0.001 and "overproducing" or "balanced"
    elseif produced > need * 1.05 then
        return "overproducing"
    elseif produced + 0.001 < need then
        return used + 0.001 < need and "starving" or "bottleneck"
    end
    return "balanced"
end

local build_science_throughput_rows = function(sciences, diagnostic, forecast)
    local res = {}
    local seen = {}
    diagnostic = diagnostic or {}
    forecast = forecast or {}
    local dominant_science = diagnostic.dominant_missing_science and
        diagnostic.dominant_missing_science.science
    for _, science in ipairs(sciences or {}) do
        if type(science) == "string" and not seen[science] then
            seen[science] = true
            local rate = get_research_details_pack_rate(diagnostic.science_pack_rates, science) or {}
            local production = forecast[science] or {}
            local need = math.max(0, rate.maximum_per_minute or 0)
            local used = math.max(0, rate.working_per_minute or 0)
            local produced = math.max(0, production.production_per_minute or 0)
            local gap = produced - need
            local status = get_science_throughput_status(need, used, produced)
            table.insert(res, {
                science = science,
                need = need,
                used = used,
                produced = produced,
                gap = gap,
                gap_ratio = math.min(1, math.abs(gap) / math.max(need, produced, 1)),
                status = status,
                status_rank = research_details_throughput_status_rank[status] or 99,
                primary = science == dominant_science
            })
        end
    end
    table.sort(res, function(a, b)
        if a.primary ~= b.primary then
            return a.primary
        elseif a.status_rank ~= b.status_rank then
            return a.status_rank < b.status_rank
        end
        return a.science < b.science
    end)
    return res
end

local format_throughput_rate = function(value)
    return format_status_si(value or 0)
end

local format_throughput_gap = function(value)
    value = value or 0
    if math.abs(value) < 0.001 then
        return "0 / min"
    end
    return (value > 0 and "+" or "") .. format_throughput_rate(value) .. " / min"
end

local set_throughput_cell_width = function(element, width)
    if element then
        element.style.width = width
    end
end

local add_throughput_row_label = function(parent, name, caption, width)
    local label = parent.add({
        type = "label",
        name = name,
        style = "lil_einstein_throughput_cell",
        caption = caption
    })
    set_throughput_cell_width(label, width)
    return label
end

local create_science_throughput_row = function(rows, index, item)
    local row = rows.add({
        type = "frame",
        name = "research_details_row_" .. index,
        style = "lil_einstein_throughput_row",
        direction = "horizontal",
        tags = {science = item.science}
    })
    if not row then
        return nil
    end
    local table_element = row.add({
        type = "table",
        name = "research_details_row_table_" .. index,
        style = "lil_einstein_throughput_row_table",
        column_count = #research_details_throughput_column_order
    })
    if not table_element then
        return row
    end

    local science_cell = table_element.add({
        type = "flow",
        name = "research_details_science_cell_" .. index,
        style = "lil_einstein_throughput_science_cell",
        direction = "horizontal"
    })
    set_throughput_cell_width(science_cell, research_details_throughput_columns.science)
    science_cell.add({
        type = "sprite",
        name = "research_details_science_icon_" .. index,
        sprite = "item/" .. item.science,
        style = "lil_einstein_throughput_science_icon",
        tooltip = {"item-name." .. item.science}
    })
    science_cell.add({
        type = "label",
        name = "research_details_science_name_" .. index,
        style = "lil_einstein_throughput_cell",
        caption = {"item-name." .. item.science}
    })
    add_throughput_row_label(table_element, "research_details_need_" .. index, "",
                             research_details_throughput_columns.capacity)
    add_throughput_row_label(table_element, "research_details_used_" .. index, "",
                             research_details_throughput_columns.active)
    add_throughput_row_label(table_element, "research_details_produced_" .. index, "",
                             research_details_throughput_columns.produced)

    local gap_cell = table_element.add({
        type = "flow",
        name = "research_details_gap_cell_" .. index,
        style = "lil_einstein_throughput_gap_cell",
        direction = "horizontal"
    })
    set_throughput_cell_width(gap_cell, research_details_throughput_columns.gap)
    gap_cell.add({
        type = "line",
        name = "research_details_gap_zero_" .. index,
        orientation = "vertical",
        style = "lil_einstein_throughput_zero_line"
    })
    gap_cell.add({
        type = "progressbar",
        name = "research_details_gap_meter_" .. index,
        style = "lil_einstein_throughput_meter",
        value = 0
    })
    gap_cell.add({
        type = "label",
        name = "research_details_gap_label_" .. index,
        style = "lil_einstein_throughput_gap_label",
        caption = "0 / min"
    })
    add_throughput_row_label(table_element, "research_details_runtime_" .. index, "",
                             research_details_throughput_columns.runtime)

    local status_cell = table_element.add({
        type = "flow",
        name = "research_details_status_cell_" .. index,
        style = "lil_einstein_throughput_status_cell",
        direction = "horizontal"
    })
    set_throughput_cell_width(status_cell, research_details_throughput_columns.status)
    status_cell.add({
        type = "sprite",
        name = "research_details_status_icon_" .. index,
        sprite = research_details_throughput_status_sprites.balanced,
        style = "lil_einstein_throughput_status_icon"
    })
    status_cell.add({
        type = "label",
        name = "research_details_status_" .. index,
        style = "bold_label",
        caption = {"lil_einstein-throughput.status-balanced"}
    })
    return row
end

local research_details_throughput_row_names = function(index)
    return {
        row = "research_details_row_" .. index,
        science_icon = "research_details_science_icon_" .. index,
        science_name = "research_details_science_name_" .. index,
        need = "research_details_need_" .. index,
        used = "research_details_used_" .. index,
        produced = "research_details_produced_" .. index,
        runtime = "research_details_runtime_" .. index,
        zero = "research_details_gap_zero_" .. index,
        meter = "research_details_gap_meter_" .. index,
        gap = "research_details_gap_label_" .. index,
        status_icon = "research_details_status_icon_" .. index,
        status = "research_details_status_" .. index
    }
end

local refresh_science_throughput_row = function(row, item, index, state)
    if not row or not row.valid then
        return
    end
    state = state or {}
    local names = research_details_throughput_row_names(index)
    local color = research_details_throughput_status_colors[item.status] or
        research_details_throughput_status_colors.balanced
    local need_caption = format_throughput_rate(item.need)
    local used_caption = format_throughput_rate(item.used)
    local produced_caption = format_throughput_rate(item.produced)
    local runtime_caption = format_throughput_runtime(item.depletion_seconds)
    local stock_caption = format_throughput_rate(item.stock)
    local in_transit_caption = format_throughput_rate(item.in_transit)
    local gap_caption = format_throughput_gap(item.gap)
    local status_caption = {throughput_prefix .. "status-" .. item.status}
    local status_sprite = research_details_throughput_status_sprites[item.status] or
        research_details_throughput_status_sprites.balanced

    if state.science ~= item.science then
        local science_icon = gutil.get_child(row, names.science_icon)
        local science_name = gutil.get_child(row, names.science_name)
        if science_icon then
            science_icon.sprite = "item/" .. item.science
        end
        if science_name then
            science_name.caption = {"item-name." .. item.science}
        end
        state.science = item.science
    end

    if state.need ~= need_caption then
        local need = gutil.get_child(row, names.need)
        if need then
            need.caption = need_caption
        end
        state.need = need_caption
    end
    if state.used ~= used_caption then
        local used = gutil.get_child(row, names.used)
        if used then
            used.caption = used_caption
        end
        state.used = used_caption
    end
    if state.produced ~= produced_caption then
        local produced = gutil.get_child(row, names.produced)
        if produced then
            produced.caption = produced_caption
        end
        state.produced = produced_caption
    end
    if state.runtime ~= runtime_caption or state.stock ~= stock_caption or
        state.in_transit ~= in_transit_caption then
        local runtime = gutil.get_child(row, names.runtime)
        if runtime then
            runtime.caption = runtime_caption
            runtime.tooltip = {throughput_prefix .. "runtime-tooltip", stock_caption, in_transit_caption}
        end
        state.runtime = runtime_caption
        state.stock = stock_caption
        state.in_transit = in_transit_caption
    end
    if state.gap_ratio ~= item.gap_ratio or state.status ~= item.status then
        local meter = gutil.get_child(row, names.meter)
        if meter then
            meter.value = item.gap_ratio
            meter.style.color = color
        end
        state.gap_ratio = item.gap_ratio
    end
    if state.gap ~= gap_caption or state.status ~= item.status then
        local gap = gutil.get_child(row, names.gap)
        if gap then
            gap.caption = gap_caption
            gap.style.font_color = color
        end
        state.gap = gap_caption
    end
    if state.status_sprite ~= status_sprite then
        local status_icon = gutil.get_child(row, names.status_icon)
        if status_icon then
            status_icon.sprite = status_sprite
        end
        state.status_sprite = status_sprite
    end
    if state.status ~= item.status then
        local status = gutil.get_child(row, names.status)
        if status then
            status.caption = status_caption
            status.style.font_color = color
        end
        state.status = item.status
    end
end

local refresh_science_throughput_warning = function(panel, rows, state, snapshot_age_seconds)
    state = state or {}
    local primary
    for _, item in ipairs(rows) do
        if item.status == "starving" or item.status == "bottleneck" then
            primary = item
            break
        end
    end
    local warning_key = primary and table.concat({
        primary.status,
        primary.science,
        format_throughput_rate(primary.need),
        format_throughput_rate(primary.used),
        format_throughput_rate(primary.produced),
        format_throughput_runtime(primary.depletion_seconds),
        format_throughput_runtime(snapshot_age_seconds or 0)
    }, "\31") or "clear\31" .. format_throughput_runtime(snapshot_age_seconds or 0)
    if state.warning_key == warning_key then
        return
    end
    state.warning_key = warning_key
    local icon = gutil.get_child(panel, "research_details_warning_icon")
    local headline = gutil.get_child(panel, "research_details_warning_headline")
    local evidence = gutil.get_child(panel, "research_details_warning_evidence")
    local checked = gutil.get_child(panel, "research_details_warning_checked")
    if primary then
        local color = research_details_throughput_status_colors[primary.status]
        if icon then
            icon.sprite = research_details_throughput_status_sprites[primary.status]
        end
        if headline then
            headline.caption = {throughput_prefix .. "warning-" .. primary.status,
                                item_caption(primary.science)}
            headline.style.font_color = color
        end
        if evidence then
            evidence.caption = {throughput_prefix .. "warning-evidence", format_throughput_rate(primary.need),
                                format_throughput_rate(primary.used), format_throughput_rate(primary.produced),
                                format_throughput_gap(primary.gap), format_throughput_runtime(primary.depletion_seconds)}
            evidence.tooltip = {throughput_prefix .. "warning-evidence-tooltip",
                                format_throughput_rate(primary.stock), format_throughput_rate(primary.in_transit)}
        end
    else
        if icon then
            icon.sprite = research_details_throughput_status_sprites.balanced
        end
        if headline then
            headline.caption = {throughput_prefix .. "warning-clear"}
            headline.style.font_color = research_details_throughput_status_colors.balanced
        end
        if evidence then
            evidence.caption = {throughput_prefix .. "warning-evidence-none"}
            evidence.tooltip = nil
        end
    end
    if checked then
        checked.caption = {throughput_prefix .. "last-checked",
                           format_throughput_runtime(snapshot_age_seconds or 0)}
    end
end

local refresh_science_throughput_details = function(player_index, anchor, diagnostic)
    local panel = gutil.get_child(anchor, "research_details_panel")
    local header = panel and gutil.get_child(panel, "research_details_table_header")
    local rows = panel and gutil.get_child(panel, "research_details_rows")
    if not panel or not header or not rows then
        return false
    end
    local p = game.get_player(player_index)
    if not p then
        return true
    end
    diagnostic = diagnostic or queue.get_research_display_diagnostic(p.force.index) or {}
    local forecast = queue.get_science_display_forecast(p.force.index) or {}
    local horizon_seconds = policy.get_setting(p.force.index, "forecast_seconds") or
        research_details_throughput_default_horizon_seconds
    local items = build_science_throughput_rows(util.get_all_sciences(), diagnostic, forecast,
                                                horizon_seconds)
    local current = p.force.current_research
    local current_name = current and current.name or nil

    local anchor_index = anchor.index
    local rendered = throughput_render_cache[anchor_index]
    if not rendered or not rendered.element.valid or rendered.element ~= anchor then
        rendered = {element = anchor, layout_done = false, signature = nil, row_states = {}, warning = {},
                    title_done = false, current_name = nil}
        throughput_render_cache[anchor_index] = rendered
    end

    if not rendered.title_done then
        local title = gutil.get_child(panel, "research_details_title")
        if title then
            title.caption = {throughput_prefix .. "details-title"}
        end
        rendered.title_done = true
    end
    if rendered.current_name ~= current_name then
        local current_label = gutil.get_child(panel, "research_details_current_research")
        if current_label then
            current_label.caption = current_name and {throughput_prefix .. "current-research", technology_caption(current_name)} or
                {throughput_prefix .. "current-research-none"}
        end
        rendered.current_name = current_name
    end

    local snapshot_tick = queue.get_research_health_snapshot_tick(p.force.index)
    local snapshot_age_seconds = snapshot_tick and snapshot_tick >= 0 and
        math.max(0, (game.tick - snapshot_tick) / 60) or 0
    refresh_science_throughput_warning(panel, items, rendered.warning, snapshot_age_seconds)

    if not rendered.layout_done then
        for _, column in ipairs(research_details_throughput_column_order) do
            set_throughput_cell_width(gutil.get_child(header, "research_details_header_" .. column),
                                      research_details_throughput_columns[column])
        end
        header.style.width = 1578
        local pane = gutil.get_child(panel, "research_details_scroll_pane")
        if pane then
            pane.style.width = 1578
            pane.style.height = 630
            pane.horizontal_scroll_policy = "never"
            pane.vertical_scroll_policy = "auto"
        end
        rows.style.width = 1578
        rendered.layout_done = true
    end

    local signature_parts = {}
    for _, item in ipairs(items) do
        table.insert(signature_parts, item.science)
    end
    table.sort(signature_parts)
    local signature = table.concat(signature_parts, "\31")
    if rendered.signature ~= signature or #rows.children ~= #items then
        rows.clear()
        for index, item in ipairs(items) do
            create_science_throughput_row(rows, index, item)
        end
        rendered.signature = signature
        rendered.row_states = {}
    end

    if #rows.children == #items then
        local invalid_row = false
        for index, item in ipairs(items) do
            local row = rows.children[index]
            if not row or not row.valid or not row.tags then
                invalid_row = true
                break
            end
        end
        if invalid_row then
            rows.clear()
            for rebuild_index, rebuild_item in ipairs(items) do
                create_science_throughput_row(rows, rebuild_index, rebuild_item)
            end
            rendered.row_states = {}
        else
            for index, item in ipairs(items) do
                local row = rows.children[index]
                if row.tags.science ~= item.science then
                    row.tags = {science = item.science}
                    rendered.row_states[index] = nil
                end
            end
        end
    end

    if #rows.children == #items then
        for index, item in ipairs(items) do
            local row = rows.children[index]
            local row_state = rendered.row_states[index]
            if not row_state then
                row_state = {}
                rendered.row_states[index] = row_state
            end
            refresh_science_throughput_row(row, item, index, row_state)
        end
    end
    return true
end

local analyze_science_throughput = function(player_index, anchor)
    local panel = gutil.get_child(anchor, "research_details_panel")
    local analysis = panel and gutil.get_child(panel, "research_details_analysis")
    local analysis_text = panel and gutil.get_child(panel, "research_details_analysis_text")
    if not panel or not analysis or not analysis_text or not panel.visible then
        return
    end
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local diagnostic = queue.get_research_display_diagnostic(p.force.index) or {}
    local forecast = queue.get_science_display_forecast(p.force.index) or {}
    local rows = build_science_throughput_rows(util.get_all_sciences(), diagnostic, forecast)
    local finding
    for _, item in ipairs(rows) do
        if item.status == "starving" or item.status == "bottleneck" then
            local insight = queue.get_science_pack_insight(p.force.index, item.science) or {}
            local labs = insight.labs or {}
            local transit = insight.in_transit and insight.in_transit.total or 0
            if item.produced >= item.need and ((labs.starved_labs or 0) > 0 or transit > 0) then
                finding = {throughput_prefix .. "analysis-delivery", item_caption(item.science),
                           format_throughput_rate(transit)}
            elseif item.produced < item.need then
                finding = {throughput_prefix .. "analysis-production", item_caption(item.science),
                           format_throughput_rate(item.need - item.produced)}
            else
                finding = {throughput_prefix .. "analysis-labs", item_caption(item.science)}
            end
            break
        end
    end
    analysis_text.caption = finding or {throughput_prefix .. "analysis-clear"}
    analysis.visible = true
end

local close_science_throughput_analysis = function(anchor)
    local panel = gutil.get_child(anchor, "research_details_panel")
    local analysis = panel and gutil.get_child(panel, "research_details_analysis")
    if analysis then
        analysis.visible = false
    end
end

local refresh_research_pack_demand_table = function(panel, diagnostic, forecast)
    local frame = gutil.get_child(panel, "research_details_pack_demand")
    if not frame then
        return
    end
    frame.style.width = research_details_content_width
    local rates = diagnostic and diagnostic.science_pack_rates or {}
    local active = #rates > 0 and (diagnostic.expected_spm or 0) > 0
    local header = gutil.get_child(frame, "research_details_pack_demand_header")
    local rows = gutil.get_child(frame, "research_details_pack_demand_rows")
    local empty = gutil.get_child(frame, "research_details_pack_demand_empty")
    if header then
        header.visible = active
        header.style.width = research_details_content_width
        for _, column in ipairs(research_details_demand_column_order) do
            set_details_cell_width(gutil.get_child(header, "research_details_pack_demand_header_" .. column),
                                   research_details_demand_columns[column])
        end
    end
    if empty then
        empty.visible = not active
    end
    if not rows then
        return
    end
    rows.style.width = research_details_content_width
    rows.visible = active
    if not active then
        return
    end

    if #rows.children ~= #rates * #research_details_demand_column_order then
        rows.clear()
        for index, item in ipairs(rates) do
            add_details_table_cell(rows, "research_details_pack_demand_science_" .. index,
                                   item_caption(item.science), research_details_demand_columns.science, false)
            add_details_table_cell(rows, "research_details_pack_demand_maximum_" .. index, "",
                                   research_details_demand_columns.maximum, false)
            add_details_table_cell(rows, "research_details_pack_demand_working_" .. index, "",
                                   research_details_demand_columns.working, false)
            add_details_table_cell(rows, "research_details_pack_demand_produced_" .. index, "",
                                   research_details_demand_columns.produced, false)
        end
    end

    for index, item in ipairs(rates) do
        local production = forecast and forecast[item.science]
        local produced = production and production.production_per_minute ~= nil and
                         format_spaced_number(production.production_per_minute) or "--"
        local science = gutil.get_child(rows, "research_details_pack_demand_science_" .. index)
        local maximum = gutil.get_child(rows, "research_details_pack_demand_maximum_" .. index)
        local working = gutil.get_child(rows, "research_details_pack_demand_working_" .. index)
        local produced_label = gutil.get_child(rows, "research_details_pack_demand_produced_" .. index)
        if science then
            science.caption = item_caption(item.science)
        end
        if maximum then
            maximum.caption = format_spaced_number(item.maximum_per_minute)
        end
        if working then
            working.caption = format_spaced_number(item.working_per_minute)
        end
        if produced_label then
            produced_label.caption = produced
        end
    end
end

local refresh_research_pack_table = function(pack_cell, cluster, index)
    local pack_table = gutil.get_child(pack_cell, "research_details_pack_table_" .. index)
    if not pack_table then
        return
    end
    pack_table.style.width = research_details_columns.action
    local rates = cluster and cluster.science_pack_rates or {}
    local column_count = #research_details_pack_column_order
    if #pack_table.children ~= column_count + (#rates * column_count) then
        pack_table.clear()
        for _, column in ipairs(research_details_pack_column_order) do
            add_details_table_cell(pack_table, "research_details_pack_header_" .. column .. "_" .. index,
                                   {"lil_einstein-throughput.pack-table-" .. column},
                                   research_details_pack_columns[column], true)
        end
        for rate_index, item in ipairs(rates) do
            for _, column in ipairs(research_details_pack_column_order) do
                add_details_table_cell(pack_table,
                                       "research_details_pack_" .. column .. "_" .. index .. "_" .. rate_index,
                                       "", research_details_pack_columns[column], false,
                                       column == "missing" and
                                           "lil_einstein_throughput_missing_label" or nil)
            end
        end
    end

    for rate_index, item in ipairs(rates) do
        local missing = get_cluster_missing_pack(cluster, item.science)
        local base = column_count + ((rate_index - 1) * column_count)
        local science = pack_table.children[base + 1]
        local stock = pack_table.children[base + 2]
        local maximum = pack_table.children[base + 3]
        local working = pack_table.children[base + 4]
        local missing_label = pack_table.children[base + 5]
        if science then
            science.caption = item_caption(item.science)
        end
        if maximum then
            maximum.caption = format_spaced_number(item.maximum_per_minute)
        end
        if working then
            working.caption = format_spaced_number(item.working_per_minute)
        end
        if stock then
            stock.caption = format_spaced_number((cluster.local_stock and cluster.local_stock[item.science]) or 0)
        end
        if missing_label then
            missing_label.caption = missing and
                {"lil_einstein-throughput.pack-missing-cell",
                 format_spaced_number(missing.missing_per_minute or 0),
                 format_spaced_number(-(missing.lost_spm or 0))} or "--"
        end
    end
end

local create_research_details_row = function(rows, index, cluster)
    local missing_pack = get_dominant_missing_pack(cluster)
    local initial_captions = {
        location = cluster_location_caption(cluster),
        missing = format_missing_pack_summary(missing_pack, cluster.lost_spm),
        labs = {"lil_einstein-throughput.labs-cell", cluster.working_labs or 0,
                cluster.compatible_labs or 0, cluster.incompatible_labs or 0},
        capacity = {"lil_einstein-throughput.capacity-cell",
                    format_spaced_number(cluster.working_spm), format_spaced_number(cluster.expected_spm)},
        cause = get_cluster_causes_caption(cluster),
        action = get_diagnostic_action(nil, cluster),
        action_detail = missing_pack and
            {"lil_einstein-throughput.action-missing-pack", item_caption(missing_pack.science),
             format_spaced_number(missing_pack.missing_per_minute or 0)} or ""
    }
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
        style = "lil_einstein_throughput_table",
        column_count = #research_details_column_order
    })
    cells.style.width = research_details_content_width
    for _, column in ipairs(research_details_column_order) do
        if column == "action" then
            local action_cell = cells.add({
                type = "flow",
                name = "research_details_action_cell_" .. index,
                style = "lil_einstein_throughput_pack_cell",
                direction = "vertical"
            })
            action_cell.style.width = research_details_columns.action
            action_cell.add({
                type = "table",
                name = "research_details_pack_table_" .. index,
                style = "lil_einstein_throughput_pack_table",
                column_count = #research_details_pack_column_order
            })
            local inspect_labs = action_cell.add({
                type = "button",
                name = "research_details_inspect_labs_" .. index,
                caption = {throughput_prefix .. "inspect-labs", 0},
                visible = false,
                tags = {
                    lil_einstein_on_click = true,
                    handler = "inspect_research_cluster_labs",
                    cluster_key = cluster.key,
                    ignore_force_enable = true
                }
            })
            inspect_labs.style.width = research_details_columns.action
            add_details_table_cell(action_cell, "research_details_action_" .. index,
                                   initial_captions.action,
                                   research_details_columns.action, false)
            add_details_table_cell(action_cell, "research_details_action_detail_" .. index,
                                   initial_captions.action_detail,
                                   research_details_columns.action, false,
                                   "lil_einstein_throughput_missing_label")
        elseif column == "missing" then
            add_details_table_cell(cells, "research_details_missing_" .. index,
                                   initial_captions.missing,
                                   research_details_columns.missing, false,
                                   "lil_einstein_throughput_missing_label")
        else
            add_details_table_cell(cells, "research_details_" .. column .. "_" .. index,
                                   initial_captions[column],
                                   research_details_columns[column], false)
        end
    end
    return row
end

local refresh_research_details

local set_research_details_main_visibility = function(panel, visible)
    for _, name in ipairs({
        "research_details_headline",
        "research_details_evidence",
        "research_details_scope_note",
        "research_details_overlap_note",
        "research_details_pack_demand",
        "research_details_ceiling_hint",
        "research_details_header",
        "research_details_scroll_pane"
    }) do
        local element = gutil.get_child(panel, name)
        if element then
            element.visible = visible
        end
    end
end

local refresh_research_lab_inspection = function(player_index, anchor, cluster_key, diagnostic)
    local panel = gutil.get_child(anchor, "research_details_panel")
    local inspection = panel and gutil.get_child(panel, "research_lab_inspection_panel")
    if not panel or not inspection then
        return
    end

    local p = game.get_player(player_index)
    if not p then
        return
    end
    diagnostic = diagnostic or queue.get_research_display_diagnostic(p.force.index)
    local cluster = find_diagnostic_cluster(diagnostic, cluster_key)
    local affected = get_cluster_affected_labs(cluster)
    local missing = get_dominant_missing_pack(cluster)
    local summary = gutil.get_child(inspection, "research_lab_inspection_summary")
    if summary then
        summary.caption = {throughput_prefix .. "inspect-labs-summary", item_caption(missing and missing.science),
                           #affected, cluster_location_caption(cluster)}
        summary.style.width = research_details_content_width
        summary.style.single_line = false
    end

    local header = gutil.get_child(inspection, "research_lab_inspection_header")
    if header then
        header.style.width = research_details_content_width
        for _, column in ipairs(research_lab_inspection_column_order) do
            set_details_cell_width(gutil.get_child(header,
                "research_lab_inspection_header_" .. column), research_lab_inspection_columns[column])
        end
    end

    local empty = gutil.get_child(inspection, "research_lab_inspection_empty")
    if empty then
        empty.visible = #affected == 0
    end
    local pane = gutil.get_child(inspection, "research_lab_inspection_scroll_pane")
    if pane then
        pane.style.width = research_details_content_width
        pane.style.height = 545
        pane.horizontal_scroll_policy = "never"
        pane.vertical_scroll_policy = "auto"
    end
    local rows = gutil.get_child(inspection, "research_lab_inspection_rows")
    if not rows then
        return
    end
    rows.style.width = research_details_content_width
    if #rows.children ~= #affected * #research_lab_inspection_column_order then
        rows.clear()
        for index, descriptor in ipairs(affected) do
            add_details_table_cell(rows, "research_lab_inspection_name_" .. index, "",
                                   research_lab_inspection_columns.name, false)
            add_details_table_cell(rows, "research_lab_inspection_location_" .. index, "",
                                   research_lab_inspection_columns.location, false)
            add_details_table_cell(rows, "research_lab_inspection_status_" .. index, "",
                                   research_lab_inspection_columns.status, false)
            add_details_table_cell(rows, "research_lab_inspection_missing_" .. index, "",
                                   research_lab_inspection_columns.missing, false)
        end
    end

    for index, descriptor in ipairs(affected) do
        local name = gutil.get_child(rows, "research_lab_inspection_name_" .. index)
        local location = gutil.get_child(rows, "research_lab_inspection_location_" .. index)
        local status = gutil.get_child(rows, "research_lab_inspection_status_" .. index)
        local missing_label = gutil.get_child(rows, "research_lab_inspection_missing_" .. index)
        if name then
            name.caption = lab_identity_caption(descriptor)
        end
        if location then
            location.caption = lab_location_caption(descriptor)
        end
        if status then
            status.caption = lab_status_caption(descriptor.status_key)
        end
        if missing_label then
            missing_label.caption = lab_missing_caption(descriptor)
        end
    end
end

local show_research_lab_inspection = function(player_index, anchor, cluster_key)
    local panel = gutil.get_child(anchor, "research_details_panel")
    local inspection = panel and gutil.get_child(panel, "research_lab_inspection_panel")
    if not panel or not inspection or not panel.visible then
        return
    end
    state.set_player_setting(player_index, "research_lab_cluster_key", cluster_key)
    set_research_details_main_visibility(panel, false)
    inspection.visible = true
    refresh_research_lab_inspection(player_index, anchor, cluster_key)
end

local hide_research_lab_inspection = function(player_index, anchor)
    local panel = gutil.get_child(anchor, "research_details_panel")
    local inspection = panel and gutil.get_child(panel, "research_lab_inspection_panel")
    if not panel or not inspection then
        return
    end
    state.clear_player_setting(player_index, "research_lab_cluster_key")
    inspection.visible = false
    set_research_details_main_visibility(panel, true)
    refresh_research_details(player_index, anchor)
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
        for _, name in ipairs({
            "research_details_cells_" .. index,
            "research_details_location_" .. index,
            "research_details_missing_" .. index,
            "research_details_labs_" .. index,
            "research_details_capacity_" .. index,
            "research_details_cause_" .. index,
            "research_details_action_cell_" .. index,
            "research_details_inspect_labs_" .. index,
            "research_details_action_" .. index,
            "research_details_action_detail_" .. index
        }) do
            if not gutil.get_child(row, name) then
                return false
            end
        end
    end
    return true
end

refresh_research_details = function(player_index, anchor, diagnostic)
    local panel = gutil.get_child(anchor, "research_details_panel")
    if not panel or not panel.visible then
        return
    end

    if refresh_science_throughput_details(player_index, anchor, diagnostic) then
        return
    end

    local p = game.get_player(player_index)
    if not p then
        return
    end
    diagnostic = diagnostic or queue.get_research_display_diagnostic(p.force.index)
    local inspection_key = state.get_player_setting(player_index, "research_lab_cluster_key")
    local forecast = queue.get_science_display_forecast(p.force.index)
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
    for _, name in ipairs({
        "research_details_evidence",
        "research_details_scope_note",
        "research_details_overlap_note",
        "research_details_ceiling_hint"
    }) do
        local label = gutil.get_child(panel, name)
        if label then
            label.style.width = research_details_content_width
            label.style.single_line = false
        end
    end
    refresh_research_pack_demand_table(panel, diagnostic, forecast)

    local header = gutil.get_child(panel, "research_details_header")
    if header then
        header.style.width = research_details_content_width
        for _, column in ipairs(research_details_column_order) do
            set_details_cell_width(gutil.get_child(header, "research_details_header_" .. column),
                                   research_details_columns[column])
        end
    end
    local pane = gutil.get_child(panel, "research_details_scroll_pane")
    if pane then
        pane.style.width = research_details_content_width
        pane.style.height = 545
        pane.horizontal_scroll_policy = "never"
        pane.vertical_scroll_policy = "auto"
    end

    local rows = gutil.get_child(panel, "research_details_rows")
    if not rows then
        if inspection_key then
            refresh_research_lab_inspection(player_index, anchor, inspection_key, diagnostic)
        end
        return
    end
    rows.style.width = research_details_content_width
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
        if inspection_key then
            refresh_research_lab_inspection(player_index, anchor, inspection_key, diagnostic)
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
        local missing = gutil.get_child(row, "research_details_missing_" .. index)
        local labs = gutil.get_child(row, "research_details_labs_" .. index)
        local capacity = gutil.get_child(row, "research_details_capacity_" .. index)
        local cause = gutil.get_child(row, "research_details_cause_" .. index)
        local action_cell = gutil.get_child(row, "research_details_action_cell_" .. index)
        local inspect_labs = gutil.get_child(row, "research_details_inspect_labs_" .. index)
        local action = gutil.get_child(row, "research_details_action_" .. index)
        local action_detail = gutil.get_child(row, "research_details_action_detail_" .. index)
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
        if missing then
            missing.caption = format_missing_pack_summary(get_dominant_missing_pack(cluster), cluster.lost_spm)
        end
        if labs then
            labs.caption = {"lil_einstein-throughput.labs-cell", cluster.working_labs or 0,
                            cluster.compatible_labs or 0, cluster.incompatible_labs or 0}
        end
        if capacity then
            capacity.caption = {"lil_einstein-throughput.capacity-cell",
                                format_spaced_number(cluster.working_spm), format_spaced_number(cluster.expected_spm)}
        end
        if cause then
            cause.caption = get_cluster_causes_caption(cluster)
        end
        if action_cell then
            refresh_research_pack_table(action_cell, cluster, index)
        end
        if inspect_labs then
            local affected_labs = get_cluster_affected_labs(cluster)
            inspect_labs.visible = #affected_labs > 0
            inspect_labs.caption = {throughput_prefix .. "inspect-labs", #affected_labs}
        end
        if action then
            action.caption = get_diagnostic_action(diagnostic, cluster)
        end
        if action_detail then
            local missing_pack = get_dominant_missing_pack(cluster)
            action_detail.visible = missing_pack ~= nil
            action_detail.caption = missing_pack and
                {"lil_einstein-throughput.action-missing-pack", item_caption(missing_pack.science),
                 format_spaced_number(missing_pack.missing_per_minute or 0)} or ""
        end
    end
    if inspection_key then
        refresh_research_lab_inspection(player_index, anchor, inspection_key, diagnostic)
    end
end

local refresh_research_metrics = function(player_index, anchor)
    local p, summary = get_research_context(player_index, anchor)
    if not p or not summary then
        return
    end

    local diagnostic = queue.get_research_display_diagnostic(p.force.index)
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

local refresh_research_status_bar = function(player_index, anchor, advance)
    local p = game.get_player(player_index)
    local status_bar = gutil.get_child(anchor, "research_status_bar")
    if not p or not status_bar or status_bar.valid == false then
        return
    end

    local force_index = p.force.index
    local insights = build_research_status_insights(
        queue.get_research_display_diagnostic(force_index),
        queue.get_research_summary(force_index),
        queue.get_research_control_state and queue.get_research_control_state(force_index) or {},
        queue.get_science_display_forecast(force_index))
    local set_signature = {}
    for _, insight in ipairs(insights) do
        table.insert(set_signature, insight.kind .. ":" .. tostring(insight.science or ""))
    end
    set_signature = table.concat(set_signature, "|")

    local cache = research_status_cache[anchor.index]
    if not cache or cache.element ~= anchor or cache.element.valid == false or
        cache.signature ~= set_signature then
        cache = {element = anchor, signature = set_signature, index = 1}
        research_status_cache[anchor.index] = cache
    elseif advance then
        cache.index = (cache.index % #insights) + 1
    end

    local insight = insights[cache.index] or insights[1]
    local render_key = tostring(insight.key or insight.kind) .. ":" .. tostring(cache.index)
    if cache.render_key ~= render_key then
        status_bar.caption = insight.caption
        status_bar.tooltip = insight.tooltip or insight.caption
        cache.render_key = render_key
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
        local rendered = graph_hover_cache[overlay.index]
        if rendered and rendered.element == overlay then
            rendered.column_index = column_index
        end
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

local render_research_graph_job = function(player_index, anchor, budget)
    local job = graph_render_jobs[anchor.index]
    if not job or not job.element.valid or job.element ~= anchor then
        graph_render_jobs[anchor.index] = nil
        return
    end

    local first = math.max(
        1,
        job.next_index - (budget or research_graph_render_budget) + 1
    )
    for i = job.next_index, first, -1 do
        local col = job.plot["research_graph_column_" .. i]
        local hover_col = job.overlay and job.overlay["research_graph_hover_column_" .. i]
        local value = job.history[i] or 0
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
                local previous_value = job.history[i - 1] or value
                local y = get_research_graph_y(value, job.axis_max)
                local previous_y = get_research_graph_y(previous_value, job.axis_max)
                local vertical_before_height = 0
                local vertical_after_height = 0
                if previous_y < y then
                    set_research_graph_spacer(spacer, previous_y)
                    vertical_before_height = y - previous_y
                else
                    set_research_graph_spacer(spacer, y)
                    vertical_after_height = previous_y - y
                end

                if job.has_history or value > 0 or previous_value > 0 then
                    set_research_graph_segment(vertical_before, 1, vertical_before_height)
                    set_research_graph_segment(horizontal, column_width, 1)
                    set_research_graph_segment(vertical_after, 1, vertical_after_height)
                else
                    if vertical_before.visible then
                        vertical_before.visible = false
                    end
                    if horizontal.visible then
                        horizontal.visible = false
                    end
                    if vertical_after.visible then
                        vertical_after.visible = false
                    end
                end
            end
        end
    end

    job.next_index = first - 1
    if job.next_index < 1 then
        graph_render_jobs[anchor.index] = nil
        refresh_research_graph_hover(player_index, anchor, job.history, job.axis_max)
    end
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

    graph_render_jobs[anchor.index] = {
        element = anchor,
        history = history,
        has_history = has_history,
        axis_max = axis_max,
        plot = plot,
        overlay = overlay,
        next_index = research_graph_column_count
    }
    render_research_graph_job(player_index, anchor, research_graph_render_budget)
end

local tick_research_graph = function(player_index, anchor)
    render_research_graph_job(player_index, anchor, research_graph_render_budget)
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
    local science_counts = queue.get_science_display_counts(force_index)

    -- Add all the sciences as icons to the table
    for _, s in pairs(sci) do
        local container = scitbl.add({
            type = "flow",
            direction = "vertical",
            tags = {ignore_enable = true}
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
            toggled = state.get_player_setting(player_index, "science_pack_panel_science") == s,
            tooltip = get_science_tooltip(player_index, force_index, s, count),
            tags = {
                lil_einstein_on_click = true,
                handler = "open_science_pack_details",
                science = s,
                ignore_force_enable = true
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
    local formatted = tostring(value) .. (suffix or "")
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

local add_policy_dropdown = function(flow, force_index, setting_name, caption, order, item_prefix, tooltip)
    local row = flow.add({type = "flow", direction = "horizontal"})
    row.style.vertical_align = "center"
    local label = row.add({type = "label", caption = caption, tooltip = tooltip})
    label.style.width = 265
    local items = {}
    local selected = 1
    local current = policy.get_setting(force_index, setting_name)
    for index, value in ipairs(order or {}) do
        items[index] = {"lil_einstein-policy." .. item_prefix .. value}
        if value == current then
            selected = index
        end
    end
    row.add({
        type = "drop-down",
        items = items,
        selected_index = selected,
        tooltip = tooltip,
        tags = {
            lil_einstein_on_state_change = true,
            handler = "policy_policy_dropdown",
            setting_name = setting_name
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
    local selected_strategy = policy.strategy_order[selected] or "balanced"
    local strategy_help = {"lil_einstein-strategy-help." .. selected_strategy}
    strategy_label.tooltip = strategy_help
    strategy_row.add({
        type = "drop-down",
        items = items,
        selected_index = selected,
        tooltip = strategy_help,
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
    add_policy_number(flow, p.force.index, "forecast_seconds", {"lil_einstein-policy.forecast-horizon"}, 30, "s")
    add_policy_number(flow, p.force.index, "replan_interval_seconds", {"lil_einstein-policy.replan-interval"}, 30, "s")
    add_policy_number(flow, p.force.index, "parallel_slots", {"lil_einstein-policy.parallel-slots"}, 1)
    add_policy_toggle(flow, p.force.index, "instant_switch_override", {"lil_einstein-policy.instant-switch-override"},
        {"lil_einstein-policy.instant-switch-override-description"})
    add_policy_dropdown(flow, p.force.index, "reserve_for_type", {"lil_einstein-policy.reserve-for-type"},
        policy.reserve_for_type_order, "reserve-for-type-", {"lil_einstein-policy.reserve-for-type-description"})
    add_policy_number(flow, p.force.index, "plan_horizon_minutes", {"lil_einstein-policy.plan-horizon"}, 5, "m")
end

local format_policy_time = function(seconds)
    if not seconds then
        return "--"
    end
    if seconds == math.huge then
        return "∞"
    end
    if seconds >= 3600 then
        return string.format("%.1fh", seconds / 3600)
    end
    if seconds >= 60 then
        return string.format("%.1fm", seconds / 60)
    end
    return tostring(math.floor(seconds + 0.5)) .. "s"
end

local format_policy_history_detail = function(item)
    if not item then
        return "Research plan updated"
    end
    if item.reason == "reserve-for-type" then
        local after = item.after
        local value = after == "safety_first" and "Safety first" or tostring(after or "unchanged")
        return "Reserve for type: " .. value
    elseif item.action == "strategy" then
        return "Strategy: " .. tostring(item.detail or item.after or "updated")
    end
    return tostring(item.detail or item.reason or item.trigger or item.action or "Research plan updated")
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
            caption = string.format("%s  +%s/−%s min  runtime %s", gutil.format_cost(data.stock or 0),
                gutil.format_si(data.production_per_minute or 0),
                gutil.format_si(data.consumption_per_minute or 0), format_policy_time(data.depletion_seconds))
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
                           gutil.format_si(item.production_per_minute)}
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
    local filter_row = flow.add({type = "flow", direction = "horizontal"})
    filter_row.style.vertical_align = "center"
    local filter_label = filter_row.add({type = "label", caption = {"lil_einstein-policy.history-filter"}})
    filter_label.style.width = 265
    local selected_filter = state.get_player_setting(player_index, "policy_history_filter", "all")
    local selected_index = 1
    local filter_items = {}
    for index, value in ipairs(policy_history_filters) do
        filter_items[index] = {"lil_einstein-policy.history-filter-" .. value}
        if value == selected_filter then
            selected_index = index
        end
    end
    filter_row.add({
        type = "drop-down",
        items = filter_items,
        selected_index = selected_index,
        tags = {lil_einstein_on_state_change = true, handler = "policy_history_filter"}
    })
    add_policy_toggle(flow, p.force.index, "multiplayer_lock", {"lil_einstein-policy.multiplayer-lock"},
        {"lil_einstein-policy.multiplayer-lock-description"}, p.admin)
    local filter = state.get_player_setting(player_index, "policy_history_filter", "all")
    local history = filter == "all" and policy.get_history(p.force.index) or
        policy.get_history(p.force.index, {category = filter})
    if #history == 0 then
        flow.add({type = "label", caption = {"lil_einstein-policy.no-history"}})
        return
    end
    for index = 1, math.min(10, #history) do
        local item = history[index]
        local seconds_ago = math.max(0, math.floor((game.tick - (item.tick or game.tick)) / 60))
        local detail = format_policy_history_detail(item)
        flow.add({
            type = "label",
            caption = {"lil_einstein-policy.history-row", format_policy_time(seconds_ago), item.player, item.action,
                       detail}
        })
    end
end

local set_decision_caption = function(anchor, name, caption)
    local element = gutil.get_child(anchor, name)
    if element then
        element.caption = caption
    end
    return element
end

local set_decision_sprite = function(anchor, name, sprite)
    local element = gutil.get_child(anchor, name)
    if element and sprite then
        element.sprite = sprite
    end
    return element
end

local get_decision_candidate = function(force_index)
    local f = game and game.forces and game.forces[force_index]
    if not f then
        return nil, nil, nil
    end
    local tech_name = f.current_research and f.current_research.name
    if not tech_name then
        local names = queue.get_queue(force_index)
        tech_name = names and names[1]
    end
    if not tech_name then
        return nil, nil, nil
    end
    return tech_name, tech.get_single_tech_state_ext(force_index, tech_name), f.technologies[tech_name]
end

local get_decision_technology_caption = function(tech_name)
    if not tech_name then
        return "No planned research"
    end
    local prototype = prototypes and prototypes.technology and prototypes.technology[tech_name]
    return prototype and prototype.localised_name or tech_name
end

local populate_decision_console_header = function(player_index, anchor)
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local force_index = p.force.index
    local strategy = policy.get_setting(force_index, "strategy") or "balanced"
    local strategy_caption = {"lil_einstein-strategy." .. strategy}
    local strategy_help = {"lil_einstein-strategy-help." .. strategy}
    local strategy_dropdown = gutil.get_child(anchor, "decision_strategy_dropdown")
    if strategy_dropdown then
        local items = {}
        local selected = 1
        for index, name in ipairs(policy.strategy_order) do
            items[index] = {"lil_einstein-strategy." .. name}
            if name == strategy then
                selected = index
            end
        end
        strategy_dropdown.items = items
        strategy_dropdown.selected_index = selected
        strategy_dropdown.tooltip = strategy_help
    end

    set_decision_caption(anchor, "decision_mode_value", strategy_caption)
    set_decision_caption(anchor, "decision_mode_detail", strategy_help)
    local planning_paused = policy.get_setting(force_index, "planning_paused") == true
    local instant_override = policy.get_setting(force_index, "instant_switch_override") == true
    local manual_override = gutil.get_child(anchor, "decision_manual_override")
    local lock_current = gutil.get_child(anchor, "decision_lock_current")
    if manual_override then
        manual_override.state = instant_override
    end
    if lock_current then
        lock_current.state = planning_paused
    end

    local tech_name, xcur, current = get_decision_candidate(force_index)
    local tech_caption = get_decision_technology_caption(tech_name)
    if tech_name then
        set_decision_sprite(anchor, "decision_candidate_icon", "technology/" .. tech_name)
        set_decision_sprite(anchor, "decision_next_research_icon", "technology/" .. tech_name)
    else
        set_decision_sprite(anchor, "decision_candidate_icon", "utility/technology")
        set_decision_sprite(anchor, "decision_next_research_icon", "utility/technology")
    end
    set_decision_caption(anchor, "decision_candidate_name", tech_caption)
    set_decision_caption(anchor, "decision_next_research_name", tech_caption)
    local priority = xcur and policy.get_tech_science_priority(force_index, xcur) or nil
    set_decision_caption(anchor, "decision_candidate_score", priority and ("Priority score: " .. tostring(priority)) or "Priority score: --")
    set_decision_caption(anchor, "decision_candidate_priority", current and ("Level: " .. tostring(current.level or 1)) or "Level: --")

    local diagnostic = queue.get_research_display_diagnostic(force_index) or {}
    local health_state = diagnostic.state or "idle"
    local health_value = (health_state == "operational_fault" or health_state == "pack_bound") and "Watch" or "Good"
    set_decision_caption(anchor, "decision_health_value", health_value)
    set_decision_caption(anchor, "decision_health_detail", health_state == "idle" and "No active research." or
        (health_state == "measuring" and "Measuring current research." or "Research health is being monitored."))

    local summary = queue.get_research_summary(force_index) or {}
    local remaining = summary.remaining_seconds
    set_decision_caption(anchor, "decision_next_research_start", "Est. start: " .. format_policy_time(remaining))
    set_decision_caption(anchor, "decision_switch_in", "Switch in: " .. format_policy_time(remaining))
    set_decision_caption(anchor, "decision_parallel_slots", "Parallel slots: " .. tostring(policy.get_setting(force_index, "parallel_slots") or 1))
    set_decision_caption(anchor, "decision_supply_horizon", "Supply horizon: " .. tostring(policy.get_setting(force_index, "forecast_seconds") or 0) .. "s")
    set_decision_caption(anchor, "decision_plan_override", "Plan override: " .. (instant_override and "Instant" or "Normal"))
    set_decision_caption(anchor, "decision_min_switch_value", tostring(policy.get_setting(force_index, "min_switch_seconds") or 0) .. "s")

    local reserve = policy.get_setting(force_index, "reserve_for_type") or "safety_first"
    local reserve_caption = reserve == "safety_first" and "Safety first" or reserve
    set_decision_caption(anchor, "decision_rationale", "Reserve-for-type policy: " .. reserve_caption .. ".")

    local snapshot_tick = queue.get_research_health_snapshot_tick(force_index)
    local checked = snapshot_tick and snapshot_tick >= 0 and format_policy_time(math.max(0, (game.tick - snapshot_tick) / 60)) or "--"
    set_decision_caption(anchor, "decision_last_checked", "Last checked: " .. checked .. " ago")

    local forecast = queue.get_science_display_forecast and queue.get_science_display_forecast(force_index)
    if not forecast or not next(forecast) then
        forecast = queue.get_science_forecast and queue.get_science_forecast(force_index)
    end
    forecast = forecast or {}
    local sufficient = true
    local limiting_science
    if current then
        for _, ingredient in pairs(current.research_unit_ingredients or {}) do
            local science = ingredient.name
            local item = forecast[science] or {}
            if (item.stock or 0) < (ingredient.amount or 1) then
                sufficient = false
                limiting_science = science
                break
            end
        end
    end
    set_decision_caption(anchor, "decision_science_status", sufficient and "Science sufficient" or "Science at risk")
    set_decision_caption(anchor, "decision_science_detail", sufficient and "All required packs are above minimum." or
        ("Waiting on " .. tostring(limiting_science or "required science") .. "."))
    set_decision_caption(anchor, "decision_science_detail_two", sufficient and "Supply runtime covers the switch window." or
        "The planner will avoid an uncovered switch.")
end

local add_decision_setting = function(flow, force_index, setting_name, caption, step, suffix)
    local row = flow.add({type = "flow", direction = "horizontal"})
    row.style.height = 27
    row.style.vertical_align = "center"
    local label = row.add({type = "label", caption = caption})
    label.style.width = 180
    local value = policy.get_setting(force_index, setting_name) or 0
    local value_label = row.add({type = "label", name = "decision_setting_" .. setting_name,
        caption = tostring(value) .. (suffix or "")})
    value_label.style.width = 58
    value_label.style.horizontal_align = "right"
    row.add({type = "button", style = "lil_einstein_settings_stepper_left", tags = {
        lil_einstein_on_click = true, handler = "adjust_policy_setting", setting_name = setting_name, delta = -step
    }})
    row.add({type = "button", style = "lil_einstein_settings_stepper_right", tags = {
        lil_einstein_on_click = true, handler = "adjust_policy_setting", setting_name = setting_name, delta = step
    }})
end

local add_decision_dropdown = function(flow, force_index, setting_name, caption, order, item_prefix)
    local row = flow.add({type = "flow", direction = "horizontal"})
    row.style.height = 27
    row.style.vertical_align = "center"
    local label = row.add({type = "label", caption = caption})
    label.style.width = 180
    local items = {}
    local selected = 1
    local current = policy.get_setting(force_index, setting_name)
    for index, value in ipairs(order or {}) do
        items[index] = {"lil_einstein-policy." .. item_prefix .. value}
        if value == current then
            selected = index
        end
    end
    row.add({
        type = "drop-down",
        items = items,
        selected_index = selected,
        tags = {
            lil_einstein_on_state_change = true,
            handler = "policy_policy_dropdown",
            setting_name = setting_name
        }
    })
end

local populate_decision_automation = function(player_index, anchor)
    local p = game.get_player(player_index)
    if not p then
        return
    end
    local force_index = p.force.index
    local behavior = gutil.get_child(anchor, "decision_automation_behavior")
    local settings = gutil.get_child(anchor, "decision_automation_settings")
    local evidence = gutil.get_child(anchor, "decision_evidence_snapshot")
    local history_flow = gutil.get_child(anchor, "decision_recent_changes")
    if not behavior or not settings or not evidence or not history_flow then
        return
    end

    behavior.clear()
    behavior.add({type = "label", style = "lil_einstein_decision_console_content_title", caption = "Automation behavior"})
    local selected = policy.get_setting(force_index, "strategy") or "balanced"
    for _, name in ipairs({"conservative", "balanced", "aggressive"}) do
        local row = behavior.add({type = "flow", direction = "horizontal"})
        row.style.height = 42
        local radio = row.add({type = "button", style = name == selected and "lil_einstein_radio_button_on" or "lil_einstein_radio_button_off",
            tags = {lil_einstein_on_click = true, handler = "decision_strategy", strategy = name}})
        radio.style.right_margin = 7
        local text = row.add({type = "flow", direction = "vertical"})
        text.add({type = "label", caption = {"lil_einstein-strategy." .. name}})
        text.add({type = "label", caption = {"lil_einstein-strategy-help." .. name}})
    end
    behavior.add({type = "line"})
    local pause = policy.get_setting(force_index, "planning_paused") == true
    local parallel = policy.get_setting(force_index, "parallel_research") == true
    local cluster = policy.get_setting(force_index, "cluster_mode") == true
    for _, item in ipairs({
        {"planning_paused", "Pause after current research", pause},
        {"parallel_research", "Enable parallel research", parallel},
        {"cluster_mode", "Require a usable lab cluster", cluster}
    }) do
        local row = behavior.add({type = "flow", direction = "horizontal"})
        row.style.height = 27
        local toggle = row.add({type = "button", style = item[3] and "lil_einstein_settings_checkbox_on" or "lil_einstein_settings_checkbox_off",
            tags = {lil_einstein_on_click = true, handler = "toggle_policy_setting", setting_name = item[1]}})
        toggle.style.right_margin = 7
        row.add({type = "label", caption = item[2]})
    end

    settings.clear()
    settings.add({type = "label", style = "lil_einstein_decision_console_content_title", caption = "Operational settings"})
    add_decision_setting(settings, force_index, "min_switch_seconds", "Minimum switch time", 5, "s")
    add_decision_setting(settings, force_index, "forecast_seconds", "Supply horizon", 30, "s")
    add_decision_setting(settings, force_index, "parallel_slots", "Parallel slots", 1)
    add_decision_setting(settings, force_index, "replan_interval_seconds", "Replan interval", 30, "s")
    add_decision_setting(settings, force_index, "plan_horizon_minutes", "Plan horizon", 5, "m")
    add_decision_dropdown(settings, force_index, "reserve_for_type", {"lil_einstein-policy.reserve-for-type"},
        policy.reserve_for_type_order, "reserve-for-type-")
    settings.add({type = "label", style = "lil_einstein_decision_console_note",
        caption = "Normal replan follows the interval. Plan or setting changes request an immediate replan."})

    evidence.clear()
    evidence.add({type = "label", style = "lil_einstein_decision_console_content_title", caption = "Evidence snapshot"})
    evidence.add({type = "label", style = "lil_einstein_decision_console_note",
        caption = "Runtime to depletion uses stock, measured production, consumption, and deliveries. ∞ means no depletion is projected."})
    local table_element = evidence.add({type = "table", name = "decision_evidence_table",
        style = "lil_einstein_decision_console_science_table", column_count = 5})
    for _, caption in ipairs({"Science pack", "In stock", "In production", "Per minute", "Runtime"}) do
        table_element.add({type = "label", caption = caption})
    end
    local forecast = queue.get_science_display_forecast and queue.get_science_display_forecast(force_index)
    if not forecast or not next(forecast) then
        forecast = queue.get_science_forecast and queue.get_science_forecast(force_index)
    end
    forecast = forecast or {}
    for _, science in ipairs(util.get_all_sciences()) do
        local item = forecast[science] or {}
        table_element.add({type = "sprite", sprite = "item/" .. science, tooltip = {"item-name." .. science}})
        table_element.add({type = "label", caption = gutil.format_cost(item.stock or 0)})
        table_element.add({type = "label", caption = gutil.format_si(item.production_per_minute or 0)})
        table_element.add({type = "label", caption = gutil.format_si(item.net_per_minute or 0)})
        table_element.add({type = "label", caption = format_policy_time(item.depletion_seconds)})
    end

    history_flow.clear()
    history_flow.add({type = "label", style = "lil_einstein_decision_console_content_title", caption = "Recent changes"})
    local history = policy.get_history(force_index) or {}
    if #history == 0 then
        history_flow.add({type = "label", caption = {"lil_einstein-policy.no-history"}})
    else
        for index = 1, math.min(6, #history) do
            local item = history[index]
            local row = history_flow.add({type = "flow", style = "lil_einstein_decision_console_history_row", direction = "horizontal"})
            local seconds_ago = math.max(0, math.floor((game.tick - (item.tick or game.tick)) / 60))
            row.add({type = "label", style = "lil_einstein_decision_console_history_time", caption = format_policy_time(seconds_ago) .. " ago"})
            row.add({type = "label", style = "lil_einstein_decision_console_history_detail",
                caption = format_policy_history_detail(item)})
        end
    end
    local full_history = history_flow.add({type = "button", caption = "View full history",
        tags = {lil_einstein_on_click = true, handler = "policy_tab", tab = "history"}})
    full_history.style.width = 398
end

local apply_policy_tab = function(player_index, anchor)
    local selected = state.get_player_setting(player_index, "policy_active_tab", "automation")
    local valid = false
    for _, tab in ipairs(policy_tabs) do
        if tab.name == selected then
            valid = true
            break
        end
    end
    if not valid then
        selected = "automation"
        state.set_player_setting(player_index, "policy_active_tab", selected)
    end

    for _, tab in ipairs(policy_tabs) do
        local section = gutil.get_child(anchor, tab.section .. "_section")
        if section then
            section.visible = tab.name == selected
        end
        local button = gutil.get_child(anchor, tab.button)
        if button then
            button.enabled = tab.name ~= selected
        end
    end
    local automation_surface = gutil.get_child(anchor, "decision_automation_surface")
    local policy_scroll_pane = gutil.get_child(anchor, "policy_scroll_pane")
    if automation_surface then
        automation_surface.visible = selected == "automation"
    end
    if policy_scroll_pane then
        policy_scroll_pane.visible = selected ~= "automation"
    end
end

local populate_policy_panel = function(player_index, anchor)
    populate_decision_console_header(player_index, anchor)
    populate_decision_automation(player_index, anchor)
    local pane = gutil.get_child(anchor, "policy_scroll_pane")
    if pane then
        pane.style.height = 328
        pane.style.width = 1596
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
    apply_policy_tab(player_index, anchor)
end

local policy_panel_is_visible = function(anchor)
    local panel = gutil.get_child(anchor, "policy_panel")
    return panel and panel.visible == true
end

local research_details_panel_is_visible = function(anchor)
    local panel = gutil.get_child(anchor, "research_details_panel")
    return panel and panel.visible == true
end

local science_pack_panel_is_visible = function(anchor)
    local panel = gutil.get_child(anchor, "science_pack_panel")
    return panel and panel.visible == true
end

content.repopulate_static = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        populate_policy_panel(player_index, anchor)
        return
    elseif research_details_panel_is_visible(anchor) then
        refresh_research_details(player_index, anchor)
        return
    elseif science_pack_panel_is_visible(anchor) then
        refresh_science_pack_panel(player_index, anchor)
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
    elseif science_pack_panel_is_visible(anchor) then
        refresh_science_pack_panel(player_index, anchor)
        gcupcoming.populate(player_index, anchor)
        refresh_research_status(player_index, anchor)
        set_master_enable(player_index, anchor)
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

content.request_upcoming = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return true
    end
    return gcupcoming.request_populate(player_index, anchor)
end

content.tick_upcoming = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return true
    end
    return gcupcoming.tick_populate(player_index, anchor)
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
    refresh_science_counts(player_index, anchor, 1)
end

content.refresh_science_pack_panel = function(player_index, anchor)
    refresh_science_pack_panel(player_index, anchor)
end

content.refresh_research_status = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    refresh_research_status(player_index, anchor)
end

content.refresh_master_enable = function(player_index, anchor)
    if policy_panel_is_visible(anchor) or research_details_panel_is_visible(anchor) then
        return
    end
    set_master_enable(player_index, anchor)
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

content.build_research_status_insights = build_research_status_insights

content.refresh_research_status_bar = function(player_index, anchor, advance)
    refresh_research_status_bar(player_index, anchor, advance)
end

content.refresh_research_details = function(player_index, anchor)
    refresh_research_details(player_index, anchor)
end

content.build_science_throughput_rows = build_science_throughput_rows

content.analyze_science_throughput = function(player_index, anchor)
    analyze_science_throughput(player_index, anchor)
end

content.close_science_throughput_analysis = function(anchor)
    close_science_throughput_analysis(anchor)
end

content.show_research_lab_inspection = function(player_index, anchor, cluster_key)
    show_research_lab_inspection(player_index, anchor, cluster_key)
end

content.hide_research_lab_inspection = function(player_index, anchor)
    hide_research_lab_inspection(player_index, anchor)
end

content.refresh_research_graph = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    refresh_research_graph(player_index, anchor)
end

content.tick_research_graph = function(player_index, anchor)
    if policy_panel_is_visible(anchor) then
        return
    end
    tick_research_graph(player_index, anchor)
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

content.clear_runtime_cache = function()
    graph_render_cache = {}
    science_render_cache = {}
    science_pack_panel_render_cache = {}
    throughput_render_cache = {}
    graph_render_jobs = {}
    graph_hover_cache = {}
    research_status_cache = {}
    gcupcoming.clear_runtime_cache()
end

return content
