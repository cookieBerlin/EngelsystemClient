#!/usr/bin/env bash
# Runs all three coverage gates: EngelsystemClientKit, the iOS app, and the Watch app
# (docs/testing.md, ADR 0009/0010). Stops at the first failing gate.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== EngelsystemClientKit"
Scripts/check-coverage.sh

echo "== iOS app"
Scripts/check-app-coverage.sh

echo "== Watch app"
SCHEME="EngelsystemClient Watch App" \
TARGET="EngelsystemClient Watch App.app" \
TEST_TARGET="EngelsystemClient Watch AppTests" \
DESTINATION="${WATCH_DESTINATION:-platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)}" \
Scripts/check-app-coverage.sh

echo "All coverage gates passed."
