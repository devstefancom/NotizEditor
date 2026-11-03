import AppKit
import SwiftUI

/// What the status bar shows; separate from AppModel so typing doesn't redraw the whole window.
@MainActor
final class EditorStatus: ObservableObject {
    @Published var line = 1
    @Published var column = 1
    @Published var characters = 0
    @Published var words = 0
    @Published var lines = 1
    @Published var selectedCharacters = 0
    @Published var selectedLines = 0
    @Published var editPoints = 1
}

@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings.shared
    let find = FindModel()
    let status = EditorStatus()
    @Published private(set) var root: URL
    @Published private(set) var tree: [FileNode] = []
    @Published var expanded: Set<URL> = [] { didSet { settings.expandedFolders = expanded.map(\.path).sorted() } }
    @Published var selection: URL? { didSet { if selection != oldValue, !relocating { selectionChanged() } } }
    @Published private(set) var document: TextDocument?
    @Published private(set) var openError: String?
    @Published var renaming: URL?
    @Published var search = "" { didSet { scheduleSearch() } }
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var otherFiles: [URL] = []
    @Published var outline: [OutlineItem] = []
    @Published var showGoToLine = false
    @Published private(set) var scripts: [URL] = []
    weak var textView: EditorTextView?
    /// A line to jump to once the note is shown (command line "--line").
    var pendingLine: Int?
    private var documents: [URL: TextDocument] = [:]
    private var watcher: FolderWatcher?
    private var searchTask: Task<Void, Never>?
    private var relocating = false

    init() {
        root = URL(fileURLWithPath: AppSettings.shared.notesFolder, isDirectory: true).standardizedFileURL
        expanded = Set(settings.expandedFolders.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL })
        otherFiles = settings.otherFiles.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        prepareRoot()
        scripts = Scripts.list()
        let last = URL(fileURLWithPath: settings.lastOpened)
        if !settings.lastOpened.isEmpty, FileManager.default.fileExists(atPath: last.path) { selection = last.standardizedFileURL }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.checkExternalChanges()
                self?.scripts = Scripts.list()
            }
        }
    }

    // MARK: - Notes folder

    private func prepareRoot() {
        let fileManager = FileManager.default
        var isFolder: ObjCBool = false
        if !fileManager.fileExists(atPath: root.path, isDirectory: &isFolder) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let welcome = root.appendingPathComponent(L("Welcome") + ".txt")
            if let data = TextFile.encode(L("WELCOME_NOTE"), encoding: .utf8, hasBOM: false, lineEnding: settings.defaultLineEnding) {
                try? data.write(to: welcome)
                if settings.lastOpened.isEmpty { settings.lastOpened = welcome.standardizedFileURL.path }
            }
        }
        watcher = FolderWatcher(root) { [weak self] in
            Task { @MainActor in
                self?.reloadTree()
                self?.checkExternalChanges()
            }
        }
        reloadTree()
    }

    func chooseNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Choose")
        panel.message = L("Choose the folder for your notes.")
        panel.directoryURL = root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveAll()
        settings.notesFolder = url.path
        root = url.standardizedFileURL
        selection = nil
        prepareRoot()
    }

    func reloadTree() {
        tree = FileNode.load(root, sortByDate: settings.sortByDate)
        if !search.isEmpty { scheduleSearch() }
    }

    func isInsideRoot(_ url: URL) -> Bool { url.standardizedFileURL.path.hasPrefix(root.path + "/") }

    nonisolated static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Where a new note goes: the selected folder, the folder of the selected note, else the notes folder.
    var targetFolder: URL {
        guard let selection, isInsideRoot(selection) else { return root }
        return Self.isFolder(selection) ? selection : selection.deletingLastPathComponent()
    }

    // MARK: - Opening

    private func selectionChanged() {
        guard let selection else {
            showDocument(nil)
            return
        }
        if Self.isFolder(selection) {
            showDocument(nil)
            return
        }
        open(selection)
    }

    private func showDocument(_ document: TextDocument?, error: String? = nil) {
        if self.document !== document { self.document?.save() }
        self.document = document
        openError = error
        outline = []
    }

    private func open(_ url: URL) {
        if let cached = documents[url] {
            if cached.changedOnDisk, !cached.isDirty { try? cached.reload() }
            showDocument(cached)
            settings.lastOpened = url.path
            return
        }
        do {
            let document = try TextDocument(url: url)
            documents[url] = document
            showDocument(document)
            settings.lastOpened = url.path
        } catch TextFile.Failure.binary {
            showDocument(nil, error: L("“%@” is not a text file.", url.lastPathComponent))
        } catch TextFile.Failure.undecodable {
            showDocument(nil, error: L("“%@” couldn't be read as text.", url.lastPathComponent))
        } catch {
            showDocument(nil, error: error.localizedDescription)
        }
    }

    /// Files from the Finder, the Dock, "Open …" or the command line.
    func openFiles(_ urls: [URL]) {
        for url in urls.map(\.standardizedFileURL) {
            if Self.isFolder(url) { continue }
            if isInsideRoot(url) {
                var folder = url.deletingLastPathComponent()
                while folder.path.count > root.path.count {
                    expanded.insert(folder)
                    folder = folder.deletingLastPathComponent()
                }
            } else if !otherFiles.contains(url) {
                otherFiles.insert(url, at: 0)
                settings.otherFiles = otherFiles.map(\.path)
            }
            selection = url
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openFiles(panel.urls)
    }

    func closeOtherFile(_ url: URL) {
        documents[url]?.save()
        documents[url] = nil
        otherFiles.removeAll { $0 == url }
        settings.otherFiles = otherFiles.map(\.path)
        if selection == url { selection = nil }
    }

    /// notizeditor://open?path=<hex>&line=<n> and notizeditor://new?path=<hex> from the command line tool.
    func handle(_ url: URL) {
        guard url.scheme == "notizeditor", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let hex = items["path"], let path = Self.decodeHex(hex) else { return }
        let file = URL(fileURLWithPath: path)
        switch url.host {
        case "open":
            if let line = items["line"].flatMap(Int.init) { pendingLine = line }
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: Data())   // like "cot new.txt"
            }
            openFiles([file])
            if let line = pendingLine, document?.url == file.standardizedFileURL, let textView {
                pendingLine = nil
                textView.goToLine(line)
            }
        case "new":
            let data = (try? Data(contentsOf: file)) ?? Data()
            try? FileManager.default.removeItem(at: file)
            let text = (try? TextFile.decode(data).string) ?? ""
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm"
            newNote(in: root, content: text, name: L("Terminal") + " " + formatter.string(from: Date()))
        default:
            break
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func decodeHex(_ hex: String) -> String? {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    // MARK: - Saving

    func saveAll() {
        for document in documents.values { document.save() }
    }

    /// The file was changed by another program (or deleted) while it is open.
    func checkExternalChanges() {
        guard let document else { return }
        if !document.existsOnDisk {
            documents[document.url] = nil
            otherFiles.removeAll { $0 == document.url }
            selection = nil
            return
        }
        guard document.changedOnDisk else { return }
        if !document.isDirty {
            reloadDocument(document)
            return
        }
        let alert = NSAlert()
        alert.messageText = L("“%@” was changed by another program.", document.name)
        alert.informativeText = L("Do you want to keep your version or load the changed file?")
        alert.addButton(withTitle: L("Keep My Version"))
        alert.addButton(withTitle: L("Load Changed File"))
        if alert.runModal() == .alertFirstButtonReturn {
            document.save(force: true)
        } else {
            reloadDocument(document)
        }
    }

    func reloadDocument(_ document: TextDocument, encoding: String.Encoding? = nil) {
        let selection = textView?.selectedRange()
        do {
            try document.reload(encoding: encoding)
        } catch {
            let alert = NSAlert()
            alert.messageText = encoding.map { L("The file can't be read as %@.", TextEncodings.name($0)) } ?? L("The file couldn't be read.")
            alert.runModal()
            return
        }
        NotificationCenter.default.post(name: .documentReloaded, object: document)
        if let selection, let textView, NSMaxRange(selection) <= (textView.string as NSString).length {
            textView.setSelectedRange(selection)
        }
    }

    /// Format → Reinterpret as: reads the file again in another encoding (for files that look garbled).
    func reinterpret(as encoding: String.Encoding) {
        guard let document else { return }
        if document.isDirty {
            let alert = NSAlert()
            alert.messageText = L("Reinterpreting reads the file again from the disk.")
            alert.informativeText = L("Changes that aren't saved yet are lost.")
            alert.addButton(withTitle: L("Reinterpret"))
            alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        reloadDocument(document, encoding: encoding)
    }

    // MARK: - Files and folders

    private func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate.standardizedFileURL
    }

    func newNote(in folder: URL? = nil, content: String = "", name: String? = nil) {
        let folder = folder ?? targetFolder
        let url = uniqueURL(in: folder, name: (name ?? L("New Note")) + ".txt")
        let data = TextFile.encode(content, encoding: .utf8, hasBOM: false, lineEnding: settings.defaultLineEnding) ?? Data()
        do {
            try data.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        if folder != root { expanded.insert(folder) }
        search = ""
        reloadTree()
        selection = url
        if name == nil { renaming = url }
    }

    func newFolder(in folder: URL? = nil) {
        let folder = folder ?? targetFolder
        let url = uniqueURL(in: folder, name: L("New Folder"))
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        if folder != root { expanded.insert(folder) }
        search = ""
        reloadTree()
        selection = url
        renaming = url
    }

    private static let textExtensions: Set<String> = Set(Syntax.all.flatMap(\.extensions)).union(["txt", "text"])

    func rename(_ url: URL, to newName: String) {
        renaming = nil
        var name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty, !name.hasPrefix(".") || url.lastPathComponent.hasPrefix(".") else { return }
        if !Self.isFolder(url), url.pathExtension.lowercased() == "txt",
           !Self.textExtensions.contains((name as NSString).pathExtension.lowercased()) {
            name += ".txt"   // the extension of notes isn't shown, so it isn't typed either
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        guard target != url else { return }
        let onlyCase = target.path.lowercased() == url.path.lowercased()
        if FileManager.default.fileExists(atPath: target.path), !onlyCase {
            let alert = NSAlert()
            alert.messageText = L("The name “%@” is already taken.", name)
            alert.informativeText = L("Please choose a different name.")
            alert.runModal()
            return
        }
        move(url, to: target)
    }

    @discardableResult
    private func move(_ url: URL, to target: URL) -> Bool {
        for (key, document) in documents where key == url || key.path.hasPrefix(url.path + "/") { document.save() }
        do {
            if target.path.lowercased() == url.path.lowercased() {
                // Only upper/lower case changes: the Mac's file system sees the same name, so go via a temporary one.
                let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
                try FileManager.default.moveItem(at: url, to: temporary)
                try FileManager.default.moveItem(at: temporary, to: target)
            } else {
                try FileManager.default.moveItem(at: url, to: target)
            }
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
        relocate(from: url, to: target)
        reloadTree()
        return true
    }

    /// Open notes, the selection and the open folders follow a renamed or moved file or folder.
    private func relocate(from old: URL, to new: URL) {
        func mapped(_ url: URL) -> URL {
            if url == old { return new }
            if url.path.hasPrefix(old.path + "/") { return URL(fileURLWithPath: new.path + url.path.dropFirst(old.path.count)) }
            return url
        }
        var moved: [URL: TextDocument] = [:]
        for (url, document) in documents {
            let target = mapped(url)
            if target != url { document.moved(to: target) }
            moved[target] = document
        }
        documents = moved
        expanded = Set(expanded.map(mapped))
        relocating = true
        selection = selection.map(mapped)
        relocating = false
        if settings.lastOpened == old.path { settings.lastOpened = new.path }
    }

    /// Drag and drop in the sidebar: moves notes within the notes folder, copies files from the Finder.
    @discardableResult
    func drop(_ urls: [URL], into folder: URL) -> Bool {
        var changed = false
        for url in urls.map(\.standardizedFileURL) {
            if url.deletingLastPathComponent() == folder { continue }
            if folder == url || folder.path.hasPrefix(url.path + "/") { continue }   // a folder into itself
            let target = uniqueURL(in: folder, name: url.lastPathComponent)
            if isInsideRoot(url) {
                changed = move(url, to: target) || changed
            } else {
                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    changed = true
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
        if changed {
            if folder != root { expanded.insert(folder) }
            reloadTree()
        }
        return changed
    }

    func duplicate(_ url: URL) {
        let name = url.pathExtension.isEmpty ? L("%@ copy", url.lastPathComponent)
            : L("%@ copy", url.deletingPathExtension().lastPathComponent) + "." + url.pathExtension
        documents[url]?.save()
        let target = uniqueURL(in: url.deletingLastPathComponent(), name: name)
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        reloadTree()
        selection = target
    }

    func trash(_ url: URL) {
        if Self.isFolder(url), let node = node(for: url), node.noteCount > 0 {
            let alert = NSAlert()
            alert.messageText = L("Move “%@” to the Trash?", url.lastPathComponent)
            alert.informativeText = L("The folder contains %d notes. You can get them back from the Trash.", node.noteCount)
            alert.addButton(withTitle: L("Move to Trash"))
            alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        for (key, document) in documents where key == url || key.path.hasPrefix(url.path + "/") {
            document.save()
            documents[key] = nil
        }
        if let current = document?.url, current == url || current.path.hasPrefix(url.path + "/") { showDocument(nil) }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        if let selection, selection == url || selection.path.hasPrefix(url.path + "/") { self.selection = nil }
        reloadTree()
    }

    func node(for url: URL) -> FileNode? {
        func find(_ nodes: [FileNode]) -> FileNode? {
            for node in nodes {
                if node.url == url { return node }
                if let found = find(node.children ?? []) { return found }
            }
            return nil
        }
        return find(tree)
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func toggleSort() {
        settings.sortByDate.toggle()
        reloadTree()
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = search
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        let tree = self.tree
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) { NoteSearch.run(query, in: tree) }.value
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }

    /// Opens a search hit and shows the search word in the find bar.
    func openSearchResult(_ url: URL) {
        selection = url
        let word = search.split(separator: " ").first.map(String.init) ?? search
        find.query = word
        find.show(replace: false, focus: false)
        DispatchQueue.main.async { [weak self] in
            guard let self, let textView = self.textView else { return }
            self.find.updateMatches(in: textView)
            self.find.findNext(in: textView, from: 0)
        }
    }

    // MARK: - Editor

    func updateOutline() {
        guard let document else { outline = []; return }
        let text = (document.text as NSString).copy() as! NSString
        outline = Highlighter(syntax: document.syntax).outline(in: text)
    }

    func jump(to item: OutlineItem) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.clearExtraCarets()
        textView.setSelectedRange(NSRange(location: item.range.location, length: 0))
        textView.scrollRangeToVisible(item.range)
        textView.showFindIndicator(for: item.range)
    }

    func setSyntax(_ syntax: Syntax) {
        document?.syntax = syntax
        updateOutline()
    }

    func inspectCharacter() {
        guard let textView else { return }
        let string = textView.string as NSString
        var location = textView.selectedRange().location
        if textView.selectedRange().length == 0, location >= string.length { location -= 1 }
        guard location >= 0, location < string.length else { NSSound.beep(); return }
        let range = string.rangeOfComposedCharacterSequence(at: location)
        CharacterInspector.show(CharacterInfo(string.substring(with: range)), for: range, in: textView)
    }

    func printDocument() {
        guard let document else { return }
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.string = document.text
        view.font = settings.font
        view.textColor = .black
        view.backgroundColor = .white
        view.isRichText = false
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = document.name
        operation.run()
    }
}

extension Notification.Name {
    static let documentReloaded = Notification.Name("NotizEditorDocumentReloaded")
}
