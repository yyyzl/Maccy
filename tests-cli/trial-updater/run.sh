#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-trial-updater.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
swiftc -D MEMORY_TRIAL "$root/Maccy/SoftwareUpdater.swift" \
  "$root/tests-cli/trial-updater/main.swift" -o "$build_dir/test"
"$build_dir/test"
