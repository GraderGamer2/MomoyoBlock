# Changelog

## 0.8.0 · 2026-11-23

- Relay Nine's artificial gravity fades beyond the hull. Falling far enough under the planet's pull drops the explorer above the current planet's landing pad.
- Restore one second of vacuum grace per five seconds of breathing, up to eight seconds. Air interruptions pause recovery, and saves keep both the remaining grace and partial recovery.
- Mining sand now yields a separate stack of sand that can be placed again.
- Group workbench recipes under Materials, Construction, Survival, and Tools. Crafting keeps the selected tab open.
- Render at the resized window's resolution and keep the title bar, HUD, and tiles at their original scale on larger windows. Stream extra terrain to fill the expanded view.

## 0.7.0 · 2026-11-23

- Added an eight-second grace period when an explorer in orbit runs out of breathable air. The HUD counts down before vacuum damage begins at two health points per second.
- Added craftable airlock panels and oxygen recyclers. Players can build and pressurize small airtight rooms for shelter on planets or in orbit.
- Habitat air fills, leaks, and refills over time. Expeditions save habitat pressure and vacuum exposure.

## 0.6.0 · 2026-11-23

- Added a nine-slot hotbar and five suit storage slots. Materials, workbenches, food, water, and spare air occupy movable stacks. Existing expeditions keep their inventory.
- Increased the starter pulse range to 2.1 tiles and added three upgrade levels. The previous Prospector module becomes level 1.
- Removed the workbench from the planetary beacon. Use field crafting to make a bench, or visit Relay Nine's workshop.
- Added a 1.5-second starter jetpack burst, followed by a cooldown and a recharge on solid ground.
- Started cold exposure on EVA. Hull breaches now vent gradually, pull the explorer and loose debris toward the opening, and allow life support to refill the cabin after repair.
- Added pressure glass, support frames, and insulation. Glass seals hull openings. Insulation reduces heat and cold exposure under a roof.

## 0.5.0 · 2026-11-23

- Derive planet gravity from seeded radius and rock composition. The HUD shows local gravity, and the star chart adds radius, mass, density, and composition. Relay Nine uses artificial gravity.
- Give the explorer a short-range pulse tool for mining and collecting. Solid terrain blocks pulses. The starter tool has unlimited durability, and the Prospector module increases range and mining speed.
- Add field crafting and deployable workbenches. Smelt ore, repair the suit, and craft equipment at a workbench anywhere in reach. A deployed bench can be recovered with the pulse tool.
- Track suit integrity, air leaks, and whether the suit is equipped. Storms and high pressure wear the suit. Bare or breached suits leave the explorer exposed to local air, pressure, temperatures, and storms.
- Preserve existing terrain and vitals on upgrade. Older suits start at full integrity, and crafted Prospector Picks become Prospector modules.

## 0.4.1 · 2026-11-22

- Added a body temperature gauge with a cold-to-hot scale, Celsius reading, and feedback for exposure and recovery.
- Exposure gradually changes body temperature. Severe heat or cold drains health, and controlled air near beacons and in Relay Nine lets the explorer recover.
- Persisted body temperature in expedition saves. Upgrading a 0.4.0 save keeps the explorer's position and equipment and starts body temperature at 37 °C.

## 0.4.0 · 2026-11-22

- Lowered air consumption in vacuum and the additional cost of severe weather. Reduced health loss on an empty tank.
- Refit Relay Nine with a pressurized observation cabin, landing pad, workshop, airlock, and exterior EVA deck. Mining the cabin's hull vents it until the breach is repaired.
- Mining now takes time based on block hardness. Hold on a block within reach to mine it. The targeted block and HUD show progress.
- Added a workshop at Relay Nine and at planetary landing beacons. Use gathered materials to make a Prospector Pick, spare air canisters, or a pressure liner. Equipment and reserve air persist in saves.
- Added seeded atmospheric pressure and temperature. Heat raises water use, cold raises food use, and dense atmospheres strain the suit. Solid overhead cover reduces storm exposure.
- Skip empty sky during terrain generation and apply edits only to modified chunks while reproducing the same generated terrain.
- Draw precipitation behind solid terrain so rain and snow appear in open space.
- Update expedition saves automatically. Old station saves reopen on the landing pad and keep their block edits.

## 0.3.0 · 2026-11-22

- Removed the original planet edges and underground floor. Nearby chunks stream around the explorer with stable local physics far from spawn.
- Reduced mining, placement, and gathering reach to two tiles. The HUD points back to the beacon when you are away.
- Added randomly seeded galaxies and a generated starting planet for each new expedition. Planet names, air, gravity, terrain, weather patterns, plants, and ambient wildlife vary independently within the procedural system.
- Updated the weather HUD and effects together, and expire action messages after four seconds.
- Added multiple expedition saves. Existing worlds preserve their terrain and journal data. New saves store compact, compressed changes and regenerate the untouched world from its seed.
- Cached the matching native Wayland template in Actions so content builds can reuse it.

## 0.2.0 · 2026-11-22

- Added a title and pause menu, persistent settings, and a draggable Wayland title bar with window controls.
- Added adjustable FPS limit, VSync, master volume, and a choice of OpenGL Compatibility or Vulkan Mobile.
- Added health, hunger, thirst, suit oxygen, gathering, and rescue at beacons.
- Added a star chart with seeded planet addresses, four initial planetary profiles, forage, ambient wildlife, and recurring weather.
- Persisted planet-specific terrain and harvests, station edits, and survival status. Added migration for expeditions from 0.1.
- Made the Linux x86_64 release Wayland-only and updated the release smoke test to use a Wayland compositor.

## 0.1.0 · 2026-11-22

- Opened a first playable route between Cinder Reach and Relay Nine, with direct movement and building on the surface and in orbit.
- Added a hotbar, mining, block placement, and protected travel beacons. Both locations retain their edits between trips.
- Added a versioned expedition save with atomic replacement and protection for unreadable saves.
- Added distance-based streaming of 32 × 32 tile chunks, packed block storage, and updates to changed terrain cells.
- Added a Linux x86_64 release using Godot 4.7.2, GCC `-O3`, and full LTO. The packaged runtime keeps its data under `~/.MomoyoBlock` and disables file and console logging.
- Added headless gameplay checks and a packaged build check that launches the game, travels to orbit, and verifies the resulting save.
