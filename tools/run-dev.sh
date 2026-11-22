#!/bin/sh
set -eu

project_dir=$(CDPATH="" cd -- "$(dirname -- "$0")/.." && pwd -P)
case ${HOME:-} in
	/*) ;;
	*) printf '%s\n' 'MomoyoBlock needs an absolute home directory.' >&2; exit 1 ;;
esac

root="$HOME/.MomoyoBlock/dev"
export XDG_DATA_HOME="$root"
export XDG_CONFIG_HOME="$root/config"
export XDG_CACHE_HOME="$root/cache"
export XDG_STATE_HOME="$root/state"
export MESA_SHADER_CACHE_DIR="$XDG_CACHE_HOME"
export __GL_SHADER_DISK_CACHE_PATH="$XDG_CACHE_HOME"
export TMPDIR="$root/tmp"
mkdir -p -- "$XDG_CACHE_HOME" "$TMPDIR"
if [ -f "$root/profile/settings.cfg" ] && grep -Fxq 'renderer="mobile"' "$root/profile/settings.cfg"; then
	set -- --rendering-method mobile "$@"
fi
exec "${GODOT:-godot}" --display-driver wayland --path "$project_dir" --quiet "$@"
