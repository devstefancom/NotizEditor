import AppKit
import SwiftUI

/// Find and replace in the open note: plain text or regular expressions, all matches marked in yellow.
@MainActor
final class FindModel: ObservableObject {
    @Published var query = ""
    @Published var replacement = ""
    @Published var useRegex = false
    @Published var ignoreCase = true
    @Published var wholeWord = false
    @Published var inSelection = false
    @Published var isVisible = false
    @Published var showReplace = false
    /// Changed to put the cursor into the search field.
    @Published var focusRequest = 0
    @Published private(set) var matchCount = 0
    @Published private(set) var currentIndex: Int?
    @Published private(set) var error: String?
    private(set) var matches: [NSRange] = []
    /// The selection when "In selection" was switched on.
    private var scope: NSRange?

    func show(replace: Bool, focus: Bool = true) {
        isVisible = true
        if replace { showReplace = true }
        if focus { focusRequest += 1 }
    }

    func hide(in textView: EditorTextView?) {
        isVisible = false
        matches = []
        textView?.findMatches = []
        if let textView { textView.window?.makeFirstResponder(textView) }
    }

    private func regex() -> NSRegularExpression? {
        guard !query.isEmpty else { error = nil; return nil }
        var pattern = useRegex ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord { pattern = #"(?<!\w)(?:"# + pattern + #")(?!\w)"# }
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if ignoreCase { options.insert(.caseInsensitive) }
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            error = nil
            return regex
        } catch {
            self.error = L("Invalid regular expression")
            return nil
        }
    }

    private var template: String {
        guard useRegex else { return NSRegularExpression.escapedTemplate(for: replacement) }
        return replacement.replacingOccurrences(of: #"\n"#, with: "\n").replacingOccurrences(of: #"\t"#, with: "\t")
    }

    func updateMatches(in textView: EditorTextView) {
        guard isVisible, let regex = regex() else {
            matches = []
            matchCount = 0
            currentIndex = nil
            textView.findMatches = []
            return
        }
        let string = textView.string
        let length = (string as NSString).length
        if inSelection, scope == nil, textView.selectedRange().length > 0 { scope = textView.selectedRange() }
        if !inSelection { scope = nil }
        var range = scope ?? NSRange(location: 0, length: length)
        if NSMaxRange(range) > length { range = NSRange(location: 0, length: length) }
        var found: [NSRange] = []
        regex.enumerateMatches(in: string, range: range) { match, _, stop in
            guard let match, match.range.length > 0 else { return }
            found.append(match.range)
            if found.count >= 20_000 { stop.pointee = true }
        }
        matches = found
        matchCount = found.count
        textView.findMatches = found
        updateCurrent(in: textView)
    }

    private func updateCurrent(in textView: EditorTextView) {
        let selection = textView.selectedRange()
        currentIndex = matches.firstIndex { NSEqualRanges($0, selection) }
    }

    private func select(_ range: NSRange, in textView: EditorTextView) {
        textView.clearExtraCarets()
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
        updateCurrent(in: textView)
    }

    func findNext(in textView: EditorTextView, from start: Int? = nil) {
        if matches.isEmpty { updateMatches(in: textView) }
        guard !matches.isEmpty else { NSSound.beep(); return }
        let location = start ?? NSMaxRange(textView.selectedRange())
        let next = matches.first { $0.location >= location && !NSEqualRanges($0, textView.selectedRange()) } ?? matches[0]
        select(next, in: textView)
    }

    func findPrevious(in textView: EditorTextView) {
        if matches.isEmpty { updateMatches(in: textView) }
        guard !matches.isEmpty else { NSSound.beep(); return }
        let location = textView.selectedRange().location
        let previous = matches.last { $0.location < location } ?? matches[matches.count - 1]
        select(previous, in: textView)
    }

    /// Replaces the selected match and goes to the next one.
    func replace(in textView: EditorTextView) {
        guard let regex = regex() else { return }
        let selection = textView.selectedRange()
        let string = textView.string
        if let match = regex.firstMatch(in: string, range: selection), NSEqualRanges(match.range, selection) {
            let text = regex.replacementString(for: match, in: string, offset: 0, template: template)
            textView.replace(selection, with: text, select: false)
            updateMatches(in: textView)
        }
        findNext(in: textView)
    }

    func replaceAll(in textView: EditorTextView) {
        updateMatches(in: textView)
        guard let regex = regex(), !matches.isEmpty else { NSSound.beep(); return }
        let string = textView.string
        let template = self.template
        var replacements: [NSRange: String] = [:]
        for range in matches {
            if let match = regex.firstMatch(in: string, options: [.anchored, .withoutAnchoringBounds], range: range) {
                replacements[range] = regex.replacementString(for: match, in: string, offset: 0, template: template)
            }
        }
        textView.edit(matches, selectInserted: true) { replacements[$0] ?? "" }
        scope = nil
        updateMatches(in: textView)
        textView.collapseToMainSelection()
    }

    /// Every match gets its own selection, to type over all at once.
    func selectAll(in textView: EditorTextView) {
        updateMatches(in: textView)
        guard !matches.isEmpty else { NSSound.beep(); return }
        textView.window?.makeFirstResponder(textView)
        textView.setEditPoints(matches)
    }

    /// ⌘E: the selected text becomes the search text.
    func useSelection(in textView: EditorTextView) {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { NSSound.beep(); return }
        query = (textView.string as NSString).substring(with: selection)
        if useRegex { query = NSRegularExpression.escapedPattern(for: query) }
        isVisible = true
        updateMatches(in: textView)
    }
}

struct FindBar: View {
    @ObservedObject var find: FindModel
    let textView: () -> EditorTextView?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    find.showReplace.toggle()
                } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(find.showReplace ? 90 : 0))
                }
                .buttonStyle(.borderless)
                .help(L("Show replace"))
                TextField(L("Find"), text: $find.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit { if let tv = textView() { find.findNext(in: tv) } }
                    .onExitCommand { find.hide(in: textView()) }
                Text(countLabel)
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(find.error == nil ? Color.secondary : Color.red)
                    .frame(minWidth: 70, alignment: .trailing)
                ControlGroup {
                    Button { if let tv = textView() { find.findPrevious(in: tv) } } label: { Image(systemName: "chevron.left") }
                        .help(L("Previous (⇧⌘G)"))
                    Button { if let tv = textView() { find.findNext(in: tv) } } label: { Image(systemName: "chevron.right") }
                        .help(L("Next (⌘G)"))
                }
                .frame(width: 64)
                Toggle(isOn: $find.ignoreCase) { Text("Aa") }.toggleStyle(.button).help(L("Ignore upper and lower case"))
                Toggle(isOn: $find.wholeWord) { Text("W") }.toggleStyle(.button).help(L("Whole words only"))
                Toggle(isOn: $find.useRegex) { Text(".*") }.toggleStyle(.button).help(L("Regular expression"))
                Toggle(isOn: $find.inSelection) { Image(systemName: "text.badge.checkmark") }.toggleStyle(.button)
                    .help(L("Only in the selected text"))
                Button(L("Done")) { find.hide(in: textView()) }
            }
            if find.showReplace {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 14, height: 1)
                    TextField(find.useRegex ? L("Replace ($1 = first group)") : L("Replace"), text: $find.replacement)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if let tv = textView() { find.replace(in: tv) } }
                    Button(L("Replace")) { if let tv = textView() { find.replace(in: tv) } }
                    Button(L("Replace All")) { if let tv = textView() { find.replaceAll(in: tv) } }
                    Button(L("Select All")) { if let tv = textView() { find.selectAll(in: tv) } }
                        .help(L("Selects every match, so you can type over all of them at once"))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        .onAppear { searchFocused = true; refresh() }
        .onChange(of: find.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: find.query) { _, _ in refresh() }
        .onChange(of: find.useRegex) { _, _ in refresh() }
        .onChange(of: find.ignoreCase) { _, _ in refresh() }
        .onChange(of: find.wholeWord) { _, _ in refresh() }
        .onChange(of: find.inSelection) { _, _ in refresh() }
    }

    private func refresh() {
        if let tv = textView() { find.updateMatches(in: tv) }
    }

    private var countLabel: String {
        if let error = find.error { return error }
        if find.query.isEmpty { return "" }
        if find.matchCount == 0 { return L("Not found") }
        if let index = find.currentIndex { return L("%d of %d", index + 1, find.matchCount) }
        return find.matchCount == 1 ? L("1 match") : L("%d matches", find.matchCount)
    }
}
