#!/bin/bash
set -euo pipefail

# Generates the Swift DTOs/API client classes from the Engelsystem OpenAPI spec.
# Requires: brew install openapi-generator
#
# Run from the project root, e.g.:
#   ./Scripts/generate-api.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT_SPEC="$PROJECT_ROOT/EngelsystemClientKit/Resources/openapi.yml"
OUTPUT_DIR="$PROJECT_ROOT/EngelsystemClientKit/Sources/EngelsystemClientKit/Generated"

if [ ! -f "$INPUT_SPEC" ]; then
  echo "Error: $INPUT_SPEC not found."
  echo "Place the openapi.yml there before running this script."
  exit 1
fi

openapi-generator generate \
  -i "$INPUT_SPEC" \
  -g swift5 \
  -o "$OUTPUT_DIR" \
  --additional-properties=library=urlsession,responseAs=AsyncAwait,projectName=EngelsystemAPI

echo "Codegen complete. Output in: $OUTPUT_DIR"
echo "If Xcode doesn't pick up the new files automatically: in the package folder,"
echo "right-click in Xcode -> 'Add Files to ...' and select the Generated folder."
