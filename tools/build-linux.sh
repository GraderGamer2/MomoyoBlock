#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_dir"

version=4.7.2
release="$version-stable"
editor_asset="Godot_v${release}_linux.x86_64"
source_asset="godot-$release.tar.xz"
accesskit=0.22.3
download_url="https://github.com/godotengine/godot-builds/releases/download/$release"
download_dir="$project_dir/build/downloads"
source_dir="$project_dir/build/godot-$version"
template="$source_dir/bin/godot.linuxbsd.template_release.x86_64"
stage="$project_dir/build/package"
archive="$project_dir/dist/MomoyoBlock-linux-x86_64.tar.gz"

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
	printf '%s\n' 'This build targets Linux x86_64.' >&2
	exit 1
fi

mkdir -p "$download_dir" "$stage" "$(dirname -- "$archive")"
touch "$project_dir/build/.gdignore" "$project_dir/dist/.gdignore"

fetch() {
	local url=$1 path=$2 digest=$3
	if [[ ! -f $path ]] || ! sha256sum --status -c <<< "$digest  $path"; then
		curl --fail --silent --show-error --location --retry 3 --output "$path.part" "$url"
		sha256sum --status -c <<< "$digest  $path.part"
		mv -- "$path.part" "$path"
	fi
}

if [[ -z ${GODOT:-} ]]; then
	fetch "$download_url/$editor_asset.zip" "$download_dir/$editor_asset.zip" \
		cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
	unzip -oq "$download_dir/$editor_asset.zip" -d "$project_dir/build"
	GODOT="$project_dir/build/$editor_asset"
fi
editor_version=$("$GODOT" --version)
if [[ $editor_version != "$version.stable."* ]]; then
	printf 'Expected Godot %s stable, got %s\n' "$version" "$editor_version" >&2
	exit 1
fi
export GODOT

tools/test-dev.sh

if [[ ! -f $source_dir/.momoyo-source-ready ]]; then
	fetch "$download_url/$source_asset" "$download_dir/$source_asset" \
		a18ce0ccec3ecc40b0dd6c4f5132ca934e9fb7c2979717940ff32aee1eb35481
	mkdir -p "$source_dir"
	tar -xJf "$download_dir/$source_asset" -C "$source_dir" --strip-components=1
	touch "$source_dir/.momoyo-source-ready"
fi
if ! grep -Fq '#include "momoyoblock_runtime.h"' "$source_dir/platform/linuxbsd/godot_linuxbsd.cpp"; then
	patch --batch --forward -d "$source_dir" -p1 < tools/godot-linux-runtime.patch
fi
if ! cmp -s tools/momoyoblock_runtime.h "$source_dir/platform/linuxbsd/momoyoblock_runtime.h"; then
	cp tools/momoyoblock_runtime.h "$source_dir/platform/linuxbsd/"
fi

accesskit_dir="$source_dir/bin/build_deps/accesskit-c-$accesskit"
if [[ ! -f $accesskit_dir/.momoyo-sdk-ready ]]; then
	fetch "https://github.com/godotengine/godot-accesskit-c-static/releases/download/$accesskit/accesskit-c-$accesskit.zip" \
		"$download_dir/accesskit.zip" 41b30b1382d03b225b6f7e8721269a32557a68065804f3797bdffc34a3273498
	mkdir -p "$source_dir/bin/build_deps"
	unzip -oq "$download_dir/accesskit.zip" -d "$source_dir/bin/build_deps"
	touch "$accesskit_dir/.momoyo-sdk-ready"
fi

# Godot maps optimize=speed to -O3 and lto=full to GCC's -flto.
command -v wayland-scanner >/dev/null
scons --directory="$source_dir" --jobs="${MOMOYO_BUILD_JOBS:-4}" \
	platform=linuxbsd target=template_release arch=x86_64 optimize=speed lto=full \
	debug_symbols=no use_llvm=no x11=no wayland=yes "accesskit_sdk_path=$accesskit_dir"
test -x "$template"

mkdir -p "$stage/.MomoyoBlock/licenses"
tools/run-dev.sh --headless --export-release "Linux x86_64" "$stage/.MomoyoBlock/MomoyoBlock"
cp "$source_dir/LICENSE.txt" "$stage/.MomoyoBlock/licenses/Godot-LICENSE.txt"
cp "$source_dir/COPYRIGHT.txt" "$stage/.MomoyoBlock/licenses/Godot-COPYRIGHT.txt"
test -x "$stage/.MomoyoBlock/MomoyoBlock"
tar -czf "$archive" -C "$stage" .MomoyoBlock
printf 'Built %s\n' "$archive"
