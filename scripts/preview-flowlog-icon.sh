#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/Productivity/Flowlog.icon"
OUT="$ICON/.previews"
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

mkdir -p "$OUT"

"$ICTOOL" "$ICON" \
  --export-image --output-file "$OUT/Default.png" \
  --platform macOS --rendition Default \
  --width 1024 --height 1024 --scale 2

"$ICTOOL" "$ICON" \
  --export-image --output-file "$OUT/Dark.png" \
  --platform macOS --rendition Dark \
  --width 1024 --height 1024 --scale 2

# ictool tint-color ≈ hue 0–1; ~0.62 reads closest to macOS blue in previews
"$ICTOOL" "$ICON" \
  --export-image --output-file "$OUT/TintedLight.png" \
  --platform macOS --rendition TintedLight \
  --width 1024 --height 1024 --scale 2 \
  --tint-color 0.62 --tint-strength 0.9

"$ICTOOL" "$ICON" \
  --export-image --output-file "$OUT/TintedDark.png" \
  --platform macOS --rendition TintedDark \
  --width 1024 --height 1024 --scale 2 \
  --tint-color 0.62 --tint-strength 0.9

echo "Wrote previews to $OUT"
