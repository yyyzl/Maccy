#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-clipboard-test.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
swiftc "$root/Maccy/ApplicationImageCache.swift" \
  "$root/tests-cli/swiftdata-load/models.swift" \
  "$root/tests-cli/clipboard-metadata/main.swift" \
  -o "$build_dir/clipboard-metadata-test"
"$build_dir/clipboard-metadata-test"
