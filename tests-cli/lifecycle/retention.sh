#!/bin/bash
# 仅供快放诊断：对象/引用统计与分配器对照，不能作为常规内存验收。
set -euo pipefail
umask 077
app=$1
output=$2
test_id=org.yyyzl.MaccyMemoryLifecycle
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == "$test_id" ]]
codesign --verify --deep --strict "$app"
mkdir -p "$output"
results=$(mktemp -d /tmp/maccy-retention-results.XXXXXX)
store="retention-$(date +%Y%m%d%H%M%S)-${RANDOM}"
flags=(-ignoreEvents YES -ignoreOnlyNextEvent NO -showInStatusBar NO -clearOnQuit NO -clearSystemClipboard NO -historySize 200 -KeyboardShortcuts_popup NO -KeyboardShortcuts_pin NO -KeyboardShortcuts_delete NO -SUEnableAutomaticChecks NO)
active_pid=''
cleanup() {
  if [[ -n "$active_pid" ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  if [[ -f "$results/run.log" ]]; then
    grep -E '\[MaccyLifecycle\]' "$results/run.log" > "$output/lifecycle.log" || true
  fi
}
trap cleanup EXIT HUP INT TERM
launch() {
  env -u GH_TOKEN -u GITHUB_TOKEN -u ACTIONS_RUNTIME_TOKEN -u ACTIONS_ID_TOKEN_REQUEST_TOKEN \
    "$app/Contents/MacOS/Maccy" --isolated-lifecycle "--scenario=$1" "--store=$store" --cycles=240 "${flags[@]}" > "$2" 2>&1 &
  active_pid=$!
}
printf 'Private synthetic results: %s\n' "$results"
launch seed "$results/seed.log"
wait "$active_pid"
active_pid=''
grep -Eq '\[MaccyLifecycle\] SEED_OK' "$results/seed.log"
launch retention "$results/run.log"
started=$(date +%s)
printf 'phase,elapsed_seconds,physical_footprint,peak_footprint\n' > "$output/footprint.csv"
sample() {
  metrics=$(footprint "$active_pid" | awk '/phys_footprint:/{physical=$2" "$3} /phys_footprint_peak:/{peak=$2" "$3} END{print physical","peak}')
  printf '%s,%s,%s\n' "$1" "$(( $(date +%s) - started ))" "$metrics" | tee -a "$output/footprint.csv"
}
snapshot() {
  heap -s --noContent -H "$active_pid" > "$output/heap-$1.txt" 2>&1 || true
  vmmap -summary "$active_pid" > "$output/vmmap-$1.txt" 2>&1 || true
}
while ! grep -Eq '\[MaccyLifecycle\] READY scenario=retention' "$results/run.log"; do
  if grep -Eq '\[MaccyLifecycle\] FAIL' "$results/run.log" || ! kill -0 "$active_pid" 2>/dev/null; then
    grep -E '\[MaccyLifecycle\]' "$results/run.log"; exit 1
  fi
  (( $(date +%s) - started < 240 * 8 + 300 )) || { echo 'FAIL diagnostic timeout'; exit 1; }
  sample fast-mixed
  for milestone in 60 120 180; do
    if [[ ! -f "$output/heap-$milestone.txt" ]] && grep -Eq "CYCLE_READY cycle=$milestone " "$results/run.log"; then
      snapshot "$milestone"
    fi
  done
  sleep 5
done
sample idle-0
sleep 60
sample idle-60
snapshot final
heap -s --noContent '--addresses=CFData*[1M-]' "$active_pid" > "$output/data-addresses-metadata.txt" 2>&1 || true
address=$(python3 - "$output/data-addresses-metadata.txt" <<'PY'
import pathlib, re, sys
match = re.search(r'^\s*(0x[0-9a-fA-F]+)\b', pathlib.Path(sys.argv[1]).read_text(), re.M)
print(match.group(1) if match else '')
PY
)
if [[ "$address" =~ ^0x[0-9a-fA-F]+$ ]]; then
  leaks --noContent --nostacks "--traceTree=$address" "$active_pid" > "$output/data-reference-tree.txt" 2>&1 || true
fi
heap -s --noContent '--addresses=NSImage' "$active_pid" > "$output/image-addresses-metadata.txt" 2>&1 || true
for _ in {1..4}; do sleep 60; done
sample idle-after-5min
while ! grep -Eq '\[MaccyLifecycle\] ALLOCATOR_RELIEF' "$results/run.log"; do
  kill -0 "$active_pid"
  (( $(date +%s) - started < 240 * 8 + 900 )) || { echo 'FAIL allocator comparison timeout'; exit 1; }
  sleep 5
done
sample allocator-relief
sleep 15
sample allocator-relief-15
python3 - "$results/run.log" <<'PY'
import pathlib, re, sys
log = pathlib.Path(sys.argv[1]).read_text()
cycles = re.findall(r'CYCLE_READY cycle=(\d+) previews=(\d+) thumbnails=(\d+)', log)
assert cycles == [(str(i), '0', '0') for i in range(1, 241)], 'Incomplete operations or closed caches'
assert '[MaccyLifecycle] NEW_IMAGES_PREVIEWED' in log and '[MaccyLifecycle] ALLOCATOR_RELIEF' in log
assert '[MaccyLifecycle] FAIL' not in log
print('DIAGNOSTIC COMPLETE: accelerated pacing and profiling; no normal-memory pass is claimed')
PY
