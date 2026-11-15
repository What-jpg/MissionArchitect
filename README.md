# Mission Architect

A game prototype built with Godot 4 based on concept v3 dated November 14, 2026. A single-player offline game in Ukrainian and English: design a rocket, launch from Earth, perform a transfer, deploy a satellite, or manually land on the Moon. User-provided assets have been integrated: character, rocket, lander, hub stations, planets, lunar surface, icons, and buttons. Visual objects and screen layouts are stored in separate Godot scenes.

## Launching the Game

Open `project.godot` in Godot 4.7.2 and press **F5**, or run `./launch.sh`. Tested with Godot 4.7.2 on Linux using OpenGL Compatibility. Other Godot 4.x versions and operating systems have not been tested separately.

The game and UI are rendered at **1920×1080**. World geometry and physics remain in local 320×180 units at ×6 scale.


## Getting Started

1. Select “New Expedition” → choose a normal game or enable the sandbox checkbox → select “Start Expedition”. Sandbox mode unlocks all missions and parts, removes costs, and disables record tracking.
2. In the hub, approach the console and press **E** to select a mission. Then approach the workbench and press **E** to open the workshop. Scroll through the builder tabs using the mouse wheel. Parts and fuel are paid for together at launch. The construction price represents reserved expenses; money is deducted only after confirmation.
3. Approach the rocket → press **E** → confirm launch. The default starter rocket can complete the first orbital mission. After launch, a separate screen displays the remaining resources.
4. In orbit, press Space or the “Impulse” button. Data collected after a mission can be sold or spent on research in the laboratory. Unlocking the next mission requires both successful completion of the previous mission and the corresponding research.
5. On the Moon, control rotation and thrust. The landing pad is also visible on the minimap. A soft touchdown outside the target area allows another takeoff using the remaining fuel.

## Controls

| Action | Keyboard |
|---|---|
| Move in the hub / rotate the lander | A/D or ←/→ |
| Ladder between floors | S/↓ — down, W/↑ — up; movement is animated |
| Open a station | E only when near the object and on the same floor |
| Thrust / impulse | W / ↑ / Space |
| Pause | Esc |

## Implemented Features

- Two-story science complex: archive, mission control, communications, laboratory, and workshop.
- Rocket builder: 1–2 stages, engines, fuel for each stage, panels, batteries, antennas, radar, instruments, landing legs, altimeter, satellite, part class, and operating time. Six resources with neutral indicators.
- Four sequential missions, two Earth orbits, three difficulty levels (“Young Astronaut”, “Engineer”, “Mission Director”), and sandbox mode.
- Launch sequence with atmospheric layers and speed markers. Transfers are available only for lunar missions and include a trajectory, data transmission, and four possible events.
- Lunar flight, collisions, and soft/hard touchdown mechanics.
- Comprehensive economy system (balance details and results are documented in `docs/ECONOMY.md`).
- Reports with reason codes, scores up to 100, ranks, and local records.

## Files

- `scripts/sim.gd` — pure calculations without UI; reads balance JSON.
- `scripts/game_state.gd` — autoloaded game state, exchange rate, economy, progress, input, and saving.
- `scripts/lander.gd` — custom physics; convex shape queries against the same surface polygon that is rendered.
- `scripts/main.gd` and `scenes/Main.tscn` — scene transitions, UI data binding, and flight simulation.
- `scenes/Hub.tscn`, `scenes/hub/` — science complex, character, ladder, and interactive objects.
- `scenes/vehicles/`, `scenes/world/` — vehicles, flight, and editable polygons for three lunar regions.
- `scenes/screens/` — native 1920×1080 layouts, map clusters, builder row templates, and modal pause screen.
- `assets/art/` — extracted PNGs; `assets/source_sheets/` — original JPGs.
- `docs/EDITING.md` — how to modify scenes and graphics yourself.
- `data/` — parts, missions, balance, Guide, and report reasons.
- `docs/ASSETS.md` — asset list, formats, and handoff procedure.
- `docs/IMPLEMENTATION.md` — concept compliance, simplifications, and checks.


## Downloading the Finished Game

Standalone `.exe` / Linux binaries can be exported through **Project → Export** after installing the corresponding export templates.
