#!/usr/bin/env bash
# Build (et optionnellement installe) l'app iOS / iPadOS AuditViewerIOS.
#
# IMPORTANT — le dépôt vit sous ~/Documents (synchronisé iCloud). macOS y stampe
# l'attribut étendu `com.apple.provenance` sur les produits de build, et `codesign`
# le refuse (« resource fork, Finder information, or similar detritus not allowed »).
# On builde donc vers un derivedDataPath HORS iCloud ($TMPDIR par défaut).
#
# Usage :
#   ./build.sh                 # build simulateur (vérification de compilation)
#   ./build.sh <device-udid>   # build signé + install + lancement sur l'appareil
#                              # (UDID via : xcrun devicectl list devices)
set -euo pipefail

MAC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$MAC_DIR/AuditViewer.xcodeproj"
SCHEME="AuditViewerIOS"
BUNDLE_ID="com.vincent.AuditViewerIOS"
# Hors ~/Documents pour éviter le stamp iCloud com.apple.provenance.
DERIVED="${AUDITVIEWER_IOS_DERIVED:-${TMPDIR%/}/AuditViewerIOS-build}"

cd "$MAC_DIR"
echo "▸ xcodegen generate"
xcodegen generate >/dev/null
echo "▸ derivedData : $DERIVED"

DEVICE_ID="${1:-}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "▸ build simulateur (vérification de compilation)"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
  echo "✓ build simulateur OK"
  exit 0
fi

echo "▸ build signé pour l'appareil $DEVICE_ID"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates build

APP="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
echo "▸ install : $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
echo "▸ launch : $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
echo "✓ installé et lancé sur l'appareil"
