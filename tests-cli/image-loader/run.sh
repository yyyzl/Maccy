#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-loader-test.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
swiftc "$root/Maccy/Extensions/NSImage+Resized.swift" \
  "$root/Maccy/Observables/HistoryImageLoader.swift" \
  "$root/tests-cli/swiftdata-load/models.swift" \
  "$root/tests-cli/image-loader/main.swift" -o "$build_dir/test"
"$build_dir/test"
