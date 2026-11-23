# MomoyoBlock

MomoyoBlock is a 2D side-view survival and building sandbox. Start on a generated planet, use Relay Nine to chart jumps across a seeded galaxy, and build shelters while managing food, water, and suit oxygen. This alpha uses placeholder visuals.

## Play on Linux x86_64 with Wayland

Download `MomoyoBlock-linux-x86_64.tar.gz` from the [Actions build](https://github.com/GraderGamer2/MomoyoBlock/actions/workflows/build.yml). Extract it into your home directory and launch it from a Wayland session.

```sh
tar -xzf MomoyoBlock-linux-x86_64.tar.gz -C "$HOME"
"$HOME/.MomoyoBlock/MomoyoBlock"
```

Re-extracting the archive updates the game. Expeditions live under `~/.MomoyoBlock/profile/saves/`. Existing expeditions keep their planets and block edits. Expeditions saved on Relay Nine before 0.4 resume at the landing pad. Choose **New expedition** from the main menu for a randomly generated starting planet in a separate save. **Continue expedition** opens the most recently saved slot, and **Load expedition** lets you pick another. Settings live at `~/.MomoyoBlock/profile/settings.cfg`. The installed game, data, and caches stay under `~/.MomoyoBlock`. Release file and console logging are disabled.

The Linux template includes the native Wayland display driver. It requires x86_64 with SSE4.2 and a GPU that supports the selected renderer. The built-in title bar supports moving, minimizing, maximizing, restoring, and closing the window. Drag the lower-right corner to resize. The game, HUD, and menus scale to fit while rendering at the window's native resolution. The title bar and window buttons keep their size when you maximize.

## Controls

| Input | Action |
|---|---|
| A / D or ← / → | Walk |
| Space | Jump |
| Hold Shift | Fire the starter suit's jetpack |
| Hold left click | Mine with the pulse tool |
| Right click | Place the selected block or use the selected supply |
| 1–9 or mouse wheel | Select a hotbar slot |
| Tab | Open the inventory and move stacks |
| F | Collect the nearest food or water source with the pulse tool |
| R / T | Eat a ration or drink water |
| C | Open field crafting or the nearby workbench |
| U | Equip or remove the suit |
| O | Use a spare air canister |
| E at a beacon | Travel between the current planet and Relay Nine |
| E beside an airlock or recycler | Cycle the airlock or commission life support |
| Right click a fuel generator | Load a fuel cell from accessible inventory |
| M at the Relay Nine beacon | Open the star chart and pick a sector |
| F5 | Save |
| Esc | Pause or return to the previous menu |

The starter pulse tool mines and collects within **2.1 tiles**. Keep the pointer on a block while holding left click to mine it. Harder blocks take longer, and solid tiles stop the pulse. The tool has unlimited durability. Its three upgrades increase hard-block mining power and extend range to **2.65**, **3.1**, and **3.6 tiles**. Placement has a two-tile reach. Mined sand has its own stack and can be placed from the hotbar.

Press **C** anywhere to make a field workbench from **2 soil and 4 stone**. Select it in the hotbar, then right-click an open tile in reach. Press **C** nearby to browse **Materials**, **Construction**, **Survival**, **Tools**, and **Life support**. Mine the workbench to pack it up. Beacons provide travel and shelter. Relay Nine's workshop is inside the cabin.

The explorer carries **9 hotbar slots and 5 suit storage slots**. Open the inventory with **Tab** and drag a stack or choose a source and destination. Suit storage is accessible while wearing the suit. New stacks hold up to 64 items. Larger stacks carried over from older saves can be used down over time.

Planets generate nearby terrain as you walk or dig. The HUD shows local gravity, weather, outdoor temperature, pressure, and the direction back to the beacon. Planetary gravity follows mass and radius. Larger planets of the same density have stronger gravity, and metal-rich planets are heavier than ice-rich planets of the same size. Relay Nine has a local artificial gravity field. Farther out, the planet's weaker pull takes over. Fall far enough below the station and you'll enter the atmosphere above that planet's landing pad.

The **Body temp** gauge tracks your explorer's temperature in Celsius. Prolonged exposure can push it below 34 °C or above 40 °C and start draining health. Mild air, landing beacons, and Relay Nine's sealed cabin let body temperature gradually return to 37 °C. Cold exposure begins when you step into vacuum. The suit slows cooling, and insulation reduces temperature exposure under a roof.

The suit loses integrity in harsh weather and above 175 kPa. Pressure liners reduce wear from dense air, and overhead cover reduces storm exposure. Below **55% integrity**, the suit uses extra oxygen in unsafe air. A breached or removed suit gives no protection from vacuum or unbreathable air. Extreme pressure, temperature, and storms can also injure an unsuited explorer.

Suit oxygen replenishes in breathable air and near a landing beacon. A hull breach drains the cabin over time and pulls the explorer and loose debris toward the opening. The airflow weakens as pressure drops. Patch the breach with alloy or pressure glass and give life support time to refill the cabin. Rescue sends you back to the beacon, restores at least 35% suit integrity, and costs some construction supplies.

In orbit, a full vacuum reserve gives you **8 seconds** without breathable air before health starts to fall by **2 points per second**. Breathable air or a working suit with oxygen pauses the countdown. Every **5 seconds** of breathing restores **1 second** of grace, up to eight. If you run out of air again before recovering fully, the countdown resumes where it left off. Saves keep the remaining grace and partial recovery.

## Build an oxygen shelter

1. At a workbench, open **Life support** and craft an **oxygen recycler**, **fuel generator**, and **fuel cells**. Craft **airlock panels** for an entrance and **habitat batteries** for extended backup power.
2. Build an airtight rectangle with alloy or pressure glass. The interior can be **2–16 tiles wide** and **2–10 tiles high**. Fit the recycler, generator, and any batteries into the same floor, with the recycler facing the room.
3. Stack two airlock panels in a side wall. Leave two tiles of clearance on both sides and press **E** beside the airlock to enter.
4. Press **E** near the recycler to commission the room. Right-click the generator within reach to load one fuel cell. The HUD tracks breathable air, fuel, and battery reserve.

A fuel cell runs the generator for **90 seconds**. While running, it powers the recycler and charges the reserve. Each battery adds **120 seconds** of storage to the recycler's **30-second** buffer. A breach vents the room and stops the recycler, while the generator can keep charging the batteries. Repair the seal to resume filling. If the reserve runs out, the room gradually loses breathable air. Fuel and charge advance with expedition time, including time spent away from the habitat. Existing shelters keep their saved air and get a charged starting buffer.

## Jetpack and exploration

The starter jetpack burns for **1.5 seconds** per full charge. After a burst it cools down for **1.25 seconds**, then recharges on solid ground. It requires a working suit.

The star chart uses signed 32-bit coordinates per axis. A saved galaxy seed and generation revision reproduce each planet's name, terrain, and environmental properties. Saves store compact block and harvest changes for modified planets. They load full terrain for the nearby chunks during play.

Use **Settings** from the title or pause menu. **Apply settings** saves the frame cap, VSync request, master volume, and renderer. FPS, VSync, and volume apply immediately. The compositor and graphics driver determine supported presentation modes. Renderer changes apply on the next launch. Launch with `--rendering-method gl_compatibility` to choose Compatibility for one session.

## Develop locally

Install [Godot 4.7.2 Standard](https://godotengine.org/download/archive/4.7.2-stable/) as `godot` or set `GODOT` to the editor executable. Keep your development files inside the game directory by cloning into `~/.MomoyoBlock/dev/source`.

```sh
mkdir -p "$HOME/.MomoyoBlock/dev"
git clone https://github.com/GraderGamer2/MomoyoBlock.git "$HOME/.MomoyoBlock/dev/source"
cd "$HOME/.MomoyoBlock/dev/source"
tools/run-dev.sh --editor
tools/test-dev.sh
```

Use `tools/run-dev.sh` to play from source. Development uses `~/.MomoyoBlock/dev/profile` and keeps terminal warnings and errors. Headless launches are available for tests.

## Build a playtest

Run `tools/build-linux.sh` with GCC, SCons, Wayland’s scanner, curl, unzip, and patch. The script verifies upstream downloads and builds the Wayland-only Godot 4.7.2 release template with GCC `-O3` and full LTO. The workflow can reuse the optimized template when the engine inputs and toolchain match. It runs the gameplay tests and embeds the current game in each build. The workflow also runs `tools/test-package.sh` with Weston and software graphics to verify that the Linux export creates a native Wayland window and presents frames.

The archive is written to `dist/MomoyoBlock-linux-x86_64.tar.gz`. Updates to `project.godot` or the workflow definition on `main` automatically build a playtest. The workflow can also run on demand.

[Godot Linux build guide](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_linuxbsd.html) · [Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md)
