import AppKit
import SwiftUI

/// Everything you can set in NotizEditor, kept in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    /// Where the notes live; created on first start.
    @Published var notesFolder: String { didSet { defaults.set(notesFolder, forKey: "notesFolder") } }
    /// Empty: the system's monospaced font.
    @Published var fontName: String { didSet { defaults.set(fontName, forKey: "fontName") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: "lineSpacing") } }
    @Published var tabWidth: Int { didSet { defaults.set(tabWidth, forKey: "tabWidth") } }
    @Published var indentWithSpaces: Bool { didSet { defaults.set(indentWithSpaces, forKey: "indentWithSpaces") } }
    @Published var autoIndent: Bool { didSet { defaults.set(autoIndent, forKey: "autoIndent") } }
    @Published var autoClose: Bool { didSet { defaults.set(autoClose, forKey: "autoClose") } }
    @Published var wrapLines: Bool { didSet { defaults.set(wrapLines, forKey: "wrapLines") } }
    @Published var showLineNumbers: Bool { didSet { defaults.set(showLineNumbers, forKey: "showLineNumbers") } }
    @Published var showInvisibles: Bool { didSet { defaults.set(showInvisibles, forKey: "showInvisibles") } }
    @Published var highlightCurrentLine: Bool { didSet { defaults.set(highlightCurrentLine, forKey: "highlightCurrentLine") } }
    @Published var showPageGuide: Bool { didSet { defaults.set(showPageGuide, forKey: "showPageGuide") } }
    @Published var pageGuideColumn: Int { didSet { defaults.set(pageGuideColumn, forKey: "pageGuideColumn") } }
    @Published var spellCheck: Bool { didSet { defaults.set(spellCheck, forKey: "spellCheck") } }
    @Published var highlightMatches: Bool { didSet { defaults.set(highlightMatches, forKey: "highlightMatches") } }
    @Published var defaultLineEnding: LineEnding { didSet { defaults.set(defaultLineEnding.rawValue, forKey: "defaultLineEnding") } }
    @Published var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    @Published var sortByDate: Bool { didSet { defaults.set(sortByDate, forKey: "sortByDate") } }
    @Published var expandedFolders: [String] { didSet { defaults.set(expandedFolders, forKey: "expandedFolders") } }
    @Published var otherFiles: [String] { didSet { defaults.set(otherFiles, forKey: "otherFiles") } }
    @Published var lastOpened: String { didSet { defaults.set(lastOpened, forKey: "lastOpened") } }

    private init() {
        // Before anything is read: settings saved under the app's earlier identifier (see LegacySettings).
        if let id = Bundle.main.bundleIdentifier,
           let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            LegacySettings.takeOver(into: .standard, ownID: id, folder: library.appendingPathComponent("Preferences", isDirectory: true))
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let stored = defaults.string(forKey: "notesFolder") {
            notesFolder = stored
        } else {
            // The default name follows the language ("Notes"/"Notizen"). Remember it on the first start – and take a
            // folder that exists already – so the notes don't seem gone after switching the Mac's language.
            let names = [L("Notes"), "Notizen", "Notes"]
            let existing = names.first { FileManager.default.fileExists(atPath: documents.appendingPathComponent($0).path) }
            let chosen = documents.appendingPathComponent(existing ?? names[0], isDirectory: true).path
            notesFolder = chosen
            defaults.set(chosen, forKey: "notesFolder")
        }
        // Versteckte Systemschriften („.AppleSystemUIFontMonospaced-…“) zählen als „System (Monospace)“ –
        // so hatte es das Schriftfenster früher gespeichert, ohne dass sich die Familie ändern ließ.
        let gespeichert = defaults.string(forKey: "fontName") ?? ""
        fontName = gespeichert.hasPrefix(".") ? "" : gespeichert
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 13
        lineSpacing = defaults.object(forKey: "lineSpacing") as? Double ?? 1.2
        tabWidth = defaults.object(forKey: "tabWidth") as? Int ?? 4
        indentWithSpaces = defaults.object(forKey: "indentWithSpaces") as? Bool ?? false
        autoIndent = defaults.object(forKey: "autoIndent") as? Bool ?? true
        autoClose = defaults.object(forKey: "autoClose") as? Bool ?? false
        wrapLines = defaults.object(forKey: "wrapLines") as? Bool ?? true
        showLineNumbers = defaults.object(forKey: "showLineNumbers") as? Bool ?? true
        showInvisibles = defaults.object(forKey: "showInvisibles") as? Bool ?? false
        highlightCurrentLine = defaults.object(forKey: "highlightCurrentLine") as? Bool ?? true
        showPageGuide = defaults.object(forKey: "showPageGuide") as? Bool ?? false
        pageGuideColumn = defaults.object(forKey: "pageGuideColumn") as? Int ?? 80
        spellCheck = defaults.object(forKey: "spellCheck") as? Bool ?? false
        highlightMatches = defaults.object(forKey: "highlightMatches") as? Bool ?? true
        defaultLineEnding = LineEnding(rawValue: defaults.string(forKey: "defaultLineEnding") ?? "") ?? .lf
        theme = defaults.string(forKey: "theme") ?? Theme.all[0].id
        sortByDate = defaults.object(forKey: "sortByDate") as? Bool ?? false
        expandedFolders = defaults.stringArray(forKey: "expandedFolders") ?? []
        otherFiles = defaults.stringArray(forKey: "otherFiles") ?? []
        lastOpened = defaults.string(forKey: "lastOpened") ?? ""
    }

    var font: NSFont {
        let size = CGFloat(fontSize)
        if !fontName.isEmpty, let font = NSFont(name: fontName, size: size) { return font }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var currentTheme: Theme { Theme.all.first { $0.id == theme } ?? Theme.all[0] }

    var indentUnit: String { indentWithSpaces ? String(repeating: " ", count: max(1, tabWidth)) : "\t" }
}

/// The colours of the editor. Each theme has a light and a dark version and follows the Mac's appearance.
struct Theme: Identifiable {
    let id: String
    let name: String
    let background: NSColor
    let text: NSColor
    let invisibles: NSColor
    let currentLine: NSColor
    let colors: [TokenKind: NSColor]

    func color(_ kind: TokenKind) -> NSColor { colors[kind] ?? text }

    private static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }

    static let all: [Theme] = [
        Theme(id: "standard", name: L("Standard"),
              background: .textBackgroundColor, text: .textColor,
              invisibles: dynamic(0xB9BDC4, 0x5A5F66),
              currentLine: dynamic(0xE8F2FF, 0x23272E),
              colors: [.keyword: dynamic(0xAD3DA4, 0xFF7AB2), .command: dynamic(0x3E8087, 0x78C2B3),
                       .type: dynamic(0x0B6E8E, 0x6BDFFF), .attribute: dynamic(0x815F03, 0xCC9768),
                       .variable: dynamic(0x0F68A0, 0x4EB0CC), .value: dynamic(0xAD3DA4, 0xFF7AB2),
                       .number: dynamic(0x1C00CF, 0xD9C97C), .string: dynamic(0xC41A16, 0xFC6A5D),
                       .character: dynamic(0xA6501B, 0xFD8F3F), .comment: dynamic(0x6C7986, 0x7F8C98),
                       .markup: dynamic(0x8A6E00, 0xE5C07B)]),
        Theme(id: "solarized", name: "Solarized",
              background: dynamic(0xFDF6E3, 0x002B36), text: dynamic(0x586E75, 0x93A1A1),
              invisibles: dynamic(0xD3CBB7, 0x2A4A53),
              currentLine: dynamic(0xEEE8D5, 0x073642),
              colors: [.keyword: dynamic(0x859900, 0x859900), .command: dynamic(0x268BD2, 0x268BD2),
                       .type: dynamic(0xB58900, 0xB58900), .attribute: dynamic(0xCB4B16, 0xCB4B16),
                       .variable: dynamic(0x268BD2, 0x268BD2), .value: dynamic(0xD33682, 0xD33682),
                       .number: dynamic(0xD33682, 0xD33682), .string: dynamic(0x2AA198, 0x2AA198),
                       .character: dynamic(0x2AA198, 0x2AA198), .comment: dynamic(0x93A1A1, 0x586E75),
                       .markup: dynamic(0x6C71C4, 0x6C71C4)]),
        Theme(id: "paper", name: L("Paper"),
              background: dynamic(0xFBFAF7, 0x1E1E1C), text: dynamic(0x2B2B2B, 0xDAD7D0),
              invisibles: dynamic(0xCFCBC2, 0x4A4843),
              currentLine: dynamic(0xF2EFE8, 0x2A2926),
              colors: [.keyword: dynamic(0x1F5FA8, 0x8CB4E8), .command: dynamic(0x2B2B2B, 0xDAD7D0),
                       .type: dynamic(0x2B2B2B, 0xDAD7D0), .attribute: dynamic(0x7A6A3A, 0xC8B887),
                       .variable: dynamic(0x2B2B2B, 0xDAD7D0), .value: dynamic(0x8A4B8C, 0xC9A2CB),
                       .number: dynamic(0x8A4B8C, 0xC9A2CB), .string: dynamic(0x3F7A3A, 0x9CC797),
                       .character: dynamic(0x3F7A3A, 0x9CC797), .comment: dynamic(0x9A958A, 0x7E7A71),
                       .markup: dynamic(0x9A6A1F, 0xD9B070)]),
        Theme(id: "contrast", name: L("High Contrast"),
              background: dynamic(0xFFFFFF, 0x000000), text: dynamic(0x000000, 0xFFFFFF),
              invisibles: dynamic(0x999999, 0x777777),
              currentLine: dynamic(0xF0F0F0, 0x1C1C1C),
              colors: [.keyword: dynamic(0x9B0078, 0xFF6EC7), .command: dynamic(0x005F5F, 0x5FFFD7),
                       .type: dynamic(0x00488A, 0x7FD4FF), .attribute: dynamic(0x6B4A00, 0xFFC94D),
                       .variable: dynamic(0x00488A, 0x7FD4FF), .value: dynamic(0x9B0078, 0xFF6EC7),
                       .number: dynamic(0x2400B0, 0xFFE066), .string: dynamic(0xA00000, 0xFF8A80),
                       .character: dynamic(0xA00000, 0xFF8A80), .comment: dynamic(0x505050, 0xAAAAAA),
                       .markup: dynamic(0x6B4A00, 0xFFC94D)]),
    ]
}

/// NotizEditor → Settings (⌘,).
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            general.tabItem { Label(L("General"), systemImage: "gearshape") }
            editor.tabItem { Label(L("Editor"), systemImage: "character.cursor.ibeam") }
            appearance.tabItem { Label(L("Appearance"), systemImage: "paintpalette") }
            tools.tabItem { Label(L("Tools"), systemImage: "terminal") }
        }
        .frame(width: 560)
        .padding(20)
    }

    private var general: some View {
        Form {
            LabeledContent(L("Notes folder")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((settings.notesFolder as NSString).abbreviatingWithTildeInPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(L("Choose …")) { model.chooseNotesFolder() }
                        Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([model.root]) }
                    }
                    Text(L("Your notes are normal text files in this folder. You can also choose a folder in iCloud Drive or Dropbox."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker(L("Line endings of new notes"), selection: $settings.defaultLineEnding) {
                ForEach(LineEnding.allCases) { Text($0.title).tag($0) }
            }
            Text(L("New notes are saved as UTF-8 text (.txt) – Windows, Mac and Linux open them without problems."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle(L("Sort notes by date changed"), isOn: $settings.sortByDate)
        }
    }

    private var editor: some View {
        Form {
            Picker(L("Tab width"), selection: $settings.tabWidth) {
                ForEach([2, 3, 4, 8], id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle(L("Indent with spaces instead of tabs"), isOn: $settings.indentWithSpaces)
            Toggle(L("Keep the indentation of the previous line"), isOn: $settings.autoIndent)
            Toggle(L("Close brackets and quotes automatically"), isOn: $settings.autoClose)
            Divider()
            Toggle(L("Wrap lines"), isOn: $settings.wrapLines)
            Toggle(L("Show line numbers"), isOn: $settings.showLineNumbers)
            Toggle(L("Show invisible characters"), isOn: $settings.showInvisibles)
            Toggle(L("Highlight current line"), isOn: $settings.highlightCurrentLine)
            Toggle(L("Highlight all occurrences of the selected word"), isOn: $settings.highlightMatches)
            // Das Zahlenfeld steckt in der Beschriftung des Häkchens: Eine HStack-Zeile setzte das Häkchen im Formular
            // sonst in die linke Spalte (gemeldet 17.11.2026).
            Toggle(isOn: $settings.showPageGuide) {
                HStack(spacing: 8) {
                    Text(L("Show page guide at column"))
                    TextField("", value: $settings.pageGuideColumn, format: .number)
                        .labelsHidden().frame(width: 50)
                        .disabled(!settings.showPageGuide)
                }
            }
            Toggle(L("Check spelling while typing"), isOn: $settings.spellCheck)
        }
    }

    private var appearance: some View {
        Form {
            // Auswahlmenü statt Schriftfenster (17.11.2026): Über das Schriftfenster des Macs kam die Familie nicht an,
            // nur die Größe. Ein Menü speichert die Wahl sofort und ohne Umweg.
            // Jeder Name steht im Menü in seiner eigenen Schrift (wie in Pages), darunter eine Textprobe (Wunsch 17.11.2026).
            LabeledContent(L("Font")) {
                FontPopUp(selection: $settings.fontName)
            }
            // Kurze Bezeichnung links, Wert und Pfeile rechts – „Schriftgröße: 13 pt“ als Ganzes war für die
            // linke Spalte zu lang und wurde auf Deutsch links abgeschnitten.
            LabeledContent(L("Font size")) {
                HStack(spacing: 6) {
                    Text("\(Int(settings.fontSize)) pt").monospacedDigit()
                    Stepper(L("Font size"), value: $settings.fontSize, in: 8...48, step: 1).labelsHidden()
                }
            }
            LabeledContent(L("Preview")) {
                Text(L("Font preview text"))
                    .font(Font(settings.font.withSize(min(max(CGFloat(settings.fontSize), 11), 22)) as CTFont))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            }
            Picker(L("Line spacing"), selection: $settings.lineSpacing) {
                Text(L("Tight")).tag(1.0)
                Text(L("Normal")).tag(1.2)
                Text(L("Wide")).tag(1.5)
            }
            Picker(L("Colours"), selection: $settings.theme) {
                ForEach(Theme.all) { Text($0.name).tag($0.id) }
            }
            Text(L("Every colour scheme has a light and a dark version and follows your Mac."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tools: some View {
        Form {
            LabeledContent(L("Command line")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Open files from the Terminal with: notizeditor file.txt"))
                    Button(CommandLineTool.isInstalled ? L("Reinstall …") : L("Install …")) { CommandLineTool.install() }
                    Text(L("Pipe text into a new note: echo Hello | notizeditor · Jump to a line: notizeditor --line 12 file.txt"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledContent(L("Scripts")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Your own scripts appear in the Scripts menu and work on the selected text."))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Open Scripts Folder")) { Scripts.openFolder() }
                }
            }
        }
    }
}

/// Schriftfamilien für das Auswahlmenü in den Einstellungen: je Familie der normale Schnitt.
struct FontChoice: Identifiable {
    let family: String
    let postScript: String
    var id: String { postScript }
}

@MainActor
enum FontList {
    static let all: [FontChoice] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .compactMap { family in
                guard let font = manager.font(withFamily: family, traits: [], weight: 5, size: 13) else { return nil }
                return FontChoice(family: family, postScript: font.fontName)
            }
            .sorted { $0.family.localizedStandardCompare($1.family) == .orderedAscending }
    }()

    static var monospaced: [FontChoice] { all.filter { NSFont(name: $0.postScript, size: 13)?.isFixedPitch == true } }
    static var others: [FontChoice] { all.filter { NSFont(name: $0.postScript, size: 13)?.isFixedPitch != true } }
}

/// Schriftauswahl als echtes Aufklappmenü, in dem jeder Name in seiner eigenen Schrift erscheint. Ein SwiftUI-`Picker`
/// kann das nicht – er zeigt alle Einträge in der Menüschrift.
struct FontPopUp: NSViewRepresentable {
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        fill(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if (button.selectedItem?.representedObject as? String) != selection { fill(button) }
    }

    private func fill(_ button: NSPopUpButton) {
        let menu = NSMenu()
        let size = NSFont.systemFontSize
        menu.addItem(item(L("System monospaced"), tag: "", font: .monospacedSystemFont(ofSize: size, weight: .regular)))
        // Eine gespeicherte Schrift, die nicht (mehr) in der Liste steht, bleibt wählbar.
        if !selection.isEmpty, !FontList.all.contains(where: { $0.postScript == selection }) {
            let font = NSFont(name: selection, size: size)
            menu.addItem(item(font?.displayName ?? selection, tag: selection, font: font))
        }
        for (header, fonts) in [(L("Monospaced"), FontList.monospaced), (L("Other fonts"), FontList.others)] {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: header))
            for choice in fonts {
                menu.addItem(item(choice.family, tag: choice.postScript, font: NSFont(name: choice.postScript, size: size)))
            }
        }
        button.menu = menu
        let index = menu.items.firstIndex { ($0.representedObject as? String) == selection } ?? 0
        button.selectItem(at: index)
    }

    private func item(_ title: String, tag: String, font: NSFont?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = tag
        // Symbolschriften (z. B. Webdings) können ihren eigenen Namen nicht darstellen – dann normale Menüschrift.
        if let font, font.coveredCharacterSet.isSuperset(of: CharacterSet(charactersIn: title)) {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        }
        return item
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: FontPopUp
        init(_ parent: FontPopUp) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            parent.selection = sender.selectedItem?.representedObject as? String ?? ""
        }
    }
}
