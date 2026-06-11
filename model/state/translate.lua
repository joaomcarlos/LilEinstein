local logger = require("lib.log")

local translate = {}

local get_global_player = function(player_index)
    -- init_settings_player(player_index)
    return storage.players[player_index].state
end

local get_translation_player = function(player_index, create)
    -- Ensure translate entry
    storage.translate = storage.translate or {}
    local st = storage.translate
    st.players = st.players or {}
    if create and not st.players[player_index] then
        st.players[player_index] = {}
    end
    return st.players[player_index]
end

translate.request = function(player_index)
    -- Get storage
    local stp = get_translation_player(player_index, true)

    -- Clear previous translations
    for k, v in pairs(stp or {}) do
        k = nil
    end

    -- Create array of attributes to be translated
    stp.attributes = {"entity", "item", "fluid", "equipment", "recipe", "technology", "ammo_category", "space_location"}
end

translate.tick_request = function()
    -- Early exit if no storage
    if not storage or not storage.translate or not storage.translate.players then
        return
    end

    -- Start profiler
    -- local pro = game.create_profiler(false)

    local count = 1
    local MAX_COUNT = 100

    -- for player_index, prop in pairs(storage.translate.players) do
    local player_index, prop = next(storage.translate.players)

    if prop.attributes and #prop.attributes > 0 then

        -- Get the player
        local p = game.get_player(player_index)

        -- Get/init the player's translation array
        local gp = get_global_player(player_index)
        gp.translations = gp.translations or {}
        local gpt = gp.translations
        gpt.requested = gpt.requested or {}
        local gptr = gpt.requested

        -- Get the current attribute to be translated
        local ia = #prop.attributes
        local a = prop.attributes[ia]

        while count < MAX_COUNT do

            -- Get the next prototype to be translated
            -- local k, t = next(prototypes[a], prop.key)
            local iter, tbl, key = pairs(prototypes[a])
            local k, t = iter(tbl, prop.key)

            if k then
                -- Store the request ID in the requested array and add the type/field identifiers so we can map it easier when we get the translation back 
                local propn = {
                    type = a,
                    name = t.name,
                    localised_name = t.localised_name,
                    field = "localised_name"
                }
                local idn = p.request_translation(t.localised_name)
                if idn then
                    gptr[idn] = propn
                end

                local propd = {
                    type = a,
                    name = t.name,
                    localised_description = t.localised_description,
                    field = "localised_description"
                }
                local idd = p.request_translation(t.localised_description)
                if idd then
                    gptr[idd] = propd
                end

            else
                -- If we did not get a new key from the prototypes array it means we processed all prototypes
                -- So we can delete this attribute
                table.remove(prop.attributes, ia)

                prop.key = nil

                -- Early exit the loop
                break
            end

            -- Store the current key so we know where to continue in the next iteration
            prop.key = k

            -- Increment
            count = count + 1
        end
    else
        -- We processed all attributes, so we can delete this player's entry
        storage.translate[player_index] = nil
    end
    -- end

    -- Stop profiler
    -- pro.stop()
    -- log("Processed " .. count .. " translation requests")
    -- log(pro)

end

-- translate.request = function(player_index)
--     local p = game.get_player(player_index)
--     if not p then
--         game.print("[LilEinstein] ERROR: Requested translation but no player found for player_index " .. player_index ..
--                        ", please open a bug report on the mod portal")
--         return
--     end
--     local f = p.force
--     local gp = get_global_player(player_index)
--     gp.translations = {}
--     local gpt = gp.translations
--     gpt.queued = {}
--     local gptq = gpt.queued
--     gpt.requested = {}
--     local gptr = gpt.requested

--     local prop = {}

--     local att = {"entity", "item", "fluid", "equipment", "recipe", "technology"} -- Needed "quality", "tile"?
--     -- local att = {"technology"}
--     for _, a in pairs(att) do

--         local pro = game.create_profiler(false)
--         for _, t in pairs(prototypes[a]) do
--             -- Store the request ID in the requested array and add the type/field identifiers so we can map it easier when we get the translation back 
--             local propn = {
--                 type = a,
--                 name = t.name,
--                 localised_name = t.localised_name,
--                 field = "localised_name"
--             }
--             -- table.insert(gptq, propn)
--             local idn = p.request_translation(t.localised_name)
--             if idn then
--                 gptr[idn] = propn
--             end

--             local propd = {
--                 type = a,
--                 name = t.name,
--                 localised_description = t.localised_description,
--                 field = "localised_description"
--             }
--             -- table.insert(gptq, propd)
--             local idd = p.request_translation(t.localised_description)
--             if idd then
--                 gptr[idd] = propd
--             end
--         end

--         pro.stop()
--         log("state.init_player profiled for translation " .. a)
--         log(pro)
--     end
-- end

translate.store = function(player_index, id, translated_string, localised_string)
    -- Get the player storage or early exit if we have no translations array
    -- init_settings_player(player_index)
    local gpt = storage.players[player_index].state.translations
    if not gpt then
        return
    end

    -- Early exit if this is an unrequested translation (eg. from other mods)
    if not gpt.requested then
        return
    end
    local gptr = gpt.requested[id]
    if not gptr then
        return
    end

    if gpt[gptr.type] == nil or next(gpt[gptr.type]) == nil then
        gpt[gptr.type] = {}
    end
    local gptt = gpt[gptr.type]
    if gptt[gptr.name] == nil or next(gptt[gptr.name]) == nil then
        gptt[gptr.name] = {}
    end

    -- Store the translation
    gptt[gptr.name][gptr.field] = translated_string

    -- Remove the requested ID from the array
    gpt.requested[id] = nil
end

translate.get = function(player_index, type, name, field)
    local gp = get_global_player(player_index)
    if not gp then
        return
    end
    local gpt = gp.translations
    if not gpt then
        logger.error(nil, "Unable to search locale, please wait until translations are complete and try again")
        translate.request(player_index)
        return
    end
    local gptt = gpt[type]
    if not gptt then
        return
    end
    local gpttn = gptt[name]
    if not gpttn then
        return
    else
        return gpttn[field]
    end
end

return translate
