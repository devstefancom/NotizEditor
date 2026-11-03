import AppKit
import SwiftUI

@main
struct NotizEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("NotizEditor", id: "main") {
            ContentView(find: appDelegate.model.find)
                .environmentObject(appDelegate.model)
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            FileCommands(model: appDelegate.model)
            EditCommands(model: appDelegate.model, find: appDelegate.model.find)
            ViewCommands(model: appDelegate.model)
            TextCommands(model: appDelegate.model)
            FormatCommands(model: appDelegate.model)
            ScriptCommands(model: appDelegate.model)
            HelpCommands()
            CommandGroup(after: .appSettings) {
                Button(L("Install Command Line Tool …")) { CommandLineTool.install() }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.model)
        }

        Window(HelpText("NotizEditor Help", de: "NotizEditor Hilfe").text, id: "help") {
            HelpView(topics: HelpContent.topics)
        }
        .defaultSize(width: 900, height: 640)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SELFTEST
        SelfTest.run(model)
        #else
        _ = AppMover.offerMoveIfNeeded()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.saveAll()
        return .terminateNow
    }

    func applicationWillResignActive(_ notification: Notification) {
        model.saveAll()
    }

    /// Files dropped on the Dock icon, "Open With", and the notizeditor:// links of the command line tool.
    func application(_ application: NSApplication, open urls: [URL]) {
        let links = urls.filter { $0.scheme == "notizeditor" }
        links.forEach(model.handle)
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { model.openFiles(files) }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var find: FindModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 250, max: 420)
        } detail: {
            detail
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.newNote() } label: { Label(L("New Note"), systemImage: "square.and.pencil") }
                    .help(L("New Note (⌘N)"))
                Button { model.newFolder() } label: { Label(L("New Folder"), systemImage: "folder.badge.plus") }
                    .help(L("New Folder (⇧⌘N)"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    if model.outline.isEmpty {
                        Text(L("No headings found"))
                    }
                    ForEach(model.outline) { item in
                        if item.isSeparator {
                            Divider()
                        } else {
                            Button(String(repeating: "    ", count: item.level) + item.title) { model.jump(to: item) }
                        }
                    }
                } label: {
                    Label(L("Outline"), systemImage: "list.bullet.indent")
                }
                .help(L("Outline: jump to a heading or function"))
                .disabled(model.document == nil)
                Button {
                    if find.isVisible { find.hide(in: model.textView) } else { find.show(replace: false) }
                } label: {
                    Label(L("Find"), systemImage: "magnifyingglass")
                }
                .help(L("Find and replace (⌘F)"))
                .disabled(model.document == nil)
            }
        }
        .sheet(isPresented: $model.showGoToLine) { GoToLineSheet() }
    }

    @ViewBuilder private var detail: some View {
        if let document = model.document {
            EditorScreen(document: document, find: find)
        } else if let error = model.openError, let url = model.selection {
            ContentUnavailableView {
                Label(error, systemImage: "doc.questionmark")
            } description: {
                Text(L("NotizEditor opens text files. You can open this file with another app."))
            } actions: {
                Button(L("Open with Default App")) { NSWorkspace.shared.open(url) }
                Button(L("Show in Finder")) { model.reveal(url) }
            }
        } else if let url = model.selection, AppModel.isFolder(url) {
            let count = model.node(for: url)?.noteCount ?? 0
            ContentUnavailableView {
                Label(url.lastPathComponent, systemImage: "folder")
            } description: {
                Text(count == 1 ? L("1 note") : L("%d notes", count))
            } actions: {
                Button(L("New Note")) { model.newNote(in: url) }
            }
        } else {
            ContentUnavailableView {
                Label(L("No Note Selected"), systemImage: "note.text")
            } description: {
                Text(L("Choose a note on the left or create a new one."))
            } actions: {
                Button(L("New Note")) { model.newNote() }
            }
        }
    }

    private var title: String {
        guard let url = model.document?.url ?? model.selection else { return "NotizEditor" }
        return url.pathExtension.lowercased() == "txt" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }

    private var subtitle: String {
        guard let url = model.document?.url else { return "" }
        let folder = url.deletingLastPathComponent()
        if model.isInsideRoot(url) || folder == model.root {
            return folder == model.root ? model.root.lastPathComponent
                : model.root.lastPathComponent + "/" + folder.path.dropFirst(model.root.path.count + 1)
        }
        return (folder.path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - Menus

struct FileCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("New Note")) { model.newNote() }
                .keyboardShortcut("n")
            Button(L("New Folder")) { model.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(L("Open …")) { model.showOpenPanel() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button(L("Save")) { model.document?.save(force: true) }
                .keyboardShortcut("s")
                .disabled(model.document == nil)
            Button(L("Rename …")) { model.renaming = model.selection }
                .disabled(model.selection.map { !model.isInsideRoot($0) } ?? true)
            Button(L("Show in Finder")) { if let url = model.selection { model.reveal(url) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selection == nil)
            Divider()
            Button(L("Move to Trash")) { if let url = model.selection { model.trash(url) } }
                .disabled(model.selection.map { !model.isInsideRoot($0) } ?? true)
        }
        CommandGroup(replacing: .printItem) {
            Button(L("Print …")) { model.printDocument() }
                .keyboardShortcut("p")
                .disabled(model.document == nil)
        }
    }
}

struct EditCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var find: FindModel

    var body: some Commands {
        CommandGroup(replacing: .textEditing) {
            Menu(L("Find")) {
                Button(L("Find …")) { find.show(replace: false) }
                    .keyboardShortcut("f")
                Button(L("Find and Replace …")) { find.show(replace: true) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button(L("Find Next")) { if let tv = model.textView { find.findNext(in: tv) } }
                    .keyboardShortcut("g")
                Button(L("Find Previous")) { if let tv = model.textView { find.findPrevious(in: tv) } }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button(L("Use Selection to Find")) { if let tv = model.textView { find.useSelection(in: tv) } }
                    .keyboardShortcut("e")
            }
            .disabled(model.document == nil)
            Button(L("Go to Line …")) { model.showGoToLine = true }
                .keyboardShortcut("l")
                .disabled(model.document == nil)
            Divider()
            Button(L("Select Next Occurrence")) { model.textView?.selectNextOccurrence() }
                .keyboardShortcut("d")
                .disabled(model.document == nil)
            Button(L("Select All Occurrences")) { model.textView?.selectAllOccurrences() }
                .keyboardShortcut("g", modifiers: [.command, .control])
                .disabled(model.document == nil)
            Button(L("Split Selection into Lines")) { model.textView?.splitSelectionIntoLines() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.document == nil)
        }
    }
}

struct ViewCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var settings = AppSettings.shared

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle(L("Line Numbers"), isOn: $settings.showLineNumbers)
            Toggle(L("Invisible Characters"), isOn: $settings.showInvisibles)
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Toggle(L("Wrap Lines"), isOn: $settings.wrapLines)
            Toggle(L("Page Guide"), isOn: $settings.showPageGuide)
            Toggle(L("Highlight Current Line"), isOn: $settings.highlightCurrentLine)
            Toggle(L("Check Spelling While Typing"), isOn: $settings.spellCheck)
            Divider()
            Button(L("Bigger")) { settings.fontSize = min(72, settings.fontSize + 1) }
                .keyboardShortcut("+")
            Button(L("Smaller")) { settings.fontSize = max(8, settings.fontSize - 1) }
                .keyboardShortcut("-")
            Button(L("Actual Size")) { settings.fontSize = 13 }
                .keyboardShortcut("0")
            Divider()
            Menu(L("Colours")) {
                Picker(L("Colours"), selection: $settings.theme) {
                    ForEach(Theme.all) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

struct TextCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu(L("Text")) {
            let off = model.document == nil
            Button(L("Indent")) { model.textView?.shiftLines(outdent: false) }
                .keyboardShortcut("]")
            Button(L("Outdent")) { model.textView?.shiftLines(outdent: true) }
                .keyboardShortcut("[")
            Button(L("Comment / Uncomment")) { model.textView?.toggleComment() }
                .keyboardShortcut("/")
            Divider()
            Button(L("Duplicate Line")) { model.textView?.duplicateLines() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button(L("Delete Line")) { model.textView?.deleteLines() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button(L("Move Line Up")) { model.textView?.moveLines(up: true) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button(L("Move Line Down")) { model.textView?.moveLines(up: false) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button(L("Join Lines")) { model.textView?.joinLines() }
                .keyboardShortcut("j", modifiers: [.command, .control])
            Divider()
            Menu(L("Case")) {
                transforms([.uppercase, .lowercase, .capitalize])
            }
            Menu(L("Lines")) {
                transforms([.sortLines, .sortLinesNumerically, .reverseLines, .shuffleLines, .removeDuplicateLines, .removeEmptyLines])
            }
            Menu(L("Whitespace")) {
                transforms([.trimTrailingWhitespace, .tabsToSpaces, .spacesToTabs])
            }
            Menu(L("Unicode Normalization")) {
                transforms([.nfc, .nfd, .nfkc, .nfkd])
            }
            Menu(L("Character Width")) {
                transforms([.fullwidthToHalfwidth, .halfwidthToFullwidth])
            }
            transforms([.straightenQuotes])
            Divider()
            Button(L("Character Info")) { model.inspectCharacter() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(off)
        }
    }

    @ViewBuilder private func transforms(_ list: [TextTransform]) -> some View {
        ForEach(list, id: \.self) { transform in
            Button(transform.title) { model.textView?.apply(transform) }
                .disabled(model.document == nil)
        }
    }
}

struct FormatCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu(L("Format")) {
            if let document = model.document {
                Menu(L("Text Encoding")) { EncodingMenu(document: document).environmentObject(model) }
                Menu(L("Line Endings")) { LineEndingMenu(document: document) }
                Menu(L("Syntax")) { SyntaxMenu(model: model, document: document) }
                Divider()
                WritingMenu(document: document)
            } else {
                Text(L("No note open"))
            }
        }
    }
}

private struct SyntaxMenu: View {
    let model: AppModel
    @ObservedObject var document: TextDocument

    var body: some View {
        Toggle(Syntax.plain.name, isOn: Binding(get: { document.syntax == .plain }, set: { _ in model.setSyntax(.plain) }))
        Divider()
        ForEach(Syntax.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, id: \.id) { syntax in
            Toggle(syntax.name, isOn: Binding(get: { document.syntax == syntax }, set: { _ in model.setSyntax(syntax) }))
        }
    }
}

private struct WritingMenu: View {
    @ObservedObject var document: TextDocument

    var body: some View {
        Toggle(L("Vertical Text"), isOn: $document.isVertical)
        Toggle(L("Right to Left"), isOn: $document.rightToLeft)
    }
}

struct ScriptCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu(L("Scripts")) {
            ForEach(model.scripts, id: \.self) { script in
                Button(Scripts.title(script)) { Scripts.run(script, model: model) }
                    .disabled(model.document == nil)
            }
            if !model.scripts.isEmpty { Divider() }
            Button(L("Open Scripts Folder")) { Scripts.openFolder() }
        }
    }
}
