import Foundation

// Finds what to colour in a text and the entries of the outline menu. Pure Foundation, so it can run
// in the background for big files and be tested without a window; EditorTextView applies the colours.

struct Token {
    let kind: TokenKind
    let range: NSRange
}

struct OutlineItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let range: NSRange
    let level: Int
    let isSeparator: Bool
}

struct Highlighter {
    let syntax: Syntax

    private static let lock = NSLock()
    nonisolated(unsafe) private static var compiled: [String: [(TokenKind, NSRegularExpression)]] = [:]

    /// Word lists and patterns, compiled once per language.
    private var rules: [(TokenKind, NSRegularExpression)] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let rules = Self.compiled[syntax.id] { return rules }
        var rules: [(TokenKind, NSRegularExpression)] = []
        func add(_ kind: TokenKind, _ pattern: String, caseInsensitive: Bool = false) {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if caseInsensitive { options.insert(.caseInsensitive) }
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) { rules.append((kind, regex)) }
        }
        func words(_ kind: TokenKind, _ list: [String]) {
            guard !list.isEmpty else { return }
            let alternatives = list.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern).joined(separator: "|")
            add(kind, #"(?<![\w$@.])(?:"# + alternatives + #")(?![\w$])"#, caseInsensitive: syntax.caseInsensitive)
        }
        if syntax.numbers {
            add(.number, #"(?<![\w.$#])(?:0[xX][0-9A-Fa-f_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)(?![\w])"#)
        }
        words(.type, syntax.types)
        words(.command, syntax.commands)
        words(.value, syntax.values)
        words(.keyword, syntax.keywords)
        for (kind, pattern) in syntax.patterns { add(kind, pattern) }
        Self.compiled[syntax.id] = rules
        return rules
    }

    /// Everything to colour, in the order to apply it (later tokens win).
    func tokens(in text: NSString) -> [Token] {
        guard syntax.id != Syntax.plain.id, text.length > 0 else { return [] }
        let string = text as String
        let whole = NSRange(location: 0, length: text.length)
        var tokens: [Token] = []
        for (kind, regex) in rules {
            regex.enumerateMatches(in: string, range: whole) { match, _, _ in
                if let range = match?.range, range.length > 0 { tokens.append(Token(kind: kind, range: range)) }
            }
        }
        tokens += commentsAndStrings(in: text)
        return tokens
    }

    /// Comments and strings, found in one pass from the start so a "//" inside a string or a quote inside
    /// a comment doesn't count.
    func commentsAndStrings(in text: NSString) -> [Token] {
        let length = text.length
        guard syntax.lineComment != nil || syntax.blockComment != nil || !syntax.quotes.isEmpty || !syntax.multilineQuotes.isEmpty
        else { return [] }
        var buffer = [unichar](repeating: 0, count: length)
        text.getCharacters(&buffer, range: NSRange(location: 0, length: length))

        func units(_ s: String) -> [unichar] { Array(s.utf16) }
        let lineComment = syntax.lineComment.map(units)
        let block = syntax.blockComment.map { (units($0.0), units($0.1)) }
        let multiline = syntax.multilineQuotes.map(units)
        let quotes = Set(syntax.quotes.compactMap { $0.utf16.first })

        func matches(_ pattern: [unichar], at index: Int) -> Bool {
            guard index + pattern.count <= length else { return false }
            for offset in 0..<pattern.count where buffer[index + offset] != pattern[offset] { return false }
            return true
        }
        /// Index just after `end`, searching from `from`; skips backslash escapes if asked. The text's end if not found.
        func find(_ end: [unichar], from: Int, escapes: Bool) -> Int {
            var index = from
            while index < length {
                if escapes, buffer[index] == 92 { index += 2; continue }
                if matches(end, at: index) { return index + end.count }
                index += 1
            }
            return length
        }

        var tokens: [Token] = []
        var index = 0
        while index < length {
            let unit = buffer[index]
            if let (start, end) = block, matches(start, at: index) {
                let stop = find(end, from: index + start.count, escapes: false)
                tokens.append(Token(kind: .comment, range: NSRange(location: index, length: stop - index)))
                index = stop
                continue
            }
            if let delimiter = multiline.first(where: { matches($0, at: index) }) {
                let stop = find(delimiter, from: index + delimiter.count, escapes: true)
                tokens.append(Token(kind: .string, range: NSRange(location: index, length: stop - index)))
                index = stop
                continue
            }
            if let lineComment, matches(lineComment, at: index),
               !syntax.lineCommentNeedsSpace || index == 0 || [32, 9, 10].contains(buffer[index - 1]) {
                var stop = index
                while stop < length, buffer[stop] != 10 { stop += 1 }
                tokens.append(Token(kind: .comment, range: NSRange(location: index, length: stop - index)))
                index = stop
                continue
            }
            if quotes.contains(unit) {
                var stop = index + 1
                while stop < length, buffer[stop] != unit, buffer[stop] != 10 {
                    stop += buffer[stop] == 92 ? 2 : 1
                }
                stop = min(stop + 1, length)
                var kind = TokenKind.string
                if syntax.keyStrings {
                    var next = stop
                    while next < length, [32, 9].contains(buffer[next]) { next += 1 }
                    if next < length, buffer[next] == 58 { kind = .variable }   // "key":
                }
                tokens.append(Token(kind: kind, range: NSRange(location: index, length: stop - index)))
                index = stop
                continue
            }
            index += 1
        }
        return tokens
    }

    /// The entries of the outline menu, in text order.
    func outline(in text: NSString) -> [OutlineItem] {
        let string = text as String
        let whole = NSRange(location: 0, length: text.length)
        var items: [(NSRange, String, Int, Bool)] = []
        for rule in syntax.outline {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.anchorsMatchLines]) else { continue }
            let hasTitle = rule.pattern.contains("(?<title>"), hasLevel = rule.pattern.contains("(?<level>")
            regex.enumerateMatches(in: string, range: whole) { match, _, _ in
                guard let match else { return }
                var titleRange = match.range
                if hasTitle { titleRange = match.range(withName: "title") } else if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                    titleRange = match.range(at: 1)
                }
                var level = rule.level ?? 0
                if rule.level == nil, hasLevel {
                    let levelRange = match.range(withName: "level")
                    if levelRange.location != NSNotFound {
                        let marker = text.substring(with: levelRange)
                        level = max(0, (Int(marker) ?? marker.count) - 1)
                    }
                }
                let title = titleRange.location == NSNotFound ? "" : text.substring(with: titleRange)
                    .trimmingCharacters(in: .whitespaces)
                items.append((match.range, title, level, rule.isSeparator))
            }
        }
        items.sort { $0.0.location < $1.0.location }
        var seenLines = Set<Int>()
        var result: [OutlineItem] = []
        for item in items {
            let line = text.lineRange(for: NSRange(location: item.0.location, length: 0)).location
            guard seenLines.insert(line).inserted else { continue }   // one entry per line
            result.append(OutlineItem(id: result.count, title: item.1, range: item.0, level: item.2, isSeparator: item.3))
        }
        return result
    }
}
