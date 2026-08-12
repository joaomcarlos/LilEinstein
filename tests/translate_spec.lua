package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path

local original_translate = package.loaded["model.state.translate"]
local original_log = package.loaded["lib.log"]
local original_log_preload = package.preload["lib.log"]
local log_errors = {}

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) ..
            ", got " .. tostring(actual), 2)
    end
end

local function assert_nil(actual, message)
    if actual ~= nil then
        error((message or "expected nil") .. ": got " .. tostring(actual), 2)
    end
end

local function assert_true(actual, message)
    if not actual then
        error(message or "expected a truthy value", 2)
    end
end

local function load_translate()
    package.loaded["model.state.translate"] = nil
    package.loaded["lib.log"] = nil
    package.preload["lib.log"] = function()
        return {
            error = function(_, message)
                log_errors[#log_errors + 1] = message
            end
        }
    end
    return require("model.state.translate")
end

local function new_fixture()
    local request_calls = {}
    local next_request_id = 1000
    local player = {}

    function player.request_translation(localised_string)
        request_calls[#request_calls + 1] = localised_string
        local request_id = next_request_id
        next_request_id = next_request_id + 1
        return request_id
    end

    storage = {
        players = {
            [1] = {state = {}}
        }
    }
    game = {
        get_player = function(player_index)
            if player_index == 1 then
                return player
            end
        end,
        print = function() end
    }
    prototypes = {}

    return request_calls
end

local function technology(name)
    return {
        name = name,
        localised_name = {"technology-name", name},
        localised_description = {"technology-description", name}
    }
end

local function test_request_initializes_attribute_queue()
    local translate = load_translate()
    new_fixture()

    translate.request(1)

    local pending = storage.translate.players[1]
    assert_true(pending ~= nil, "request must create a per-player translation entry")
    assert_equal(#pending.attributes, 8, "request must queue every supported prototype type")
    assert_equal(pending.attributes[1], "entity", "request must start with entity prototypes")
    assert_equal(pending.attributes[8], "space_location", "request must include space locations")
end

local function test_request_replaces_previous_translation_cursor()
    local translate = load_translate()
    new_fixture()
    storage.translate = {players = {[1] = {old = true}}}
    translate.request(1)
    assert_nil(storage.translate.players[1].old, "request must discard stale cursor fields")
    assert_equal(#storage.translate.players[1].attributes, 8)
end

local function test_tick_request_returns_without_translation_storage()
    local translate = load_translate()

    storage = nil
    translate.tick_request()

    storage = {}
    translate.tick_request()

    storage = {translate = {}}
    translate.tick_request()

    storage = {translate = {players = nil}}
    translate.tick_request()
end

local function test_tick_request_stores_name_and_description_requests()
    local translate = load_translate()
    local request_calls = new_fixture()
    prototypes.technology = {
        automation = technology("automation")
    }
    storage.translate = {
        players = {
            [1] = {attributes = {"technology"}}
        }
    }

    translate.tick_request()

    assert_equal(#request_calls, 2, "tick_request must request both prototype fields")
    assert_equal(request_calls[1][2], "automation", "name request must use the prototype name localisation")
    assert_equal(request_calls[2][2], "automation", "description request must use the prototype description localisation")

    local translations = storage.players[1].state.translations
    assert_equal(translations.requested[1000].type, "technology", "name request type must be recorded")
    assert_equal(translations.requested[1000].name, "automation", "name request prototype must be recorded")
    assert_equal(translations.requested[1000].field, "localised_name", "name request field must be recorded")
    assert_equal(translations.requested[1001].field, "localised_description",
        "description request field must be recorded")
    assert_equal(#storage.translate.players[1].attributes, 0,
        "tick_request must finish an attribute before advancing")
end

local function test_tick_request_is_bounded_and_resumes_from_cursor()
    local translate = load_translate()
    local request_calls = new_fixture()
    local technologies = {}
    for index = 1, 120 do
        local name = "technology-" .. tostring(index)
        technologies[name] = technology(name)
    end
    prototypes.technology = technologies
    storage.translate = {
        players = {
            [1] = {attributes = {"technology"}}
        }
    }

    translate.tick_request()

    assert_equal(#request_calls, 198, "one tick must process at most 99 prototypes")
    assert_true(storage.translate.players[1].key ~= nil,
        "a bounded tick must retain a cursor when prototypes remain")
    assert_equal(#storage.translate.players[1].attributes, 1,
        "a bounded tick must retain the active attribute")

    translate.tick_request()

    assert_equal(#request_calls, 240, "the next tick must resume after the saved cursor")
    assert_equal(#storage.translate.players[1].attributes, 0,
        "the resumed tick must remove the completed attribute")
    assert_nil(storage.translate.players[1].key, "the completed attribute must clear its cursor")

    translate.tick_request()
    assert_equal(#request_calls, 240, "a completed translation entry must not issue more requests")
end

local function test_store_saves_translation_and_consumes_request()
    local translate = load_translate()
    new_fixture()
    storage.players[1].state.translations = {
        requested = {
            [17] = {type = "technology", name = "automation", field = "localised_name"},
            [18] = {type = "technology", name = "automation", field = "localised_description"},
            [19] = {type = "technology", name = "logistics", field = "localised_name"}
        },
        technology = {
            existing = {localised_name = "Existing"}
        }
    }

    translate.store(1, 17, "Automation", {"technology-name", "automation"})
    translate.store(1, 18, "Automation description", {"technology-description", "automation"})

    local technology_translations = storage.players[1].state.translations.technology
    assert_equal(technology_translations.automation.localised_name, "Automation",
        "store must save a translated name under its prototype")
    assert_equal(technology_translations.automation.localised_description, "Automation description",
        "store must save a translated description under its prototype")
    assert_nil(storage.players[1].state.translations.requested[17],
        "store must consume a completed name request")
    assert_nil(storage.players[1].state.translations.requested[18],
        "store must consume a completed description request")
    assert_equal(technology_translations.existing.localised_name, "Existing",
        "store must preserve translations for other prototypes")
    assert_true(storage.players[1].state.translations.requested[19] ~= nil,
        "store must not consume unrelated requests")
end

local function test_store_ignores_missing_or_unknown_requests()
    local translate = load_translate()
    new_fixture()

    translate.store(1, 1, "ignored", nil)
    assert_nil(storage.players[1].state.translations,
        "store must ignore results before a translation cache exists")

    storage.players[1].state.translations = {requested = {}}
    translate.store(1, 2, "ignored", nil)
    assert_nil(storage.players[1].state.translations.technology,
        "store must ignore results that were not requested")
    storage.players[1].state.translations = {}
    translate.store(1, 2, "ignored", nil)

    storage.players[1].state.translations = {
        requested = {[3] = {type = "item", name = "iron-plate", field = "localised_name"}}
    }
    translate.store(1, 3, "Iron", nil)
    assert_equal(storage.players[1].state.translations.item["iron-plate"].localised_name, "Iron")
end

local function test_get_returns_cached_translation_and_nil_for_misses()
    local translate = load_translate()
    new_fixture()
    storage.players[1].state.translations = {
        technology = {
            automation = {localised_name = "Automation"}
        }
    }

    assert_equal(translate.get(1, "technology", "automation", "localised_name"), "Automation",
        "get must return a cached translation")
    assert_nil(translate.get(1, "technology", "missing", "localised_name"),
        "get must return nil for an unknown prototype")
    assert_nil(translate.get(1, "item", "automation", "localised_name"),
        "get must return nil for an unknown prototype type")
    assert_nil(translate.get(1, "technology", "automation", "localised_description"),
        "get must return nil for an unknown field")
end

local function test_get_requests_a_translation_cache_when_missing()
    local translate = load_translate()
    new_fixture()
    log_errors = {}

    assert_nil(translate.get(1, "technology", "automation", "localised_name"),
        "get must not fabricate a value before translations are ready")
    assert_equal(#log_errors, 1, "get must report a missing translation cache")
    assert_equal(#storage.translate.players[1].attributes, 8,
        "get must schedule a fresh translation request when its cache is missing")

    storage.players[1].state = nil
    assert_nil(translate.get(1, "technology", "automation", "localised_name"),
        "get must return nil when the player state is absent")
end

local tests = {
    {"request initializes attribute queue", test_request_initializes_attribute_queue},
    {"request replaces previous translation cursor", test_request_replaces_previous_translation_cursor},
    {"tick returns without translation storage", test_tick_request_returns_without_translation_storage},
    {"tick stores name and description requests", test_tick_request_stores_name_and_description_requests},
    {"tick is bounded and resumes from cursor", test_tick_request_is_bounded_and_resumes_from_cursor},
    {"store saves translation and consumes request", test_store_saves_translation_and_consumes_request},
    {"store ignores missing or unknown requests", test_store_ignores_missing_or_unknown_requests},
    {"get returns cached translation and nil for misses", test_get_returns_cached_translation_and_nil_for_misses},
    {"get requests cache when missing", test_get_requests_a_translation_cache_when_missing}
}

local passed = 0
for _, test in ipairs(tests) do
    local ok, err = pcall(test[2])
    if not ok then
        error("translate_spec / " .. test[1] .. " failed: " .. tostring(err), 0)
    end
    passed = passed + 1
end

package.loaded["model.state.translate"] = original_translate
package.loaded["lib.log"] = original_log
package.preload["lib.log"] = original_log_preload
storage = nil
game = nil
prototypes = nil

print("translate_spec: " .. tostring(passed) .. " passed")
return passed
