#!/usr/bin/env python3

from __future__ import annotations

import csv
import json
import math
import statistics
import sys
from pathlib import Path


def percentile(values: list[float], value: float) -> float:
    if not values:
        return 0.0

    ordered = sorted(values)
    index = max(
        0,
        min(
            len(ordered) - 1,
            math.ceil(value * len(ordered)) - 1,
        ),
    )
    return ordered[index]


def main() -> int:
    if len(sys.argv) != 2:
        print(
            f"Uso: {sys.argv[0]} archivo.csv",
            file=sys.stderr,
        )
        return 2

    path = Path(sys.argv[1])

    rows: list[dict[str, str]] = []

    with path.open(
        newline="",
        encoding="utf-8",
    ) as file:
        rows.extend(csv.DictReader(file))

    if not rows:
        print("El archivo no contiene muestras.", file=sys.stderr)
        return 1

    latencies = [
        float(row["latency_ms"])
        for row in rows
        if row.get("latency_ms")
    ]

    successes = [
        row for row in rows
        if row.get("result") == "OK"
    ]

    failures = [
        row for row in rows
        if row.get("result") != "OK"
    ]

    first_failure = None
    first_recovery = None
    failure_seen = False

    longest_failure_streak = 0
    current_failure_streak = 0

    for row in rows:
        timestamp = int(row["timestamp_ms"])

        if row["result"] != "OK":
            failure_seen = True
            current_failure_streak += 1
            longest_failure_streak = max(
                longest_failure_streak,
                current_failure_streak,
            )

            if first_failure is None:
                first_failure = timestamp
        else:
            if failure_seen and first_recovery is None:
                first_recovery = timestamp

            current_failure_streak = 0

    recovery_ms = None

    if first_failure is not None and first_recovery is not None:
        recovery_ms = first_recovery - first_failure

    summary = {
        "source": str(path),
        "samples": len(rows),
        "successes": len(successes),
        "failures": len(failures),
        "availability_percent": round(
            100 * len(successes) / len(rows),
            3,
        ),
        "latency_ms": {
            "mean": round(statistics.fmean(latencies), 3),
            "median": round(statistics.median(latencies), 3),
            "p95": round(percentile(latencies, 0.95), 3),
            "maximum": round(max(latencies), 3),
        },
        "first_failure_timestamp_ms": first_failure,
        "first_recovery_timestamp_ms": first_recovery,
        "observed_recovery_ms": recovery_ms,
        "longest_failure_streak": longest_failure_streak,
        "interpretation": (
            "sin_fallos_observados"
            if not failures
            else "fallos_observados"
        ),
    }

    print(
        json.dumps(
            summary,
            indent=2,
            ensure_ascii=False,
        )
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
