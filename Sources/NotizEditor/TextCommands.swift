import Foundation

// The commands of the Text menu that change whole lines or the selected text. Pure functions from text to text,
// so they can be tested; EditorTextView applies them to the selection (or to the whole note) with undo.

enum TextTransform: String, CaseIterable {
    case uppercase, lowercase, capitalize
    case sortLines, sortLinesNumerically, reverseLines, removeDuplicateLines, shuffleLines, removeEmptyLines
    case trimTrailingWhitespace, tabsToSpaces, spacesToTabs
    case nfc, nfd, nfkc, nfkd
    case fullwidthToHalfwidth, halfwidthToFullwidth
    case straightenQuotes

    var title: String {
        switch self {
        case .uppercase: L("Make Upper Case")
        case .lowercase: L("Make Lower Case")
        case .capitalize: L("Capitalize Words")
        case .sortLines: L("Sort Lines")
        case .sortLinesNumerically: L("Sort Lines by Number")
        case .reverseLines: L("Reverse Lines")
        case .removeDuplicateLines: L("Remove Duplicate Lines")
        case .shuffleLines: L("Shuffle Lines")
        case .removeEmptyLines: L("Remove Empty Lines")
        case .trimTrailingWhitespace: L("Trim Trailing Whitespace")
        case .tabsToSpaces: L("Convert Tabs to Spaces")
        case .spacesToTabs: L("Convert Spaces to Tabs")
        case .nfc: "NFC"
        case .nfd: "NFD"
        case .nfkc: "NFKC"
        case .nfkd: "NFKD"
        case .fullwidthToHalfwidth: L("Fullwidth to Halfwidth")
        case .halfwidthToFullwidth: L("Halfwidth to Fullwidth")
        case .straightenQuotes: L("Straighten Quotes")
        }
    }

    /// Works on whole lines: the selection is widened to full lines first.
    var isLineBased: Bool {
        switch self {
        case .sortLines, .sortLinesNumerically, .reverseLines, .removeDuplicateLines, .shuffleLines, .removeEmptyLines,
             .trimTrailingWhitespace, .tabsToSpaces, .spacesToTabs: true
        default: false
        }
    }

    func apply(_ text: String, tabWidth: Int = 4) -> String {
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .capitalize: return text.capitalized
        case .nfc: return text.precomposedStringWithCanonicalMapping
        case .nfd: return text.decomposedStringWithCanonicalMapping
        case .nfkc: return text.precomposedStringWithCompatibilityMapping
        case .nfkd: return text.decomposedStringWithCompatibilityMapping
        case .fullwidthToHalfwidth: return text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        case .halfwidthToFullwidth: return text.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? text
        case .straightenQuotes:
            return text.replacingOccurrences(of: "[“”„‟″]", with: "\"", options: .regularExpression)
                .replacingOccurrences(of: "[‘’‚‛′]", with: "'", options: .regularExpression)
        default: break
        }
        // Line based: keep a final line break where it was.
        let endsWithNewline = text.hasSuffix("\n")
        var lines = (endsWithNewline ? String(text.dropLast()) : text).components(separatedBy: "\n")
        switch self {
        case .sortLines: lines.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        case .sortLinesNumerically: lines.sort { Self.leadingNumber($0) < Self.leadingNumber($1) }
        case .reverseLines: lines.reverse()
        case .removeDuplicateLines:
            var seen = Set<String>()
            lines = lines.filter { seen.insert($0).inserted }
        case .shuffleLines: lines.shuffle()
        case .removeEmptyLines: lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .trimTrailingWhitespace: lines = lines.map(Self.trimTrailing)
        case .tabsToSpaces: lines = lines.map { Self.expandTabs($0, width: tabWidth) }
        case .spacesToTabs: lines = lines.map { Self.leadingSpacesToTabs($0, width: tabWidth) }
        default: break
        }
        return lines.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
    }

    private static func leadingNumber(_ line: String) -> Double {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { "0123456789.,-".contains($0) }.replacingOccurrences(of: ",", with: ".")
        return Double(digits) ?? .greatestFiniteMagnitude
    }

    static func trimTrailing(_ line: String) -> String {
        var line = line
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return line
    }

    static func expandTabs(_ line: String, width: Int) -> String {
        var result = ""
        var column = 0
        for character in line {
            if character == "\t" {
                let spaces = width - column % width
                result += String(repeating: " ", count: spaces)
                column += spaces
            } else {
                result.append(character)
                column += 1
            }
        }
        return result
    }

    /// Only the indentation at the start of the line; spaces inside the text stay.
    static func leadingSpacesToTabs(_ line: String, width: Int) -> String {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let columns = expandTabs(String(indent), width: width).count
        return String(repeating: "\t", count: columns / width) + String(repeating: " ", count: columns % width)
            + line.dropFirst(indent.count)
    }
}

enum TextEditing {
    /// Indents or outdents every line of `text` by one level.
    static func shift(_ text: String, outdent: Bool, indentUnit: String, tabWidth: Int) -> String {
        let endsWithNewline = text.hasSuffix("\n")
        let lines = (endsWithNewline ? String(text.dropLast()) : text).components(separatedBy: "\n")
        let shifted = lines.map { line -> String in
            guard outdent else { return line.isEmpty ? line : indentUnit + line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(spaces, tabWidth)))
        }
        return shifted.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
    }

    /// Comments the lines out, or back in if all of them are commented already.
    static func toggleLineComment(_ text: String, marker: String) -> String {
        let endsWithNewline = text.hasSuffix("\n")
        let lines = (endsWithNewline ? String(text.dropLast()) : text).components(separatedBy: "\n")
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allCommented = !content.isEmpty && content.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(marker) }
        // New comment markers go at the smallest indentation, so the block stays aligned.
        let indent = content.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let changed = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allCommented {
                guard let range = line.range(of: marker) else { return line }
                var after = line[range.upperBound...]
                if after.hasPrefix(" ") { after = after.dropFirst() }
                return String(line[..<range.lowerBound]) + after
            }
            let index = line.index(line.startIndex, offsetBy: indent)
            return String(line[..<index]) + marker + " " + line[index...]
        }
        return changed.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
    }

    static func toggleBlockComment(_ text: String, start: String, end: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(start), trimmed.hasSuffix(end), trimmed.count >= start.count + end.count {
            var inner = String(trimmed.dropFirst(start.count).dropLast(end.count))
            if inner.hasPrefix(" ") { inner.removeFirst() }
            if inner.hasSuffix(" ") { inner.removeLast() }
            return text.replacingOccurrences(of: trimmed, with: inner)
        }
        return start + " " + text + " " + end
    }

    /// Words like CotEditor counts them: everything between spaces and punctuation, in any script.
    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }
}

/// What the character inspector shows about one character.
struct CharacterInfo {
    let character: String
    let scalars: [(code: String, name: String)]
    let utf8: String
    let utf16: String

    init(_ character: String) {
        self.character = character
        scalars = character.unicodeScalars.map { scalar in
            let code = String(format: "U+%04X", scalar.value)
            let name = scalar.properties.nameAlias ?? scalar.properties.name ?? Self.controlName(scalar) ?? "–"
            return (code, name)
        }
        utf8 = character.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
        utf16 = character.utf16.map { String(format: "%04X", $0) }.joined(separator: " ")
    }

    private static func controlName(_ scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 9: "CHARACTER TABULATION"
        case 10: "LINE FEED (LF)"
        case 13: "CARRIAGE RETURN (CR)"
        default: nil
        }
    }
}
