#!/bin/bash
# Runs only the dedicated synthetic bundle; never uses either real history store.
set -euo pipefail
umask 077
app=$1
label=${2:-candidate}
selected=${3:-all}
[[ "$selected" == all || "$selected" == browse || "$selected" == visibility || "$selected" == contracts ]]
test_id=org.yyyzl.MaccyMemoryLifecycle
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == "$test_id" ]]
codesign --verify --deep --strict "$app"
run_id="$(date +%Y%m%d%H%M%S)-${RANDOM}"
results=$(mktemp -d /tmp/maccy-lifecycle-results.XXXXXX)
store_root="$HOME/Library/Containers/$test_id/Data/Library/Application Support/Maccy/Lifecycle"
active_pid=''
cleanup() {
  if [[ -n "$active_pid" ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM
flags=(-ignoreEvents YES -ignoreOnlyNextEvent NO -showInStatusBar NO -clearOnQuit NO -clearSystemClipboard NO -historySize 200 -KeyboardShortcuts_popup NO -KeyboardShortcuts_pin NO -KeyboardShortcuts_delete NO -SUEnableAutomaticChecks NO)
launch() {
  "$app/Contents/MacOS/Maccy" --isolated-lifecycle "--scenario=$1" "--store=$2" "${flags[@]}" > "$3" 2>&1 &
  active_pid=$!
}
wait_marker() {
  for ((attempt=0; attempt<240; attempt++)); do
    if grep -Eq "\[MaccyLifecycle\] $2" "$1"; then return; fi
    if grep -Eq '\[MaccyLifecycle\] FAIL' "$1" || ! kill -0 "$active_pid" 2>/dev/null; then
      cat "$1"; return 1
    fi
    sleep 0.5
  done
  cat "$1"; echo 'Timed out waiting for isolated scenario' >&2; return 1
}

printf 'Results: %s\n' "$results"
seed_store="${run_id}-seed"
launch seed "$seed_store" "$results/seed.log"
wait_marker "$results/seed.log" SEED_OK
wait "$active_pid"
active_pid=''
printf 'variant,scenario,seconds_after_ready,physical_footprint,peak_footprint\n' > "$results/footprint.csv"
for scenario in idle text duplicate image preview browse visibility contracts copy; do
  if [[ "$selected" != all && "$selected" != "$scenario" ]]; then continue; fi
  store="${run_id}-${scenario}"
  python3 - "$store_root/$seed_store/Storage.sqlite" "$store_root/$store/Storage.sqlite" <<'PY'
import pathlib, sqlite3, sys
source, target = map(pathlib.Path, sys.argv[1:])
assert source.is_file() and not target.exists(), 'Refusing to overwrite a fixture'
target.parent.mkdir(mode=0o700)
with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as src:
    with sqlite3.connect(target) as dst:
        src.backup(dst)
PY
  launch "$scenario" "$store" "$results/$scenario.log"
  wait_marker "$results/$scenario.log" READY
  for delay in 0 5 15; do
    if (( delay == 5 )); then sleep 5; fi
    if (( delay == 15 )); then sleep 10; fi
    metrics=$(footprint "$active_pid" | awk '/phys_footprint:/{physical=$2" "$3} /phys_footprint_peak:/{peak=$2" "$3} END{print physical","peak}')
    printf '%s,%s,%s,%s\n' "$label" "$scenario" "$delay" "$metrics" | tee -a "$results/footprint.csv"
  done
  cleanup
  active_pid=''
done
python3 - "$results/footprint.csv" <<'PY'
import csv, sys
def mib(value):
    number, unit = value.split()
    return float(number) * {'B': 1/1048576, 'KB': 1/1024, 'MB': 1, 'GB': 1024}[unit]
rows = list(csv.DictReader(open(sys.argv[1])))
assert len(rows) in (3, 27) and all(row['physical_footprint'] for row in rows)
failed = [row for row in rows if row['seconds_after_ready'] == '15' and mib(row['physical_footprint']) >= 100]
for row in failed:
    print('FAIL steady-state budget:', row['scenario'], row['physical_footprint'])
if failed:
    sys.exit(1)
print('PASS: every synthetic scenario is below 100 MiB after 15 seconds')
PY
