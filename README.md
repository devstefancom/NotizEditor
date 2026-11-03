# NotizEditor

Notizen und Texteditor für den Mac – von devstefan.com. Vorbild für den Funktionsumfang ist CotEditor.

- **Notizen sind normale Dateien:** jede Notiz ist eine `.txt`-Datei in `~/Documents/Notizen` (änderbar, auch iCloud Drive
  oder Dropbox). Links Ordner anlegen, umbenennen, per Drag & Drop verschieben; Suche über Namen und Inhalt aller Notizen.
- **Kodierung und Zeilenenden bleiben erhalten:** UTF-8/16/32 mit und ohne BOM, Windows-1252, ISO Latin 1, Mac Roman,
  Japanisch, Chinesisch, Koreanisch, Kyrillisch … werden erkannt; LF/CRLF/CR bleiben beim Speichern, wie sie waren.
  Umwandeln und „Neu interpretieren als“ in der Statusleiste und im Menü Format.
- **Editor:** Zeilennummern, unsichtbare Zeichen, aktuelle Zeile, Seitenführung, Zeilenumbruch, vertikaler Text,
  rechts-nach-links, Farben für 34 Sprachen, Gliederungsmenü, Suchen & Ersetzen mit regulären Ausdrücken,
  mehrere Cursor (⌘-Klick, ⌥-Ziehen, ⌘D, ⌃⌘G, ⇧⌘L), Zeilenbefehle, Unicode-Normalisierung, Zeichen-Info,
  automatisches Speichern, Listen-Fortsetzung, Kommandozeilen-Werkzeug `notizeditor` und eigene Skripte.
- Englisch und Deutsch, keine Abhängigkeiten, keine Server, keine Telemetrie.

## Bauen

```
./build.sh            # Test-Build nach build/NotizEditor.app
./build.sh --install  # nach /Applications
./build.sh --release  # universell, signiert, von Apple beglaubigt, build/NotizEditor-<Version>.dmg
```

Beglaubigung nutzt das notarytool-Profil `knipser-notary` (einmalig `Scripts/setup-notary.sh`).
Vertrieb: Direkt-Download von devstefan.com, nicht Mac App Store.

## Testen

```
Tests/run-tests.sh      # Dateien, Kodierungen, Farben, Gliederung, Textbefehle
Tests/run-ui-test.sh    # die echte App im Hintergrund: Notizen, Tippen, mehrere Cursor, Suchen, Verschieben
```

## Lizenz

MIT – siehe [LICENSE](LICENSE). © 2026 devstefan.com
