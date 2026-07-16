#!/usr/bin/env bash

set -u

medir() {
    local nombre="$1"
    local uri="$2"
    local iteraciones="${3:-50}"
    local exitosas=0
    local inicio fin tiempo_ms qps latencia

    inicio="$(date +%s%N)"

    for _ in $(seq 1 "$iteraciones"); do
        if timeout 3 ldapwhoami -x -H "$uri" >/dev/null 2>&1; then
            exitosas=$((exitosas + 1))
        fi
    done

    fin="$(date +%s%N)"
    tiempo_ms=$(( (fin - inicio) / 1000000 ))

    qps="$(
      awk \
        -v n="$exitosas" \
        -v ms="$tiempo_ms" \
        'BEGIN {
            if (ms > 0)
                printf "%.2f", n / (ms / 1000)
            else
                print "0"
        }'
    )"

    latencia="$(
      awk \
        -v ms="$tiempo_ms" \
        -v n="$iteraciones" \
        'BEGIN {
            if (n > 0)
                printf "%.2f", ms / n
            else
                print "0"
        }'
    )"

    printf '%s,iteraciones=%d,exitosas=%d,tiempo_ms=%d,qps=%s,latencia_media_ms=%s\n' \
      "$nombre" \
      "$iteraciones" \
      "$exitosas" \
      "$tiempo_ms" \
      "$qps" \
      "$latencia"
}

medir \
  'ldap1_directo' \
  'ldaps://ldap1.fis.epn.ec' \
  50

medir \
  'haproxy' \
  'ldaps://ldap.fis.epn.edu.ec' \
  50
