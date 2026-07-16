#!/usr/bin/env bash

set -u

TARGET='ldaps://ldap.fis.epn.edu.ec'
OUT="${1:-$HOME/ldap-ha-failover.csv}"

printf 'timestamp_ms,result,latency_ms\n' > "$OUT"

for _ in $(seq 1 120); do
    timestamp_ms="$(date +%s%3N)"
    start_ns="$(date +%s%N)"

    if timeout 2 ldapwhoami -x -H "$TARGET" >/dev/null 2>&1; then
        result='OK'
    else
        result='FAIL'
    fi

    end_ns="$(date +%s%N)"
    latency_ms=$(( (end_ns - start_ns) / 1000000 ))

    printf '%s,%s,%s\n' \
      "$timestamp_ms" \
      "$result" \
      "$latency_ms" |
    tee -a "$OUT"

    sleep 0.2
done
