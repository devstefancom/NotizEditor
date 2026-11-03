#!/bin/bash
# Speichert einmalig die Zugangsdaten für Apples Beglaubigungsdienst (notarytool) im Schlüsselbund.
# Danach kann ./build.sh --release ohne weitere Eingaben beglaubigen.
# Voraussetzung: Mitgliedschaft im Apple Developer Program und ein app-spezifisches Passwort
# (account.apple.com → Anmelden & Sicherheit → App-spezifische Passwörter).
set -euo pipefail
PROFILE="${KNIPSER_NOTARY_PROFILE:-knipser-notary}"
TEAM=$(security find-identity -v -p codesigning | grep -m1 -o 'Developer ID Application: .*(\([A-Z0-9]\{10\}\))' | grep -o '([A-Z0-9]\{10\})' | tr -d '()' || true)
[ -n "$TEAM" ] && echo "Team-ID aus deinem Developer-ID-Zertifikat: $TEAM"
echo "notarytool fragt jetzt nach Apple-ID, Team-ID und app-spezifischem Passwort."
xcrun notarytool store-credentials "$PROFILE" ${TEAM:+--team-id "$TEAM"}
echo "✓ Profil „${PROFILE}“ gespeichert. Jetzt: ./build.sh --release"
