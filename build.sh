#!/bin/bash
# Compile PostClip.app (binaire universel Intel + Apple Silicon) sans projet Xcode.
#   ./build.sh            → build/PostClip.app
#   ./build.sh install    → copie aussi dans /Applications et lance l'app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/PostClip.app"
FLAGS=(-O -swift-version 5 -framework AppKit -framework SwiftUI -framework ServiceManagement)

# Icône (générée une seule fois)
if [ ! -f Resources/AppIcon.icns ]; then
  echo "→ Génération de l'icône"
  TMP=$(mktemp -d)
  swift scripts/make_icon.swift "$TMP/icon.png" >/dev/null
  mkdir -p "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

echo "→ Compilation"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
swiftc "${FLAGS[@]}" -target arm64-apple-macos13.0  -o build/obj/PostClip-arm64  Sources/*.swift
swiftc "${FLAGS[@]}" -target x86_64-apple-macos13.0 -o build/obj/PostClip-x86_64 Sources/*.swift
lipo -create build/obj/PostClip-arm64 build/obj/PostClip-x86_64 -output "$APP/Contents/MacOS/PostClip"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null
echo "✓ $APP"

if [ "${1:-}" = "install" ]; then
  pkill -x PostClip 2>/dev/null || true
  rm -rf /Applications/PostClip.app
  cp -R "$APP" /Applications/
  # La signature ad hoc change à chaque build : on réinitialise l'autorisation pour éviter un accès "fantôme".
  tccutil reset Accessibility com.leonardomondada.PostClip >/dev/null 2>&1 || true
  open /Applications/PostClip.app
  echo "✓ Installé dans /Applications et lancé"
fi
