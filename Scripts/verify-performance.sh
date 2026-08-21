#!/bin/zsh
set -euo pipefail

pid="$(pgrep -x CaffeineModes | head -1)"
if [[ -z "$pid" ]]; then
    print -u2 "Start the built Caffeine Modes app, then run this check."
    exit 1
fi

samples="$(for _ in {1..12}; do ps -p "$pid" -o %cpu=,rss=; sleep 5; done)"
average_cpu="$(print -r -- "$samples" | awk '{cpu += $1; count += 1} END {printf "%.3f", cpu/count}')"
maximum_rss_kb="$(print -r -- "$samples" | awk 'BEGIN {max=0} {if ($2 > max) max=$2} END {print max}')"

awk -v cpu="$average_cpu" 'BEGIN { exit !(cpu < 0.2) }'
awk -v rss="$maximum_rss_kb" 'BEGIN { exit !(rss < 51200) }'
printf 'PASS PERFORMANCE cpu=%s%% rss=%sKB\n' "$average_cpu" "$maximum_rss_kb"
