#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-smoke-compile.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
swiftc -D DEBUG "$root/tests-cli/smoke-compile/stubs.swift" \
  "$root/Maccy/Observables/IsolatedMemorySmoke.swift" \
  "$root/tests-cli/smoke-compile/main.swift" -o "$build_dir/test"
"$build_dir/test"
