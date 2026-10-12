#!/usr/bin/env bash
# Runs the EngelsystemClientKit tests with coverage and fails if any non-excluded source file
# has less than 100 % line coverage (docs/testing.md, ADR 0009).
# Usage: Scripts/check-coverage.sh
# Env:   COVERAGE_THRESHOLD (default 1.0 = 100 %)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXCLUSIONS_FILE="$ROOT/Scripts/coverage-exclusions.txt"
THRESHOLD="${COVERAGE_THRESHOLD:-1.0}"

cd "$ROOT/EngelsystemClientKit"
swift test --enable-code-coverage >/dev/null
CODECOV_JSON="$(swift test --show-codecov-path)"

python3 - "$CODECOV_JSON" "$EXCLUSIONS_FILE" "$THRESHOLD" <<'PY'
import fnmatch, json, sys

report_path, exclusions_path, threshold = sys.argv[1], sys.argv[2], float(sys.argv[3])

patterns = []
with open(exclusions_path, encoding="utf-8") as handle:
    for raw in handle:
        line = raw.split("#", 1)[0].strip()
        if line:
            patterns.append(line)

with open(report_path, encoding="utf-8") as handle:
    files = json.load(handle)["data"][0]["files"]

failures, covered_total, executable_total, checked = [], 0, 0, 0
for entry in files:
    path = entry["filename"]
    if "/Tests/" in path or "/.build/" in path or any(fnmatch.fnmatch(path, p) for p in patterns):
        continue
    lines = entry["summary"]["lines"]
    if lines["count"] == 0:
        continue
    checked += 1
    covered_total += lines["covered"]
    executable_total += lines["count"]
    if lines["covered"] / lines["count"] < threshold:
        failures.append((lines["percent"], lines["count"] - lines["covered"], path))

if checked == 0:
    print("error: no source files measured", file=sys.stderr)
    sys.exit(2)

print(f"Measured files: {checked}, overall line coverage: {covered_total / executable_total:.2%}")
if failures:
    print(f"\nFiles below {threshold:.0%} line coverage (percent, uncovered lines):")
    for percent, uncovered, path in sorted(failures):
        print(f"  {percent:6.1f}%  {uncovered:4d}  {path.split('Sources/EngelsystemClientKit/')[-1]}")
    sys.exit(1)
print("Coverage gate passed.")
PY
