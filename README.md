# MomoyoBlock

MomoyoBlock is a 2D side-view survival and building sandbox. Explore Cinder Reach, use Relay Nine to chart jumps to seeded planets, and build shelters while managing food, water, and suit oxygen. This alpha uses placeholder visuals.

## Play on Linux x86_64 with Wayland

Download `MomoyoBlock-linux-x86_64.tar.gz` from the [Actions build](https://github.com/GraderGamer2/MomoyoBlock/actions/workflows/build.yml). Extract it into your home directory and launch it from a Wayland session.

```sh
tar -xzf MomoyoBlock-linux-x86_64.tar.gz -C "$HOME"
"$HOME/.MomoyoBlock/MomoyoBlock"
```

Re-extracting the archive updates the game. Saves live at `~/.MomoyoBlock/profile/saves/expedition.save` and existing 0.1 expeditions load in 0.2. Settings live at `~/.MomoyoBlock/profile/settings.cfg`. The installed game, data, and caches stay under `~/.MomoyoBlock`. Release file and console logging are disabled.

The Linux template includes the native Wayland display driver. It requires x86_64 with SSE4.2 and a GPU that supports the selected renderer. The built-in title bar supports moving, minimizing, maximizing, restoring, and closing the window. Drag the lower-right corner to resize.

## Controls

| Input | Action |
|---|---|
| A / D or ← / → | Walk |
| Space | Jump |
| Left click | Mine a block in reach |
| Right click | Place the selected block |
| 1–4 | Select a building material |
| F | Gather the nearest food or water source in reach |
| R / T | Eat a ration or drink water |
| E at a beacon | Travel between the current planet and Relay Nine |
| M at the Relay Nine beacon | Open the star chart and pick a sector |
| F5 | Save |
| Esc | Pause or return to the previous menu |

Oxygen replenishes in breathable air and near a landing beacon. Vacuum and unbreathable atmospheres drain the tank. Hunger, thirst, and oxygen depletion damage health. Rescue sends you back to the beacon and costs half your carried blocks.

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

Run `tools/build-linux.sh` with GCC, SCons, Wayland’s scanner, curl, unzip, and patch. The script verifies upstream downloads and builds the Wayland-only Godot 4.7.2 release template with GCC `-O3` and full LTO. It embeds the game. The workflow also runs `tools/test-package.sh` with Weston and software graphics to verify that the Linux export creates a native Wayland window and presents frames.

The archive is written to `dist/MomoyoBlock-linux-x86_64.tar.gz`. Run the workflow on demand after gameplay changes. Updating its definition on `main` also starts a build.

[Godot Linux build guide](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_linuxbsd.html) · [Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md)
