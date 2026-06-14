#!/usr/bin/env bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AuditViewer"
BUILD_DIR="$PROJ_DIR/.build/release"
APP_BUNDLE="$PROJ_DIR/build/$APP_NAME.app"
WEB_SRC="$PROJ_DIR/Resources/web"

echo "→ Compilation Swift…"
cd "$PROJ_DIR"
swift build -c release 2>&1

echo "→ Création du bundle .app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binaire
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist
cp "$PROJ_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Icône
if [ -f "$PROJ_DIR/AppIcon.icns" ]; then
    cp "$PROJ_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  ✓ Icône copiée"
fi

# Ressources web (rendu markdown) — vendorisées dans le repo
if [ -d "$WEB_SRC" ]; then
    cp -r "$WEB_SRC" "$APP_BUNDLE/Contents/Resources/web"
    echo "  ✓ Ressources web copiées"
else
    echo "  ⚠ Ressources web introuvables — le rendu markdown ne fonctionnera pas"
    echo "    Attendu : $WEB_SRC"
fi

# Ressources de la carte/graphe (propres à AuditViewer)
if [ -d "$PROJ_DIR/Resources/webgraph" ]; then
    cp -r "$PROJ_DIR/Resources/webgraph" "$APP_BUNDLE/Contents/Resources/webgraph"
    echo "  ✓ Ressources carte copiées"
else
    echo "  ⚠ Resources/webgraph introuvable — la carte des liens ne fonctionnera pas"
fi

echo "→ Bundle produit : $APP_BUNDLE"
echo ""
echo "Pour lancer :"
echo "  open '$APP_BUNDLE'"
echo ""
echo "Pour installer dans /Applications :"
echo "  cp -r '$APP_BUNDLE' /Applications/"
