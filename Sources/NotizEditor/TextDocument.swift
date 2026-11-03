import AppKit

/// One open text file. Changes are saved automatically a moment after you stop typing, when you switch to
/// another note and when NotizEditor quits – in the file's own encoding and line endings.
@MainActor
final class TextDocument: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var url: URL
    let storage = NSTextStorage()
    let undoManager = UndoManager()
    @Published var encoding: String.Encoding
    @Published var hasBOM: Bool
    @Published var lineEnding: LineEnding
    @Published var mixedLineEndings: Bool
    @Published var syntax: Syntax
    @Published private(set) var isDirty = false
    @Published var isVertical = false
    @Published var rightToLeft = false
    /// Where you were, restored when you come back to this note.
    var selection: [NSRange] = [NSRange(location: 0, length: 0)]
    var scrollPosition: NSPoint = .zero
    private(set) var fileDate: Date?
    private var saveTimer: Timer?

    static let maximumSize = 64 * 1024 * 1024

    init(url: URL) throws {
        self.url = url
        let decoded = try Self.read(url)
        encoding = decoded.encoding
        hasBOM = decoded.hasBOM
        lineEnding = decoded.lineEnding
        mixedLineEndings = decoded.mixedLineEndings
        syntax = Syntax.detect(fileName: url.lastPathComponent)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: decoded.string)
        fileDate = Self.modificationDate(url)
    }

    var name: String { url.lastPathComponent }
    var text: String { storage.string }

    private static func read(_ url: URL, encoding: String.Encoding? = nil) throws -> DecodedText {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maximumSize { throw DocumentError.tooLarge }
        let data = try Data(contentsOf: url)
        return try TextFile.decode(data, encoding: encoding, defaultLineEnding: AppSettings.shared.defaultLineEnding)
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    var changedOnDisk: Bool {
        guard let date = Self.modificationDate(url) else { return false }
        return date != fileDate
    }

    var existsOnDisk: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Reads the file again – after a change outside NotizEditor, or in another encoding ("Reinterpret as").
    func reload(encoding forced: String.Encoding? = nil) throws {
        let decoded = try Self.read(url, encoding: forced)
        encoding = decoded.encoding
        hasBOM = decoded.hasBOM
        lineEnding = decoded.lineEnding
        mixedLineEndings = decoded.mixedLineEndings
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: decoded.string)
        undoManager.removeAllActions()
        fileDate = Self.modificationDate(url)
        saveTimer?.invalidate()
        isDirty = false
    }

    func textDidChange() {
        isDirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.save() }
        }
    }

    /// The file was renamed or moved in NotizEditor.
    func moved(to newURL: URL) {
        let keepSyntax = syntax != Syntax.detect(fileName: url.lastPathComponent)
        url = newURL
        if !keepSyntax { syntax = Syntax.detect(fileName: newURL.lastPathComponent) }
    }

    /// Writes the file if there are changes. Returns false if it couldn't (the reason was shown).
    @discardableResult
    func save(force: Bool = false) -> Bool {
        saveTimer?.invalidate()
        guard isDirty || force else { return true }
        guard existsOnDisk || force else {
            // Deleted or moved away outside NotizEditor: don't bring it back silently.
            isDirty = false
            return true
        }
        guard var data = TextFile.encode(text, encoding: encoding, hasBOM: hasBOM, lineEnding: lineEnding) else {
            return saveWithUnsupportedCharacters()
        }
        if data.isEmpty, hasBOM { data = Data(TextEncodings.bom(encoding)) }
        do {
            let permissions = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
            try data.write(to: url, options: .atomic)
            if let permissions { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
            fileDate = Self.modificationDate(url)
            isDirty = false
            mixedLineEndings = false
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = L("“%@” couldn't be saved.", name)
            alert.runModal()
            return false
        }
    }

    /// The text has characters the file's encoding can't hold (an emoji in a Windows-1252 file, for example).
    private func saveWithUnsupportedCharacters() -> Bool {
        let characters = TextFile.unsupportedCharacters(in: text, encoding: encoding).map(String.init).joined(separator: " ")
        let alert = NSAlert()
        alert.messageText = L("“%@” contains characters that %@ can't store.", name, TextEncodings.name(encoding))
        alert.informativeText = L("Characters: %@\n\nSave the note as UTF-8 instead? UTF-8 can store every character and opens everywhere.", characters)
        alert.addButton(withTitle: L("Save as UTF-8"))
        alert.addButton(withTitle: L("Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            saveTimer?.invalidate()
            return false
        }
        encoding = .utf8
        return save(force: true)
    }

    /// Format → Encoding: saves the same text in another encoding.
    func convert(to newEncoding: String.Encoding) {
        guard newEncoding != encoding else { return }
        if TextFile.encode(text, encoding: newEncoding, hasBOM: false, lineEnding: lineEnding) == nil {
            let alert = NSAlert()
            alert.messageText = L("Some characters can't be stored in %@.", TextEncodings.name(newEncoding))
            alert.informativeText = L("Characters: %@", TextFile.unsupportedCharacters(in: text, encoding: newEncoding)
                .map(String.init).joined(separator: " "))
            alert.runModal()
            return
        }
        encoding = newEncoding
        if !TextEncodings.supportsBOM(newEncoding) { hasBOM = false }
        isDirty = true
        save()
    }

    func setLineEnding(_ ending: LineEnding) {
        guard ending != lineEnding || mixedLineEndings else { return }
        lineEnding = ending
        isDirty = true
        save()
    }

    func setBOM(_ bom: Bool) {
        guard bom != hasBOM, TextEncodings.supportsBOM(encoding) else { return }
        hasBOM = bom
        isDirty = true
        save()
    }
}

enum DocumentError: LocalizedError {
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .tooLarge: L("The file is larger than 64 MB.")
        }
    }
}
