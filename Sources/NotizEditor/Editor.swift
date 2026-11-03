import AppKit
import SwiftUI

/// The right side of the window: find bar, text and status bar.
struct EditorScreen: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var document: TextDocument
    @ObservedObject var find: FindModel

    var body: some View {
        VStack(spacing: 0) {
            if find.isVisible {
                FindBar(find: find) { model.textView }
                Divider()
            }
            EditorContainer(document: document, model: model)
            Divider()
            StatusBar(document: document, status: model.status)
        }
    }
}

/// One text view for all notes; switching notes swaps the text it shows (each note keeps its own undo history).
struct EditorContainer: NSViewRepresentable {
    @ObservedObject var document: TextDocument
    @ObservedObject var settings = AppSettings.shared
    let model: AppModel

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let layoutManager = EditorLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        document.storage.addLayoutManager(layoutManager)

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        let ruler = LineNumberRuler(editor: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true

        context.coordinator.attach(textView, ruler: ruler, scrollView: scrollView)
        model.textView = textView
        context.coordinator.show(document)
        context.coordinator.applySettings()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = context.coordinator.textView { model.textView = textView }
        context.coordinator.show(document)
        context.coordinator.applySettings()
    }
}

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let model: AppModel
    private(set) weak var textView: EditorTextView?
    private weak var ruler: LineNumberRuler?
    private weak var scrollView: NSScrollView?
    private var document: TextDocument?
    private var settingsSignature = ""
    private var documentSignature = ""
    private var pending: [String: DispatchWorkItem] = [:]
    private var settings: AppSettings { .shared }

    init(model: AppModel) {
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(forName: .documentReloaded, object: nil, queue: .main) { [weak self] note in
            let reloaded = note.object as? TextDocument
            Task { @MainActor in
                guard let self, let document = reloaded, document === self.document else { return }
                self.textView?.invalidateLines()
                self.applyAttributes()
                self.textView?.highlight(immediately: true)
                self.updateStatistics()
                self.model.updateOutline()
            }
        }
    }

    func attach(_ textView: EditorTextView, ruler: LineNumberRuler, scrollView: NSScrollView) {
        self.textView = textView
        self.ruler = ruler
        self.scrollView = scrollView
        textView.onEditPointsChange = { [weak self] in self?.selectionChanged() }
    }

    /// Runs `work` once, `delay` seconds after the last call with the same key.
    private func debounce(_ key: String, _ delay: TimeInterval, _ work: @escaping () -> Void) {
        pending[key]?.cancel()
        let item = DispatchWorkItem(block: work)
        pending[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Showing a note

    func show(_ document: TextDocument) {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        if document === self.document {
            if documentSignature != signature(of: document) {
                textView.syntax = document.syntax
                applySettings(force: true)
                textView.highlight(immediately: true)
                model.updateOutline()
            }
            return
        }
        if let old = self.document {
            old.selection = textView.selectedRanges.map(\.rangeValue)
            old.scrollPosition = scrollView?.contentView.bounds.origin ?? .zero
        }
        self.document = document
        textView.clearExtraCarets()
        textView.findMatches = []
        if layoutManager.textStorage !== document.storage { layoutManager.replaceTextStorage(document.storage) }
        textView.syntax = document.syntax
        textView.invalidateLines()
        applySettings(force: true)

        let length = document.storage.length
        let ranges = document.selection.filter { NSMaxRange($0) <= length }
        textView.selectedRanges = (ranges.isEmpty ? [NSRange(location: 0, length: 0)] : ranges).map { NSValue(range: $0) }
        textView.highlight(immediately: true)
        let position = document.scrollPosition
        DispatchQueue.main.async { [weak self] in
            guard let self, self.document === document, let scrollView = self.scrollView else { return }
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: position.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        updateStatistics()
        selectionChanged()
        model.updateOutline()
        if model.find.isVisible { model.find.updateMatches(in: textView) }
        if let line = model.pendingLine {
            model.pendingLine = nil
            DispatchQueue.main.async { textView.goToLine(line) }
        }
    }

    private func signature(of document: TextDocument) -> String {
        "\(document.syntax.id)|\(document.isVertical)|\(document.rightToLeft)"
    }

    // MARK: - Settings

    func applySettings(force: Bool = false) {
        guard let textView, let scrollView, let document else { return }
        let signature = [settings.font.fontName, "\(settings.fontSize)", "\(settings.lineSpacing)", "\(settings.tabWidth)",
                         settings.theme, "\(settings.wrapLines)", "\(settings.showLineNumbers)", "\(settings.showInvisibles)",
                         "\(settings.spellCheck)", "\(settings.showPageGuide)", "\(settings.pageGuideColumn)",
                         "\(settings.highlightCurrentLine)", self.signature(of: document)].joined(separator: "|")
        guard force || signature != settingsSignature else { return }
        let themeChanged = !settingsSignature.isEmpty && !settingsSignature.contains("|\(settings.theme)|")
        settingsSignature = signature
        documentSignature = self.signature(of: document)

        let vertical = document.isVertical
        if textView.layoutOrientation != (vertical ? .vertical : .horizontal) {
            textView.setLayoutOrientation(vertical ? .vertical : .horizontal)
        }
        scrollView.rulersVisible = settings.showLineNumbers && !vertical
        ruler?.updateThickness()
        scrollView.tile()
        setWrap(settings.wrapLines || vertical, textView: textView, scrollView: scrollView)
        textView.isContinuousSpellCheckingEnabled = settings.spellCheck
        applyAttributes()
        if themeChanged { textView.highlight(immediately: true) }
        ruler?.updateThickness()
        ruler?.needsDisplay = true
        textView.needsDisplay = true
    }

    private func applyAttributes() {
        guard let textView, let document, let layoutManager = textView.layoutManager as? EditorLayoutManager else { return }
        let theme = settings.currentTheme
        let font = settings.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(settings.lineSpacing)
        paragraph.tabStops = []
        paragraph.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width * CGFloat(max(1, settings.tabWidth))
        paragraph.baseWritingDirection = document.rightToLeft ? .rightToLeft : .natural
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.text, .paragraphStyle: paragraph]
        let storage = document.storage
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        textView.font = font
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = paragraph
        textView.backgroundColor = theme.background
        textView.insertionPointColor = theme.text
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        scrollView?.backgroundColor = theme.background
        layoutManager.showInvisibles = settings.showInvisibles
        layoutManager.invisiblesColor = theme.invisibles
        layoutManager.invisiblesFont = font
        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
    }

    private func setWrap(_ wrap: Bool, textView: EditorTextView, scrollView: NSScrollView) {
        guard let container = textView.textContainer else { return }
        if wrap {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            if textView.layoutOrientation == .horizontal {
                // The width next to the line numbers (the clip view keeps them out of the way with a content inset).
                let width = scrollView.contentSize.width
                textView.frame.size.width = width
                container.containerSize = NSSize(width: width - textView.textContainerInset.width * 2, height: CGFloat.greatestFiniteMagnitude)
            }
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    // MARK: - NSTextViewDelegate

    func undoManager(for view: NSTextView) -> UndoManager? { document?.undoManager }

    func textDidChange(_ notification: Notification) {
        guard let textView, let document else { return }
        document.textDidChange()
        textView.invalidateLines()
        ruler?.updateThickness()
        ruler?.needsDisplay = true
        let length = document.storage.length
        debounce("highlight", length < 100_000 ? 0.05 : 0.3) { [weak self] in self?.textView?.highlight() }
        debounce("statistics", length < 100_000 ? 0.1 : 0.5) { [weak self] in self?.updateStatistics() }
        debounce("outline", 0.6) { [weak self] in self?.model.updateOutline() }
        if model.find.isVisible {
            debounce("find", 0.25) { [weak self] in
                guard let self, let textView = self.textView else { return }
                self.model.find.updateMatches(in: textView)
            }
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        selectionChanged()
    }

    private func selectionChanged() {
        guard let textView else { return }
        let status = model.status
        let selection = textView.selectedRange()
        status.line = textView.lineNumber(at: selection.location)
        status.column = textView.column(at: selection.location)
        let ranges = textView.selectedRanges.map(\.rangeValue)
        let selected = ranges.reduce(0) { $0 + $1.length }
        if selected == 0 {
            status.selectedCharacters = 0
            status.selectedLines = 0
        } else {
            let string = textView.string as NSString
            status.selectedCharacters = ranges.reduce(0) { $0 + string.substring(with: $1).count }
            status.selectedLines = ranges.reduce(0) { total, range in
                total + textView.lineNumber(at: max(range.location, NSMaxRange(range) - 1)) - textView.lineNumber(at: range.location) + 1
            }
        }
        status.editPoints = textView.editRanges.count
        ruler?.needsDisplay = true
        textView.setNeedsDisplay(textView.visibleRect)
        debounce("words", 0.15) { [weak self] in self?.textView?.updateWordMatches() }
    }

    private func updateStatistics() {
        guard let textView else { return }
        let text = textView.string
        let status = model.status
        status.lines = textView.lineCount
        if (text as NSString).length > 2_000_000 {
            status.characters = (text as NSString).length
            status.words = 0
            return
        }
        status.characters = text.count
        status.words = TextEditing.wordCount(text)
    }
}

/// Line, column, counts – and the file's language, encoding and line endings, which can be changed here.
struct StatusBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var document: TextDocument
    @ObservedObject var status: EditorStatus

    var body: some View {
        HStack(spacing: 14) {
            Button(L("Line %d, Column %d", status.line, status.column)) { model.showGoToLine = true }
                .buttonStyle(.plain)
                .help(L("Go to Line … (⌘L)"))
            if status.editPoints > 1 {
                Text(L("%d insertion points", status.editPoints)).foregroundStyle(Color.accentColor)
            }
            if status.selectedCharacters > 0 {
                Text(L("Selected: %@ characters, %d lines", grouped(status.selectedCharacters), status.selectedLines))
            }
            Text(L("%@ characters · %@ words · %@ lines", grouped(status.characters), grouped(status.words), grouped(status.lines)))
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                ForEach(Syntax.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, id: \.id) { syntax in
                    Toggle(syntax.name, isOn: Binding(get: { document.syntax == syntax }, set: { _ in model.setSyntax(syntax) }))
                }
                Divider()
                Toggle(Syntax.plain.name, isOn: Binding(get: { document.syntax == .plain }, set: { _ in model.setSyntax(.plain) }))
            } label: {
                Text(document.syntax.name)
            }
            .help(L("Language for colours and outline"))
            Menu {
                EncodingMenu(document: document)
            } label: {
                Text(TextEncodings.shortName(document.encoding, bom: document.hasBOM))
            }
            .help(L("Text encoding"))
            Menu {
                LineEndingMenu(document: document)
            } label: {
                Text(document.mixedLineEndings ? document.lineEnding.label + " ⚠︎" : document.lineEnding.label)
            }
            .help(document.mixedLineEndings ? L("The file has mixed line endings. Choose one to unify them.") : L("Line endings"))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

struct EncodingMenu: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var document: TextDocument

    var body: some View {
        Section(L("Save as")) {
            ForEach(Array(TextEncodings.menu.enumerated()), id: \.offset) { _, encoding in
                if let encoding {
                    Toggle(TextEncodings.name(encoding), isOn: Binding(get: { document.encoding == encoding },
                                                                     set: { _ in document.convert(to: encoding) }))
                } else {
                    Divider()
                }
            }
        }
        Divider()
        Toggle(L("With byte order mark (BOM)"), isOn: Binding(get: { document.hasBOM }, set: { document.setBOM($0) }))
            .disabled(!TextEncodings.supportsBOM(document.encoding))
        Divider()
        Menu(L("Reinterpret as")) {
            ForEach(Array(TextEncodings.menu.enumerated()), id: \.offset) { _, encoding in
                if let encoding {
                    Button(TextEncodings.name(encoding)) { model.reinterpret(as: encoding) }
                } else {
                    Divider()
                }
            }
        }
    }
}

struct LineEndingMenu: View {
    @ObservedObject var document: TextDocument

    var body: some View {
        ForEach(LineEnding.allCases) { ending in
            Toggle(ending.title, isOn: Binding(get: { document.lineEnding == ending && !document.mixedLineEndings },
                                               set: { _ in document.setLineEnding(ending) }))
        }
    }
}

struct GoToLineSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Go to Line")).font(.headline)
            TextField(L("Line (1–%d)", model.status.lines), text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(go)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Go")) { go() }.keyboardShortcut(.defaultAction).disabled(Int(text) == nil)
            }
        }
        .padding(20)
    }

    private func go() {
        guard let line = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
        dismiss()
        DispatchQueue.main.async {
            guard let textView = model.textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.goToLine(line)
        }
    }
}

/// The character inspector: the character big, with its Unicode code points and names.
enum CharacterInspector {
    @MainActor
    static func show(_ info: CharacterInfo, for range: NSRange, in textView: EditorTextView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: CharacterInspectorView(info: info))
        var rect = textView.caretRect(at: range.location)
        rect.size.width = max(8, textView.caretRect(at: NSMaxRange(range)).minX - rect.minX)
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
    }
}

private struct CharacterInspectorView: View {
    let info: CharacterInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(display)
                .font(.system(size: 64))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(Array(info.scalars.enumerated()), id: \.offset) { _, scalar in
                    GridRow {
                        Text(scalar.code).font(.body.monospaced()).textSelection(.enabled)
                        Text(scalar.name).textSelection(.enabled)
                    }
                }
                GridRow {
                    Text("UTF-8").foregroundStyle(.secondary)
                    Text(info.utf8).font(.body.monospaced()).textSelection(.enabled)
                }
                GridRow {
                    Text("UTF-16").foregroundStyle(.secondary)
                    Text(info.utf16).font(.body.monospaced()).textSelection(.enabled)
                }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var display: String {
        switch info.character {
        case "\n": "↵"
        case "\t": "⇥"
        case " ": "␣"
        default: info.character
        }
    }
}
