import Foundation

// Tests for the parts without a window: reading/writing files, line endings, colours, outline, text commands.
// Run with Tests/run-tests.sh.

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() { print("✓ \(message)") } else { failures += 1; print("✗ \(message) (Zeile \(line))") }
}

@main
enum CoreTests {
    static func main() throws {
        // Encodings and line endings
        let windows = Data("Grüße\r\naus\r\nHamburg\r\n".data(using: .windowsCP1252)!)
        let decoded = try TextFile.decode(windows)
        check(decoded.encoding == .windowsCP1252, "Windows-1252 erkannt")
        check(decoded.lineEnding == .crlf && !decoded.mixedLineEndings, "CRLF erkannt")
        check(decoded.string == "Grüße\naus\nHamburg\n", "Zeilenenden intern als LF")
        let back = TextFile.encode(decoded.string, encoding: decoded.encoding, hasBOM: false, lineEnding: decoded.lineEnding)
        check(back == windows, "Windows-Datei wird Byte für Byte gleich gespeichert")

        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("Hallo\nWelt".utf8)
        let withBOM = try TextFile.decode(bom)
        check(withBOM.encoding == .utf8 && withBOM.hasBOM && withBOM.string == "Hallo\nWelt", "UTF-8 mit BOM")
        check(TextFile.encode(withBOM.string, encoding: .utf8, hasBOM: true, lineEnding: .lf) == bom, "BOM bleibt erhalten")

        let utf16 = "Notiz ✓\n".data(using: .utf16LittleEndian)!
        check((try? TextFile.decode(utf16))?.encoding == .utf16LittleEndian, "UTF-16 LE ohne BOM erkannt")
        let utf16BOM = Data([0xFF, 0xFE]) + utf16
        let decoded16 = try TextFile.decode(utf16BOM)
        check(decoded16.encoding == .utf16LittleEndian && decoded16.hasBOM && decoded16.string == "Notiz ✓\n", "UTF-16 LE mit BOM")

        check((try? TextFile.decode(Data("€ ✓ 😀".utf8)))?.encoding == .utf8, "UTF-8 erkannt")
        check((try? TextFile.decode(Data()))?.encoding == .utf8, "Leere Datei ist UTF-8")
        do {
            _ = try TextFile.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x01, 0x02]))
            check(false, "Binärdatei wird abgelehnt")
        } catch TextFile.Failure.binary { check(true, "Binärdatei wird abgelehnt") }

        let mixed = LineEnding.detect(in: "a\r\nb\nc\r\nd")
        check(mixed.ending == .crlf && mixed.mixed, "Gemischte Zeilenenden erkannt")
        check(LineEnding.detect(in: "a\rb\rc").ending == .cr, "CR erkannt")
        check(TextFile.encode("€", encoding: .ascii, hasBOM: false, lineEnding: .lf) == nil, "Nicht darstellbare Zeichen werden gemeldet")
        check(TextFile.unsupportedCharacters(in: "a€b✓", encoding: .windowsCP1252) == ["✓"], "Nicht darstellbare Zeichen werden genannt")

        // Language detection and colours
        check(Syntax.detect(fileName: "index.HTML").id == "html", "HTML an der Endung erkannt")
        check(Syntax.detect(fileName: ".htaccess").id == "apache", ".htaccess erkannt")
        check(Syntax.detect(fileName: "Makefile").id == "makefile", "Makefile am Namen erkannt")
        check(Syntax.detect(fileName: "Einkauf.txt").id == "plain", "Text bleibt Text")

        let swift = "let url = \"http://x // y\" // Kommentar\nfunc go() { return 42 }" as NSString
        let tokens = Highlighter(syntax: Syntax.named("swift")!).tokens(in: swift)
        func kind(of word: String) -> TokenKind? {
            let range = swift.range(of: word)
            return tokens.last { NSIntersectionRange($0.range, range).length == range.length }?.kind
        }
        check(kind(of: "let") == .keyword, "Swift: Schlüsselwort")
        check(kind(of: "\"http://x // y\"") == .string, "Swift: // im String ist kein Kommentar")
        check(kind(of: "// Kommentar") == .comment, "Swift: Kommentar")
        check(kind(of: "42") == .number, "Swift: Zahl")

        let json = "{\"name\": \"Wert\", \"an\": true}" as NSString
        let jsonTokens = Highlighter(syntax: Syntax.named("json")!).tokens(in: json)
        check(jsonTokens.contains { $0.kind == .variable && json.substring(with: $0.range) == "\"name\"" }, "JSON: Schlüssel")
        check(jsonTokens.contains { $0.kind == .string && json.substring(with: $0.range) == "\"Wert\"" }, "JSON: Wert")

        let shell = "echo $# # Kommentar" as NSString
        let shellComments = Highlighter(syntax: Syntax.named("shell")!).tokens(in: shell).filter { $0.kind == .comment }
        check(shellComments.count == 1 && shell.substring(with: shellComments[0].range) == "# Kommentar", "Shell: $# ist kein Kommentar")

        // Outline
        let markdown = "# Titel\nText\n## Teil eins\n```\n# kein Titel\n```\n### Unterpunkt\n" as NSString
        let outline = Highlighter(syntax: Syntax.named("markdown")!).outline(in: markdown)
        check(outline.map(\.title).prefix(2) == ["Titel", "Teil eins"], "Markdown-Gliederung")
        check(outline.first { $0.title == "Unterpunkt" }?.level == 2, "Markdown-Ebenen")
        let swiftOutline = Highlighter(syntax: Syntax.named("swift")!).outline(in: "// MARK: - Laden\nstruct A {\n    func b() {}\n}" as NSString)
        check(swiftOutline.map(\.title) == ["Laden", "A", "b"] && swiftOutline[2].level == 1, "Swift-Gliederung")

        // Text commands
        check(TextTransform.sortLines.apply("b\nä\na\n") == "a\nä\nb\n", "Zeilen sortieren (mit Umlauten)")
        check(TextTransform.removeDuplicateLines.apply("a\nb\na") == "a\nb", "Doppelte Zeilen entfernen")
        check(TextTransform.trimTrailingWhitespace.apply("a  \nb\t\n") == "a\nb\n", "Leerzeichen am Zeilenende")
        check(TextTransform.tabsToSpaces.apply("\tx\ty", tabWidth: 4) == "    x   y", "Tabs zu Leerzeichen")
        check(TextTransform.spacesToTabs.apply("      x", tabWidth: 4) == "\t  x", "Leerzeichen zu Tabs")
        check(TextTransform.nfd.apply("ä").unicodeScalars.count == 2 && TextTransform.nfc.apply("a\u{308}").unicodeScalars.count == 1,
              "Unicode-Normalisierung")
        check(TextTransform.fullwidthToHalfwidth.apply("ＡＢＣ１") == "ABC1", "Vollbreite zu Halbbreite")
        check(TextTransform.straightenQuotes.apply("„Hallo“ ‚du‘") == "\"Hallo\" 'du'", "Typografische Anführungszeichen")
        check(TextEditing.shift("a\n  b\n", outdent: false, indentUnit: "    ", tabWidth: 4) == "    a\n      b\n", "Einrücken")
        check(TextEditing.shift("    a\n\tb", outdent: true, indentUnit: "    ", tabWidth: 4) == "a\nb", "Ausrücken")
        let commented = TextEditing.toggleLineComment("  a\n    b\n", marker: "//")
        check(commented == "  // a\n  //   b\n", "Auskommentieren")
        check(TextEditing.toggleLineComment(commented, marker: "//") == "  a\n    b\n", "Kommentar entfernen")
        check(TextEditing.toggleBlockComment("x", start: "/*", end: "*/") == "/* x */"
              && TextEditing.toggleBlockComment("/* x */", start: "/*", end: "*/") == "x", "Block-Kommentar")
        check(TextEditing.wordCount("Hallo Welt, wie geht's?") == 4, "Wörter zählen")
        let info = CharacterInfo("é")
        check(info.scalars.first?.code == "U+00E9" && info.utf8 == "C3 A9", "Zeichen-Info")

        print(failures == 0 ? "\nAlle Tests bestanden." : "\n\(failures) Test(s) fehlgeschlagen.")
        exit(failures == 0 ? 0 : 1)
    }
}
