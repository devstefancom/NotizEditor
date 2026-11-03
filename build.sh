#!/bin/bash
# Builds NotizEditor.app into ./build (no Xcode project needed, only the Command Line Tools).
#   ./build.sh            build
#   ./build.sh --install  build and copy to /Applications
#   ./build.sh --dmg      universal build (Apple Silicon + Intel) packed into build/NotizEditor-<version>.dmg
#   ./build.sh --release  like --dmg, but signed with "Developer ID Application", notarized by Apple and stapled
#                         (needs the Apple Developer Program; set up the notary profile once with Scripts/setup-notary.sh)
set -euo pipefail
cd "$(dirname "$0")"

NAME="NotizEditor"
APP="build/$NAME.app"
BUNDLE_ID=de.stefanhogh.notizeditor
MODE="${1:-}"
mkdir -p build

ARCHS=(arm64)
[ "$MODE" = "--dmg" ] || [ "$MODE" = "--release" ] && ARCHS=(arm64 x86_64)
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    echo "▸ Kompiliere ($ARCH) …"
    swiftc -O -parse-as-library -target "$ARCH-apple-macos14.0" -swift-version 5 -module-name NotizEditor \
        $(find Sources/NotizEditor -name '*.swift') -o "build/NotizEditor-$ARCH"
    BINARIES+=("build/NotizEditor-$ARCH")
done
lipo -create "${BINARIES[@]}" -output build/NotizEditor

echo "▸ Erzeuge App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/NotizEditor "$APP/Contents/MacOS/NotizEditor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj Resources/bin "$APP/Contents/Resources/"

if [ ! -f build/AppIcon.icns ] || [ Scripts/make-icon.swift -nt build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift Scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Release: Developer ID (required for notarization). Otherwise also Developer ID if present, else "Apple Development", else ad-hoc.
IDENTITY="${NOTIZEDITOR_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ "$MODE" = "--release" ]; then
    if DEV=$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"'); then IDENTITY="${DEV//\"/}"
    else
        echo "✗ Kein „Developer ID Application“-Zertifikat gefunden."
        echo "  Xcode → Einstellungen → Accounts → Team → Manage Certificates → + → Developer ID Application"
        exit 1
    fi
elif [ -z "$IDENTITY" ]; then
    # Test builds use the same Developer ID as releases, so macOS treats every build as the same app.
    if DEV=$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"'); then IDENTITY="${DEV//\"/}"
    elif DEV=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development: [^"]*"'); then IDENTITY="${DEV//\"/}"
    else IDENTITY="-"; fi
fi
SIGN_OPTS=(--force --options runtime --identifier "$BUNDLE_ID")
[ "$MODE" = "--release" ] && SIGN_OPTS+=(--timestamp)
echo "▸ Signiere ($IDENTITY) …"
if ! codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" "$APP"; then
    [ "$MODE" = "--release" ] && { echo "✗ Signieren fehlgeschlagen."; exit 1; }
    echo "⚠︎ Signieren mit „$IDENTITY“ fehlgeschlagen – signiere ad-hoc."
    codesign "${SIGN_OPTS[@]}" --sign - "$APP"
fi

if [ "$MODE" = "--dmg" ] || [ "$MODE" = "--release" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    DMG="build/NotizEditor-$VERSION.dmg"
    echo "▸ Erzeuge $DMG …"
    rm -rf build/dmg "$DMG"
    mkdir -p build/dmg
    cp -R "$APP" build/dmg/
    ln -s /Applications build/dmg/Applications
    # Lines tagged [release] apply to notarized builds, [unsigned] to the others.
    if [ "$MODE" = "--release" ]; then KEEP=release DROP=unsigned; else KEEP=unsigned DROP=release; fi
    sed -e "s/{VERSION}/$VERSION/g" -e "/^\[$DROP\]/d" -e "s/^\[$KEEP\]//" "Resources/Read Me.txt" > "build/dmg/Read Me.txt"
    hdiutil create -quiet -volname "$NAME $VERSION" -srcfolder build/dmg -fs HFS+ -format UDZO "$DMG"
    rm -rf build/dmg
    if [ "$MODE" = "--release" ]; then
        codesign --force --timestamp --sign "$IDENTITY" "$DMG"
        PROFILE="${NOTIZEDITOR_NOTARY_PROFILE:-knipser-notary}"
        echo "▸ Lade zur Beglaubigung bei Apple hoch (Profil „$PROFILE“, dauert meist 1–5 Minuten) …"
        OUT=$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1) || true
        echo "$OUT"
        if ! grep -q "status: Accepted" <<<"$OUT"; then
            ID=$(grep -m1 -o 'id: [0-9a-f-]\{36\}' <<<"$OUT" | cut -d' ' -f2 || true)
            echo "✗ Beglaubigung abgelehnt oder fehlgeschlagen."
            [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE"
            exit 1
        fi
        echo "▸ Hefte das Beglaubigungs-Ticket an …"
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
        spctl --assess --type open --context context:primary-signature -v "$DMG"
    elif [ "$IDENTITY" != "-" ]; then
        codesign --force --sign "$IDENTITY" "$DMG"
    fi
    echo "✓ $DMG"
elif [ "$MODE" = "--install" ]; then
    echo "▸ Installiere nach /Applications …"
    pkill -x NotizEditor 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" /Applications/
    echo "✓ /Applications/$NAME.app"
else
    echo "✓ $APP"
fi
