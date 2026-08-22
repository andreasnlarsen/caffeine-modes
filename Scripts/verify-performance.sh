#!/bin/zsh
set -euo pipefail

pid="$(pgrep -x CaffeineModes | head -1)"
if [[ -z "$pid" ]]; then
    print -u2 "Start the built Caffeine Modes app, then run this check."
    exit 1
fi

read_cpu_seconds() {
    ps -p "$pid" -o time= | awk '
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            day_count = split($0, day_parts, "-")
            if (day_count == 2) {
                days = day_parts[1]
                time_value = day_parts[2]
            } else {
                days = 0
                time_value = $0
            }

            component_count = split(time_value, components, ":")
            if (component_count == 2) {
                seconds = (days * 86400) + (components[1] * 60) + components[2]
            } else if (component_count == 3) {
                seconds = (days * 86400) + (components[1] * 3600) + (components[2] * 60) + components[3]
            } else {
                exit 1
            }
            printf "%.2f\n", seconds
        }
    '
}

if ! cpu_seconds_started="$(read_cpu_seconds)" || [[ -z "$cpu_seconds_started" ]]; then
    print -u2 "FAIL PERFORMANCE Caffeine Modes stopped before measurement."
    exit 1
fi

measurement_started_at="$SECONDS"
footprint_samples=""
for sample_number in {0..11}; do
    target_seconds=$((measurement_started_at + (sample_number * 5)))
    remaining_seconds=$((target_seconds - SECONDS))
    if (( remaining_seconds > 0 )); then
        sleep "$remaining_seconds"
    fi

    if ! footprint_bytes="$(footprint -f bytes -p "$pid" | awk '
        /Footprint:/ && measured_bytes == "" {
            for (field = 1; field < NF; field += 1) {
                if ($field == "Footprint:" && $(field + 1) ~ /^[0-9]+$/) {
                    measured_bytes = $(field + 1)
                    break
                }
            }
        }
        END {
            if (measured_bytes != "") {
                print measured_bytes
            }
        }
    ')" || [[ -z "$footprint_bytes" ]]; then
        print -u2 "FAIL PERFORMANCE macOS footprint could not measure Caffeine Modes."
        exit 1
    fi
    footprint_samples+="${footprint_bytes}"$'\n'
done

remaining_seconds=$((measurement_started_at + 60 - SECONDS))
if (( remaining_seconds > 0 )); then
    sleep "$remaining_seconds"
fi

if ! cpu_seconds_finished="$(read_cpu_seconds)" || [[ -z "$cpu_seconds_finished" ]]; then
    print -u2 "FAIL PERFORMANCE Caffeine Modes stopped during measurement."
    exit 1
fi
measurement_elapsed_seconds=$((SECONDS - measurement_started_at))
average_cpu="$(awk \
    -v started="$cpu_seconds_started" \
    -v finished="$cpu_seconds_finished" \
    -v elapsed="$measurement_elapsed_seconds" \
    'BEGIN {printf "%.3f", ((finished - started) / elapsed) * 100}')"
maximum_footprint_bytes="$(print -r -- "$footprint_samples" | awk 'BEGIN {max=0} {if ($1 > max) max=$1} END {print max}')"
maximum_footprint_mb="$(awk -v bytes="$maximum_footprint_bytes" 'BEGIN {printf "%.1f", bytes / 1048576}')"

if ! awk -v cpu="$average_cpu" 'BEGIN { exit !(cpu < 0.2) }'; then
    print -u2 "FAIL PERFORMANCE average CPU ${average_cpu}% is not below 0.2%."
    exit 1
fi
if ! awk -v bytes="$maximum_footprint_bytes" 'BEGIN { exit !(bytes < 52428800) }'; then
    print -u2 "FAIL PERFORMANCE peak physical footprint ${maximum_footprint_mb} MB is not below 50 MB."
    exit 1
fi
printf 'PASS PERFORMANCE cpu=%s%% footprint=%sMB\n' "$average_cpu" "$maximum_footprint_mb"
