# LilEinstein

Runs the research queue for you: it picks the next technology, watches your science supply, and switches research when a pack runs dry.

- **Toolbar shortcut**: opens the control center beside your technology list.
- **Strategy profiles**: cheapest first, unlock recipes, logistics, combat, space, spoilable science, productivity, and a few more.
- **Per-science priorities**: hysteresis and flow forecasts, so the queue stops flip-flopping between technologies.
- **Repeat policies**: per-technology rules and level caps for infinite research.
- **Plan presets**: save a plan, export it as a string, paste it into another save.
- **Multiplayer**: lock controls to server admins, with a shared history of recent plan changes.

Queue a technology or target something you want built, and it keeps research pointed at that goal. Science counts force-wide: packs spread across different lab networks still make a technology runnable, and cargo in transit feeds the forecast. When a pack runs dry it switches to something you can research right now, then returns to your target once supply recovers.

The control center shows where science is short: per-pack demand, stock, supply gap, and which labs are starving.

Conflicts with `some-autoresearch`, `UltimateResearchQueue2`, and `paralell-lab`. Optional support for `simultaneous-research` and `Ultracube`.

Requires Factorio 2.1.0 or later. Safe to add to an existing save.

[Source on GitHub](https://github.com/joaomcarlos/LilEinstein)
