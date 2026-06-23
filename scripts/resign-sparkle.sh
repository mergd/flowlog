#!/usr/bin/env bash
set -euo pipefail

# Re-sign Sparkle's embedded helpers with the app's Developer ID certificate.
# SPM-linked Sparkle ships ad-hoc signed; notarization requires these to match the app.

app="${1:?Usage: scripts/resign-sparkle.sh /path/to/Flowlog.app}"
framework="$app/Contents/Frameworks/Sparkle.framework"
[[ -d "$framework" ]] || exit 0

if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  identity="$EXPANDED_CODE_SIGN_IDENTITY"
else
  identity="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi
[[ -n "$identity" ]] || { echo "No Developer ID Application identity found" >&2; exit 1; }

entitlements="${2:-}"
base="$framework/Versions/B"

sign() {
  codesign -f -s "$identity" -o runtime --timestamp "$@"
}

sign "$base/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$base/XPCServices/Downloader.xpc"
sign "$base/Autoupdate"
sign "$base/Updater.app"
sign "$framework"

if [[ -n "$entitlements" ]]; then
  codesign -f -s "$identity" -o runtime --timestamp --entitlements "$entitlements" "$app"
else
  codesign -f -s "$identity" -o runtime --timestamp "$app"
fi
