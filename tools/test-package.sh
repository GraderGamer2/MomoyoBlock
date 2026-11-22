#!/usr/bin/env bash
set -euo pipefail

tools_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

if [[ ${1:-} == --window ]]; then
	runtime=$2
	console_file=$3
	save=$4
	work_dir=$5
	mkdir -p "$work_dir/compositor-home"
	export XDG_RUNTIME_DIR="$work_dir/wayland"
	install -d -m 700 "$XDG_RUNTIME_DIR"
	export WAYLAND_DISPLAY=momoyo-ci

	# Xvfb hosts Weston's test window. The game connects only to the Wayland socket.
	env HOME="$work_dir/compositor-home" XDG_DATA_HOME="$work_dir/compositor-home/data" \
		XDG_CACHE_HOME="$work_dir/compositor-home/cache" XDG_CONFIG_HOME="$work_dir/compositor-home/config" \
		weston --backend=x11-backend.so --shell=kiosk-shell.so --renderer=pixman \
			--socket="$WAYLAND_DISPLAY" --width=1280 --height=720 --idle-time=0 --no-config \
			--log="$work_dir/weston.log" &
	compositor_pid=$!
	game_pid=
	trap 'if [[ -n $game_pid ]]; then kill "$game_pid" 2>/dev/null || true; wait "$game_pid" 2>/dev/null || true; fi; kill "$compositor_pid" 2>/dev/null || true; wait "$compositor_pid" 2>/dev/null || true' EXIT
	for ((try=0; try<40; try++)); do
		if [[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]]; then
			break
		fi
		sleep 0.15
	done
	if [[ ! -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]]; then
		cat "$work_dir/weston.log" >&2
		exit 1
	fi
	window_id=$(timeout 15s xdotool search --sync --onlyvisible --name 'Weston')
	timeout 5s xdotool windowfocus --sync "$window_id"
	env -u DISPLAY LIBGL_ALWAYS_SOFTWARE=1 "$runtime" --display-driver wayland --audio-driver Dummy > "$console_file" 2>&1 &
	game_pid=$!
	xdotool mousemove --window "$window_id" 110 60

	for ((try=0; try<40; try++)); do
		if [[ -s $save ]]; then
			break
		fi
		if ! kill -0 "$game_pid" 2>/dev/null; then
			printf '%s\n' 'The Wayland game exited before opening an expedition.' >&2
			cat "$work_dir/weston.log" >&2
			exit 1
		fi
		xdotool key Return F5
		sleep 0.25
	done
	if [[ ! -s $save ]]; then
		printf '%s\n' 'The Wayland game did not start and save from the main menu.' >&2
		cat "$work_dir/weston.log" >&2
		exit 1
	fi

	xdotool key e
	timeout 18s "$tools_dir/run-dev.sh" --headless res://tests/smoke.tscn -- check-export-save "$save" station
	xdotool key m
	sleep 0.25
	xdotool key Return
	timeout 18s "$tools_dir/run-dev.sh" --headless res://tests/smoke.tscn -- check-export-save "$save" east

	# This point is inside the custom close button on the 1280 x 720 fullscreen test output.
	xdotool mousemove --window "$window_id" 1254 19 click 1
	for ((try=0; try<40; try++)); do
		if ! kill -0 "$game_pid" 2>/dev/null; then
			wait "$game_pid"
			game_pid=
			exit 0
		fi
		sleep 0.15
	done
	printf '%s\n' 'The in-game close button did not close the Wayland window.' >&2
	exit 1
fi

fixture_dir=$(mktemp -d)
trap 'rm -rf -- "$fixture_dir"' EXIT
fixture_home="$fixture_dir/Player Home"
outside="$fixture_dir/xdg-decoys"
mkdir -p "$fixture_home" "$outside"
tar -xzf "$1" -C "$fixture_home"
root="$fixture_home/.MomoyoBlock"
runtime="$root/MomoyoBlock"
save="$root/profile/saves/expedition.save"
test -x "$runtime"
test -s "$root/licenses/Godot-LICENSE.txt"
LC_ALL=C readelf -h "$runtime" > "$fixture_dir/elf.txt"
grep -Eq 'Machine:.*X86-64' "$fixture_dir/elf.txt"

fixture_env=(
	"HOME=$fixture_home"
	"XDG_DATA_HOME=$outside/data"
	"XDG_CACHE_HOME=$outside/cache"
	"XDG_CONFIG_HOME=$outside/config"
	"XDG_STATE_HOME=$outside/state"
	"MESA_SHADER_CACHE_DIR=$outside/mesa"
	"TMPDIR=$outside/temp"
)
console="$fixture_dir/console"
env "${fixture_env[@]}" "$runtime" --headless --fixed-fps 60 --quit-after 15 > "$console" 2>&1
test ! -s "$console"
test -d "$root/profile"
if env "${fixture_env[@]}" "$runtime" --display-driver x11 --quit-after 1; then
	printf '%s\n' 'The packaged runtime accepted the X11 display driver.' >&2
	exit 1
fi

# Exercise real keyboard input on the packaged Linux runtime with a software display.
env "${fixture_env[@]}" TMPDIR="$fixture_dir" xvfb-run -a -e "$fixture_dir/display.log" \
	-s '-screen 0 1280x720x24' "$0" --window "$runtime" "$console" "$save" "$fixture_dir"
test ! -s "$console"
test -s "$save"
test -z "$(find "$outside" -mindepth 1 -print -quit)"
test -z "$(find "$fixture_home" -mindepth 1 -maxdepth 1 ! -name .MomoyoBlock -print -quit)"
test -z "$(find "$root" -iname '*.log' -print -quit)"
printf '%s\n' 'Wayland package, menu, flight, close button, silent output and home directory passed.'
