--- The gui module is the view
local gui = {}

local gutil = require("view.gui.gutil")
local state = require("model.state")
local const = require("lib.const")

local builder = require("view.gui.builder")
local components = require("view.gui.components")
local debug_report = require("view.gui.debug_report")

local target = "screen"
local repopulate_jobs = {}

local open = function(player_index, parent)
    -- Close any open windows
    local p = game.get_player(player_index)
    p.opened = nil

    -- Reset search state
    state.set_player_setting(player_index, "search_is_focused", false)
    gutil.clear_child_cache()
    components.clear_runtime_cache()
    repopulate_jobs[player_index] = nil

    -- Build the skeleton
    builder.build(player_index, parent)
    local main = gui.get(player_index)
    if not main then
        return
    end

    -- Repopulate the content
    components.repopulate_all(player_index, main)
    if state.get_player_setting(player_index, "policy_panel_open", false) then
        gui.toggle_policy_panel(player_index)
    elseif state.get_player_setting(player_index, "research_details_open", false) then
        gui.toggle_research_details(player_index)
    end
end

local close = function(player_index, anchor)
    -- Destroy the window
    anchor.destroy()
    gutil.clear_child_cache()
    components.clear_runtime_cache()
    repopulate_jobs[player_index] = nil

    -- Clear the search text
    state.clear_player_setting(player_index, "search_text")
    state.clear_player_setting(player_index, "research_graph_hover_column")
    state.clear_player_setting(player_index, "research_lab_cluster_key")
end

gui.init_player = function(player_index)
    if gui.is_debug_report_open(player_index) then
        gui.close_debug_report(player_index)
    end
    local p = game.get_player(player_index)
    if p.opened and p.opened.name == "lil_einstein_gui" then
        local anchor = gui.get(p.index)
        close(p.index, anchor)
    end
end

gui.get = function(player_index)
    local player = game.get_player(player_index)
    if not player then
        return
    end
    local main = player.gui[target]["lil_einstein_gui"]
    return main
end

gui.is_open = function(player_index)
    return (gui.get(player_index) ~= nil)
end

gui.toggle = function(player_index)
    local player = game.get_player(player_index)
    if not player then
        return
    end

    if gui.is_debug_report_open(player_index) then
        gui.close_debug_report(player_index)
    elseif gui.is_open(player_index) then
        close(player_index, gui.get(player_index))
    else
        open(player_index, player.gui[target])
    end
end

gui.toggle_policy_panel = function(player_index)
    local anchor = gui.get(player_index)
    if not anchor then
        return
    end
    local content_flow = gutil.get_child(anchor, "content_flow")
    local policy_panel = gutil.get_child(anchor, "policy_panel")
    if not content_flow or not policy_panel then
        return
    end
    local show_policy = not policy_panel.visible
    policy_panel.visible = show_policy
    content_flow.visible = not show_policy
    local research_details_panel = gutil.get_child(anchor, "research_details_panel")
    if research_details_panel then
        research_details_panel.visible = false
    end
    state.set_player_setting(player_index, "research_details_open", false)
    state.set_player_setting(player_index, "policy_panel_open", show_policy)
    if show_policy then
        gutil.clear_child_cache()
        components.repopulate_policy(player_index, anchor)
    else
        components.repopulate_all(player_index, anchor)
    end
end

gui.toggle_research_details = function(player_index)
    local anchor = gui.get(player_index)
    if not anchor then
        return
    end
    local content_flow = gutil.get_child(anchor, "content_flow")
    local policy_panel = gutil.get_child(anchor, "policy_panel")
    local details_panel = gutil.get_child(anchor, "research_details_panel")
    if not content_flow or not policy_panel or not details_panel then
        return
    end

    local show_details = not details_panel.visible
    details_panel.visible = show_details
    content_flow.visible = not show_details
    policy_panel.visible = false
    state.set_player_setting(player_index, "research_details_open", show_details)
    state.set_player_setting(player_index, "policy_panel_open", false)
    if show_details then
        components.refresh_research_details(player_index, anchor)
        local cluster_key = state.get_player_setting(player_index, "research_lab_cluster_key")
        if cluster_key then
            components.show_research_lab_inspection(player_index, anchor, cluster_key)
        end
    else
        state.clear_player_setting(player_index, "research_lab_cluster_key")
        components.repopulate_all(player_index, anchor)
    end
end

gui.is_debug_report_open = function(player_index)
    local player = game.get_player(player_index)
    if not player then
        return false
    end
    local report = player.gui[target]["lil_einstein_debug_report"]
    return report ~= nil and (report.valid == nil or report.valid)
end

gui.open_debug_report = function(player_index)
    local player = game.get_player(player_index)
    if not player or not gui.is_open(player_index) then
        return
    end
    if gui.is_debug_report_open(player_index) then
        gui.close_debug_report(player_index)
    end
    local report = debug_report.generate(player_index)
    builder.build_debug_report(player_index, player.gui[target], report)
end

gui.close_debug_report = function(player_index)
    local player = game.get_player(player_index)
    if not player then
        return
    end
    local report = player.gui[target]["lil_einstein_debug_report"]
    local main = gui.get(player_index)
    if report and report.valid ~= false then
        if player.opened == report then
            player.opened = nil
        end
        report.destroy()
    end
    if main and main.valid ~= false then
        player.opened = main
    end
end

gui.show_research_lab_inspection = function(player_index, cluster_key)
    local anchor = gui.get(player_index)
    if anchor then
        components.show_research_lab_inspection(player_index, anchor, cluster_key)
    end
end

gui.hide_research_lab_inspection = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.hide_research_lab_inspection(player_index, anchor)
    end
end

gui.is_search_focussed = function(player_index)
    local p = game.get_player(player_index)
    local f = p.force
    local st = state.get_force_setting(f.index, "master_enable", const.default_settings.force.master_enable)
    return (state.get_player_setting(player_index, "search_is_focused", false) and st == "right")
end

gui.focus_search = function(player_index)
    -- Remember settings
    local p = game.get_player(player_index)
    local f = p.force
    local anchor = gui.get(player_index)
    local st = state.get_force_setting(f.index, "master_enable", const.default_settings.force.master_enable)

    if anchor and st == "right" then
        -- The text field
        local src = gutil.get_child(anchor, "search_textfield")
        if src then
            src.visible = true
            src.focus()
            src.select(1, 0)
        end

        -- The button
        local btn = gutil.get_child(anchor, "search_button")
        btn.toggled = true
        btn.sprite = "utility/search_icon"

        -- The state
        state.set_player_setting(player_index, "search_is_focused", true)
    end
end

gui.defocus_search = function(player_index)
    local p = game.get_player(player_index)
    local anchor = gui.get(player_index)

    -- The text field
    local src = gutil.get_child(anchor, "search_textfield")
    src.text = ""
    src.visible = false
    state.set_player_setting(player_index, "search_is_focused", false)
    state.set_player_setting(player_index, "search_text", nil)

    -- The button
    local btn = gutil.get_child(anchor, "search_button")
    btn.toggled = false
    btn.sprite = "utility/search"

    -- Re-attach our GUI as opened
    p.opened = anchor

end

gui.update_search_field = function(player_index)
    local p = game.get_player(player_index)
    local anchor = gui.get(player_index)
    local src = gutil.get_child(anchor, "search_textfield")

    if anchor then
        state.set_player_setting(player_index, "search_text", src.text)
        gutil.clear_child_cache()
        components.repopulate_tech(player_index, anchor)
    end
end

gui.repopulate_open = function(force_index)
    for _, p in pairs(game.players) do
        if p.force.index == force_index then
            local anchor = gui.get(p.index)
            if anchor then
                components.repopulate_all(p.index, anchor)
            end
        end
    end
end

gui.request_repopulate_open = function(force_index)
    for _, p in pairs(game.players) do
        if p.force.index == force_index then
            local anchor = gui.get(p.index)
            if anchor then
                local job = repopulate_jobs[p.index]
                if job and job.anchor == anchor then
                    job.refresh_requested = true
                else
                    repopulate_jobs[p.index] = {
                        anchor = anchor,
                        stage = "upcoming_request",
                        refresh_requested = false
                    }
                end
            end
        end
    end
end

gui.tick_repopulate = function(player_index)
    local job = repopulate_jobs[player_index]
    if not job then
        return "idle"
    end
    local anchor = gui.get(player_index)
    if not anchor or not job.anchor.valid or job.anchor ~= anchor then
        repopulate_jobs[player_index] = nil
        return "invalid"
    end

    local processed_stage = job.stage
    if job.stage == "upcoming_request" then
        job.stage = components.request_upcoming(player_index, anchor) and "finish_progress" or "upcoming"
    elseif job.stage == "upcoming" then
        if components.tick_upcoming(player_index, anchor) then
            job.stage = "finish_progress"
        end
    elseif job.stage == "finish_progress" then
        components.refresh_research_progress(player_index, anchor)
        job.stage = "finish_metrics"
    elseif job.stage == "finish_metrics" then
        components.refresh_research_metrics(player_index, anchor)
        job.stage = "finish_graph"
    elseif job.stage == "finish_graph" then
        components.refresh_research_graph(player_index, anchor)
        job.stage = "finish"
    elseif job.stage == "finish" then
        if job.refresh_requested then
            job.refresh_requested = false
            job.stage = "upcoming_request"
        else
            repopulate_jobs[player_index] = nil
        end
    end
    return processed_stage
end

gui.refresh_upcoming = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_upcoming(player_index, anchor)
    end
end

gui.refresh_upcoming_times = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_upcoming_times(player_index, anchor)
    end
end

gui.refresh_science_counts = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_science_counts(player_index, anchor)
    end
end

gui.tick_science_counts = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_science_counts(player_index, anchor)
    end
end

gui.tick_research_graph = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.tick_research_graph(player_index, anchor)
    end
end

gui.refresh_research_status = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_research_status(player_index, anchor)
    end
end

gui.refresh_research_progress = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_research_progress(player_index, anchor)
    end
end

gui.refresh_research_metrics = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_research_metrics(player_index, anchor)
    end
end

gui.refresh_research_graph = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.refresh_research_graph(player_index, anchor)
    end
end

gui.show_research_graph_hover = function(player_index, column_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.show_research_graph_hover(player_index, anchor, column_index)
    end
end

gui.hide_research_graph_hover = function(player_index)
    local anchor = gui.get(player_index)
    if anchor then
        components.hide_research_graph_hover(player_index, anchor)
    end
end

return gui
