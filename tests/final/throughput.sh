#!/usr/bin/env bash

set -euo pipefail

MODE="${1:?Modo requerido: ldap o web}"
TARGET="${2:?Target requerido}"
TOTAL="${3:-200}"
PARALLEL="${4:-10}"
OUT="${5:-throughput.csv}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

start_ns="$(date +%s%N)"

case "$MODE" in
    ldap)
        seq 1 "$TOTAL" |
        xargs \
          -P "$PARALLEL" \
          -I '{}' \
          bash -c '
            if timeout 7 ldapwhoami -x -H "$1" >/dev/null 2>&1; then
                echo OK
            else
                echo FAIL
            fi
          ' _ "$TARGET" \
          > "$TMP"
        ;;

    web)
        if ! klist -s; then
            echo "Se necesita un ticket Kerberos." >&2
            exit 1
        fi

        seq 1 "$TOTAL" |
        xargs \
          -P "$PARALLEL" \
          -I '{}' \
          bash -c '
            code="$(
              curl \
                --negotiate \
                -u : \
                --max-time 7 \
                --silent \
                --output /dev/null \
                --write-out "%{http_code}" \
                "$1"
            )"

            if [ "$code" = "200" ]; then
                echo OK
            else
                echo FAIL
            fi
          ' _ "$TARGET" \
          > "$TMP"
        ;;

    *)
        echo "Modo no reconocido: $MODE" >&2
        exit 2
        ;;
esac

end_ns="$(date +%s%N)"

successes="$(grep -c '^OK$' "$TMP" || true)"
failures="$(grep -c '^FAIL$' "$TMP" || true)"

elapsed_ms="$(
  awk \
    -v start="$start_ns" \
    -v end="$end_ns" \
    'BEGIN {
        printf "%.3f", (end - start) / 1000000
    }'
)"

throughput="$(
  awk \
    -v success="$successes" \
    -v start="$start_ns" \
    -v end="$end_ns" \
    'BEGIN {
        seconds = (end - start) / 1000000000

        if (seconds > 0)
            printf "%.3f", success / seconds
        else
            print "0"
    }'
)"

printf \
'mode,target,total,parallel,successes,failures,elapsed_ms,throughput_per_second\n' \
  > "$OUT"

printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "$MODE" \
  "$TARGET" \
  "$TOTAL" \
  "$PARALLEL" \
  "$successes" \
  "$failures" \
  "$elapsed_ms" \
  "$throughput" |
tee -a "$OUT"
