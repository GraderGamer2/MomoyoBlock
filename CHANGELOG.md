# Changelog

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
