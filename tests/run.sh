#!/usr/bin/env bash
# Runs the offline tests against a scratch game folder with the mod installed (needs Lua 5.4 or newer).
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/uwhud-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mod="$scratch/Game/Binaries/Win64/ue4ss/Mods/UEUltrawideHUDMod"
mkdir -p "$mod"
cp -r "$repo/src/UEUltrawideHUDMod/." "$mod/"
for f in "$repo"/src/UEUltrawideHUDMod/Scripts/*.lua "$repo"/tests/*.lua; do
    luac -p "$f"
done
lua "$repo/tests/run_tests.lua" "$repo" "$scratch"
