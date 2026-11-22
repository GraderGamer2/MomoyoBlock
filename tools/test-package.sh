#!/usr/bin/env bash
set -euo pipefail

fixture_dir=$(mktemp -d)
compositor_pid=
cleanup() {
	if [[ -n $compositor_pid ]]; then
		kill "$compositor_pid" 2>/dev/null || true
		wait "$compositor_pid" 2>/dev/null || true
	fi
	rm -rf -- "$fixture_dir"
}
trap cleanup EXIT

fixture_home="$fixture_dir/Player Home"
outside="$fixture_dir/xdg-decoys"
mkdir -p "$fixture_home" "$outside"
tar -xzf "$1" -C "$fixture_home"
root="$fixture_home/.MomoyoBlock"
runtime="$root/MomoyoBlock"
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
env "${fixture_env[@]}" timeout 15s "$runtime" --headless --fixed-fps 60 --quit-after 15 > "$console" 2>&1
test ! -s "$console"
test -d "$root/profile"
if env "${fixture_env[@]}" "$runtime" --display-driver x11 --quit-after 1; then
	printf '%s\n' 'The packaged runtime accepted the X11 display driver.' >&2
	exit 1
fi
printf '%s\n' 'x86_64 headless boot and X11 rejection passed.'

compositor_home="$fixture_dir/compositor-home"
mkdir -p "$compositor_home"
runtime_dir="$fixture_dir/wayland"
install -d -m 700 "$runtime_dir"
socket=momoyo-ci
protocol="$fixture_dir/wayland-protocol"
env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET \
	HOME="$compositor_home" XDG_DATA_HOME="$compositor_home/data" \
	XDG_CACHE_HOME="$compositor_home/cache" XDG_CONFIG_HOME="$compositor_home/config" \
	XDG_RUNTIME_DIR="$runtime_dir" LIBGL_ALWAYS_SOFTWARE=1 WAYLAND_DEBUG=server \
	weston --backend=headless-backend.so --shell=kiosk-shell.so --renderer=pixman \
		--socket="$socket" --width=1280 --height=720 --idle-time=0 --no-config \
		--log="$fixture_dir/weston.log" > "$protocol" 2>&1 &
compositor_pid=$!
for ((try=0; try<40; try++)); do
	if [[ -S $runtime_dir/$socket ]]; then
		break
	fi
	sleep 0.15
done
if [[ ! -S $runtime_dir/$socket ]]; then
	printf '%s\n' 'Weston did not start a Wayland socket.' >&2
	cat "$fixture_dir/weston.log" >&2 || true
	tail -35 "$protocol" >&2
	exit 1
fi

if ! env -u DISPLAY -u WAYLAND_SOCKET "${fixture_env[@]}" XDG_RUNTIME_DIR="$runtime_dir" \
	WAYLAND_DISPLAY="$socket" LIBGL_ALWAYS_SOFTWARE=1 \
	timeout 35s "$runtime" --display-driver wayland --audio-driver Dummy --quit-after 60 > "$console" 2>&1; then
	printf '%s\n' 'The packaged game could not run 60 frames on Wayland.' >&2
	cat "$fixture_dir/weston.log" >&2
	tail -45 "$protocol" >&2
	exit 1
fi
if ! grep -Eq 'xdg_surface[^.]*\.get_toplevel' "$protocol" ||
	! grep -Eq 'wl_surface[^.]*\.attach\(wl_buffer' "$protocol"; then
	printf '%s\n' 'Wayland did not receive a toplevel window with a rendered buffer.' >&2
	tail -45 "$protocol" >&2
	exit 1
fi
test ! -s "$console"
test -z "$(find "$outside" -mindepth 1 -print -quit)"
test -z "$(find "$fixture_home" -mindepth 1 -maxdepth 1 ! -name .MomoyoBlock -print -quit)"
test -z "$(find "$root" -iname '*.log' -print -quit)"
printf '%s\n' 'Wayland toplevel, frame presentation, silent output, and home directory passed.'
