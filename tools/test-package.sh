#!/usr/bin/env bash
set -euo pipefail

tools_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

if [[ ${1:-} == --window ]]; then
	runtime=$2
	console_file=$3
	save=$4
	"$runtime" --display-driver x11 --audio-driver Dummy > "$console_file" 2>&1 &
	game_pid=$!
	trap 'kill "$game_pid" 2>/dev/null || true; wait "$game_pid" 2>/dev/null || true' EXIT
	window_id=$(timeout 20s xdotool search --sync --onlyvisible --pid "$game_pid" --name '^MomoyoBlock$')
	xdotool windowfocus --sync "$window_id"
	for ((try=0; try<30; try++)); do
		if [[ -s $save ]]; then
			break
		fi
		xdotool key F5
		sleep 0.2
	done
	if [[ ! -s $save ]]; then
		printf '%s\n' 'The packaged game did not respond to F5.' >&2
		exit 1
	fi
	xdotool key e
	timeout 18s "$tools_dir/run-dev.sh" --headless res://tests/smoke.tscn -- check-export-save "$save"
	exit
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

# Exercise real keyboard input on the packaged Linux runtime with a software display.
env "${fixture_env[@]}" TMPDIR="$fixture_dir" xvfb-run -a -e "$fixture_dir/display.log" \
	-s '-screen 0 1280x800x24' "$0" --window "$runtime" "$console" "$save"
test ! -s "$console"
test -s "$save"
test -z "$(find "$outside" -mindepth 1 -print -quit)"
test -z "$(find "$fixture_home" -mindepth 1 -maxdepth 1 ! -name .MomoyoBlock -print -quit)"
test -z "$(find "$root" -iname '*.log' -print -quit)"
printf '%s\n' 'Packaged x86_64 runtime, silent output, flight and home directory passed.'
