import SwiftUI

/// NotizEditor's help topics (shown by Help.swift, which is the same in every app).
enum HelpContent {
    static let topics: [HelpTopic] = [
        HelpTopic(
            id: "overview", icon: "rectangle.split.2x1",
            title: HelpText("The window at a glance", de: "Das Fenster im Überblick"),
            summary: HelpText("What's where in NotizEditor", de: "Was wo in NotizEditor ist"),
            blocks: [
                .steps([
                    HelpText("**Left:** your notes folder with its subfolders. Click a note to open it. The number next to a folder counts its notes.",
                             de: "**Links:** dein Notizen-Ordner mit seinen Unterordnern. Ein Klick öffnet eine Notiz. Die Zahl neben einem Ordner zählt seine Notizen."),
                    HelpText("**Top left:** the search field – it searches the names and the text of all notes.",
                             de: "**Oben links:** das Suchfeld – es durchsucht die Namen und den Text aller Notizen."),
                    HelpText("**Middle:** the text. Line numbers on the left, colours for code, the current line lightly marked.",
                             de: "**Mitte:** der Text. Links die Zeilennummern, Farben für Code, die aktuelle Zeile leicht hervorgehoben."),
                    HelpText("**Bottom:** line and column, characters, words and lines – and the language, text encoding and line endings of the file. Click them to change them.",
                             de: "**Unten:** Zeile und Spalte, Zeichen, Wörter und Zeilen – und Sprache, Kodierung und Zeilenenden der Datei. Ein Klick darauf ändert sie."),
                    HelpText("**Top right:** the outline (jump to headings or functions) and the search.",
                             de: "**Oben rechts:** die Gliederung (zu Überschriften oder Funktionen springen) und die Suche."),
                ]),
                .tip(HelpText("There is no Save button: NotizEditor saves by itself a moment after you stop typing, when you switch notes and when you quit.",
                              de: "Es gibt keinen Sichern-Knopf: NotizEditor speichert von selbst, kurz nachdem du aufhörst zu tippen, beim Wechseln der Notiz und beim Beenden.")),
            ]),
        HelpTopic(
            id: "notes", icon: "note.text",
            title: HelpText("Notes and folders", de: "Notizen und Ordner"),
            summary: HelpText("Create, rename, move and delete", de: "Anlegen, umbenennen, verschieben und löschen"),
            blocks: [
                .steps([
                    HelpText("**New note:** ⌘N, or the pencil at the top. It goes into the selected folder. Type the name and press Return.",
                             de: "**Neue Notiz:** ⌘N oder der Stift oben. Sie landet im ausgewählten Ordner. Namen eintippen und Return drücken."),
                    HelpText("**New folder:** ⇧⌘N, or the folder button at the top.", de: "**Neuer Ordner:** ⇧⌘N oder der Ordner-Knopf oben."),
                    HelpText("**Rename:** right-click → **Rename**.", de: "**Umbenennen:** Rechtsklick → **Umbenennen**."),
                    HelpText("**Move:** drag a note or folder onto another folder. Drag it onto the empty area below to move it back to the top level.",
                             de: "**Verschieben:** eine Notiz oder einen Ordner auf einen anderen Ordner ziehen. Auf die freie Fläche darunter ziehen, um sie wieder nach ganz oben zu holen."),
                    HelpText("**Delete:** select it and press ⌫, or right-click → **Move to Trash**. It goes to the Trash, so you can get it back.",
                             de: "**Löschen:** auswählen und ⌫ drücken, oder Rechtsklick → **In den Papierkorb legen**. Es landet im Papierkorb, du kannst es also zurückholen."),
                ]),
                .tip(HelpText("Drag files from the Finder into the list to copy them into your notes.",
                              de: "Zieh Dateien aus dem Finder in die Liste, um sie in deine Notizen zu kopieren.")),
            ]),
        HelpTopic(
            id: "files", icon: "doc.plaintext",
            title: HelpText("Normal files – also for Windows", de: "Normale Dateien – auch für Windows"),
            summary: HelpText("Where your notes are and how they are stored", de: "Wo deine Notizen liegen und wie sie gespeichert werden"),
            blocks: [
                .text(HelpText("Every note is a normal text file (.txt) in the folder **Documents → Notes**. Every program can open it: TextEdit on the Mac, Notepad on Windows, any editor on Linux or a phone.",
                               de: "Jede Notiz ist eine ganz normale Textdatei (.txt) im Ordner **Dokumente → Notizen**. Jedes Programm kann sie öffnen: TextEdit auf dem Mac, der Editor unter Windows, jeder Editor unter Linux oder auf dem Handy.")),
                .text(HelpText("New notes are stored as UTF-8. Files that come from somewhere else keep their encoding and line endings – a Windows file stays a Windows file.",
                               de: "Neue Notizen werden als UTF-8 gespeichert. Dateien von woanders behalten ihre Kodierung und ihre Zeilenenden – eine Windows-Datei bleibt eine Windows-Datei.")),
                .tip(HelpText("To have your notes on several computers, choose a folder in iCloud Drive or Dropbox: NotizEditor → Settings → General → Notes folder.",
                              de: "Um deine Notizen auf mehreren Rechnern zu haben, wähle einen Ordner in iCloud Drive oder Dropbox: NotizEditor → Einstellungen → Allgemein → Notizen-Ordner.")),
                .text(HelpText("You can also open any other text file: **File → Open …** (⌘O), drag it on the NotizEditor icon in the Dock, or right-click it in the Finder → **Open With → NotizEditor**. It then appears under **Other Files**.",
                               de: "Du kannst auch jede andere Textdatei öffnen: **Ablage → Öffnen …** (⌘O), auf das NotizEditor-Symbol im Dock ziehen, oder im Finder Rechtsklick → **Öffnen mit → NotizEditor**. Sie erscheint dann unter **Andere Dateien**.")),
            ]),
        HelpTopic(
            id: "find", icon: "magnifyingglass",
            title: HelpText("Find and replace", de: "Suchen und Ersetzen"),
            summary: HelpText("In one note – or in all of them", de: "In einer Notiz – oder in allen"),
            blocks: [
                .steps([
                    HelpText("**⌘F** opens the find bar above the text. All matches are marked in yellow.",
                             de: "**⌘F** öffnet die Suchleiste über dem Text. Alle Treffer werden gelb markiert."),
                    HelpText("**Return** or **⌘G** jumps to the next match, **⇧⌘G** to the previous one.",
                             de: "**Return** oder **⌘G** springt zum nächsten Treffer, **⇧⌘G** zum vorherigen."),
                    HelpText("**⌥⌘F** (or the little arrow) shows the replace field. **Replace All** works as one step – ⌘Z undoes it.",
                             de: "**⌥⌘F** (oder der kleine Pfeil) zeigt das Ersetzen-Feld. **Alle ersetzen** ist ein einziger Schritt – ⌘Z macht ihn rückgängig."),
                ]),
                .keys([
                    ("Aa", HelpText("Ignore upper and lower case", de: "Groß-/Kleinschreibung egal")),
                    ("W", HelpText("Only whole words", de: "Nur ganze Wörter")),
                    (".*", HelpText("Regular expression – in the replacement, $1 is the first group", de: "Regulärer Ausdruck – beim Ersetzen ist $1 die erste Gruppe")),
                ]),
                .tip(HelpText("To search all notes, use the search field at the top of the list. Click a hit and the word is marked in the note.",
                              de: "Um alle Notizen zu durchsuchen, nimm das Suchfeld oben in der Liste. Klick auf einen Treffer, und das Wort wird in der Notiz markiert.")),
            ]),
        HelpTopic(
            id: "multi", icon: "character.cursor.ibeam",
            title: HelpText("Several cursors at once", de: "Mehrere Cursor gleichzeitig"),
            summary: HelpText("Change many places in one go", de: "Viele Stellen auf einmal ändern"),
            blocks: [
                .keys([
                    ("⌘-Klick", HelpText("Adds another insertion point (click it again to remove it)", de: "Fügt eine weitere Einfügemarke hinzu (nochmal klicken entfernt sie)")),
                    ("⌥-Ziehen", HelpText("Selects a rectangle (column selection)", de: "Wählt ein Rechteck aus (Spaltenauswahl)")),
                    ("⌘D", HelpText("Selects the word, then each next occurrence in addition", de: "Wählt das Wort aus, dann zusätzlich jedes nächste Vorkommen")),
                    ("⌃⌘G", HelpText("Selects all occurrences", de: "Wählt alle Vorkommen aus")),
                    ("⇧⌘L", HelpText("One cursor at the end of every selected line", de: "Ein Cursor am Ende jeder ausgewählten Zeile")),
                    ("esc", HelpText("Back to one cursor", de: "Zurück zu einem Cursor")),
                ]),
                .text(HelpText("Everything you type, delete or paste then happens at every cursor. The status bar shows how many there are.",
                               de: "Alles, was du tippst, löschst oder einfügst, passiert dann an jedem Cursor. Die Statusleiste zeigt, wie viele es sind.")),
            ]),
        HelpTopic(
            id: "text", icon: "text.alignleft",
            title: HelpText("Working with lines", de: "Mit Zeilen arbeiten"),
            summary: HelpText("The Text menu", de: "Das Menü Text"),
            blocks: [
                .keys([
                    ("⌘] / ⌘[", HelpText("Indent / outdent the selected lines (also Tab / ⇧Tab)", de: "Ausgewählte Zeilen ein-/ausrücken (auch Tab / ⇧Tab)")),
                    ("⌘/", HelpText("Comment out / in (for code)", de: "Aus-/einkommentieren (für Code)")),
                    ("⇧⌘D", HelpText("Duplicate line", de: "Zeile duplizieren")),
                    ("⇧⌘K", HelpText("Delete line", de: "Zeile löschen")),
                    ("⌥⌘↑ / ⌥⌘↓", HelpText("Move line up / down", de: "Zeile nach oben / unten schieben")),
                    ("⌃⌘J", HelpText("Join lines", de: "Zeilen verbinden")),
                    ("⌘L", HelpText("Go to line", de: "Gehe zu Zeile")),
                    ("⌥⌘I", HelpText("Character info: Unicode name and code", de: "Zeichen-Info: Unicode-Name und -Code")),
                ]),
                .text(HelpText("Also in the Text menu: upper/lower case, sort lines, remove duplicate or empty lines, trim trailing spaces, tabs ↔ spaces, Unicode normalization (NFC, NFD, NFKC, NFKD) and full-/half-width characters.",
                               de: "Außerdem im Menü Text: Groß-/Kleinschreibung, Zeilen sortieren, doppelte oder leere Zeilen entfernen, Leerzeichen am Zeilenende entfernen, Tabs ↔ Leerzeichen, Unicode-Normalisierung (NFC, NFD, NFKC, NFKD) und Voll-/Halbbreite.")),
                .tip(HelpText("Lists continue by themselves: after a line with “- ”, “* ” or “1. ” Return starts the next item. Return on an empty item ends the list.",
                              de: "Listen gehen von selbst weiter: Nach einer Zeile mit „- “, „* “ oder „1. “ beginnt Return den nächsten Punkt. Return auf einem leeren Punkt beendet die Liste.")),
            ]),
        HelpTopic(
            id: "code", icon: "chevron.left.forwardslash.chevron.right",
            title: HelpText("Code and colours", de: "Code und Farben"),
            summary: HelpText("Syntax highlighting and outline", de: "Farbige Hervorhebung und Gliederung"),
            blocks: [
                .text(HelpText("NotizEditor colours more than 30 languages – HTML, CSS, JavaScript, Swift, Python, PHP, JSON, Markdown, Shell, SQL, .htaccess and many more. The language is chosen by the file extension; change it at the bottom right or in **Format → Syntax**.",
                               de: "NotizEditor färbt mehr als 30 Sprachen ein – HTML, CSS, JavaScript, Swift, Python, PHP, JSON, Markdown, Shell, SQL, .htaccess und viele mehr. Die Sprache richtet sich nach der Dateiendung; ändern unten rechts oder unter **Format → Syntax**.")),
                .text(HelpText("The **Outline** button at the top right lists the headings (Markdown, HTML) or functions and classes (code) of the file – click one to jump there.",
                               de: "Der Knopf **Gliederung** oben rechts listet die Überschriften (Markdown, HTML) oder Funktionen und Klassen (Code) der Datei – ein Klick springt hin.")),
                .tip(HelpText("Colour schemes, font, line numbers, invisible characters and the page guide: **NotizEditor → Settings** and the **View** menu.",
                              de: "Farbschema, Schrift, Zeilennummern, unsichtbare Zeichen und Seitenführung: **NotizEditor → Einstellungen** und das Menü **Darstellung**.")),
            ]),
        HelpTopic(
            id: "encoding", icon: "textformat.abc",
            title: HelpText("Encodings and line endings", de: "Kodierung und Zeilenenden"),
            summary: HelpText("When umlauts look wrong", de: "Wenn Umlaute falsch aussehen"),
            blocks: [
                .text(HelpText("NotizEditor recognises the encoding of a file by itself (UTF-8, UTF-16, Windows-1252, ISO Latin 1, Mac Roman, Japanese, Chinese, Korean, Cyrillic …). The status bar shows it at the bottom right.",
                               de: "NotizEditor erkennt die Kodierung einer Datei selbst (UTF-8, UTF-16, Windows-1252, ISO Latin 1, Mac Roman, Japanisch, Chinesisch, Koreanisch, Kyrillisch …). Die Statusleiste zeigt sie unten rechts.")),
                .steps([
                    HelpText("**Umlauts look garbled** (like “GrÃ¼ÃŸe”)? Click the encoding at the bottom → **Reinterpret as** → try **Windows Latin 1** or **UTF-8**.",
                             de: "**Umlaute sehen kaputt aus** (z. B. „GrÃ¼ÃŸe“)? Unten auf die Kodierung klicken → **Neu interpretieren als** → **Westeuropäisch (Windows Latin 1)** oder **UTF-8** probieren."),
                    HelpText("**Store the file in another encoding:** choose it under **Save as** in the same menu.",
                             de: "**Datei in anderer Kodierung speichern:** im selben Menü unter **Speichern als** wählen."),
                    HelpText("**Line endings:** LF is macOS/Linux, CRLF is Windows. Both open fine everywhere today; CRLF only matters for very old Windows programs.",
                             de: "**Zeilenenden:** LF ist macOS/Linux, CRLF ist Windows. Beide öffnen heute überall problemlos; CRLF ist nur für sehr alte Windows-Programme wichtig."),
                ]),
                .note(HelpText("If a note contains characters its encoding can't store (an emoji in a Windows-1252 file), NotizEditor asks before saving and offers UTF-8.",
                               de: "Enthält eine Notiz Zeichen, die ihre Kodierung nicht speichern kann (ein Emoji in einer Windows-1252-Datei), fragt NotizEditor vor dem Speichern und bietet UTF-8 an.")),
            ]),
        HelpTopic(
            id: "terminal", icon: "terminal",
            title: HelpText("Command line and scripts", de: "Kommandozeile und Skripte"),
            summary: HelpText("For the Terminal and your own tools", de: "Für das Terminal und eigene Werkzeuge"),
            blocks: [
                .steps([
                    HelpText("**NotizEditor → Install Command Line Tool …** sets up the command **notizeditor** (asks for your Mac password once).",
                             de: "**NotizEditor → Kommandozeilen-Werkzeug installieren …** richtet den Befehl **notizeditor** ein (fragt einmal nach deinem Mac-Passwort)."),
                ]),
                .keys([
                    ("notizeditor datei.txt", HelpText("Opens the file (creates it if it doesn't exist)", de: "Öffnet die Datei (legt sie an, wenn es sie nicht gibt)")),
                    ("notizeditor --line 12 datei.txt", HelpText("Opens the file at line 12", de: "Öffnet die Datei in Zeile 12")),
                    ("ls | notizeditor", HelpText("Puts the text into a new note", de: "Legt den Text als neue Notiz an")),
                ]),
                .text(HelpText("**Scripts menu:** put your own scripts (zsh, Python, Ruby, …) into the scripts folder (Scripts → Open Scripts Folder). A script gets the selected text – or the whole note – as input; what it prints replaces the selection. Three examples are included.",
                               de: "**Menü Skripte:** Leg eigene Skripte (zsh, Python, Ruby, …) in den Skripte-Ordner (Skripte → Skripte-Ordner öffnen). Ein Skript bekommt den ausgewählten Text – oder die ganze Notiz – als Eingabe; was es ausgibt, ersetzt die Auswahl. Drei Beispiele sind dabei.")),
                .note(HelpText("Comment lines at the top of a script change that: “# input: selection | document | none” and “# output: replace-selection | replace-document | insert | new-note | none”.",
                               de: "Kommentarzeilen oben im Skript ändern das: „# input: selection | document | none“ und „# output: replace-selection | replace-document | insert | new-note | none“.")),
            ]),
        HelpTopic(
            id: "keys", icon: "keyboard",
            title: HelpText("Keyboard shortcuts", de: "Tastenkürzel"),
            summary: HelpText("The most important ones", de: "Die wichtigsten"),
            blocks: [
                .keys([
                    ("⌘N", HelpText("New note", de: "Neue Notiz")),
                    ("⇧⌘N", HelpText("New folder", de: "Neuer Ordner")),
                    ("⌘O", HelpText("Open another file", de: "Andere Datei öffnen")),
                    ("⌘F / ⌥⌘F", HelpText("Find / find and replace", de: "Suchen / Suchen und Ersetzen")),
                    ("⌘G / ⇧⌘G", HelpText("Next / previous match", de: "Nächster / vorheriger Treffer")),
                    ("⌘E", HelpText("Search for the selected text", de: "Nach dem ausgewählten Text suchen")),
                    ("⌘L", HelpText("Go to line", de: "Gehe zu Zeile")),
                    ("⌘+ / ⌘- / ⌘0", HelpText("Bigger / smaller / normal text size", de: "Schrift größer / kleiner / normal")),
                    ("⇧⌘I", HelpText("Show invisible characters", de: "Unsichtbare Zeichen zeigen")),
                    ("⌘P", HelpText("Print", de: "Drucken")),
                ]),
            ]),
    ]
}
