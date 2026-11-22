# Changelog

## 0.1.0 · 2026-11-22

- Opened a first playable route between Cinder Reach and Relay Nine, with direct movement and building on the surface and in orbit.
- Added a hotbar, mining, block placement, and protected travel beacons. Both locations retain their edits between trips.
- Added a versioned expedition save with atomic replacement and protection for unreadable saves.
- Added distance-based streaming of 32 × 32 tile chunks, packed block storage, and updates to changed terrain cells.
- Added a Linux x86_64 release using Godot 4.7.2, GCC `-O3`, and full LTO. The packaged runtime keeps its data under `~/.MomoyoBlock` and disables file and console logging.
- Added headless gameplay checks and a packaged build check that launches the game, travels to orbit, and verifies the resulting save.
