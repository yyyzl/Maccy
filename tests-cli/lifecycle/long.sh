#!/bin/bash
set -euo pipefail
umask 077
app=$1
label=${2:-candidate}
test_id=org.yyyzl.MaccyMemoryLifecycle
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == "$test_id" ]]
codesign --verify --deep --strict "$app"
results=$(mktemp -d /tmp/maccy-long-results.XXXXXX)
store="long-$(date +%Y%m%d%H%M%S)-${RANDOM}"
flags=(-ignoreEvents YES -ignoreOnlyNextEvent NO -showInStatusBar NO -clearOnQuit NO -clearSystemClipboard NO -historySize 200 -KeyboardShortcuts_popup NO -KeyboardShortcuts_pin NO -KeyboardShortcuts_delete NO -SUEnableAutomaticChecks NO)
active_pid=''
cleanup() {
  if [[ -n "$active_pid" ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM
printf 'Results: %s\n' "$results"
"$app/Contents/MacOS/Maccy" --isolated-lifecycle --scenario=seed "--store=$store" "${flags[@]}" > "$results/seed.log" 2>&1 &
active_pid=$!
wait "$active_pid"
active_pid=''
rg -q '\[MaccyLifecycle\] SEED_OK' "$results/seed.log"
printf 'variant,phase,elapsed_seconds,physical_footprint,peak_footprint\n' > "$results/footprint.csv"
"$app/Contents/MacOS/Maccy" --isolated-lifecycle --scenario=long "--store=$store" "${flags[@]}" > "$results/long.log" 2>&1 &
active_pid=$!
started=$(date +%s)
sample() {
  metrics=$(footprint "$active_pid" | awk '/phys_footprint:/{physical=$2" "$3} /phys_footprint_peak:/{peak=$2" "$3} END{print physical","peak}')
  printf '%s,%s,%s,%s\n' "$label" "$1" "$(( $(date +%s) - started ))" "$metrics" | tee -a "$results/footprint.csv"
}
while ! rg -q '\[MaccyLifecycle\] READY scenario=long' "$results/long.log"; do
  if rg -q '\[MaccyLifecycle\] FAIL' "$results/long.log" || ! kill -0 "$active_pid" 2>/dev/null; then
    rg '\[MaccyLifecycle\]' "$results/long.log"; exit 1
  fi
  (( $(date +%s) - started < 1800 )) || { echo 'FAIL long-run timeout'; exit 1; }
  sample mixed
  sleep 15
done
sample idle-0
sleep 15
sample idle-15
sleep 45
sample idle-60
python3 - "$results/footprint.csv" "$results/long.log" <<'PY'
import csv, re, statistics, sys
def amount(value):
    number, unit = value.split()
    return float(number) * {'B': 1/1048576, 'KB': 1/1024, 'MB': 1, 'GB': 1024}[unit]
rows = list(csv.DictReader(open(sys.argv[1])))
cycles = re.findall(r'CYCLE_READY cycle=(\d+)', open(sys.argv[2]).read())
assert cycles == [str(i) for i in range(1,61)], 'Mixed operations did not all complete'
mixed = [amount(row['physical_footprint']) for row in rows if row['phase'] == 'mixed']
assert len(mixed) >= 55 and int(rows[-1]['elapsed_seconds']) >= 900, 'Insufficient continuous coverage'
idle = amount(rows[-1]['physical_footprint'])
mean = statistics.mean(mixed)
print(f'Mixed samples={len(mixed)} mean={mean:.1f} median={statistics.median(mixed):.1f} max={max(mixed):.1f} idle60={idle:.1f} MB')
if mean >= 100 or idle >= 100:
    print('FAIL: average or idle memory exceeds the 100 MB budget'); sys.exit(1)
print('PASS: continuous synthetic workload and post-work idle stay within budget')
PY
