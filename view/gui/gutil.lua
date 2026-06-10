-- GUI related utilities
local state = require("model.state")
local gutil = {}

-- Format a number in SI style: 1.5M, 500K, 2.3k, etc.
gutil.format_cost = function(n)
    if not n or n < 1000 then
        return tostring(n or 0)
    end
    if n >= 1000000 then
        local val = n / 1000000
        -- Show as integer if it's a whole number, otherwise one decimal
        if val == math.floor(val) then
            return string.format("%dM", math.floor(val))
        else
            return string.format("%.1fM", val)
        end
    end
    if n >= 1000 then
        local val = n / 1000
        if val == math.floor(val) then
            return string.format("%dK", math.floor(val))
        else
            return string.format("%.1fK", val)
        end
    end
    return tostring(n)
end

gutil.disenable_recursive = function(elm, enbl)
    if not elm then
        return
    end
    -- Ignore this element if it has the ignore_force_enable tag, i.e.;
    -- Process this element if it does not have tags,
    -- or if it does have tags but not ignore_force_enable
    if not elm.tags or not elm.tags.ignore_force_enable then
        elm.enabled = enbl
    end
    for _, c in pairs(elm.children or {}) do
        if not elm.tags or not elm.tags.ignore_enable then
            gutil.disenable_recursive(c, enbl)
        end
    end
end

local get_child_recursive
get_child_recursive = function(parent, target)
    if not parent then
        return nil
    end
    if parent.name == target then
        return parent
    else
        for _, child in pairs(parent.children) do
            local res = get_child_recursive(child, target)
            if res then
                return res
            end
        end
    end
end
gutil.get_child = function(anchor, target)
    return get_child_recursive(anchor, target)
end

gutil.get_tech_name = function(player_index, xcur, override_level)

    local name = state.get_translation(player_index, "technology", xcur.technology.name, "localised_name") or xcur.technology.name
    local level = override_level or xcur.technology.level
    if level then
        -- Strip any trailing " N" or " N (infinite)" from the localized name
        -- so the override level is always shown correctly
        if type(name) == "string" then
            name = name:gsub("%s+%d+%s*%(infinite%)%s*$", "")
            name = name:gsub("%s+%d+%s*$", "")
        end
        if level > 1 then
            name = name .. " " .. level
        end

        -- Add (infinite) if applicable
        if xcur.meta.is_infinite then
            name = name .. " (infinite)"
        end
    end
    return name
end

gutil.get_tooltip_text = function(xcur, player_index, override_level, cost_override)
    -- local p = game.get_player(player_index)
    local tt = "[font=heading-2]" .. gutil.get_tech_name(player_index, xcur, override_level) .. "[/font]\n"

    if xcur.meta.has_trigger then
        tt = tt .. "[font=default-bold]Unlocked by trigger[/font]\n\n"
    else
        tt = tt .. "[font=default-bold]Cost[/font]\n"
        tt = tt .. gutil.format_cost(cost_override or xcur.technology.research_unit_count) .. "x   "
        for _, sci in pairs(xcur.meta.sciences or {}) do
            tt = tt .. "[img=item." .. sci .. "]"
        end
        tt = tt .. "[img=virtual-signal.signal-clock]" .. ((xcur.technology.research_unit_energy or 0) / 60)
        tt = tt .. "\n\n"
    end

    -- Add the effects
    local numrecipes = 0
    if #xcur.meta.prototype.effects > 0 then
        tt = tt .. "[font=default-bold]Effects[/font]\n"
        for _, eff in pairs(xcur.meta.prototype.effects) do
            -- First only the effects for which we can simply create a string
            if eff.type == "unlock-recipe" or eff.type == "give-item" then
                -- Add the simple string
                if eff.type == "unlock-recipe" and eff.recipe then
                    tt = tt .. "[img=recipe." .. eff.recipe .. "] " ..
                             (state.get_translation(player_index, "recipe", eff.recipe, "localised_name") or eff.recipe) .. " (Recipe)"
                elseif eff.type == "give-item" and eff.item then
                    tt = tt .. tostring(eff.count or 1) .. "x [item=" .. eff.item
                    if eff.quality then
                        tt = tt .. ",quality=" .. eff.quality
                    end
                    tt = tt .. "] " .. eff.item
                end

                -- Add newline if there are more effects to come
                numrecipes = numrecipes + 1
                if #xcur.meta.prototype.effects > numrecipes then
                    tt = tt .. "\n"
                end

            end
        end
    end

    local ttl = {"", tt}

    -- Add the non-recipe effects
    if #xcur.meta.prototype.effects - numrecipes > 0 then
        local i = 0
        for _, eff in pairs(xcur.meta.prototype.effects) do

            local mod
            if eff.type == "change-recipe-productivity" then
                local p1 = {"", "[img=recipe." .. eff.recipe .. "] ",
                            state.get_translation(player_index, "recipe", eff.recipe, "localised_name") or eff.recipe}
                local p2 = {"", math.floor(eff.change * 100), "%"}
                mod = {"", {"modifier-description." .. eff.type, p1, p2}}
            elseif eff.type == "ammo-damage" or eff.type == "gun-speed" then
                local moddescr = "modifier-description." .. eff.ammo_category
                if eff.type == "ammo-damage" then
                    moddescr = moddescr .. "-damage-bonus"
                else
                    moddescr = moddescr .. "-shooting-speed-bonus"
                end
                local p1 = {"", math.floor(eff.modifier * 100), "%"}
                mod = {"", "[img=ammo-category." .. eff.ammo_category .. "] ", {moddescr, p1}}
            elseif eff.type == "turret-attack" then
                local p1 = {"", math.floor(eff.modifier * 100), "%"}
                mod = {"", "[img=item." .. eff.turret_id .. "] ", -- Could be that we need img=entity instead?
                {"modifier-description." .. eff.turret_id .. "-attack-bonus", p1}}
                -- tt = tt .. "[img=ammo-turret." .. eff.turret_id .. "] " .. eff.turret_id
            elseif eff.type == "nothing" then
                mod = {"", eff.effect_description}
            elseif eff.type == "unlock-space-location" then
                local location = state.get_translation(player_index, "space_location", eff.space_location,
                    "localised_name") or eff.space_location
                local p1 = "[space-location=" .. eff.space_location .. "] " .. location
                mod = {"", {"modifier-description.space-location-discovery", p1}}
            elseif not (eff.type == "unlock-recipe" or eff.type == "give-item") then
                -- For all other effects which are not mentioned in the first block as plain text
                if eff.modifier and tonumber(eff.modifier) then
                    local p1 = {"", math.floor(eff.modifier * 100), "%"}
                    mod = {"", {"modifier-description." .. eff.type, p1}}
                else
                    mod = {"", {"modifier-description." .. eff.type}}
                end
            end
            if mod then
                i = i + 1

                -- Add newline if more arguments are to come
                if #xcur.meta.prototype.effects - numrecipes - i > 0 then
                    table.insert(mod, "\n")
                end

                -- Add the modifier to the tooltiplocale
                table.insert(ttl, mod)

                -- Break out if there are too many remaining effects and add message instead
                if i > 17 then
                    table.insert(ttl, {"", "+" .. (#xcur.meta.prototype.effects - i) .. ""})
                    break
                end
            end

            -- [modifier-description]
            -- space-location-discovery=Discovers the location __1__.
            -- unlock-quality=Unlocks the __1__ quality.
            -- change-recipe-productivity=__1__ productivity: __2__
            -- unlock-space-platforms=Unlocks space platforms.
            -- unlock-circuit-network=Unlocks circuit network.
            -- cliff-deconstruction-enabled=Allows the deconstruction planner, rail planner and forced building mode to mark cliffs for deconstruction.
            -- mining-with-fluid=Allows the usage of fluid in mining drills.
            -- vehicle-logistics=Unlocks vehicle logistics.

            -- [modifier-description]
            -- bulk-inserter-capacity-bonus=Bulk inserter capacity: +__1__
            -- inserter-stack-size-bonus=Non-bulk inserter capacity: +__1__
            -- laboratory-speed=Lab research speed: +__1__
            -- laboratory-productivity=Lab research productivity: +__1__
            -- maximum-following-robots-count=Maximum following robots: +__1__
            -- worker-robot-speed=Worker robot speed: +__1__
            -- worker-robot-storage=Worker robot capacity: +__1__
            -- character-logistic-trash-slots=Character logistic trash slots: +__1__
            -- character-mining-speed=Character mining speed: +__1__
            -- mining-drill-productivity-bonus=Mining productivity: +__1__
            -- beacon-distribution=Beacon transmission bonus: +__1__
            -- train-braking-force-bonus=Train braking force: +__1__
            -- rocket-damage-bonus=Rocket damage: +__1__
            -- rocket-shooting-speed-bonus=Rocket shooting speed: +__1__
            -- bullet-damage-bonus=Bullet damage: +__1__
            -- bullet-shooting-speed-bonus=Bullet shooting speed: +__1__
            -- shotgun-shell-damage-bonus=Shotgun shell damage: +__1__
            -- shotgun-shell-shooting-speed-bonus=Shotgun shell shooting speed: +__1__
            -- laser-damage-bonus=Laser damage: +__1__
            -- laser-shooting-speed-bonus=Laser shooting speed: +__1__
            -- electric-damage-bonus=Electric damage: +__1__
            -- gun-turret-attack-bonus=Gun turret damage: +__1__
            -- flamethrower-turret-attack-bonus=Flamethrower turret damage: +__1__
            -- flamethrower-damage-bonus=Fire damage: +__1__
            -- fluid-damage-modifier=Fluid damage modifier
            -- beam-damage-bonus=Beam damage: +__1__
            -- grenade-damage-bonus=Grenade damage: +__1__
            -- cannon-shell-damage-bonus=Cannon shell damage: +__1__
            -- cannon-shell-shooting-speed-bonus=Cannon shell shooting speed: +__1__
            -- artillery-range=Artillery shell range: +__1__
            -- artillery-shell-shooting-speed-bonus=Artillery shell shooting speed: +__1__
            -- artillery-shell-damage-bonus=Artillery shell damage: +__1__
            -- max-failed-attempts-per-tick-per-construction-queue=Construction manager speed lower threshold: +__1__
            -- max-successful-attempts-per-tick-per-construction-queue=Construction manager speed upper threshold: +__1__
            -- character-inventory-slots-bonus=Character inventory slots: +__1__
            -- character-health-bonus=Character health: +__1__
            -- worker-robot-battery=Worker robot battery: +__1__
            -- landmine-damage-bonus=Land mine damage: +__1__
            -- character-logistic-requests=Character logistic requests
            -- auto-character-logistic-trash-slots=Character auto trash filters
            -- character-build-distance=Character build distance: +__1__
            -- character-reach-distance=Character reach distance: +__1__
            -- character-resource-reach-distance=Character resource reach distance: +__1__
            -- character-item-pickup-distance=Character item pickup distance: +__1__
            -- character-item-drop-distance=Character item drop distance: +__1__
            -- character-loot-pickup-distance=Character loot pickup distance: +__1__
            -- character-running-speed=Character walking speed: +__1__
            -- character-crafting-speed=Character crafting speed: +__1__
            -- deconstruction-time-to-live=Deconstruction lifetime: +__1__
            -- follower-robot-lifetime=Follower robot lifetime: +__1__
            -- zoom-to-world-blueprint-enabled=Zoom-to-world blueprint
            -- zoom-to-world-deconstruction-planner-enabled=Zoom-to-world deconstruction planner
            -- zoom-to-world-upgrade-planner-enabled=Zoom-to-world upgrade planner
            -- zoom-to-world-enabled=Zoom-to-world
            -- zoom-to-world-ghost-building-enabled=Zoom-to-world ghost building
            -- zoom-to-world-selection-tool-enabled=Zoom-to-world selection tool
            -- rail-planner-allow-elevated-rails=Rail planner will consider usage of elevated rails to avoid obstacles
            -- create-ghost-on-entity-death=Create ghosts when entities are destroyed
        end
    end

    return ttl

    --     if #xcur.meta.prototype.effects > 0 then
    --     tt = tt .. "[font=default-bold]Effects[/font]\n"
    --     for _, eff in pairs(xcur.meta.prototype.effects) do
    --         local ss
    --         if eff.type == "unlock-recipe" or eff.type == "change-recipe-productivity" then
    --             tt = tt .. "[img=recipe." .. eff.recipe .. "] " .. eff.recipe
    --         elseif eff.type == "ammo-damage" or eff.type == "gun-speed" then
    --             tt = tt .. "[img=ammo-category." .. eff.ammo_category .. "] " .. eff.ammo_category
    --         elseif eff.type == "turret-attack" then
    --             tt = tt .. "[img=ammo-turret." .. eff.turret_id .. "] " .. eff.turret_id
    --         elseif eff.type == "give-item" then
    --             tt = tt .. (eff.count or 1) .. "x [item=" .. eff.item .. ",quality=" .. eff.quality .. "] " .. eff.item
    --         elseif eff.type == "nothing" then
    --             -- tt = tt .. serpent.line(eff.effect_description)
    --         elseif eff.type == "unlock-space-location" then
    --             tt = tt .. "[space-location=" .. eff.space_location .. "] " .. eff.space_location
    --         else
    --             tt = tt .. eff.type
    --         end
    --         tt = tt .. "\n"
    --     end
    -- end

end
return gutil
