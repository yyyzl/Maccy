#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-loader-benchmark.XXXXXX")
pid=
cleanup() {
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
  rm -rf "$build_dir"
}
trap cleanup EXIT HUP INT TERM
git -C "$root" show 2.6.1:Maccy/Extensions/NSImage+Resized.swift > "$build_dir/before.swift"
for mode in before after; do
  source="$build_dir/before.swift"
  if [ "$mode" = after ]; then source="$root/Maccy/Extensions/NSImage+Resized.swift"; fi
  swiftc -O "$source" "$root/Maccy/Observables/HistoryImageLoader.swift" \
    "$root/tests-cli/swiftdata-load/models.swift" \
    "$root/tests-cli/image-loader-benchmark/main.swift" -o "$build_dir/$mode"
done
"$build_dir/after" prepare "$build_dir/store.sqlite"
for mode in before after; do
  "$build_dir/$mode" "$mode" "$build_dir/store.sqlite" > "$build_dir/$mode.log" 2>&1 &
  pid=$!
  count=0
  while ! grep -q READY "$build_dir/$mode.log"; do
    if ! kill -0 "$pid" 2>/dev/null || [ "$count" -ge 100 ]; then
      echo "$mode benchmark did not start or failed" >&2
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
