# MomoyoBlock

MomoyoBlock is a 2D side-view building and exploration sandbox. Start on Cinder Reach, use the landing beacon to reach Relay Nine in orbit, and make changes to both locations. The first playtest uses placeholder geometry and colors.

## Play on Linux x86_64

Download `MomoyoBlock-linux-x86_64.tar.gz` from the [Actions build](https://github.com/GraderGamer2/MomoyoBlock/actions/workflows/build.yml). Extract it into your home directory and launch it.

```sh
tar -xzf MomoyoBlock-linux-x86_64.tar.gz -C "$HOME"
"$HOME/.MomoyoBlock/MomoyoBlock"
```

The archive contains the game and its runtime files. It updates the installed game on extraction, while your expedition lives at `~/.MomoyoBlock/profile/saves/expedition.save`. The game saves after travel, with **F5**, and when the window closes. Game-generated files, including graphics caches, live under `~/.MomoyoBlock`. The release disables file and console logging.

The build targets Linux x86_64 with SSE4.2 and OpenGL 3.3 or OpenGL ES 3.0 support. The engine includes native Wayland and X11.

| Input | Action |
|---|---|
| A / D or ← / → | Walk |
| Space | Jump |
| Left click | Mine a block in reach |
| Right click | Place the selected building block |
| 1–4 | Select a building material |
| E at a beacon | Travel between the surface and orbit |
| F5 | Save the expedition |

## Develop locally

Install [Godot 4.7.2 Standard](https://godotengine.org/download/archive/4.7.2-stable/) as `godot` or set `GODOT` to the editor executable. To keep your checkout and editor files in the same game directory, clone into `~/.MomoyoBlock/dev/source`.

```sh
mkdir -p "$HOME/.MomoyoBlock/dev"
git clone https://github.com/GraderGamer2/MomoyoBlock.git "$HOME/.MomoyoBlock/dev/source"
cd "$HOME/.MomoyoBlock/dev/source"
tools/run-dev.sh --editor
tools/test-dev.sh
```

Use `tools/run-dev.sh` on its own to play from source. The development profile is under `~/.MomoyoBlock/dev/profile`. Development launches retain terminal errors and warnings and disable file logging.

## Build a playtest

Run `tools/build-linux.sh` on Linux x86_64 with GCC, SCons, Wayland's scanner, Xvfb, xauth, xdotool, curl, unzip, patch, and binutils available. The script verifies the upstream downloads, builds the Godot 4.7.2 release template using GCC `-O3` and full LTO, then embeds the game and verifies the packaged runtime. It uses a portable x86_64 target and Godot's standard modules. GDScript goes through Godot's export pipeline. The game streams nearby chunks, stores block data in packed arrays, and saves terrain edits as deltas.

The archive is written to `dist/MomoyoBlock-linux-x86_64.tar.gz`. Ordinary gameplay pushes leave builds available on demand. The workflow also runs when its own definition changes on `main`.

[Godot's Linux build guide](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_linuxbsd.html) · [Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md)
