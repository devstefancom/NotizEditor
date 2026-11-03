import AppKit

// The text view of the editor: plain text with line numbers, invisible characters, the current line highlighted,
// a page guide, several insertion points at once, smart indentation and the line commands of the Text menu.

/// Draws invisible characters (spaces, tabs, line breaks) as faint symbols on top of the text.
final class EditorLayoutManager: NSLayoutManager {
    var showInvisibles = false
    var invisiblesColor: NSColor = .tertiaryLabelColor
    var invisiblesFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showInvisibles, let storage = textStorage, storage.length > 0 else { return }
        let string = storage.string as NSString
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: invisiblesFont, .foregroundColor: invisiblesColor]
        for index in characters.location..<min(NSMaxRange(characters), string.length) {
            let symbol: String
            switch string.character(at: index) {
            case 0x20: symbol = "·"
            case 0x09: symbol = "→"
            case 0x0A: symbol = "¬"
            case 0xA0: symbol = "°"
            case 0x3000: symbol = "□"
            case 0x200B, 0xFEFF: symbol = "◊"
            default: continue
            }
            let glyph = glyphIndexForCharacter(at: index)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
            let location = self.location(forGlyphAt: glyph)
            let point = NSPoint(x: origin.x + line.minX + location.x,
                                y: origin.y + line.minY + location.y - invisiblesFont.ascender)
            (symbol as NSString).draw(at: point, withAttributes: attributes)
        }
    }
}

/// The line numbers left of the text.
final class LineNumberRuler: NSRulerView {
    weak var editor: EditorTextView?

    init(editor: EditorTextView, scrollView: NSScrollView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 40
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private var numberFont: NSFont {
        let size = max(9, (editor?.font?.pointSize ?? 13) * 0.82)
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    /// Wide enough for the biggest line number.
    func updateThickness() {
        guard let editor else { return }
        let digits = max(3, String(editor.lineCount).count)
        let width = ceil(("8" as NSString).size(withAttributes: [.font: numberFont]).width * CGFloat(digits)) + 18
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let layoutManager = editor.layoutManager, let container = editor.textContainer else { return }
        let theme = AppSettings.shared.currentTheme
        theme.background.setFill()
        bounds.fill()
        theme.invisibles.withAlphaComponent(0.5).setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let font = numberFont
        let string = editor.string as NSString
        let visible = editor.visibleRect
        let offset = convert(NSPoint.zero, from: editor).y + editor.textContainerOrigin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let caretLine = editor.lineNumber(at: editor.selectedRange().location)

        func draw(_ number: Int, baseline: CGFloat) {
            let color = number == caretLine ? NSColor.labelColor : NSColor.secondaryLabelColor
            let label = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: bounds.maxX - size.width - 8, y: baseline - font.ascender), withAttributes: attributes)
        }

        var index = string.lineRange(for: NSRange(location: characters.location, length: 0)).location
        var number = editor.lineNumber(at: index)
        while index < NSMaxRange(characters) || (index == characters.location && string.length == 0) {
            guard string.length > 0 else { break }
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = fragment.minY + layoutManager.location(forGlyphAt: glyph).y + offset
            if baseline > rect.minY - 40, baseline - 40 < rect.maxY { draw(number, baseline: baseline) }
            let line = string.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(line)
            number += 1
            if line.length == 0 { break }
        }
        // The empty last line after a final line break (or an empty note).
        if layoutManager.extraLineFragmentTextContainer != nil, NSMaxRange(characters) >= string.length {
            let fragment = layoutManager.extraLineFragmentRect
            draw(editor.lineCount, baseline: fragment.minY + (editor.font?.ascender ?? 12) + offset
                 + (fragment.height - (editor.font.map { layoutManager.defaultLineHeight(for: $0) } ?? fragment.height)))
        }
    }
}

final class EditorTextView: NSTextView {
    var syntax: Syntax = .plain
    /// Additional insertion points (⌘-click); the main one is the normal selection.
    private(set) var extraCarets: [Int] = []
    var onEditPointsChange: (() -> Void)?
    private var lineStarts: [Int] = [0]
    private var lineStartsValid = false

    private var settings: AppSettings { .shared }

    // MARK: - Lines

    func invalidateLines() { lineStartsValid = false }

    private func ensureLines() {
        guard !lineStartsValid else { return }
        var starts = [0]
        let string = self.string as NSString
        let length = string.length
        var buffer = [unichar](repeating: 0, count: length)
        string.getCharacters(&buffer, range: NSRange(location: 0, length: length))
        for index in 0..<length where buffer[index] == 10 { starts.append(index + 1) }
        lineStarts = starts
        lineStartsValid = true
    }

    var lineCount: Int {
        ensureLines()
        return lineStarts.count
    }

    /// 1-based line number of a character position.
    func lineNumber(at location: Int) -> Int {
        ensureLines()
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    func lineStart(_ line: Int) -> Int {
        ensureLines()
        return lineStarts[max(0, min(line - 1, lineStarts.count - 1))]
    }

    /// Column (1-based) with tabs counted as one character, like CotEditor.
    func column(at location: Int) -> Int {
        location - lineStart(lineNumber(at: location)) + 1
    }

    // MARK: - Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let container = textContainer else { return }
        let theme = settings.currentTheme
        if settings.highlightCurrentLine, selectedRanges.count == 1, extraCarets.isEmpty {
            let string = self.string as NSString
            let paragraph = string.lineRange(for: selectedRange())
            var lineRect = NSRect.zero
            if paragraph.length > 0 || string.length == 0 {
                let glyphs = layoutManager.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
                lineRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            }
            if selectedRange().location == string.length, layoutManager.extraLineFragmentTextContainer != nil,
               string.length == 0 || string.hasSuffix("\n") {
                lineRect = layoutManager.extraLineFragmentRect
            }
            if lineRect.height > 0 {
                theme.currentLine.setFill()
                NSRect(x: 0, y: lineRect.minY + textContainerOrigin.y, width: bounds.width, height: lineRect.height).intersection(rect).fill()
            }
        }
        if settings.showPageGuide, layoutOrientation == .horizontal, let font {
            let width = ("M" as NSString).size(withAttributes: [.font: font]).width
            let x = textContainerOrigin.x + container.lineFragmentPadding + width * CGFloat(settings.pageGuideColumn)
            theme.invisibles.withAlphaComponent(0.6).setFill()
            NSRect(x: floor(x), y: rect.minY, width: 1, height: rect.height).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !extraCarets.isEmpty else { return }
        insertionPointColor.setFill()
        for location in extraCarets {
            let rect = caretRect(at: location)
            if rect.intersects(dirtyRect) { rect.fill() }
        }
    }

    /// Where an insertion point at `location` is drawn, in view coordinates.
    func caretRect(at location: Int) -> NSRect {
        guard let layoutManager else { return .zero }
        let length = (string as NSString).length
        var rect: NSRect
        if location >= length, layoutManager.extraLineFragmentTextContainer != nil, length == 0 || string.hasSuffix("\n") {
            rect = layoutManager.extraLineFragmentRect
            rect.size.width = 0
            rect.origin.x += textContainer?.lineFragmentPadding ?? 0
        } else if location >= length {
            let glyph = layoutManager.glyphIndexForCharacter(at: length - 1)
            rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer!)
            rect.origin.x = rect.maxX
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            rect = fragment
            rect.origin.x = fragment.minX + layoutManager.location(forGlyphAt: glyph).x
        }
        rect.size.width = 1.5
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    // MARK: - Several insertion points

    var hasMultipleEditPoints: Bool { !extraCarets.isEmpty || selectedRanges.count > 1 }

    /// The selection(s) plus the extra insertion points, front to back, without duplicates.
    var editRanges: [NSRange] {
        var ranges = selectedRanges.map(\.rangeValue) + extraCarets.map { NSRange(location: $0, length: 0) }
        ranges.sort { $0.location < $1.location || ($0.location == $1.location && $0.length > $1.length) }
        var result: [NSRange] = []
        for range in ranges {
            if let last = result.last, range.location < NSMaxRange(last) || (range.location == last.location && range.length == 0) {
                continue
            }
            result.append(range)
        }
        return result
    }

    func setEditPoints(_ ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }
        let sorted = ranges.sorted { $0.location < $1.location }
        let selections = sorted.filter { $0.length > 0 }
        let carets = sorted.filter { $0.length == 0 }.map(\.location)
        if selections.isEmpty {
            setSelectedRange(NSRange(location: carets[0], length: 0))
            extraCarets = Array(carets.dropFirst())
        } else {
            selectedRanges = selections.map { NSValue(range: $0) }
            extraCarets = carets
        }
        needsDisplay = true
        onEditPointsChange?()
    }

    func clearExtraCarets() {
        guard !extraCarets.isEmpty else { return }
        extraCarets = []
        needsDisplay = true
        onEditPointsChange?()
    }

    func collapseToMainSelection() {
        extraCarets = []
        if selectedRanges.count > 1 { setSelectedRange(selectedRanges[0].rangeValue) }
        needsDisplay = true
        onEditPointsChange?()
    }

    /// Replaces every range with the text `replacement` gives for it, as one undo step, then puts an
    /// insertion point after each new text – or selects the new texts.
    func edit(_ ranges: [NSRange], selectInserted: Bool = false, _ replacement: (NSRange) -> String) {
        guard let textStorage, !ranges.isEmpty else { return }
        let sorted = ranges.sorted { $0.location < $1.location }
        let strings = sorted.map(replacement)
        guard shouldChangeText(inRanges: sorted.map { NSValue(range: $0) }, replacementStrings: strings) else { return }
        textStorage.beginEditing()
        for (range, string) in zip(sorted, strings).reversed() {
            textStorage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: typingAttributes))
        }
        textStorage.endEditing()
        didChangeText()
        var delta = 0
        var points: [NSRange] = []
        for (range, string) in zip(sorted, strings) {
            let start = range.location + delta
            let length = (string as NSString).length
            points.append(selectInserted ? NSRange(location: start, length: length) : NSRange(location: start + length, length: 0))
            delta += length - range.length
        }
        setEditPoints(points)
        scrollRangeToVisible(points.last!)
    }

    /// Replaces one range and selects the new text (or puts the insertion point at `caret` inside it).
    func replace(_ range: NSRange, with string: String, select: Bool = true, caret: Int? = nil) {
        guard let textStorage, shouldChangeText(in: range, replacementString: string) else { return }
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: typingAttributes))
        didChangeText()
        let length = (string as NSString).length
        if let caret {
            setSelectedRange(NSRange(location: range.location + caret, length: 0))
        } else {
            setSelectedRange(select ? NSRange(location: range.location, length: length) : NSRange(location: range.location + length, length: 0))
        }
        scrollRangeToVisible(selectedRange())
    }

    private func moveEditPoints(by step: Int) {
        let string = self.string as NSString
        let moved = editRanges.map { range -> NSRange in
            if range.length > 0 { return NSRange(location: step < 0 ? range.location : NSMaxRange(range), length: 0) }
            if step < 0 {
                guard range.location > 0 else { return range }
                return NSRange(location: string.rangeOfComposedCharacterSequence(at: range.location - 1).location, length: 0)
            }
            guard range.location < string.length else { return range }
            return NSRange(location: NSMaxRange(string.rangeOfComposedCharacterSequence(at: range.location)), length: 0)
        }
        var unique: [NSRange] = []
        for range in moved where !unique.contains(where: { $0.location == range.location }) { unique.append(range) }
        setEditPoints(unique)
    }

    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.clickCount == 1 {
            // ⌘-click adds an insertion point (or removes one that is there).
            let location = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            var points = editRanges
            if points.count > 1, let index = points.firstIndex(where: { $0.length == 0 && $0.location == location }) {
                points.remove(at: index)
            } else if !points.contains(where: { NSLocationInRange(location, $0) || $0.location == location }) {
                points.append(NSRange(location: location, length: 0))
            }
            window?.makeFirstResponder(self)
            setEditPoints(points)
            return
        }
        clearExtraCarets()
        super.mouseDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if hasMultipleEditPoints {
            switch selector {
            case #selector(moveLeft(_:)), #selector(moveBackward(_:)):
                moveEditPoints(by: -1)
                return
            case #selector(moveRight(_:)), #selector(moveForward(_:)):
                moveEditPoints(by: 1)
                return
            default:
                let name = NSStringFromSelector(selector)
                if name.hasPrefix("move") || name.hasPrefix("scrollTo") || name.hasPrefix("page") { collapseToMainSelection() }
            }
        }
        super.doCommand(by: selector)
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMultipleEditPoints { collapseToMainSelection() } else { super.cancelOperation(sender) }
    }

    // MARK: - Typing

    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
    private static let closers: Set<String> = [")", "]", "}", "\"", "'", "`"]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if replacementRange.location != NSNotFound || hasMarkedText() {
            clearExtraCarets()
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        if hasMultipleEditPoints {
            edit(editRanges) { _ in text }
            return
        }
        if settings.autoClose, autoClose(text) { return }
        super.insertText(string, replacementRange: replacementRange)
    }

    private func character(at index: Int) -> String? {
        let string = self.string as NSString
        guard index >= 0, index < string.length else { return nil }
        return string.substring(with: string.rangeOfComposedCharacterSequence(at: index))
    }

    /// Brackets and quotes come in pairs; typing the closing one steps over it.
    private func autoClose(_ text: String) -> Bool {
        let selection = selectedRange()
        let next = character(at: NSMaxRange(selection))
        if selection.length == 0, Self.closers.contains(text), next == text {
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return true
        }
        guard let close = Self.pairs[text] else { return false }
        if text == close, let previous = character(at: selection.location - 1),
           previous.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) {
            return false   // an apostrophe in a word: don't
        }
        if selection.length == 0, let next, !next.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains),
           !Self.closers.contains(next) {
            return false   // right before a word: don't
        }
        let selected = (self.string as NSString).substring(with: selection)
        replace(selection, with: text + selected + close, select: false, caret: (text as NSString).length + (selected as NSString).length)
        if selection.length > 0 {
            setSelectedRange(NSRange(location: selection.location + 1, length: selection.length))
        }
        return true
    }

    override func deleteBackward(_ sender: Any?) {
        let string = self.string as NSString
        if hasMultipleEditPoints {
            let ranges = editRanges.compactMap { range -> NSRange? in
                if range.length > 0 { return range }
                guard range.location > 0 else { return nil }
                let previous = string.rangeOfComposedCharacterSequence(at: range.location - 1)
                return NSRange(location: previous.location, length: range.location - previous.location)
            }
            guard !ranges.isEmpty else { return }
            edit(ranges) { _ in "" }
            return
        }
        let selection = selectedRange()
        if selection.length == 0, selection.location > 0 {
            // Inside an empty pair: delete both.
            if settings.autoClose, let previous = character(at: selection.location - 1), let close = Self.pairs[previous],
               character(at: selection.location) == close {
                replace(NSRange(location: selection.location - 1, length: 2), with: "", select: false)
                return
            }
            // In the indentation with spaces: back to the previous tab stop.
            if settings.indentWithSpaces {
                let line = string.lineRange(for: selection)
                let before = string.substring(with: NSRange(location: line.location, length: selection.location - line.location))
                if !before.isEmpty, before.allSatisfy({ $0 == " " }) {
                    let width = max(1, settings.tabWidth)
                    let remove = before.count % width == 0 ? width : before.count % width
                    replace(NSRange(location: selection.location - remove, length: remove), with: "", select: false)
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if hasMultipleEditPoints {
            let string = self.string as NSString
            let ranges = editRanges.compactMap { range -> NSRange? in
                if range.length > 0 { return range }
                guard range.location < string.length else { return nil }
                return string.rangeOfComposedCharacterSequence(at: range.location)
            }
            guard !ranges.isEmpty else { return }
            edit(ranges) { _ in "" }
            return
        }
        super.deleteForward(sender)
    }

    private func indentation(atLineOf location: Int, upTo limit: Int? = nil) -> String {
        let string = self.string as NSString
        let line = string.lineRange(for: NSRange(location: location, length: 0))
        let end = min(limit ?? NSMaxRange(line), NSMaxRange(line))
        let text = string.substring(with: NSRange(location: line.location, length: end - line.location))
        return String(text.prefix { $0 == " " || $0 == "\t" })
    }

    override func insertNewline(_ sender: Any?) {
        if hasMultipleEditPoints {
            edit(editRanges) { range in "\n" + (self.settings.autoIndent ? self.indentation(atLineOf: range.location, upTo: range.location) : "") }
            return
        }
        guard settings.autoIndent else { super.insertNewline(sender); return }
        let string = self.string as NSString
        let selection = selectedRange()
        let line = string.lineRange(for: NSRange(location: selection.location, length: 0))
        let before = string.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let indent = String(before.prefix { $0 == " " || $0 == "\t" })

        // Lists in notes and Markdown go on: "- ", "* ", "1. ", "- [ ] ". An empty item ends the list.
        if syntax.id == Syntax.plain.id || syntax.id == "markdown",
           let match = before.range(of: #"^[ \t]*(?:[-*+•]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?"#, options: .regularExpression) {
            let marker = String(before[match])
            if before[match.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty, selection.length == 0 {
                replace(NSRange(location: line.location, length: selection.location - line.location), with: "", select: false)
                return
            }
            var next = marker.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            if let number = next.range(of: #"\d+"#, options: .regularExpression), let value = Int(next[number]) {
                next.replaceSubrange(number, with: String(value + 1))
            }
            super.insertText("\n" + next, replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }

        var extra = ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, "{[(".contains(last) || (syntax.id == "python" && last == ":") {
            extra = settings.indentUnit
        }
        let next = character(at: NSMaxRange(selection))
        if !extra.isEmpty, let next, let last = trimmed.last, Self.pairs[String(last)] == next {
            // Between { and }: the closing bracket gets its own line.
            replace(selection, with: "\n" + indent + extra + "\n" + indent, select: false,
                    caret: 1 + (indent as NSString).length + (extra as NSString).length)
            return
        }
        super.insertText("\n" + indent + extra, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    override func insertTab(_ sender: Any?) {
        if hasMultipleEditPoints {
            edit(editRanges) { _ in self.settings.indentUnit }
            return
        }
        let selection = selectedRange()
        if selection.length > 0, (string as NSString).substring(with: selection).contains("\n") {
            shiftLines(outdent: false)
            return
        }
        if settings.indentWithSpaces {
            let width = max(1, settings.tabWidth)
            let column = self.column(at: selection.location) - 1
            super.insertText(String(repeating: " ", count: width - column % width), replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) { shiftLines(outdent: true) }

    // MARK: - Line commands (Text menu)

    /// The full lines touched by the selection.
    var selectedLines: NSRange {
        let string = self.string as NSString
        var range = selectedRange()
        // A selection that ends right after a line break doesn't include the next line.
        if range.length > 0, NSMaxRange(range) <= string.length, string.character(at: NSMaxRange(range) - 1) == 10 {
            range.length -= 1
        }
        return string.lineRange(for: range)
    }

    private func replaceLines(_ transform: (String) -> String) {
        let range = selectedLines
        let old = (string as NSString).substring(with: range)
        let new = transform(old)
        guard new != old else { return }
        replace(range, with: new)
    }

    func shiftLines(outdent: Bool) {
        replaceLines { TextEditing.shift($0, outdent: outdent, indentUnit: settings.indentUnit, tabWidth: settings.tabWidth) }
    }

    func toggleComment() {
        if let marker = syntax.lineComment {
            replaceLines { TextEditing.toggleLineComment($0, marker: marker) }
        } else if let (start, end) = syntax.blockComment {
            let range = selectedRange().length > 0 ? selectedRange() : selectedLines
            var text = (string as NSString).substring(with: range)
            let newline = text.hasSuffix("\n")
            if newline { text.removeLast() }
            replace(range, with: TextEditing.toggleBlockComment(text, start: start, end: end) + (newline ? "\n" : ""))
        } else {
            NSSound.beep()
        }
    }

    /// The selected lines once more below; the selection moves to the copy.
    func duplicateLines() {
        let range = selectedLines
        let selection = selectedRange()
        let text = (string as NSString).substring(with: range)
        if text.hasSuffix("\n") {
            replace(NSRange(location: range.location, length: 0), with: text, select: false)
            setSelectedRange(NSRange(location: selection.location + (text as NSString).length, length: selection.length))
        } else {
            replace(NSRange(location: NSMaxRange(range), length: 0), with: "\n" + text, select: false)
            setSelectedRange(NSRange(location: selection.location + (text as NSString).length + 1, length: selection.length))
        }
    }

    func deleteLines() {
        let string = self.string as NSString
        var range = selectedLines
        if NSMaxRange(range) == string.length, range.location > 0, !string.substring(with: range).hasSuffix("\n") {
            range = NSRange(location: range.location - 1, length: range.length + 1)   // last line: take the break before it
        }
        replace(range, with: "", select: false)
    }

    func moveLines(up: Bool) {
        let string = self.string as NSString
        let range = selectedLines
        let selection = selectedRange()
        if up {
            guard range.location > 0 else { NSSound.beep(); return }
            let previous = string.lineRange(for: NSRange(location: range.location - 1, length: 0))
            var lines = string.substring(with: range)
            var above = string.substring(with: previous)
            if !lines.hasSuffix("\n") { lines += "\n"; above.removeLast() }
            replace(NSRange(location: previous.location, length: previous.length + range.length), with: lines + above, select: false)
            setSelectedRange(NSRange(location: selection.location - previous.length, length: selection.length))
        } else {
            guard NSMaxRange(range) < string.length else { NSSound.beep(); return }
            let following = string.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            var lines = string.substring(with: range)
            var below = string.substring(with: following)
            if !below.hasSuffix("\n") { below += "\n"; lines.removeLast() }
            replace(NSRange(location: range.location, length: range.length + following.length), with: below + lines, select: false)
            setSelectedRange(NSRange(location: selection.location + (below as NSString).length, length: selection.length))
        }
    }

    func joinLines() {
        let string = self.string as NSString
        var range = selectedRange()
        if range.length == 0 {
            let line = string.lineRange(for: range)
            guard NSMaxRange(line) < string.length else { NSSound.beep(); return }
            let next = string.lineRange(for: NSRange(location: NSMaxRange(line), length: 0))
            range = NSRange(location: line.location, length: NSMaxRange(next) - line.location)
            if string.substring(with: range).hasSuffix("\n") { range.length -= 1 }
        }
        let joined = string.substring(with: range).replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: " ", options: .regularExpression)
        replace(range, with: joined)
    }

    func apply(_ transform: TextTransform) {
        var range = selectedRange()
        if transform.isLineBased {
            range = range.length > 0 ? selectedLines : NSRange(location: 0, length: (string as NSString).length)
        } else if range.length == 0 {
            switch transform {
            case .uppercase, .lowercase, .capitalize: range = selectionRange(forProposedRange: range, granularity: .selectByWord)
            default: range = NSRange(location: 0, length: (string as NSString).length)
            }
        }
        let old = (string as NSString).substring(with: range)
        let new = transform.apply(old, tabWidth: settings.tabWidth)
        if new != old { replace(range, with: new) }
    }

    // MARK: - Selecting occurrences

    private var wordAtCaret: NSRange { selectionRange(forProposedRange: selectedRange(), granularity: .selectByWord) }

    /// ⌘D: selects the word, then each next occurrence in addition.
    func selectNextOccurrence() {
        let string = self.string as NSString
        let current = selectedRanges.map(\.rangeValue)
        guard let last = current.last, last.length > 0 else {
            let word = wordAtCaret
            if word.length > 0 { setSelectedRange(word) }
            return
        }
        let needle = string.substring(with: last)
        var found = string.range(of: needle, options: [], range: NSRange(location: NSMaxRange(last), length: string.length - NSMaxRange(last)))
        if found.location == NSNotFound { found = string.range(of: needle, options: [], range: NSRange(location: 0, length: last.location)) }
        guard found.location != NSNotFound, !current.contains(where: { NSEqualRanges($0, found) }) else { NSSound.beep(); return }
        setEditPoints(current + [found] + extraCarets.map { NSRange(location: $0, length: 0) })
        scrollRangeToVisible(found)
    }

    func selectAllOccurrences() {
        let string = self.string as NSString
        var needleRange = selectedRange()
        if needleRange.length == 0 { needleRange = wordAtCaret }
        guard needleRange.length > 0 else { NSSound.beep(); return }
        let needle = string.substring(with: needleRange)
        var ranges: [NSRange] = []
        var search = NSRange(location: 0, length: string.length)
        while true {
            let found = string.range(of: needle, options: [], range: search)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            search = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
        }
        setEditPoints(ranges)
    }

    /// One insertion point at the end of every selected line.
    func splitSelectionIntoLines() {
        let string = self.string as NSString
        var points: [NSRange] = []
        for range in selectedRanges.map(\.rangeValue) {
            guard range.length > 0 else { points.append(range); continue }
            var index = range.location
            while index < NSMaxRange(range) {
                var start = 0, end = 0, contentsEnd = 0
                string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
                let lineEnd = min(contentsEnd, NSMaxRange(range))
                points.append(NSRange(location: lineEnd, length: 0))
                index = end
            }
        }
        setEditPoints(points)
    }

    func goToLine(_ line: Int) {
        let start = lineStart(line)
        let range = (string as NSString).lineRange(for: NSRange(location: start, length: 0))
        clearExtraCarets()
        setSelectedRange(NSRange(location: start, length: 0))
        scrollRangeToVisible(range)
        showFindIndicator(for: range.length > 0 ? range : NSRange(location: start, length: 0))
    }

    // MARK: - Colours

    private var highlightGeneration = 0

    /// Colours the text in the background (big files) and applies the result if the text didn't change meanwhile.
    func highlight(immediately: Bool = false) {
        guard let layoutManager else { return }
        highlightGeneration += 1
        let generation = highlightGeneration
        let text = (string as NSString).copy() as! NSString
        let syntax = self.syntax
        let whole = NSRange(location: 0, length: text.length)
        if syntax.id == Syntax.plain.id || text.length > 4_000_000 {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            return
        }
        let apply: ([Token]) -> Void = { [weak self] tokens in
            guard let self, generation == self.highlightGeneration, let layoutManager = self.layoutManager,
                  layoutManager.textStorage?.length == text.length else { return }
            let theme = AppSettings.shared.currentTheme
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            for token in tokens {
                layoutManager.addTemporaryAttribute(.foregroundColor, value: theme.color(token.kind), forCharacterRange: token.range)
            }
        }
        if immediately || text.length < 50_000 {
            apply(Highlighter(syntax: syntax).tokens(in: text))
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let tokens = Highlighter(syntax: syntax).tokens(in: text)
                DispatchQueue.main.async { apply(tokens) }
            }
        }
    }

    /// Yellow marks for search matches, grey ones for the other occurrences of the selected word.
    var findMatches: [NSRange] = [] { didSet { updateBackgroundMarks() } }
    private var wordMatches: [NSRange] = []

    func updateWordMatches() {
        let string = self.string as NSString
        let selection = selectedRange()
        var matches: [NSRange] = []
        if settings.highlightMatches, selectedRanges.count == 1, selection.length > 0, selection.length < 100 {
            let word = string.substring(with: selection)
            if !word.contains(where: { $0.isWhitespace }), selectionRange(forProposedRange: selection, granularity: .selectByWord) == selection {
                var search = NSRange(location: 0, length: string.length)
                while matches.count < 1000 {
                    let found = string.range(of: word, options: [], range: search)
                    guard found.location != NSNotFound else { break }
                    if found != selection { matches.append(found) }
                    search = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
                }
            }
        }
        guard matches != wordMatches else { return }
        wordMatches = matches
        updateBackgroundMarks()
    }

    private func updateBackgroundMarks() {
        guard let layoutManager else { return }
        let whole = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        let word = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35)
        for range in wordMatches where NSMaxRange(range) <= whole.length {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: word, forCharacterRange: range)
        }
        let find = NSColor.systemYellow.withAlphaComponent(0.45)
        for range in findMatches where NSMaxRange(range) <= whole.length {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: find, forCharacterRange: range)
        }
    }
}
