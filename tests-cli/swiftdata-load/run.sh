#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-swiftdata-test.XXXXXX")
pid=
cleanup() {
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
  rm -rf "$build_dir"
}
trap cleanup EXIT HUP INT TERM
swiftc -O "$root/Maccy/ApplicationImageCache.swift" \
  "$root/tests-cli/swiftdata-load/models.swift" \
  "$root/tests-cli/swiftdata-load/main.swift" -o "$build_dir/test"
"$build_dir/test" prepare "$build_dir/store.sqlite"
for mode in legacy metadata main-thumbs scratch-thumbs payload; do
  "$build_dir/test" "$mode" "$build_dir/store.sqlite" > "$build_dir/$mode.log" 2>&1 &
  pid=$!
  count=0
  while ! grep -q READY "$build_dir/$mode.log"; do
    if ! kill -0 "$pid" 2>/dev/null || [ "$count" -ge 100 ]; then
      echo "$mode test did not start or failed" >&2
      exit 1
    fi
    count=$((count + 1))
    sleep 0.2
  done
  grep READY "$build_dir/$mode.log"
  footprint "$pid" | grep -E 'Footprint:|phys_footprint'
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pid=
done
