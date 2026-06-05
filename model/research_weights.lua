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
    ["research-productivity"] = 20,          -- Infinite, no 300% cap on research output
    ["mining-productivity"] = 12,           -- Infinite, buffs all ore/oil; extremely strong long-term
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
    ["worker-robot-speed"] = 6,             -- Infinite, dramatically scales bot bases

    -- B-tier: good ROI, situational but solid
    ["physical-projectile-damage"] = 4,
    ["stronger-explosives"] = 4,

    -- C-tier: moderate value, decent fillers
    ["laser-weapons-damage"] = 3,
    ["electric-weapons-damage"] = 3,
    ["railgun-damage"] = 3,

    -- D-tier: minor utility / low impact
    ["follower-robot-count"] = -10,
    ["refined-flammables"] = 2,

    -- Negative / avoid: low ROI or hard-capped by game mechanics
    ["artillery-shell-shooting-speed"] = -5,
    ["artillery-shell-range"] = -3,
    ["artillery-shell-damage"] = -3,
    ["health"] = -1,
}

-- Hard caps: beyond this level the research is useless or capped at 300 %.
-- When a technology reaches this level, its weight becomes -1000.
-- Format: ["technology-name"] = max_level,
M.research_caps = {
    -- Recipe-based productivity techs: capped by the 300% productivity limit
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
}

return M
