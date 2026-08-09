package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function reset_modules()
    for name in pairs(package.loaded) do
        if name == "model.queue" or name == "lib.util" or name == "lib.const" or
            name == "lib.log" or name == "model.state" or name == "model.tech" or
            name == "model.lab" or name == "model.env" or name == "model.research_weights" or
            name == "model.research_policy" then
            package.loaded[name] = nil
        end
    end
end

local function load_queue()
    reset_modules()

    package.preload["lib.util"] = function() return {} end
    package.preload["lib.log"] = function()
        return {
            error = function() end,
            log = function() end
        }
    end
    package.preload["lib.const"] = function()
        return {
            default_settings = {
                force = {
                    settings = {
                        auto_research = true,
                        requeue_infinite_tech = true
                    }
                }
            }
        }
    end
    package.preload["model.state"] = function()
        return {
            get_force_setting = function(_, setting_name, default_setting)
                if setting_name == "auto_research" then
                    return true
                end
                return default_setting
            end,
            request_next_research = function() end,
            request_gui_update = function() end
        }
    end
    package.preload["model.tech"] = function()
        return {
            get_all_tech_state_ext = function() return {} end,
            get_single_tech_state_ext = function() return nil end,
            update_queued = function() end
        }
    end
    package.preload["model.lab"] = function() return {} end
    package.preload["model.env"] = function() return {} end
    package.preload["model.research_weights"] = function()
        return {research_caps = {}}
    end
    package.preload["model.research_policy"] = function()
        return {
            get_setting = function(_, setting_name)
                if setting_name == "strategy" then
                    return "balanced"
                end
                return false
            end
        }
    end

    return require("model.queue")
end

local function make_force(current_tech, queue_names)
    local force = {
        index = 1,
        current_research = nil,
        research_queue = {}
    }
    storage = {
        forces = {
            [1] = {
                queue = {
                    current_tech = current_tech,
                    queue = queue_names
                }
            }
        }
    }
    game = {
        tick = 100,
        forces = {[1] = force},
        surfaces = {}
    }
    return force, storage.forces[1].queue
end

local function test_idle_force_rebuilds_after_research_was_cancelled()
    local queue = load_queue()
    local force, queue_state = make_force("worker-robots-speed-7", {})
    local build_calls = 0
    local reorder_calls = 0

    queue.build_queue_from_available = function(force_index)
        build_calls = build_calls + 1
        storage.forces[force_index].queue.queue = {"research-productivity"}
    end
    queue.reorder_queue_by_score = function(force_index)
        reorder_calls = reorder_calls + 1
        storage.forces[force_index].queue.current_tech = "research-productivity"
        game.forces[force_index].research_queue = {"research-productivity"}
    end

    queue.start_next_research(force)

    assert_equal(build_calls, 1, "an idle force must rebuild its queue after cancellation")
    assert_equal(reorder_calls, 1, "a rebuilt queue must be reordered")
    assert_equal(force.research_queue[1], "research-productivity",
        "cancellation must not leave the force with an empty runtime queue")
    assert_equal(queue_state.current_tech, "research-productivity",
        "the stale cancelled technology must not block the next selection")
end

local function test_active_force_keeps_current_research_guard()
    local queue = load_queue()
    local force, queue_state = make_force("worker-robots-speed-7", {"research-productivity"})
    force.current_research = {name = "worker-robots-speed-7"}
    local reorder_calls = 0

    queue.reorder_queue_by_score = function()
        reorder_calls = reorder_calls + 1
    end

    queue.start_next_research(force)

    assert_equal(reorder_calls, 0, "active research must not be rescheduled by idle recovery")
    assert_equal(queue_state.current_tech, "worker-robots-speed-7",
        "active research state must remain unchanged")
end

test_idle_force_rebuilds_after_research_was_cancelled()
test_active_force_keeps_current_research_guard()
print("queue_spec: OK")
