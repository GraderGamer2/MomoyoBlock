# MomoyoBlock

MomoyoBlock is a 2D side-view survival and building sandbox. Start on a generated planet, use Relay Nine to chart jumps across a seeded galaxy, and build shelters while managing food, water, and suit oxygen. This alpha uses placeholder visuals.

## Play on Linux x86_64 with Wayland

Download `MomoyoBlock-linux-x86_64.tar.gz` from the [Actions build](https://github.com/GraderGamer2/MomoyoBlock/actions/workflows/build.yml). Extract it into your home directory and launch it from a Wayland session.

```sh
tar -xzf MomoyoBlock-linux-x86_64.tar.gz -C "$HOME"
"$HOME/.MomoyoBlock/MomoyoBlock"
```

Re-extracting the archive updates the game. Expeditions live under `~/.MomoyoBlock/profile/saves/`. Existing expeditions keep their planets and block edits. Expeditions saved on Relay Nine before 0.4 resume at the landing pad. Choose **New expedition** from the main menu for a randomly generated starting planet in a separate save. **Continue expedition** opens the most recently saved slot, and **Load expedition** lets you pick another. Settings live at `~/.MomoyoBlock/profile/settings.cfg`. The installed game, data, and caches stay under `~/.MomoyoBlock`. Release file and console logging are disabled.

The Linux template includes the native Wayland display driver. It requires x86_64 with SSE4.2 and a GPU that supports the selected renderer. The built-in title bar supports moving, minimizing, maximizing, restoring, and closing the window. Drag the lower-right corner to resize.

## Controls

| Input | Action |
|---|---|
| A / D or ← / → | Walk |
| Space | Jump |
| Hold left click | Mine a block in reach |
| Right click | Place the selected block |
| 1–4 | Select a building material |
| F | Gather the nearest food or water source in reach |
| R / T | Eat a ration or drink water |
| C near a planetary beacon or the Relay Nine workbench | Open the workshop |
| O | Use a spare air canister |
| E at a beacon | Travel between the current planet and Relay Nine |
| M at the Relay Nine beacon | Open the star chart and pick a sector |
| F5 | Save |
| Esc | Pause or return to the previous menu |

Mine, build, and gather within two tiles of your explorer. Softer blocks are quicker to mine. Keep the pointer on the block while holding the button. Use the workshop to turn stone, ore, and alloy into a Prospector Pick for faster mining of hard blocks, air canisters for a quick top-up, or a pressure liner for dense atmospheres.

Planets generate nearby terrain as you walk or dig. The HUD shows current weather, outdoor temperature, pressure, and the direction back to the beacon. Heat raises water use, cold raises food use, and pressure above 175 kPa strains the suit. Overhead cover reduces exposure to harsh weather.

The **Body temp** gauge tracks your explorer's temperature in Celsius. Prolonged exposure can push it below 34 °C or above 40 °C and start draining health. Mild air, landing beacons, and Relay Nine's sealed cabin let body temperature gradually return to 37 °C. In orbit, the suit regulates heat during EVA. Your body temperature is saved with your other vitals.

Oxygen replenishes in breathable air, near a landing beacon, and inside Relay Nine's sealed cabin. The exterior deck is exposed to vacuum. If a breach vents the cabin, patch it with alloy. Hunger, thirst, and oxygen depletion damage health. Rescue sends you back to the beacon and costs half your carried blocks.

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
