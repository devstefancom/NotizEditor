import AppKit

// Drives the real app (window, text view, sidebar model) in the background and checks the results.
// Built only by Tests/run-ui-test.sh (compiled with -D SELFTEST), started with a temporary notes folder.

@MainActor
enum SelfTest {
    private static var failures = 0
    private static var log: [String] = []

    private static func check(_ condition: Bool, _ message: String) {
        let line = (condition ? "✓ " : "✗ ") + message
        if !condition { failures += 1 }
        log.append(line)
        print(line)
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func file(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "<unlesbar>"
    }

    private static func type(_ textView: EditorTextView, _ text: String) {
        for character in text {
            if character == "\n" { textView.insertNewline(nil) } else {
                textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    static func run(_ model: AppModel) {
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { @MainActor in
            await wait(1.5)
            let root = model.root
            print("Notizen-Ordner: \(root.path)")

            // New note, rename
            model.newNote()
            await wait(0.5)
            let created = root.appendingPathComponent(L("New Note") + ".txt")
            check(FileManager.default.fileExists(atPath: created.path), "Neue Notiz als .txt angelegt")
            check(model.renaming == created.standardizedFileURL, "Neue Notiz wartet auf ihren Namen")
            model.rename(created.standardizedFileURL, to: "Einkauf")
            await wait(0.5)
            let note = root.appendingPathComponent("Einkauf.txt").standardizedFileURL
            check(FileManager.default.fileExists(atPath: note.path), "Umbenannt zu Einkauf.txt (Endung automatisch)")
            check(model.document?.url == note, "Umbenannte Notiz bleibt offen")

            guard let textView = model.textView else { check(false, "Textfeld vorhanden"); finish(); return }
            textView.window?.makeFirstResponder(textView)

            // Lists continue, an empty item ends the list
            type(textView, "Liste:\n- Milch\n")
            check(textView.string == "Liste:\n- Milch\n- ", "Liste wird fortgesetzt")
            type(textView, "Brot\n\n")
            check(textView.string == "Liste:\n- Milch\n- Brot\n", "Leerer Listenpunkt beendet die Liste")
            type(textView, "1. eins\n")
            check(textView.string.hasSuffix("1. eins\n2. "), "Nummerierte Liste zählt weiter")
            textView.selectAll(nil)
            textView.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))

            // Auto save in UTF-8
            type(textView, "Grüße ✓")
            await wait(1.6)
            check(file(note) == "Grüße ✓", "Automatisch gespeichert (UTF-8)")
            check(model.document?.isDirty == false, "Nach dem Speichern nichts mehr offen")

            // Several insertion points
            textView.selectAll(nil)
            textView.insertText("a\nb\nc", replacementRange: NSRange(location: NSNotFound, length: 0))
            textView.selectAll(nil)
            textView.splitSelectionIntoLines()
            check(textView.editRanges.count == 3, "Auswahl in Zeilen geteilt: 3 Cursor")
            type(textView, "!")
            check(textView.string == "a!\nb!\nc!", "Tippen an allen Cursorn")
            textView.deleteBackward(nil)
            check(textView.string == "a\nb\nc", "Löschen an allen Cursorn")
            textView.cancelOperation(nil)
            check(textView.editRanges.count == 1, "Esc: zurück zu einem Cursor")

            // Without real key presses all changes since opening are one undo step,
            // so the undo tests use freshly opened files.
            let multi = root.appendingPathComponent("Mehrfach.txt")
            try? "foo bar foo baz foo".write(to: multi, atomically: true, encoding: .utf8)
            model.openFiles([multi])
            await wait(0.3)
            textView.setSelectedRange(NSRange(location: 1, length: 0))
            textView.selectNextOccurrence()
            textView.selectNextOccurrence()
            textView.selectNextOccurrence()
            check(textView.editRanges.count == 3, "⌘D wählt alle drei „foo“ nacheinander")
            type(textView, "x")
            check(textView.string == "x bar x baz x", "Alle drei auf einmal überschrieben")
            model.document?.undoManager.undo()
            check(textView.string == "foo bar foo baz foo", "⌘Z macht es in einem Schritt rückgängig (\(textView.string.debugDescription))")

            // Find and replace with a regular expression
            let mail = root.appendingPathComponent("Mail.txt")
            try? "anna@x.de, bob@y.de".write(to: mail, atomically: true, encoding: .utf8)
            model.openFiles([mail])
            await wait(0.3)
            let find = model.find
            find.show(replace: true, focus: false)
            find.useRegex = true
            find.query = #"(\w+)@"#
            find.replacement = "$1 at "
            find.updateMatches(in: textView)
            check(find.matchCount == 2, "Suche findet 2 Treffer")
            find.replaceAll(in: textView)
            check(textView.string == "anna at x.de, bob at y.de", "Alle ersetzen mit $1")
            model.document?.undoManager.undo()
            check(textView.string == "anna@x.de, bob@y.de", "Alle ersetzen ist ein Rückgängig-Schritt")
            find.hide(in: textView)

            // Line commands
            model.selection = note
            await wait(0.3)
            textView.selectAll(nil)
            textView.insertText("eins\nzwei\ndrei", replacementRange: NSRange(location: NSNotFound, length: 0))
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.moveLines(up: false)
            check(textView.string == "zwei\neins\ndrei", "Zeile nach unten verschoben")
            textView.duplicateLines()
            check(textView.string == "zwei\neins\neins\ndrei", "Zeile dupliziert")
            textView.deleteLines()
            check(textView.string == "zwei\neins\ndrei", "Zeile gelöscht")
            textView.apply(.sortLines)
            check(textView.string == "drei\neins\nzwei", "Zeilen sortiert")
            textView.selectAll(nil)
            textView.shiftLines(outdent: false)
            check(textView.string == "\tdrei\n\teins\n\tzwei", "Eingerückt (Tab)")
            textView.shiftLines(outdent: true)
            check(textView.string == "drei\neins\nzwei", "Ausgerückt")
            await wait(1.6)

            // A Windows file keeps encoding and line endings
            let windows = root.appendingPathComponent("Windows.txt")
            try? Data("Grüße\r\nZeile".data(using: .windowsCP1252)!).write(to: windows)
            model.openFiles([windows])
            await wait(0.5)
            check(model.document?.encoding == .windowsCP1252 && model.document?.lineEnding == .crlf, "Windows-Datei erkannt (1252, CRLF)")
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            type(textView, "\nNeu ä")
            model.document?.save()
            let bytes = (try? Data(contentsOf: windows)) ?? Data()
            check(bytes == "Grüße\r\nZeile\r\nNeu ä".data(using: .windowsCP1252)!, "Windows-Datei bleibt Windows-1252 mit CRLF")
            type(textView, " 😀")
            check(model.document?.encoding == .windowsCP1252, "Emoji: Kodierung erst nach Rückfrage ändern")
            model.document?.convert(to: .utf8)
            check(model.document?.encoding == .utf8 && file(windows).hasSuffix("😀"), "Nach UTF-8 umgewandelt und gespeichert")

            // Swift file: comment, colours, outline
            let swift = root.appendingPathComponent("Code.swift")
            try? "struct A {\n    func b() {}\n}\n".write(to: swift, atomically: true, encoding: .utf8)
            model.reloadTree()
            model.selection = swift.standardizedFileURL
            await wait(0.5)
            check(model.document?.syntax.id == "swift", "Swift erkannt")
            check(model.outline.map(\.title) == ["A", "b"], "Gliederung: A, b")
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.toggleComment()
            check(textView.string.hasPrefix("// struct A {"), "Auskommentiert mit //")
            textView.toggleComment()
            check(textView.string.hasPrefix("struct A {"), "Kommentar entfernt")
            textView.setSelectedRange(NSRange(location: 10, length: 0))   // after "{"
            textView.insertNewline(nil)
            check(textView.string.hasPrefix("struct A {\n" + AppSettings.shared.indentUnit + "\n"), "Einrückung nach {")

            // Folders: create, move a note in, the open note follows
            model.selection = note
            await wait(0.3)
            model.newFolder(in: root)
            await wait(0.3)
            let folderTemp = root.appendingPathComponent(L("New Folder")).standardizedFileURL
            model.rename(folderTemp, to: "Archiv")
            let folder = root.appendingPathComponent("Archiv").standardizedFileURL
            check(AppModel.isFolder(folder), "Ordner angelegt und umbenannt")
            model.selection = note
            await wait(0.3)
            model.drop([note], into: folder)
            let moved = folder.appendingPathComponent("Einkauf.txt").standardizedFileURL
            check(FileManager.default.fileExists(atPath: moved.path), "Notiz in den Ordner verschoben")
            check(model.document?.url == moved && model.selection == moved, "Offene Notiz folgt dem Verschieben")
            check(model.node(for: folder)?.noteCount == 1, "Ordner zählt 1 Notiz")

            // Search across notes
            model.search = "Zeile"
            await wait(0.8)
            check(model.searchResults.contains { $0.url.lastPathComponent == "Windows.txt" }, "Suche in allen Notizen findet Windows.txt")
            model.search = ""

            // Command line: piped text becomes a new note
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-pipe.txt")
            try? "aus dem Terminal".write(to: temporary, atomically: true, encoding: .utf8)
            let hex = Data(temporary.path.utf8).map { String(format: "%02x", $0) }.joined()
            model.handle(URL(string: "notizeditor://new?path=\(hex)")!)
            await wait(0.5)
            check(model.document?.text == "aus dem Terminal" && model.document?.url.lastPathComponent.hasPrefix(L("Terminal")) == true,
                  "notizeditor: Text aus dem Terminal als neue Notiz")

            finish()
        }
    }

    private static func finish() {
        print(failures == 0 ? "\nAlle Oberflächen-Tests bestanden." : "\n\(failures) Oberflächen-Test(s) fehlgeschlagen.")
        let report = (log + [failures == 0 ? "OK" : "FAILED"]).joined(separator: "\n")
        try? report.write(toFile: ProcessInfo.processInfo.environment["SELFTEST_REPORT"] ?? "/tmp/notizeditor-selftest.txt",
                          atomically: true, encoding: .utf8)
        if ProcessInfo.processInfo.environment["SELFTEST_KEEP_OPEN"] == nil { NSApp.terminate(nil) }
    }
}
