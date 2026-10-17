#!/usr/bin/env bash
# Copies the generated screenshots (Scripts/screenshots.sh) into docs/assets/guide/ as small PNGs for the published
# guide (docs/guide.md). Run Scripts/screenshots.sh first. The copies are committed, the full-size originals are not.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="docs/assets/guide"
mkdir -p "$OUT"

copy() { # source target-name width
  [[ -f "$1" ]] || { echo "error: missing $1 — run Scripts/screenshots.sh first" >&2; exit 1; }
  cp "$1" "$OUT/$2.png"
  sips --resampleWidth "$3" "$OUT/$2.png" > /dev/null
  echo "  $OUT/$2.png"
}

copy Screenshots/iphone/en/01-shifts.png shifts 330
copy Screenshots/iphone/en/02-news.png news 330
copy Screenshots/iphone/en/03-profile.png profile 330
copy Screenshots/iphone/en/04-locations.png locations 330
copy Screenshots/iphone/en/05-messages.png messages 330
copy Screenshots/iphone/en/06-settings.png settings 330
copy Screenshots/watch/en/01-next-shift.png watch-next-shift 220
copy Screenshots/watch/en/02-settings.png watch-settings 220

# Every screen (Scripts/screenshots.sh manual) as small PNGs under docs/assets/guide/screens/, named without the
# order number (04-shift-detail.png -> shift-detail.png). Skipped when the manual set was not generated.
MANUAL="Screenshots/manual/iphone/en"
if [[ -d "$MANUAL" ]]; then
  mkdir -p "$OUT/screens"
  rm -f "$OUT"/screens/*.png
  for file in "$MANUAL"/*.png; do
    name="$(basename "$file" .png)"
    name="${name#*-}"
    [[ -f "$OUT/$name.png" ]] && continue # already published above (the App Store set)
    copy "$file" "screens/$name" 330
  done
fi

# The dark appearance of the same screens (Scripts/screenshots.sh manual): <name>-dark.png next to the light image; the
# website swaps them when the visitor switches to dark. The App Store set has no dark counterpart of its own, so the
# top-level images (shifts, news, ...) take theirs from the manual set, which shows the same demo data.
MANUAL_DARK="Screenshots/manual-dark/iphone/en"
if [[ -d "$MANUAL_DARK" ]]; then
  for file in "$MANUAL_DARK"/*.png; do
    name="$(basename "$file" .png)"
    name="${name#*-}"
    if [[ -f "$OUT/$name.png" ]]; then
      copy "$file" "$name-dark" 330
    else
      copy "$file" "screens/$name-dark" 330
    fi
  done
fi

# The Watch's Settings pages (Scripts/screenshots.sh manual), same idea: 01-settings-sync.png -> screens/watch-settings-sync.png.
MANUAL_WATCH="Screenshots/manual/watch/en"
if [[ -d "$MANUAL_WATCH" ]]; then
  mkdir -p "$OUT/screens"
  for file in "$MANUAL_WATCH"/*.png; do
    name="$(basename "$file" .png)"
    copy "$file" "screens/watch-${name#*-}" 220
  done
fi
