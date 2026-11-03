#!/bin/bash
set -euo pipefail
umask 077
app=$1
label=${2:-candidate}
cycles=${3:-60}
scenario=${4:-long}
[[ "$cycles" == 60 || "$cycles" == 240 ]]
[[ "$scenario" == long || "$scenario" == background ]]
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
grep -Eq '\[MaccyLifecycle\] SEED_OK' "$results/seed.log"
printf 'variant,phase,elapsed_seconds,physical_footprint,peak_footprint\n' > "$results/footprint.csv"
"$app/Contents/MacOS/Maccy" --isolated-lifecycle "--scenario=$scenario" "--cycles=$cycles" "--store=$store" "${flags[@]}" > "$results/long.log" 2>&1 &
active_pid=$!
started=$(date +%s)
sample() {
  metrics=$(footprint "$active_pid" | awk '/phys_footprint:/{physical=$2" "$3} /phys_footprint_peak:/{peak=$2" "$3} END{print physical","peak}')
  printf '%s,%s,%s,%s\n' "$label" "$1" "$(( $(date +%s) - started ))" "$metrics" | tee -a "$results/footprint.csv"
}
while ! grep -Eq "\[MaccyLifecycle\] READY scenario=$scenario" "$results/long.log"; do
  if grep -Eq '\[MaccyLifecycle\] FAIL' "$results/long.log" || ! kill -0 "$active_pid" 2>/dev/null; then
    grep -E '\[MaccyLifecycle\]' "$results/long.log"; exit 1
  fi
  (( $(date +%s) - started < cycles * 20 + 600 )) || { echo 'FAIL long-run timeout'; exit 1; }
  sample mixed
  sleep 15
done
sample idle-0
sleep 15
sample idle-15
sleep 45
sample idle-60
for _ in {1..4}; do sleep 60; done
sample idle-300
python3 - "$results/footprint.csv" "$results/long.log" "$cycles" "$scenario" <<'PY'
import csv, re, statistics, sys
def amount(value):
    number, unit = value.split()
    return float(number) * {'B': 1/1048576, 'KB': 1/1024, 'MB': 1, 'GB': 1024}[unit]
rows = list(csv.DictReader(open(sys.argv[1])))
log = open(sys.argv[2]).read()
cycles = re.findall(r'CYCLE_READY cycle=(\d+) previews=(\d+) thumbnails=(\d+)', log)
assert [row[0] for row in cycles] == [str(i) for i in range(1,int(sys.argv[3])+1)], 'Mixed operations did not all complete'
if sys.argv[4] == 'background':
    assert 'BACKGROUND_MODE visible=NO key=NO' in log
    assert f'BACKGROUND_OK cycles={sys.argv[3]} validated_new_images={int(sys.argv[3]) // 3}' in log
mixed = [amount(row['physical_footprint']) for row in rows if row['phase'] == 'mixed']
assert len(mixed) >= 55 and int(rows[-1]['elapsed_seconds']) >= int(sys.argv[3])*15+300, 'Insufficient continuous coverage'
idle = amount(rows[-1]['physical_footprint'])
idle60 = amount(next(row for row in rows if row['phase'] == 'idle-60')['physical_footprint'])
mean = statistics.mean(mixed)
tail_mean = statistics.mean(mixed[-20:])
print(f'Mixed samples={len(mixed)} mean={mean:.1f} median={statistics.median(mixed):.1f} max={max(mixed):.1f} tail_mean={tail_mean:.1f} idle60={idle60:.1f} idle300={idle:.1f} MB')
assert all(row[1:] == ('0', '0') for row in cycles), 'Closed popup retained image caches'
if max(mean, tail_mean, idle60, idle) >= 100:
    print('FAIL: average, final segment or settled idle memory exceeds the 100 MB budget'); sys.exit(1)
print('PASS: continuous synthetic workload and post-work idle stay within budget')
PY
