# Roadmap

## Game direction

MomoyoBlock is an original, demanding 2D side-scrolling survival and building sandbox. The loop is to explore on foot, gather supplies, build shelter or infrastructure, and survive long enough to make the next expedition possible. The Blockheads is a reference for hands-on side-view building. No Man’s Sky informs the procedural galaxy and planetary exploration, and Empyrion – Galactic Survival informs the need for useful ships, stations, and life support.

Gravity, atmosphere, climate, flora, and fauna should determine what supplies you bring, where you build, and how far you can travel away from safety. Every sector should be worth approaching on its own terms. Returning to a sector brings back its terrain and your construction.

## 0.3 · Procedural expeditions

- Start on a randomly generated and named planet. Each expedition has its own galaxy seed, and every address can be generated on demand.
- Explore past the original planet boundaries. The renderer and collision system load nearby chunks and recenter around the explorer as distances grow.
- Discover planets with seeded weather patterns, terrain strata, forage, and ambient wildlife. Future ecosystems can build on generation by seed and stable sector address.
- Track conditions, air, and the route back to your beacon in the HUD. Mine, build, and gather within two tiles.
- Save each expedition’s seed and generator revision, plus terrain edits and harvested forage. Regions you visit without making changes need no terrain entries. Existing saves retain their previous galaxy and terrain.

## 0.4 · Relay Nine and survival equipment

- Mine blocks with visible progress and time scaled to hardness. Gather materials for a pick, reserve air, and pressure protection.
- Refit Relay Nine with a workshop and a pressurized cabin that can vent and be repaired. Use the exterior deck to build in vacuum.
- Show atmospheric pressure and temperature on the HUD and star chart. Prepare for hot, cold, and high-pressure worlds with supplies and suit equipment.
- Track body temperature separately from outdoor temperature. Exposure builds over time, and the HUD shows when the explorer is heating up, cooling down, or recovering.

## 0.5 · Field equipment and planetary gravity

- Give planets seeded radii, masses, and bulk compositions that determine surface gravity. Use the same gravity value for movement and the star chart.
- Give explorers a reusable pulse tool for short-range mining and collection. Add a craftable upgrade for range and mining speed.
- Let players deploy and recover field workbenches, smelt ore, craft tools, and repair suits away from Relay Nine.
- Make suit integrity matter during storms and pressure exposure. Let players remove the suit and experience local air, pressure, and temperature directly.

## 0.6 · Starter gear and decompression

- Use a nine-slot hotbar and five suit pockets for blocks, equipment, and supplies. Upgrade the starter pulse tool through three levels.
- Give the starter suit a short-burst jetpack and make EVA a cold environment.
- Let a breached cabin vent over time. Airflow pulls loose objects toward an opening while a pressure difference remains. Repaired cabins repressurize.
- Craft pressure glass, support frames, and insulation at workbenches. Use beacons for travel and shelter.

## 0.7 · Habitats and EVA

- Give explorers eight seconds to find air in orbit before health begins to fall. Show the countdown on the HUD.
- Let players build small sealed rooms, cycle airlocks, and commission floor-mounted oxygen recyclers.
- Persist habitat air across trips and saves. Breaches vent and repaired rooms refill over time.

## 0.8 · Orbital descent and workbench categories

- Limit Relay Nine's artificial gravity to the station and nearby space. Let explorers who fall far enough descend to the planet below.
- Recover vacuum grace gradually while breathing and keep recovery progress in the expedition save.
- Give sand its own stack and categorize workbench recipes. Scale the game and menus with the window and keep the window controls at a consistent size when maximizing.

## 0.9 · Powered habitats

- Run oxygen recyclers from fuel generators and batteries. Track remaining fuel, reserve power, and breathable air.
- Let players build larger sealed rooms and retain air, fuel, and charge across trips and saves.

## 0.10 · Connected habitats and sandbox materials

- Connect adjacent rooms through two-panel airlocks and share power and life support across the network.
- Commission valid shelters directly from their generators and guide players through incomplete shells.
- Give playtesters a per-expedition sandbox toggle and a palette of unlimited building blocks.

## 0.11 · Solar power and placement

- Craft solar panels and stackable masts for habitat roofs. Terrain and buildings shade the panels, so siting and elevation affect power yield.
- Use solar output to reduce generator fuel use and charge habitat batteries. Show local light at the panel and total solar output on the habitat HUD.

## Next · Storage and ecology

- Add storage containers and more recipes that use resources from different environments.
- Add more mineable blocks, including clay, ice, and mineral deposits, with distinct hardness and crafting uses. Expand construction with bulkheads, ladders, and floor plating.
- Make mineral deposits more abundant and rare materials more common on hot, volcanic, and other inhospitable planets than on habitable or semi-habitable worlds, rewarding players who prepare for harsher expeditions.
- Give wildlife distinct behaviors, habitats, and roles in local ecosystems. Add plant regrowth and storms that respond to climate and shelter.

## Later · Crafting grids and habitat fields

- Replace the recipe buttons with an ingredient grid. Let players arrange stacks in a compact field grid or a larger workbench grid. Show the output and let it be taken into an inventory slot.
- Add powered forcefields and habitat domes that enclose habitable air on hostile worlds. Use power capacity to determine coverage and let a failed field vent gradually.

## Later · Vehicles and shipbuilding

- Build vehicles and ships by placing hull blocks, machinery, and crafted components by hand. Let players create and save their own blueprints, supply the listed materials, and assemble the finished ship at a clear launch site.
- Give ships walkable interiors. Let the player leave the pilot seat and move between the cockpit, cargo bay, airlock, and life support while docked or in flight.
- Let players launch from a planet and reach orbit in their own ships. Compare engine thrust with local gravity and the ship's loaded mass, including cargo and fuel. Show the thrust margin, power draw, and estimated fuel cost before launch.
- Add functional power, fuel, cargo, and life support. Make damage and how the ship is loaded affect ascent, docking, and emergency returns.
- Add discovery and route planning across multiple systems. Grow the variety of independently generated scenery, species, climates, and hazards.

## Later · NPCs, trading, and encounters

- Meet traders and travelers on stations and at planetary outposts. Exchange supplies, tools, and local materials, and learn about nearby sectors.
- Build encounters around what the player finds, such as distress signals, stranded crews, and traveling merchants with unusual cargo.

## Later · Art and audio

- Discuss the visual and audio direction with the project owner and agree on which assets to use.
- Replace the prototype geometry with original block textures and artwork for terrain, explorers, NPCs, wildlife, stations, and ship interiors.
- Add animation, interface icons, weather effects, sound effects, ambient audio, and music as the scale and pacing settle.
