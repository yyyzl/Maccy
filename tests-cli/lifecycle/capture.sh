#!/bin/bash
# Publishes only synthetic metrics and lifecycle logs, never a database or image.
set -euo pipefail
umask 077
app=$1
label=$2
cycles=$3
output=$4
[[ "$label" == baseline || "$label" == bulk || "$label" == candidate || "$label" == endurance || "$label" == background ]]
scenario=long
if [[ "$label" == background ]]; then scenario=background; fi
mkdir -p "$output"
[[ ! -e "$output/$label-console.log" ]]
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
set +e
bash "$root/tests-cli/lifecycle/long.sh" "$app" "$label" "$cycles" "$scenario" | tee "$output/$label-console.log"
statuses=("${PIPESTATUS[@]}")
set -e
[[ ${statuses[1]} == 0 ]]
result_dir=$(sed -n 's/^Results: //p' "$output/$label-console.log" | head -1)
[[ "$result_dir" =~ ^/tmp/maccy-long-results\.[A-Za-z0-9]+$ ]]
if [[ -f "$result_dir/footprint.csv" ]]; then cp "$result_dir/footprint.csv" "$output/$label.csv"; fi
if [[ -f "$result_dir/long.log" ]]; then
  grep -E '\[MaccyLifecycle\]' "$result_dir/long.log" > "$output/$label.log" || true
fi
printf '%s\n' "${statuses[0]}" > "$output/$label-exit-code.txt"
exit "${statuses[0]}"
