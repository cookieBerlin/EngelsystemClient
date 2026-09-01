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

rm -rf "$OUTPUT_DIR"

openapi-generator generate \
  -i "$INPUT_SPEC" \
  -g swift5 \
  -o "$OUTPUT_DIR" \
  --global-property apiDocs=false,modelDocs=false,apiTests=false,modelTests=false \
  --additional-properties=library=urlsession,responseAs=AsyncAwait,projectName=EngelsystemAPI,swiftPackagePath=.

# The generator's non-Swift project files aren't needed (we already have our own SPM package)
rm -rf "$OUTPUT_DIR/docs" "$OUTPUT_DIR/.openapi-generator" "$OUTPUT_DIR"/.swiftformat \
  "$OUTPUT_DIR"/.openapi-generator-ignore "$OUTPUT_DIR"/.gitignore "$OUTPUT_DIR"/Cartfile \
  "$OUTPUT_DIR"/EngelsystemAPI.podspec "$OUTPUT_DIR"/Package.swift "$OUTPUT_DIR"/project.yml \
  "$OUTPUT_DIR"/README.md "$OUTPUT_DIR"/git_push.sh

echo "Codegen complete. Output in: $OUTPUT_DIR"
echo "If Xcode doesn't pick up the new files automatically: in the package folder,"
echo "right-click in Xcode -> 'Add Files to ...' and select the Generated folder."
