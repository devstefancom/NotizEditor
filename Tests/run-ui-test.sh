#!/bin/bash
# Builds NotizEditor with Tests/ui-selftest.swift and runs it in the background (it doesn't take the focus)
# with a temporary notes folder and its own settings. Prints the results.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh > /dev/null
APP=build/selftest/NotizEditor.app
rm -rf build/selftest && mkdir -p build/selftest
cp -R build/NotizEditor.app "$APP"
/usr/libexec/PlistBuddy -c "Set CFBundleIdentifier de.stefanhogh.notizeditor.selftest" "$APP/Contents/Info.plist"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 -swift-version 5 -module-name NotizEditor -D SELFTEST \
    $(find Sources/NotizEditor -name '*.swift') Tests/ui-selftest.swift -o "$APP/Contents/MacOS/NotizEditor"
codesign --force --sign - "$APP" 2>/dev/null
NOTES=$(mktemp -d -t notizeditor-notes)
REPORT=$(mktemp -t notizeditor-report)
trap 'rm -rf "$NOTES" "$REPORT"; defaults delete de.stefanhogh.notizeditor.selftest 2>/dev/null || true' EXIT
SELFTEST_REPORT="$REPORT" "$APP/Contents/MacOS/NotizEditor" -notesFolder "$NOTES" -moveToApplicationsSuppressed YES \
    > "$REPORT.out" 2>/dev/null &
PID=$!
for _ in $(seq 60); do sleep 1; kill -0 $PID 2>/dev/null || break; done
kill $PID 2>/dev/null && echo "✗ Zeitüberschreitung (hängt nach dem letzten Test)"
grep -v '^Notizen-Ordner' "$REPORT.out"
rm -f "$REPORT.out"
grep -q '^OK$' "$REPORT"
