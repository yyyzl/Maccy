#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-decorator-test.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
swiftc -emit-library -emit-module -module-name Defaults \
  "$root/tests-cli/decorator/Defaults.swift" -o "$build_dir/libDefaults.dylib" \
  -emit-module-path "$build_dir/Defaults.swiftmodule"
swiftc -emit-library -emit-module -module-name Sauce \
  "$root/tests-cli/decorator/Sauce.swift" -o "$build_dir/libSauce.dylib" \
  -emit-module-path "$build_dir/Sauce.swiftmodule"
swiftc -parse-as-library -I "$build_dir" -L "$build_dir" -lDefaults -lSauce \
  -Xlinker -rpath -Xlinker "$build_dir" \
  "$root/tests-cli/swiftdata-load/models.swift" \
  "$root/tests-cli/decorator/support.swift" \
  "$root/Maccy/ApplicationImageCache.swift" \
  "$root/Maccy/Extensions/NSImage+Resized.swift" \
  "$root/Maccy/Extensions/String+Shortened.swift" \
  "$root/Maccy/Observables/HistoryImageLoader.swift" \
  "$root/Maccy/Observables/HistoryItemDecorator.swift" \
  "$root/tests-cli/decorator/test.swift" -o "$build_dir/test"
"$build_dir/test"
