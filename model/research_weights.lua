---============================================================
--  RESEARCH WEIGHTS CONFIG
--============================================================
-- This file contains the AI scoring tables for LilEinstein.
--
-- HOW TO USE:
--   1. Copy the ENTIRE contents of this file.
--   2. Paste it into any AI chat (ChatGPT, Claude, etc.) and ask:
--      "Based on the Factorio 2.0 technologies in my current save,
--      suggest missing entries or better weight values for this table."
--   3. The AI will return updated Lua tables — paste them back here.
--
-- WEIGHT SCALE (higher = the AI prioritises this tech more):
--   20+  = Must-have, game-changing ROI (e.g. research-productivity)
--   8-12 = Very strong, long-term value (mining-productivity, belt capacity)
--   4-7  = Good ROI or situational power
--   1-3  = Minor utility / filler
--   0    = Neutral / ignored by custom weight (falls back to effect inference)
--   -1-4 = Deprioritised (only picked if nothing better is available)
--   -1000 = Hard-capped / useless, never chosen
--
-- CAPS:  If a tech reaches the level listed in research_caps,
--        its weight becomes -1000 (ignored).
--        This is useful for techs capped by the game at 300 % or level 10.
--        Practical caps for infinite combat/logistics techs are based on
--        abucnasty's breakpoint analysis (one-shot thresholds, exponential
--        cost walls where research time exceeds human lifespans).
--============================================================

local M = {}

-- Base importance weights for known technologies.
-- Higher = more valuable per level.
-- Format: ["technology-name"] = weight,
--
-- TIP: Use the in-game console to list techs:
--      /c for _,t in pairs(prototypes.technology) do game.print(t.name) end
M.research_weights = {
    -- S-tier: game-changing ROI (prioritise these above almost everything)
    ["research-productivity"] = 20,          -- Infinite, no 300% cap on research output; ESPM multiplier
    ["mining-productivity"] = 12,           -- Infinite, buffs all ore/oil; flat cost scaling, cheap UPS
    ["transport-belt-capacity"] = 10,       -- Strong but finite (stack size up to 4)
    ["processing-unit-productivity"] = 9,

    -- A-tier: very strong ROI, great long-term value
    ["rocket-part-productivity"] = 8,       -- Directly reduces rocket cost; high late-game value
    ["low-density-structure-productivity"] = 7,
    ["steel-plate-productivity"] = 7,
    ["plastic-bar-productivity"] = 6,
    ["rocket-fuel-productivity"] = 6,

    -- Space economy productivities
    ["asteroid-productivity"] = 6,          -- Infinite but recipe-based; huge for late asteroid chains
    ["scrap-recycling-productivity"] = 6,   -- Strong if you lean on recycling loops

    -- Logistics & base throughput
    ["worker-robot-speed"] = 5,             -- Infinite but exponential cost wall; practical limit ~40

    -- B-tier: good ROI, situational but solid
    ["physical-projectile-damage"] = 5,     -- Key breakpoints: L13, L18, L33 (one-shot promethium)
    ["stronger-explosives"] = 5,            -- Key breakpoint: L31 (one-shot big promethium asteroids)
    ["railgun-damage"] = 4,                 -- Useful to L20-30; years territory beyond

    -- C-tier: moderate value, decent fillers
    ["laser-weapons-damage"] = 1,           -- Rarely used; beam cost exceeds ammo cost
    ["electric-weapons-damage"] = 3,
    ["refined-flammables"] = 3,             -- Strong on Gleba

    -- D-tier: minor utility / low impact
    ["follower-robot-count"] = -10,
    ["health"] = -1,

    -- Negative / avoid: low ROI or hard-capped by game mechanics
    ["artillery-shell-shooting-speed"] = -5,
    ["artillery-shell-range"] = -3,
    ["artillery-shell-damage"] = -3,
    ["railgun-shooting-speed"] = -2,        -- Most aggressive exponential; game-capped at 12
}

-- Hard caps: beyond this level the research is useless or capped at 300 %.
-- When a technology reaches this level, its weight becomes -1000.
-- Format: ["technology-name"] = max_level,
M.research_caps = {
    -- Recipe-based productivity techs: capped by the 300% productivity limit
    -- (4 legendary prod modules = +100%, so level 20 gives the remaining 200%)
    ["processing-unit-productivity"] = 25,
    ["rocket-part-productivity"] = 30,
    ["low-density-structure-productivity"] = 25,
    ["steel-plate-productivity"] = 25,
    ["plastic-bar-productivity"] = 30,
    ["rocket-fuel-productivity"] = 30,
    ["scrap-recycling-productivity"] = 30,
    ["asteroid-productivity"] = 30,

    -- Artillery shooting speed has finite levels; past that treat as useless
    ["artillery-shell-shooting-speed"] = 10,

    -- Practical infinite-tech caps based on abucnasty breakpoint analysis:
    -- Combat techs hit one-shot thresholds, then diminishing returns are severe
    ["physical-projectile-damage"] = 33,    -- L33: one-shot medium promethium asteroids w/ red ammo
    ["stronger-explosives"] = 31,           -- L31: one-shot big promethium asteroids
    ["railgun-damage"] = 30,                -- L30: years territory beyond; months already at L30
    ["railgun-shooting-speed"] = 12,        -- Bug fix capped at 12; most aggressive exponential
    ["worker-robot-speed"] = 40,            -- Exponential cost wall; millions of years by L60
    ["laser-weapons-damage"] = 10,          -- Rarely useful; laser costs more than ammo
    ["electric-weapons-damage"] = 20,       -- Diminishing returns on Gleba defense
}

-- Per-pack production difficulty weights used in scoring.
-- Higher = more expensive to produce (in UPS, logistics, and complexity).
-- This adjusts the cost component of score_tech_detailed so that a tech
-- requiring 8 packs (including promethium) is weighted as genuinely harder
-- than a 4-pack tech on Nauvis, beyond just the ingredient count.
-- Values derived from abucnasty's UPS cost analysis per science pack.
M.pack_difficulty = {
    ["automation-science-pack"] = 1.0,      -- Nauvis, trivial
    ["logistic-science-pack"] = 1.0,        -- Nauvis, trivial
    ["military-science-pack"] = 1.0,        -- Nauvis, cheap
    ["chemical-science-pack"] = 1.2,        -- Nauvis, oil processing overhead
    ["production-science-pack"] = 1.5,      -- Nauvis, complex chain
    ["utility-science-pack"] = 1.5,         -- Nauvis, complex chain
    ["space-science-pack"] = 2.0,           -- Orbit, rocket launch overhead
    ["agricultural-science-pack"] = 3.0,    -- Gleba, spoilage mechanics, UPS-heavy
    ["electromagnetic-science-pack"] = 2.5, -- Fulgora, scrap recycling chains
    ["metallurgic-science-pack"] = 2.5,     -- Vulcanus, foundry + casting chains
    ["cryogenic-science-pack"] = 3.0,       -- Aquilo, extreme cold, cryo plant
    ["promethium-science-pack"] = 5.0,      -- Solar system edge, most expensive UPS per pack
}

-- ESPM (Effective Science Per Minute) formula constants.
-- ESPM = raw_SPM * lab_drain_multiplier * (1 + module_productivity + research_prod_level * per_level_bonus)
-- In Space Age with biolabs + 4 legendary prod modules:
--   lab_drain_multiplier = 2.0  (50% drain = 2x output per pack)
--   module_productivity  = 1.0  (4x legendary prod modules = +100%)
--   per_level_bonus      = 0.10 (research productivity: +10% per level)
-- Simplified: ESPM = raw_SPM * 2 * (2 + 0.1 * research_prod_level)
-- At level 30: ESPM = raw_SPM * 10
-- At level 100: ESPM = raw_SPM * 24
-- These are reference constants for display/target calculations; the runtime
-- always reads live values from the Factorio API (force.laboratory_productivity_bonus,
-- lab_entity.productivity_bonus, prototype.science_pack_drain_rate_percent).
M.espm_constants = {
    lab_drain_multiplier = 2.0,
    module_productivity = 1.0,
    research_prod_per_level = 0.10,
}

-- Compute the ESPM multiplier for a given research productivity level.
-- This is a reference helper for display/target purposes only; runtime
-- code must use live API values, not these constants.
-- Returns: ESPM = raw_SPM * multiplier
M.espm_multiplier = function(research_prod_level)
    local c = M.espm_constants
    return c.lab_drain_multiplier * (1 + c.module_productivity + (research_prod_level or 0) * c.research_prod_per_level)
end

return M
