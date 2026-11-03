#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-resize-test.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
swiftc "$root/Maccy/Extensions/NSImage+Resized.swift" \
  "$root/tests-cli/image-resize/main.swift" \
  -o "$build_dir/image-resize-test"
"$build_dir/image-resize-test" "$root/MaccyTests/Fixtures/guy.jpeg"
