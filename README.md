# LilEinstein

One research queue manager to rule them all! The days of endless searching for all required technologies are gone. No more frustration why you can't seem to find the research that unlocks your favorite recipes.

## Research autopilot

The research control center adds:

- Strategy profiles ranging from cheapest-first and focused targets to logistics, combat, space, spoilable science, and productivity.
- Per-science priorities, availability hysteresis, production/consumption forecasts, and projected starvation switching.
- Surface- and logistic-network-aware lab supply clusters, including each lab prototype's accepted science packs.
- Queue-wide science budgets, deficits, completion estimates, and limiting-science identification.
- Per-technology infinite research policies: global, never, once, continuous, or to a selected level.
- Named plan presets plus compact import/export strings.
- Manual trigger objectives, multiplayer administrator locking, and a shared change history.
- Native time-sliced parallel progress. When the dedicated Parallel Research mod is installed, Little Einstein instead supplies and orders its queue while that mod owns lab distribution.
- A performance mode for large overhaul technology trees. This package targets Factorio 2.0.77 and later 2.0 releases; a Factorio 2.1 release requires a separately validated package whose manifest targets 2.1.

Cluster mode can inspect packs already in a lab and packs in a logistic network covering that lab. Factorio does not expose belt or chest connectivity as a lab supply network, so direct-fed labs are evaluated individually until packs enter their input inventories. Production and consumption statistics are surface-wide; projected-starvation switching therefore only uses those rates when cluster enforcement is disabled.

Right-click a science icon in the main window to cycle its automation priority. Infinite technologies expose their repeat policy alongside the score breakdown.

# Roadmap & ideas

- Speed/stability improvements

# Collaborations welcome

- Everyone who opened bug reports and improvement ideas
