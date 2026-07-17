#!/usr/bin/env bash

set -u

URI="${1:-ldaps://ldap.fis.epn.edu.ec}"
COUNT="${2:-120}"
INTERVAL="${3:-0.25}"
OUT="${4:-ldap-probe.csv}"

printf 'timestamp_ms,result,latency_ms,detail\n' > "$OUT"

for ((iteration = 1; iteration <= COUNT; iteration++)); do
    timestamp_ms="$(date +%s%3N)"
    start_ns="$(date +%s%N)"

    response="$(
      timeout 5 \
        ldapwhoami \
          -x \
          -H "$URI" \
          2>&1
    )"

    return_code=$?
    end_ns="$(date +%s%N)"

    latency_ms="$(
      awk \
        -v start="$start_ns" \
        -v end="$end_ns" \
        'BEGIN {
            printf "%.3f", (end - start) / 1000000
        }'
    )"

    if [ "$return_code" -eq 0 ]; then
        result='OK'
    else
        result='FAIL'
    fi

    detail="$(
      printf '%s' "$response" |
      tr '\n,' ';;'
    )"

    printf '%s,%s,%s,%s\n' \
      "$timestamp_ms" \
      "$result" \
      "$latency_ms" \
      "$detail" |
    tee -a "$OUT"

    sleep "$INTERVAL"
done
