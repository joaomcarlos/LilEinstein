local tech = require("model.tech")
local env = require("model.env")
local state = require("model.state")
local queue = require("model.queue")
local cmd = require("model.cmd")
local lab = require("model.lab")
local policy = require("model.research_policy")
local gui = require("view.gui")
local gutil = require("view.gui.gutil")
local const = require("lib.const")
local util = require("lib.util")

----------------------------------------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------------------------------------

local init_player = function(player_index)
    if not storage then
        return
    end
    -- Init storage
    if not player_index then
        return
    end
    if not storage.players[player_index] then
        storage.players[player_index] = {}
    end

    -- Init each module
    state.init_player(player_index)
    gui.init_player(player_index)
end
local init_force = function(force_index)
    if not storage then
        return
    end
    -- Init storage
    if not storage.forces[force_index] then
        storage.forces[force_index] = {}
    end

    -- Init each module
    state.init_force(force_index)
    tech.init_force(force_index)
    policy.init_force(force_index)
    queue.init_force(force_index)
    lab.init_force(force_index)
end

local init = function()
    -- Init storage
    if not storage then
        storage = {}
    end
    if not storage.forces then
        storage.forces = {}
    end
    if not storage.players then
        storage.players = {}
    end

    -- Init each module
    env.init()
    lab.init()

    -- Init each force
    for _, f in pairs(game.forces) do
        init_force(f.index)
    end

    -- Init each player
    for _, p in pairs(game.players) do
        init_player(p.index)
    end
end

local load = function()
    cmd.register_commands()
end

local refetch_settings = function()
    if storage.settings == nil then
        storage.settings = {}
    end
    local g = settings.global
    storage.settings.showWarnings = g["lil_einstein-show-warnings"].value
    storage.settings.notifySwitches = g["lil_einstein-notify-switches"].value
    storage.settings.warnEveryNTicks = 60 * g["lil_einstein-warn-every-n-seconds"].value
end

script.on_configuration_changed(function()
    init()
    refetch_settings()
end)

script.on_init(function()
    init()
    load()
    refetch_settings()

    -- Sync each force's in-game queue
    for _, f in pairs(game.forces) do
        queue.sync_ingame_queue(f)
    end
end)

script.on_load(function()
    load()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
    if e.mod_name == "LilEinstein" then
        refetch_settings()
    end
end)

script.on_event({defines.events.on_player_created, defines.events.on_player_joined_game}, function(e)
    init_player(e.player_index)
end)
script.on_event({defines.events.on_force_created}, function(e)
    init_force(e.force.index)
end)

script.on_event(defines.events.on_string_translated, function(e)
    state.store_translation(e.player_index, e.id, e.result, e.localised_string)
end)
script.on_event({defines.events.on_force_reset, defines.events.on_forces_merged}, function(e)
    -- Do a complete reinit because these events will fuck up a ton of shit
    init()
end)

----------------------------------------------------------------------------------------------------
-- TICK
----------------------------------------------------------------------------------------------------

local refresh_open_research_progress = function()
    for _, p in pairs(game.players) do
        if gui.is_open(p.index) then
            gui.refresh_research_progress(p.index)
        end
    end
end

local refresh_open_research_graph = function(force_index)
    for _, p in pairs(game.players) do
        if p.force.index == force_index and gui.is_open(p.index) then
            gui.refresh_research_graph(p.index)
        end
    end
end

script.on_event(defines.events.on_tick, function(e)
    -- Do the translation request if any
    state.tick_request_translation()

    local open_force_indices = {}
    for _, p in pairs(game.connected_players) do
        if gui.is_open(p.index) then
            open_force_indices[p.force.index] = true
            gui.tick_repopulate(p.index)
            gui.tick_science_counts(p.index)
            gui.tick_research_graph(p.index)
        end
    end
    for force_index in pairs(open_force_indices) do
        queue.tick_research_health_snapshot(force_index)
    end

    for _, f in pairs(game.forces) do
        local refresh_gui = false

        if state.queue_needs_sync(f) then
            queue.sync_ingame_queue(f)
            refresh_gui = true
        end
        if state.research_needs_next(f) then
            queue.start_next_research(f)
            refresh_gui = true
        end
        if state.ingame_queue_needs_cleanup(f) then
            queue.clean_ingame_queue_timeout(f)
            refresh_gui = true
        end

        -- Sync actual game queue to reordered mod queue: run immediately when idle
        -- or every 30s (1800 ticks) while researching
        if not f.current_research or game.tick % 1800 == 0 then
            queue.start_next_research(f)
        end

        -- Every 5 seconds, check if current tech is low on packs and temporarily switch
        local switch_interval = policy.get_setting(f.index, "performance_mode") and 600 or 300
        if game.tick % switch_interval == 0 then
            queue.check_and_switch_temp_research(f)
            queue.rotate_parallel_research(f)
        end

        if state.gui_needs_update(f) or refresh_gui then
            gui.request_repopulate_open(f.index)
        end

        -- Sample actual research speed every 3 seconds for the 10-minute history graph.
        if game.tick % 180 == 0 then
            queue.record_research_progress(f.index)
            refresh_open_research_graph(f.index)
        end
    end

    refresh_open_research_progress()
end)

script.on_nth_tick(42, function(e)
    -- Do the staggered lab update
    lab.tick_update()
end)

-- Per-second countdown refresh for upcoming research panel (lightweight, no reprocessing)
script.on_nth_tick(60, function(e)
    for _, p in pairs(game.players) do
        if gui.is_open(p.index) then
            gui.refresh_upcoming_times(p.index)
            gui.refresh_science_counts(p.index)
            gui.refresh_research_metrics(p.index)
        end
    end
end)

----------------------------------------------------------------------------------------------------
-- RESEARCH
----------------------------------------------------------------------------------------------------

script.on_event(defines.events.on_research_finished, function(e)
    -- Use the force, luke
    local f = e.research.force
    tech.update_researched(f.index, e.research.name)
    queue.requeue_finished(f, e.research)
    policy.record_action(f.index, nil, "research_finished", e.research.name)
    state.request_next_research(f)
end)

local reject_locked_research_change = function(e)
    local p = e.player_index and game.get_player(e.player_index) or nil
    if not p or policy.can_edit(p) then
        return false
    end
    p.print({"lil_einstein-msg.multiplayer-locked"})
    queue.reorder_queue_by_score(e.force.index)
    state.request_next_research(e.force)
    state.request_ingame_queue_cleanup(e.force)
    return true
end

script.on_event({defines.events.on_research_queued, defines.events.on_research_moved}, function(e)
    -- When ingame research queue gets modified we need to sync that to our modqueue
    local f = e.force
    if queue.is_internal_research_queue_update(f) then
        return
    end
    if reject_locked_research_change(e) then
        return
    end
    state.request_queue_sync(f)
    state.request_ingame_queue_cleanup(f)
    policy.record_action(f.index, e.player_index, "vanilla_queue_changed", "")
end)
script.on_event(defines.events.on_research_cancelled, function(e)
    local f = e.force
    if queue.is_internal_research_queue_update(f) then
        return
    end
    if reject_locked_research_change(e) then
        return
    end
    for tn, _ in pairs(e.research or {}) do
        if not queue.consume_internal_research_cancel(f, tn) then
            queue.remove(e.force, tn)
        end
    end
    state.request_ingame_queue_cleanup(f)
end)

script.on_event(defines.events.on_research_reversed, function(e)
    -- When a tech gets reversed we need to request a next research
    -- Because the one we are researching right now might no longer be available
    local f = e.research.force

    tech.update_researched(f.index, e.research.name)
    state.request_next_research(f)
end)

----------------------------------------------------------------------------------------------------
-- ENTITY
----------------------------------------------------------------------------------------------------
local labfilter = {{
    filter = "type",
    type = "lab"
}}
local register_lab = function(entity)
    if not entity then
        return
    end
    lab.register(entity)
    queue.invalidate_science_cache(entity.force.index)
end
script.on_event(defines.events.on_built_entity, function(e)
    register_lab(e.entity)
end, labfilter)
script.on_event(defines.events.on_robot_built_entity, function(e)
    register_lab(e.entity)
end, labfilter)
script.on_event(defines.events.script_raised_built, function(e)
    register_lab(e.entity)
end, labfilter)
script.on_event(defines.events.script_raised_revive, function(e)
    if e.entity and e.entity.type == "lab" then
        register_lab(e.entity)
    end
end)
script.on_event(defines.events.on_entity_cloned, function(e)
    if e.destination and e.destination.type == "lab" then
        register_lab(e.destination)
    end
end)

----------------------------------------------------------------------------------------------------
-- KEYBINDING HOOKS
----------------------------------------------------------------------------------------------------

script.on_event("lil_einstein_toggle_gui", function(e)
    gui.toggle(e.player_index)
end)
script.on_event(defines.events.on_lua_shortcut, function(e)
    if e.prototype_name == "lil_einstein_shortcut" then
        gui.toggle(e.player_index)
    end
end)

script.on_event("lil_einstein_toggle_menu", function(e)
end)

script.on_event("lil_einstein_focus_search", function(e)
    gui.focus_search(e.player_index)
end)

----------------------------------------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------------------------------------

-- Player events handling
script.on_event(defines.events.on_gui_closed, function(e)
    if gui.is_open(e.player_index) then
        -- Check if the search field is focussed
        if gui.is_search_focussed(e.player_index) then
            gui.defocus_search(e.player_index)
        else
            gui.toggle(e.player_index)
        end
    end
end)

script.on_event(defines.events.on_gui_hover, function(e)
    if not e.element or not e.element.valid or not e.element.tags or not e.element.tags["lil_einstein_on_hover"] then
        return
    end

    local t = e.element.tags
    if t.handler == "research_graph_hover" then
        gui.show_research_graph_hover(e.player_index, t.column_index)
    end
end)

script.on_event(defines.events.on_gui_leave, function(e)
    if not e.element or not e.element.valid or not e.element.tags or not e.element.tags["lil_einstein_on_hover"] then
        return
    end

    local t = e.element.tags
    if t.handler == "research_graph_hover" then
        gui.hide_research_graph_hover(e.player_index)
    end
end)

local mutable_gui_handlers = {
    pin_upcoming_tech = true,
    add_queue_top = true,
    add_queue_bottom = true,
    hide = true,
    show = true,
    move_tech_up = true,
    move_tech_down = true,
    remove_from_queue = true,
    promote_research = true,
    demote_research = true,
    master_enable = true,
    toggle_checkbox_force_click = true,
    toggle_tech_enabled = true,
    consecutive_tech_cap_dec = true,
    consecutive_tech_cap_inc = true,
    toggle_policy_setting = true,
    adjust_policy_setting = true,
    cycle_science_priority = true,
    adjust_science_threshold = true,
    cycle_repeat_rule = true,
    adjust_repeat_level = true,
    save_plan_preset = true,
    load_plan_preset = true,
    delete_plan_preset = true,
    import_plan = true
}

script.on_event(defines.events.on_gui_click, function(e)
    -- Early exit if the gui element doesnt have our on_click tag
    if not e.element.tags or not e.element.tags["lil_einstein_on_click"] then
        return
    end

    local t = e.element.tags
    local h = t.handler
    local p = game.get_player(e.player_index)
    if not p then
        return
    end
    local f = p.force

    if mutable_gui_handlers[h] and not policy.can_edit(p) then
        p.print({"lil_einstein-msg.multiplayer-locked"})
        return
    end
    if h == "toggle_allowed_science" and e.button == defines.mouse_button_type.right and not policy.can_edit(p) then
        p.print({"lil_einstein-msg.multiplayer-locked"})
        return
    end

    -- The steps to move the tech in the queue
    local steps = 1
    if e.control then
        steps = 99999999
    elseif e.shift then
        steps = 5
    end

    -- Repopulate flag, to be set false for specific actions
    local repopulate = true

    -- Handle action
    if h == "show_technology_screen" then
        local target_player = game.get_player(e.player_index)
        target_player.open_technology_gui(e.element.name)
        repopulate = false
    elseif h == "pin_upcoming_tech" then
        local pinned = queue.get_pinned_tech(f.index)
        local clicked = t.technology
        if pinned == clicked then
            queue.set_pinned_tech(f.index, nil)
        else
            queue.set_pinned_tech(f.index, clicked)
        end
        state.request_next_research(f)
    elseif h == "show_category_checkbox" then
        -- TODO
    elseif h == "add_queue_top" then
        queue.add(f, t.technology, 1)
    elseif h == "add_queue_bottom" then
        queue.add(f, t.technology)
    elseif h == "hide" then
        tech.suspend(f.index, t.technology, true)
    elseif h == "show" then
        tech.suspend(f.index, t.technology, false)
    elseif h == "move_tech_up" then
        local before = queue.get_tech_ub(f.index, t.technology)
        queue.adjust_tech_ub(f.index, t.technology, 1)
        local after = queue.get_tech_ub(f.index, t.technology)
        -- game.print("[LilEinstein DEBUG] move_tech_up: tech=" .. tostring(t.technology) .. " force=" .. tostring(f.index) .. " UB=" .. tostring(before) .. "->" .. tostring(after))
    elseif h == "move_tech_down" then
        local before = queue.get_tech_ub(f.index, t.technology)
        queue.adjust_tech_ub(f.index, t.technology, -1)
        local after = queue.get_tech_ub(f.index, t.technology)
        -- game.print("[LilEinstein DEBUG] move_tech_down: tech=" .. tostring(t.technology) .. " force=" .. tostring(f.index) .. " UB=" .. tostring(before) .. "->" .. tostring(after))
    elseif h == "remove_from_queue" then
        queue.remove(f, t.technology)
    elseif h == "toggle_allowed_science" then
        if e.button == defines.mouse_button_type.right then
            local priority = policy.cycle_science_priority(f.index, t.science)
            policy.record_action(f.index, p.index, "science_priority", t.science .. "=" .. priority)
            state.request_next_research(f)
        else
            state.toggle_player_setting(p.index, "allowed_" .. t.science)
        end
    elseif h == "promote_research" then
        queue.promote(f, t.tech_name, steps)
    elseif h == "demote_research" then
        queue.demote(f, t.tech_name, steps)
    elseif h == "produced_science" then
        local sci = util.get_all_sciences()
        for _, s in pairs(sci) do
            state.set_player_setting(p.index, "allowed_" .. s, false)
        end
        local prod = queue.get_science_availability(f.index)
        for s, available in pairs(prod) do
            if available then
                state.set_player_setting(p.index, "allowed_" .. s, true)
            end
        end
    elseif h == "all_science" then
        local sci = util.get_all_sciences()
        for _, s in pairs(sci) do
            state.set_player_setting(p.index, "allowed_" .. s, true)
        end
    elseif h == "none_science" then
        local sci = util.get_all_sciences()
        for _, s in pairs(sci) do
            state.set_player_setting(p.index, "allowed_" .. s, false)
        end
    elseif h == "invert_science" then
        local sci = util.get_all_sciences()
        for _, s in pairs(sci) do
            state.toggle_player_setting(p.index, "allowed_" .. s)
        end
    elseif h == "search" then
        if gui.is_search_focussed(p.index) then
            gui.defocus_search(p.index)
        else
            gui.focus_search(p.index)
        end
    elseif h == "close" then
        gui.toggle(p.index)
        repopulate = false
    elseif h == "toggle_policy_panel" then
        gui.toggle_policy_panel(p.index)
        repopulate = false
    elseif h == "toggle_research_details" then
        gui.toggle_research_details(p.index)
        repopulate = false
    elseif h == "show_trigger_technology" then
        p.open_technology_gui(t.technology)
        repopulate = false
    elseif h == "master_enable" then
        local st = state.get_force_setting(f.index, "master_enable", const.default_settings.force.master_enable)
        if st == "left" then
            st = "right"
        else
            st = "left"
        end
        state.set_force_setting(f.index, "master_enable", st)
        state.request_next_research(f)
    elseif h == "toggle_checkbox_force_click" then
        local cur = state.get_force_setting(f.index, t.setting_name, const.default_settings.force.settings[t.setting_name])
        state.set_force_setting(f.index, t.setting_name, not cur)
        if t.setting_name == "auto_research" then
            state.request_next_research(f)
        end
    elseif h == "toggle_tech_enabled" then
        local enabled = queue.get_tech_enabled(f.index, t.technology)
        queue.set_tech_enabled(f.index, t.technology, not enabled)
    elseif h == "toggle_radiobutton_player" then
        state.set_player_setting(p.index, t.setting_name, t.value)
    elseif h == "consecutive_tech_cap_dec" then
        local val = state.get_force_setting(f.index, "consecutive_tech_cap", const.default_settings.force.settings.consecutive_tech_cap)
        val = math.max(1, val - 1)
        state.set_force_setting(f.index, "consecutive_tech_cap", val)
    elseif h == "consecutive_tech_cap_inc" then
        local val = state.get_force_setting(f.index, "consecutive_tech_cap", const.default_settings.force.settings.consecutive_tech_cap)
        val = val + 1
        state.set_force_setting(f.index, "consecutive_tech_cap", val)
    elseif h == "toggle_policy_setting" then
        local current = policy.get_setting(f.index, t.setting_name)
        if t.setting_name == "multiplayer_lock" and not p.admin then
            p.print({"lil_einstein-msg.admin-required"})
        else
            local new_value = not current
            policy.set_setting(f.index, t.setting_name, new_value)
            if t.setting_name == "planning_paused" and new_value then
                queue.apply_planning_pause(f)
            end
            state.request_next_research(f)
        end
    elseif h == "adjust_policy_setting" then
        local current = policy.get_setting(f.index, t.setting_name) or 0
        policy.set_setting(f.index, t.setting_name, current + (t.delta or 0))
        state.request_next_research(f)
    elseif h == "cycle_science_priority" then
        policy.cycle_science_priority(f.index, t.science)
        state.request_next_research(f)
    elseif h == "adjust_science_threshold" then
        policy.adjust_science_threshold(f.index, t.science, t.threshold_name, t.delta or 0)
        queue.invalidate_science_cache(f.index)
        state.request_next_research(f)
    elseif h == "cycle_repeat_rule" then
        local technology = f.technologies[t.technology]
        policy.cycle_repeat_rule(f.index, t.technology, technology and technology.level or 1)
    elseif h == "adjust_repeat_level" then
        local technology = f.technologies[t.technology]
        policy.adjust_repeat_max_level(f.index, t.technology, t.delta or 0, technology and technology.level or 1)
    elseif h == "save_plan_preset" then
        local anchor = gui.get(p.index)
        local field = gutil.get_child(anchor, "policy_preset_name")
        local name = field and field.text or ""
        if queue.save_preset(f.index, name) then
            state.set_player_setting(p.index, "selected_plan_preset", name)
            p.print({"lil_einstein-msg.preset-saved", name})
        else
            p.print({"lil_einstein-msg.preset-name-invalid"})
        end
    elseif h == "load_plan_preset" then
        local name = state.get_player_setting(p.index, "selected_plan_preset")
        if name and queue.load_preset(f.index, name) then
            p.print({"lil_einstein-msg.preset-loaded", name})
        end
    elseif h == "delete_plan_preset" then
        local name = state.get_player_setting(p.index, "selected_plan_preset")
        if name then
            queue.delete_preset(f.index, name)
            state.set_player_setting(p.index, "selected_plan_preset", nil)
        end
    elseif h == "export_plan" then
        local exchange = queue.export_plan(f.index)
        state.set_player_setting(p.index, "plan_exchange_string", exchange or "")
    elseif h == "import_plan" then
        local anchor = gui.get(p.index)
        local field = gutil.get_child(anchor, "policy_exchange_string")
        local ok = field and queue.import_plan(f.index, field.text)
        if ok then
            p.print({"lil_einstein-msg.plan-imported"})
        else
            p.print({"lil_einstein-msg.plan-import-failed"})
        end
    end

    if mutable_gui_handlers[h] then
        policy.record_action(f.index, p.index, h, t.technology or t.science or t.setting_name or "")
    end

    -- Refresh all open GUIs to reflect the changes
    if repopulate then
        gui.repopulate_open(f.index)
    end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e)
    -- Early exit if the gui element doesnt have our on_click tag
    if not e.element.tags or not e.element.tags["lil_einstein_on_state_change"] then
        return
    end

    local t = e.element.tags
    local h = t.handler
    local p = game.get_player(e.player_index)
    if not p then
        return
    end
    local f = p.force

    if h == "toggle_checkbox_force" and not policy.can_edit(p) then
        p.print({"lil_einstein-msg.multiplayer-locked"})
        return
    end

    -- Repopulate flag, to be set false for specific actions
    local repopulate = true

    -- Handle action
    if h == "toggle_checkbox_player" then
        state.set_player_setting(e.player_index, t.setting_name, e.element.state)
    elseif h == "toggle_radiobutton_player" then
        state.set_player_setting(e.player_index, t.setting_name, e.element.name)
    elseif h == "toggle_checkbox_force" then
        state.set_force_setting(f.index, t.setting_name, e.element.state)
        if t.setting_name == "auto_research" then
            state.request_next_research(f)
        end
    end

    -- Refresh all open GUIs to reflect the changes
    if repopulate then
        gui.repopulate_open(f.index)
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(e)
    -- Early exit if the gui element doesnt have our on_click tag
    if not e.element.tags or not e.element.tags["lil_einstein_on_state_change"] then
        return
    end

    local t = e.element.tags
    local h = t.handler
    local p = game.get_player(e.player_index)
    if not p then
        return
    end
    local f = p.force

    if h == "announcement_level" then
        if not policy.can_edit(p) then
            p.print({"lil_einstein-msg.multiplayer-locked"})
            return
        end
        state.set_force_setting(f.index, t.setting_name, e.element.selected_index)
    elseif h == "policy_strategy" then
        if not policy.can_edit(p) then
            p.print({"lil_einstein-msg.multiplayer-locked"})
            return
        end
        local strategy = policy.strategy_order[e.element.selected_index]
        if strategy then
            policy.set_setting(f.index, "strategy", strategy)
            policy.record_action(f.index, p.index, "strategy", strategy)
            state.request_next_research(f)
            gui.repopulate_open(f.index)
        end
    elseif h == "policy_preset_selection" then
        local names = queue.get_preset_names(f.index)
        state.set_player_setting(p.index, "selected_plan_preset", names[e.element.selected_index])
    end
end)

script.on_event(defines.events.on_gui_switch_state_changed, function(e)
    -- Early exit if the gui element doesnt have our on_click tag
    if not e.element.tags or not e.element.tags["lil_einstein_on_state_change"] then
        return
    end

    local t = e.element.tags
    local h = t.handler
    local p = game.get_player(e.player_index)
    if not p then
        return
    end
    local f = p.force

    if (h == "master_enable" or h == "toggle_tech_enabled") and not policy.can_edit(p) then
        p.print({"lil_einstein-msg.multiplayer-locked"})
        return
    end

    -- Repopulate flag, to be set false for specific actions
    local repopulate = true

    -- Handle action
    if h == "master_enable" then
        state.set_force_setting(f.index, "master_enable", e.element.switch_state)
        state.request_next_research(f)
    elseif h == "toggle_tech_enabled" then
        local enabled = (e.element.switch_state == "right")
        queue.set_tech_enabled(f.index, t.technology, enabled)
    end

    -- Refresh all open GUIs to reflect the changes
    if repopulate then
        gui.repopulate_open(f.index)
    end
end)

script.on_event(defines.events.on_gui_text_changed, function(e)
    -- Early exit if the gui element doesnt have our on_click tag
    if not e.element.tags or not e.element.tags["lil_einstein_on_change"] then
        return
    end

    local t = e.element.tags
    local h = t.handler
    local p = game.get_player(e.player_index)
    if not p then
        return
    end
    local f = p.force

    -- Handle action
    if h == "search_textfield" then
        gui.update_search_field(e.player_index)
    elseif h == "policy_preset_name" then
        state.set_player_setting(e.player_index, "plan_preset_name", e.element.text)
    elseif h == "policy_exchange_string" then
        state.set_player_setting(e.player_index, "plan_exchange_string", e.element.text)
    end
end)
