#!/usr/bin/env bash

set -u

COUNT="${1:-120}"
INTERVAL="${2:-0.25}"
OUT="${3:-kdc-probe.csv}"

KEYTAB='/etc/apache2/krb5/http-web.keytab'
PRINCIPAL='HTTP/web.fis.epn.ec@FIS.EPN.EC'
CONFIG="${KRB5_CONFIG:-/etc/krb5.conf}"

if [ "$EUID" -ne 0 ]; then
    echo "Ejecutar mediante sudo." >&2
    exit 1
fi

if [ ! -r "$KEYTAB" ]; then
    echo "No se puede leer $KEYTAB." >&2
    exit 1
fi

printf 'timestamp_ms,result,latency_ms,detail\n' > "$OUT"

for ((iteration = 1; iteration <= COUNT; iteration++)); do
    timestamp_ms="$(date +%s%3N)"
    start_ns="$(date +%s%N)"

    cache="/tmp/mini-idm-kdc-${$}-${iteration}.ccache"
    rm -f "$cache"

    output="$(
      timeout 7 \
        env \
          KRB5_CONFIG="$CONFIG" \
          KRB5CCNAME="FILE:$cache" \
        kinit \
          -k \
          -t "$KEYTAB" \
          "$PRINCIPAL" \
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
        detail='ticket_obtenido'
    else
        result='FAIL'
        detail="$(
          printf '%s' "$output" |
          tr '\n,' ';;'
        )"
    fi

    env \
      KRB5CCNAME="FILE:$cache" \
      kdestroy \
      >/dev/null 2>&1 ||
    true

    rm -f "$cache"

    printf '%s,%s,%s,%s\n' \
      "$timestamp_ms" \
      "$result" \
      "$latency_ms" \
      "$detail" |
    tee -a "$OUT"

    sleep "$INTERVAL"
done
