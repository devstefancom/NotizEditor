import Foundation

// Reading and writing plain text files the way they are: the encoding, a byte order mark and the line endings
// are detected when a file is opened and kept when it is saved, so Windows files stay Windows files.
// Inside the editor every line ends with "\n"; the file's own line endings are put back when saving.

/// How the lines of a file end. Windows uses CRLF, macOS and Linux LF; CR alone comes from very old Macs.
enum LineEnding: String, CaseIterable, Identifiable {
    case lf, crlf, cr

    var id: String { rawValue }

    var characters: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    var label: String { rawValue.uppercased() }

    var title: String {
        switch self {
        case .lf: L("macOS / Linux (LF)")
        case .crlf: L("Windows (CRLF)")
        case .cr: L("Classic Mac OS (CR)")
        }
    }

    /// The most frequent line ending in the text (nil without line breaks), and whether several kinds occur.
    static func detect(in string: String) -> (ending: LineEnding?, mixed: Bool) {
        var lf = 0, crlf = 0, cr = 0
        var previousCR = false
        for unit in string.utf16 {
            if unit == 10 {
                if previousCR { crlf += 1; cr -= 1 } else { lf += 1 }
                previousCR = false
            } else if unit == 13 {
                cr += 1
                previousCR = true
            } else {
                previousCR = false
            }
        }
        let counts: [(LineEnding, Int)] = [(.lf, lf), (.crlf, crlf), (.cr, cr)]
        let used = counts.filter { $0.1 > 0 }
        guard let most = used.max(by: { $0.1 < $1.1 }) else { return (nil, false) }
        return (most.0, used.count > 1)
    }
}

/// The text encodings offered in the Format menu, most common first.
enum TextEncodings {
    private static func cf(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }

    static let isoLatin9 = cf(.isoLatin9)
    static let koi8R = cf(.KOI8_R)
    static let gb18030 = cf(.GB_18030_2000)
    static let big5 = cf(.big5)
    static let eucKR = cf(.EUC_KR)

    /// Grouped like a menu: nil marks a separator.
    static let menu: [String.Encoding?] = [
        .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian, nil,
        .windowsCP1252, .isoLatin1, isoLatin9, .macOSRoman, .ascii, nil,
        .windowsCP1250, .isoLatin2, .windowsCP1251, koi8R, .windowsCP1253, .windowsCP1254, nil,
        .shiftJIS, .japaneseEUC, .iso2022JP, gb18030, big5, eucKR,
    ]

    static var all: [String.Encoding] { menu.compactMap { $0 } }

    static func name(_ encoding: String.Encoding) -> String {
        String.localizedName(of: encoding)
    }

    /// A short name for the status bar.
    static func shortName(_ encoding: String.Encoding, bom: Bool) -> String {
        let name: String
        switch encoding {
        case .utf8: name = "UTF-8"
        case .utf16LittleEndian: name = "UTF-16 LE"
        case .utf16BigEndian: name = "UTF-16 BE"
        case .utf32LittleEndian: name = "UTF-32 LE"
        case .utf32BigEndian: name = "UTF-32 BE"
        case .windowsCP1252: name = "Windows-1252"
        case .isoLatin1: name = "ISO-8859-1"
        case .macOSRoman: name = "Mac Roman"
        case .ascii: name = "ASCII"
        default: name = Self.name(encoding)
        }
        return bom ? name + " BOM" : name
    }

    /// Encodings that can have a byte order mark.
    static func supportsBOM(_ encoding: String.Encoding) -> Bool {
        [.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian].contains(encoding)
    }

    static func bom(_ encoding: String.Encoding) -> [UInt8] {
        switch encoding {
        case .utf8: [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: [0xFF, 0xFE]
        case .utf16BigEndian: [0xFE, 0xFF]
        case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
        default: []
        }
    }
}

struct DecodedText {
    /// With "\n" line endings only.
    var string: String
    var encoding: String.Encoding
    var hasBOM: Bool
    var lineEnding: LineEnding
    var mixedLineEndings: Bool
}

enum TextFile {
    enum Failure: Error {
        case binary
        case undecodable(String.Encoding)
    }

    /// Reads a file's bytes. With `encoding` the file is read in exactly that encoding ("Reinterpret as"),
    /// otherwise the encoding is detected.
    static func decode(_ data: Data, encoding forced: String.Encoding? = nil, defaultLineEnding: LineEnding = .lf) throws -> DecodedText {
        var bytes = data
        var encoding: String.Encoding
        var hasBOM = false
        var string: String?

        if let bom = detectBOM(data), forced == nil || forced == bom.encoding {
            encoding = bom.encoding
            hasBOM = true
            bytes = data.dropFirst(bom.length)
            string = String(data: bytes, encoding: encoding)
        } else if let forced {
            encoding = forced
            string = String(data: bytes, encoding: forced)
        } else {
            (string, encoding) = try detect(data)
        }
        guard let string else { throw Failure.undecodable(encoding) }
        let lines = LineEnding.detect(in: string)
        return DecodedText(string: normalizeLineEndings(string), encoding: encoding, hasBOM: hasBOM,
                           lineEnding: lines.ending ?? defaultLineEnding, mixedLineEndings: lines.mixed)
    }

    /// The bytes to write; nil when the text contains characters the encoding can't hold.
    static func encode(_ string: String, encoding: String.Encoding, hasBOM: Bool, lineEnding: LineEnding) -> Data? {
        let text = lineEnding == .lf ? string : string.replacingOccurrences(of: "\n", with: lineEnding.characters)
        guard let body = text.data(using: encoding, allowLossyConversion: false) else { return nil }
        guard hasBOM, TextEncodings.supportsBOM(encoding) else { return body }
        return Data(TextEncodings.bom(encoding)) + body
    }

    /// Characters the encoding can't hold, for the warning before saving (at most `limit`).
    static func unsupportedCharacters(in string: String, encoding: String.Encoding, limit: Int = 8) -> [Character] {
        var found: [Character] = []
        for character in string where String(character).data(using: encoding, allowLossyConversion: false) == nil {
            if !found.contains(character) { found.append(character) }
            if found.count >= limit { break }
        }
        return found
    }

    static func normalizeLineEndings(_ string: String) -> String {
        guard string.contains("\r") else { return string }
        return string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func detectBOM(_ data: Data) -> (encoding: String.Encoding, length: Int)? {
        let b = [UInt8](data.prefix(4))
        if b.starts(with: [0xEF, 0xBB, 0xBF]) { return (.utf8, 3) }
        if b.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return (.utf32LittleEndian, 4) }
        if b.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return (.utf32BigEndian, 4) }
        if b.starts(with: [0xFF, 0xFE]) { return (.utf16LittleEndian, 2) }
        if b.starts(with: [0xFE, 0xFF]) { return (.utf16BigEndian, 2) }
        return nil
    }

    /// Files without a byte order mark: UTF-8 if it is valid UTF-8, UTF-16 if every second byte is zero,
    /// otherwise the most likely of the usual single-byte and Asian encodings (old Windows files are mostly Windows-1252).
    private static func detect(_ data: Data) throws -> (String?, String.Encoding) {
        if data.isEmpty { return ("", .utf8) }
        let sample = [UInt8](data.prefix(8192))
        if sample.contains(0) {
            var evenZeros = 0, oddZeros = 0
            for (index, byte) in sample.enumerated() where byte == 0 {
                if index.isMultiple(of: 2) { evenZeros += 1 } else { oddZeros += 1 }
            }
            let half = sample.count / 2
            if oddZeros > half * 6 / 10, evenZeros <= half / 10, let s = String(data: data, encoding: .utf16LittleEndian) {
                return (s, .utf16LittleEndian)
            }
            if evenZeros > half * 6 / 10, oddZeros <= half / 10, let s = String(data: data, encoding: .utf16BigEndian) {
                return (s, .utf16BigEndian)
            }
            throw Failure.binary
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }

        var converted: NSString?
        var lossy = ObjCBool(false)
        let suggestions: [String.Encoding] = [.windowsCP1252, .isoLatin1, .macOSRoman, .shiftJIS, .japaneseEUC,
                                              TextEncodings.gb18030, TextEncodings.big5, TextEncodings.eucKR,
                                              .windowsCP1251, .windowsCP1250]
        let raw = NSString.stringEncoding(for: data, encodingOptions: [
            .suggestedEncodingsKey: suggestions.map(\.rawValue),
            .useOnlySuggestedEncodingsKey: true,
            .allowLossyKey: false,
        ], convertedString: &converted, usedLossyConversion: &lossy)
        let detected = String.Encoding(rawValue: raw)
        let asian: [String.Encoding] = [.shiftJIS, .japaneseEUC, TextEncodings.gb18030, TextEncodings.big5, TextEncodings.eucKR]
        if raw != 0, let converted, !lossy.boolValue, asian.contains(detected) { return (converted as String, detected) }
        // Single-byte encodings look alike to the detector (ü is the same byte in Windows-1250 and -1252):
        // prefer Windows-1252, the usual one for old Windows files here. Format → Reinterpret fixes a wrong guess.
        if let s = String(data: data, encoding: .windowsCP1252) { return (s, .windowsCP1252) }
        if raw != 0, let converted, !lossy.boolValue { return (converted as String, detected) }
        return (String(data: data, encoding: .isoLatin1), .isoLatin1)
    }
}
