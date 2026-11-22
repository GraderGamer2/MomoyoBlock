#!/usr/bin/env bash
set -euo pipefail

tools_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
fixture_home=$(mktemp -d)
trap 'rm -rf -- "$fixture_home"' EXIT
env HOME="$fixture_home" timeout 45s "$tools_dir/run-dev.sh" --headless --editor --import
env HOME="$fixture_home" timeout 45s "$tools_dir/run-dev.sh" --headless --fixed-fps 60 res://tests/smoke.tscn
printf '%s\n' 'Gameplay and save smoke tests passed.'
