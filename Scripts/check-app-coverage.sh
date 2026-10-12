#!/usr/bin/env bash
# Runs the iOS app's unit tests with coverage and fails if any non-excluded file of the
# app target has less than 100 % line coverage (docs/testing.md, ADR 0009/0010).
# Usage: Scripts/check-app-coverage.sh [extra xcodebuild args]
#   Watch app: SCHEME="EngelsystemClient Watch App" TARGET="EngelsystemClient Watch App.app" \
#              TEST_TARGET="EngelsystemClient Watch AppTests" DESTINATION="platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)" Scripts/check-app-coverage.sh
# Env:   COVERAGE_THRESHOLD (default 1.0), SIMULATOR (default "iPhone 17"),
#        TARGET (default "EngelsystemClient.app"; use "EngelsystemClient Watch App.app" etc.),
#        SCHEME (default "EngelsystemClient"), TEST_TARGET (default "EngelsystemClientTests"),
#        DESTINATION (default: the iOS simulator named by SIMULATOR)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXCLUSIONS_FILE="$ROOT/Scripts/coverage-exclusions.txt"
THRESHOLD="${COVERAGE_THRESHOLD:-1.0}"
SIMULATOR="${SIMULATOR:-iPhone 17}"
TARGET="${TARGET:-EngelsystemClient.app}"
SCHEME="${SCHEME:-EngelsystemClient}"
TEST_TARGET="${TEST_TARGET:-EngelsystemClientTests}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=$SIMULATOR}"
RESULT="$(mktemp -d)/cov.xcresult"

cd "$ROOT"
xcodebuild test -scheme "$SCHEME" -destination "$DESTINATION" \
  -parallel-testing-enabled NO -only-testing:"$TEST_TARGET" "$@" \
  -enableCodeCoverage YES -resultBundlePath "$RESULT" >/dev/null
xcrun xccov view --report --json "$RESULT" > "$RESULT.json"

python3 - "$RESULT.json" "$EXCLUSIONS_FILE" "$THRESHOLD" "$TARGET" <<'PY'
import fnmatch, json, sys

report_path, exclusions_path, threshold, target_name = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
patterns = []
with open(exclusions_path, encoding="utf-8") as handle:
    for raw in handle:
        line = raw.split("#", 1)[0].strip()
        if line:
            patterns.append(line)

report = json.load(open(report_path, encoding="utf-8"))
failures, covered_total, executable_total, checked = [], 0, 0, 0
for target in report["targets"]:
    if target["name"] != target_name:
        continue
    for entry in target["files"]:
        path = entry["path"]
        if any(fnmatch.fnmatch(path, p) for p in patterns) or entry["executableLines"] == 0:
            continue
        checked += 1
        covered_total += entry["coveredLines"]
        executable_total += entry["executableLines"]
        if entry["coveredLines"] / entry["executableLines"] < threshold:
            failures.append((100 * entry["coveredLines"] / entry["executableLines"],
                             entry["executableLines"] - entry["coveredLines"], path))
if checked == 0:
    print(f"error: no files measured for target {target_name}", file=sys.stderr)
    sys.exit(2)
print(f"{target_name}: measured files {checked}, overall line coverage {covered_total / executable_total:.2%}")
if failures:
    print(f"\nFiles below {threshold:.0%} (percent, uncovered lines):")
    for percent, uncovered, path in sorted(failures):
        print(f"  {percent:6.1f}%  {uncovered:4d}  {path.split('/EngelsystemClient/')[-1]}")
    sys.exit(1)
print("Coverage gate passed.")
PY
