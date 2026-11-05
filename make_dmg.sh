#!/bin/bash
# Crée build/PostClip-<version>.dmg (app + raccourci vers Applications).
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
./build.sh
STAGE=$(mktemp -d)
cp -R build/PostClip.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/PostClip-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "PostClip $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"
echo "✓ $DMG"
