#!/usr/bin/env bash

set -u

TARGET="${1:-https://web.fis.epn.ec/fis-idm}"
COUNT="${2:-120}"
INTERVAL="${3:-0.25}"
OUT="${4:-web-probe.csv}"

if ! klist -s; then
    echo "No existe un ticket Kerberos válido." >&2
    exit 1
fi

printf 'timestamp_ms,result,latency_ms,detail\n' > "$OUT"

for ((iteration = 1; iteration <= COUNT; iteration++)); do
    timestamp_ms="$(date +%s%3N)"

    response="$(
      curl \
        --negotiate \
        -u : \
        --max-time 5 \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out '%{http_code},%{time_total}' \
        "$TARGET" \
        2>/dev/null
    )"

    return_code=$?

    http_code="${response%%,*}"
    total_seconds="${response#*,}"

    if [ -z "$total_seconds" ] ||
       [ "$total_seconds" = "$response" ]; then
        total_seconds='0'
    fi

    latency_ms="$(
      awk \
        -v seconds="$total_seconds" \
        'BEGIN {
            printf "%.3f", seconds * 1000
        }'
    )"

    if [ "$return_code" -eq 0 ] &&
       [ "$http_code" = '200' ]; then
        result='OK'
    else
        result='FAIL'
    fi

    printf '%s,%s,%s,http_%s\n' \
      "$timestamp_ms" \
      "$result" \
      "$latency_ms" \
      "${http_code:-000}" |
    tee -a "$OUT"

    sleep "$INTERVAL"
done
