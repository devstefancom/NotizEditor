import Foundation

// The languages NotizEditor colours. Each one is a small description – words, comments, strings and a few
// patterns – that Highlighter.swift turns into colours, plus the rules for the outline menu (headings, functions …).
// The language is picked by file extension or file name and can be changed in Format → Syntax.

enum TokenKind: Int, CaseIterable {
    case keyword, command, type, attribute, variable, value, number, string, character, comment, markup
}

struct OutlineRule {
    /// The heading is capture group "title" if there is one, else group 1, else the whole match.
    let pattern: String
    /// Fixed indentation level, or nil to take the length of capture group "level" (for # headings).
    var level: Int? = 0
    /// Shown as a separator line in the menu (e.g. "// MARK: -").
    var isSeparator = false
}

struct Syntax: Identifiable, Hashable {
    let id: String
    let name: String
    var extensions: [String] = []
    var fileNames: [String] = []
    var lineComment: String?
    /// The line comment only counts at the start of a line or after a space (shell: "$#" is no comment).
    var lineCommentNeedsSpace = false
    var blockComment: (String, String)?
    /// Single-line strings, with backslash escapes.
    var quotes: [Character] = []
    /// Strings that may span lines, like Python's """ or Swift's """.
    var multilineQuotes: [String] = []
    var keywords: [String] = []
    var commands: [String] = []
    var types: [String] = []
    var values: [String] = []
    var caseInsensitive = false
    var numbers = true
    /// Extra patterns, applied in order after the word lists.
    var patterns: [(TokenKind, String)] = []
    var outline: [OutlineRule] = []
    /// Strings followed by ":" are keys (JSON) and get the variable colour.
    var keyStrings = false

    static func == (a: Syntax, b: Syntax) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Syntax {
    static let plain = Syntax(id: "plain", name: L("Plain Text"), numbers: false)

    /// The language for a file name, plain text if none fits.
    static func detect(fileName: String) -> Syntax {
        let lower = fileName.lowercased()
        if let byName = all.first(where: { $0.fileNames.contains(lower) }) { return byName }
        let ext = (lower as NSString).pathExtension
        guard !ext.isEmpty else { return .plain }
        return all.first { $0.extensions.contains(ext) } ?? .plain
    }

    static func named(_ id: String) -> Syntax? { all.first { $0.id == id } }

    private static let cKeywords = ["auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern",
                                    "for", "goto", "if", "inline", "register", "restrict", "return", "sizeof", "static",
                                    "struct", "switch", "typedef", "union", "volatile", "while", "_Bool", "_Atomic"]
    private static let cTypes = ["char", "double", "float", "int", "long", "short", "signed", "unsigned", "void", "bool",
                                 "size_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t",
                                 "uint64_t", "FILE"]
    private static let jsKeywords = ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
                                     "default", "delete", "do", "else", "export", "extends", "finally", "for", "from",
                                     "function", "get", "if", "import", "in", "instanceof", "let", "new", "of", "return",
                                     "set", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void",
                                     "while", "with", "yield"]
    private static let jsCommands = ["console", "document", "window", "Math", "JSON", "Promise", "Object", "Array", "String",
                                     "Number", "Boolean", "Date", "RegExp", "Map", "Set", "Error", "require", "module",
                                     "setTimeout", "setInterval", "fetch", "parseInt", "parseFloat"]
    private static let jsValues = ["true", "false", "null", "undefined", "NaN", "Infinity"]
    private static let jsOutline = [
        OutlineRule(pattern: #"^[ \t]*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\*?\s+([A-Za-z_$][\w$]*)"#),
        OutlineRule(pattern: #"^[ \t]*(?:export\s+)?(?:default\s+)?class\s+([A-Za-z_$][\w$]*)"#),
        OutlineRule(pattern: #"^[ \t]*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:function|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)"#),
    ]
    private static let markupTag = #"</?[A-Za-z][\w:.-]*|/?>"#
    private static let markupAttribute = #"(?<=\s)[A-Za-z_:][\w:.-]*(?=\s*=)"#
    private static let markupValue = #"(?<==)\s*("[^"]*"|'[^']*')"#

    static let all: [Syntax] = [
        Syntax(id: "markdown", name: "Markdown", extensions: ["md", "markdown", "mdown", "mkd"],
               numbers: false,
               patterns: [
                   (.keyword, #"(?m)^#{1,6}[ \t].*$"#),
                   (.keyword, #"(?m)^.+\n(?:=+|-+)[ \t]*$"#),
                   (.command, #"(?m)^[ \t]*(?:[-*+]|\d+[.)])[ \t]"#),
                   (.comment, #"(?m)^>.*$"#),
                   (.attribute, #"\*\*[^*\n]+\*\*|__[^_\n]+__"#),
                   (.variable, #"(?<![*\w])\*[^*\s][^*\n]*\*(?!\*)|(?<![_\w])_[^_\s][^_\n]*_(?![_\w])"#),
                   (.type, #"!?\[[^\]\n]*\]\([^)\n]*\)|<https?://[^>\s]+>"#),
                   (.markup, #"(?m)^[ \t]*(?:[-*_][ \t]*){3,}$"#),
                   (.string, #"`[^`\n]+`"#),
                   (.string, #"(?ms)^```.*?^```[ \t]*$"#),
               ],
               outline: [OutlineRule(pattern: #"^(?<level>#{1,6})[ \t]+(?<title>.+?)[ \t#]*$"#, level: nil)]),

        Syntax(id: "swift", name: "Swift", extensions: ["swift"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\""], multilineQuotes: ["\"\"\""],
               keywords: ["actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class",
                          "continue", "convenience", "default", "defer", "deinit", "didSet", "do", "dynamic", "else",
                          "enum", "extension", "fallthrough", "fileprivate", "final", "for", "func", "get", "guard", "if",
                          "import", "in", "indirect", "init", "inout", "internal", "is", "lazy", "let", "mutating",
                          "nonisolated", "open", "operator", "override", "private", "protocol", "public", "repeat",
                          "required", "rethrows", "return", "self", "Self", "set", "some", "static", "struct",
                          "subscript", "super", "switch", "throw", "throws", "try", "typealias", "unowned", "var",
                          "weak", "where", "while", "willSet", "consuming", "borrowing", "sending"],
               commands: ["print", "debugPrint", "fatalError", "precondition", "assert", "min", "max", "abs", "zip",
                          "stride", "withAnimation", "DispatchQueue", "Task"],
               types: ["Int", "Double", "Float", "Bool", "String", "Character", "Array", "Dictionary", "Set", "Optional",
                       "Result", "Error", "Void", "Never", "URL", "Data", "Date", "CGFloat", "CGPoint", "CGSize", "CGRect",
                       "UInt", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64", "Substring",
                       "View", "some", "NSObject", "NSString", "NSRange"],
               values: ["true", "false", "nil"],
               patterns: [(.attribute, #"@\w+"#), (.variable, #"#\w+"#), (.type, #"\b[A-Z][A-Za-z0-9_]*\b"#)],
               outline: [
                   OutlineRule(pattern: #"^[ \t]*//[ \t]*MARK:[ \t]*-[ \t]*$"#, isSeparator: true),
                   OutlineRule(pattern: #"^[ \t]*//[ \t]*(?:MARK|TODO|FIXME):[ \t]*(?:-[ \t]*)?(.+)$"#),
                   OutlineRule(pattern: #"^[ \t]*(?:@\w+[ \t]+)*(?:(?:public|private|fileprivate|internal|open|final|static|class|override|mutating|nonisolated)[ \t]+)*(?:class|struct|enum|protocol|extension|actor)[ \t]+([\w.]+)"#),
                   OutlineRule(pattern: #"^[ \t]*(?:@\w+[ \t]+)*(?:(?:public|private|fileprivate|internal|open|final|static|class|override|mutating|nonisolated)[ \t]+)*func[ \t]+([^\s(<]+)"#, level: 1),
               ]),

        Syntax(id: "python", name: "Python", extensions: ["py", "pyw", "pyi"],
               lineComment: "#", quotes: ["\"", "'"], multilineQuotes: ["\"\"\"", "'''"],
               keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif",
                          "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda",
                          "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case"],
               commands: ["print", "len", "range", "open", "str", "int", "float", "list", "dict", "set", "tuple", "type",
                          "isinstance", "enumerate", "zip", "map", "filter", "sorted", "sum", "min", "max", "abs", "input",
                          "super", "self", "cls"],
               types: ["object", "Exception", "ValueError", "TypeError", "KeyError", "IndexError", "bytes", "bool"],
               values: ["True", "False", "None"],
               patterns: [(.attribute, #"(?m)^[ \t]*@[\w.]+"#)],
               outline: [
                   OutlineRule(pattern: #"^class[ \t]+(\w+)"#),
                   OutlineRule(pattern: #"^(?:async[ \t]+)?def[ \t]+(\w+)"#),
                   OutlineRule(pattern: #"^[ \t]+(?:async[ \t]+)?def[ \t]+(\w+)"#, level: 1),
               ]),

        Syntax(id: "javascript", name: "JavaScript", extensions: ["js", "mjs", "cjs", "jsx"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"],
               keywords: jsKeywords, commands: jsCommands, values: jsValues, outline: jsOutline),

        Syntax(id: "typescript", name: "TypeScript", extensions: ["ts", "tsx", "mts", "cts"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"],
               keywords: jsKeywords + ["abstract", "as", "declare", "enum", "implements", "interface", "keyof", "namespace",
                                       "private", "protected", "public", "readonly", "satisfies", "type"],
               commands: jsCommands,
               types: ["string", "number", "boolean", "any", "unknown", "never", "object", "symbol", "bigint", "Record",
                       "Partial", "Readonly", "Array", "Promise"],
               values: jsValues,
               patterns: [(.attribute, #"@\w+"#)],
               outline: jsOutline + [OutlineRule(pattern: #"^[ \t]*(?:export\s+)?(?:interface|type|enum)\s+(\w+)"#)]),

        Syntax(id: "json", name: "JSON", extensions: ["json", "jsonc", "json5", "webmanifest", "geojson"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\""],
               values: ["true", "false", "null"], keyStrings: true),

        Syntax(id: "html", name: "HTML", extensions: ["html", "htm", "xhtml", "shtml", "vue", "svelte"],
               blockComment: ("<!--", "-->"), numbers: false,
               patterns: [(.keyword, markupTag), (.attribute, markupAttribute), (.string, markupValue),
                          (.value, #"&[A-Za-z0-9#]+;"#), (.markup, #"(?i)<!DOCTYPE[^>]*>"#)],
               outline: [OutlineRule(pattern: #"(?i)<h(?<level>[1-6])[^>]*>(?<title>[^<]+)"#, level: nil),
                         OutlineRule(pattern: #"(?i)<(?:section|article|nav|header|footer|main)\b[^>]*\bid="([^"]+)""#)]),

        Syntax(id: "xml", name: "XML", extensions: ["xml", "plist", "svg", "xsd", "xsl", "xslt", "rss", "atom", "storyboard", "xib"],
               blockComment: ("<!--", "-->"), numbers: false,
               patterns: [(.keyword, markupTag), (.attribute, markupAttribute), (.string, markupValue),
                          (.value, #"&[A-Za-z0-9#]+;"#), (.markup, #"<\?[^?]*\?>|<!\[CDATA\[|\]\]>"#)]),

        Syntax(id: "css", name: "CSS", extensions: ["css", "scss", "sass", "less"],
               lineComment: nil, blockComment: ("/*", "*/"), quotes: ["\"", "'"],
               patterns: [
                   (.keyword, #"(?m)^[ \t]*[^{}\n;@/][^{}\n;]*(?=\{)"#),
                   (.attribute, #"@[\w-]+"#),
                   (.command, #"(?<=[{;\s])[\w-]+(?=\s*:)"#),
                   (.value, #"#[0-9A-Fa-f]{3,8}\b"#),
                   (.variable, #"--[\w-]+|\$[\w-]+"#),
                   (.number, #"(?<![\w-])-?\d*\.?\d+(?:px|em|rem|%|vh|vw|s|ms|deg|fr|ch|pt)?\b"#),
                   (.markup, #"!important"#),
               ],
               outline: [OutlineRule(pattern: #"^[ \t]*/\*[ \t]*(?:={2,}|-{2,})?[ \t]*(.+?)[ \t]*(?:={2,}|-{2,})?[ \t]*\*/"#),
                         OutlineRule(pattern: #"^([^\s{}@/][^{}\n]*?)[ \t]*\{"#, level: 1)]),

        Syntax(id: "php", name: "PHP", extensions: ["php", "phtml", "php3", "php4", "php5"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'"],
               keywords: ["abstract", "and", "array", "as", "break", "case", "catch", "class", "clone", "const", "continue",
                          "declare", "default", "do", "echo", "else", "elseif", "empty", "enddeclare", "endfor", "endforeach",
                          "endif", "endswitch", "endwhile", "extends", "final", "finally", "fn", "for", "foreach", "function",
                          "global", "if", "implements", "include", "include_once", "instanceof", "interface", "isset", "list",
                          "match", "namespace", "new", "or", "print", "private", "protected", "public", "readonly", "require",
                          "require_once", "return", "static", "switch", "throw", "trait", "try", "unset", "use", "var",
                          "while", "yield"],
               values: ["true", "false", "null", "TRUE", "FALSE", "NULL"],
               patterns: [(.variable, #"\$\w+"#), (.markup, #"<\?php|<\?=|\?>"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:abstract\s+|final\s+)?(?:class|interface|trait)\s+(\w+)"#),
                         OutlineRule(pattern: #"^[ \t]*(?:(?:public|private|protected|static|abstract|final)\s+)*function\s+(\w+)"#, level: 1)]),

        Syntax(id: "shell", name: "Shell", extensions: ["sh", "bash", "zsh", "command", "ksh", "fish"],
               fileNames: [".bashrc", ".zshrc", ".profile", ".bash_profile", ".zprofile"],
               lineComment: "#", lineCommentNeedsSpace: true, quotes: ["\"", "'"],
               keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in",
                          "function", "select", "return", "exit", "break", "continue", "local", "export", "readonly",
                          "declare", "set", "unset", "shift", "source", "trap"],
               commands: ["echo", "printf", "cd", "ls", "cp", "mv", "rm", "mkdir", "cat", "grep", "sed", "awk", "find",
                          "chmod", "chown", "curl", "git", "test", "read", "eval", "exec", "open", "sudo", "tr", "cut",
                          "sort", "uniq", "head", "tail", "xargs", "touch", "kill", "pwd"],
               patterns: [(.variable, #"\$\{[^}\n]*\}|\$[\w@#?$!*-]"#), (.markup, #"\A#!.*"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:function[ \t]+)?([\w-]+)[ \t]*\(\)[ \t]*\{?"#)]),

        Syntax(id: "c", name: "C", extensions: ["c", "h"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'"],
               keywords: cKeywords, types: cTypes, values: ["NULL", "true", "false"],
               patterns: [(.markup, #"(?m)^[ \t]*#[ \t]*\w+"#)],
               outline: [OutlineRule(pattern: #"^(?!\s)(?:[\w*]+[ \t]+)+\**(\w+)[ \t]*\([^;]*$"#)]),

        Syntax(id: "cpp", name: "C++", extensions: ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "ino"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'"],
               keywords: cKeywords + ["alignas", "alignof", "catch", "class", "constexpr", "consteval", "constinit",
                                      "decltype", "delete", "explicit", "export", "final", "friend", "mutable", "namespace",
                                      "new", "noexcept", "operator", "override", "private", "protected", "public",
                                      "static_assert", "template", "this", "throw", "try", "typename", "using", "virtual",
                                      "co_await", "co_return", "co_yield", "concept", "requires"],
               commands: ["std", "cout", "cin", "endl", "make_shared", "make_unique", "move", "printf"],
               types: cTypes + ["string", "vector", "map", "set", "unique_ptr", "shared_ptr", "auto", "wchar_t"],
               values: ["nullptr", "NULL", "true", "false"],
               patterns: [(.markup, #"(?m)^[ \t]*#[ \t]*\w+"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:class|struct|namespace)[ \t]+(\w+)"#),
                         OutlineRule(pattern: #"^(?!\s)(?:[\w:*&<>]+[ \t]+)+[*&]*([\w:~]+)[ \t]*\([^;]*$"#, level: 1)]),

        Syntax(id: "objc", name: "Objective-C", extensions: ["m", "mm"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'"],
               keywords: cKeywords + ["self", "super", "id", "instancetype", "nonatomic", "strong", "weak", "copy",
                                      "assign", "readonly", "readwrite", "nullable", "nonnull"],
               types: cTypes + ["BOOL", "NSInteger", "NSUInteger", "CGFloat", "NSString", "NSArray", "NSDictionary", "SEL"],
               values: ["YES", "NO", "nil", "Nil", "NULL"],
               patterns: [(.attribute, #"@\w+"#), (.markup, #"(?m)^[ \t]*#[ \t]*\w+"#)],
               outline: [OutlineRule(pattern: #"^@(?:interface|implementation|protocol)[ \t]+(\w+(?:[ \t]*\([^)]*\))?)"#),
                         OutlineRule(pattern: #"^([-+][ \t]*\([^)]*\)[^{;]+)"#, level: 1),
                         OutlineRule(pattern: #"^#pragma[ \t]+mark[ \t]+-?[ \t]*(.+)$"#)]),

        Syntax(id: "csharp", name: "C#", extensions: ["cs", "csx"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'"],
               keywords: ["abstract", "as", "async", "await", "base", "break", "case", "catch", "checked", "class", "const",
                          "continue", "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "finally",
                          "fixed", "for", "foreach", "get", "goto", "if", "implicit", "in", "init", "interface", "internal",
                          "is", "lock", "namespace", "new", "operator", "out", "override", "params", "private", "protected",
                          "public", "readonly", "record", "ref", "return", "sealed", "set", "sizeof", "static", "struct",
                          "switch", "this", "throw", "try", "typeof", "unchecked", "unsafe", "using", "var", "virtual",
                          "volatile", "when", "where", "while", "yield"],
               types: ["bool", "byte", "char", "decimal", "double", "dynamic", "float", "int", "long", "object", "sbyte",
                       "short", "string", "uint", "ulong", "ushort", "void", "List", "Dictionary", "Task"],
               values: ["true", "false", "null"],
               patterns: [(.attribute, #"(?m)^[ \t]*\[[\w.]+(?:\([^)]*\))?\]"#), (.markup, #"(?m)^[ \t]*#\w+"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:(?:public|private|protected|internal|static|abstract|sealed|partial)\s+)*(?:class|struct|interface|enum|record)\s+(\w+)"#),
                         OutlineRule(pattern: #"^[ \t]*(?:(?:public|private|protected|internal|static|virtual|override|async|abstract)\s+)+[\w<>\[\],]+\s+(\w+)\s*\("#, level: 1)]),

        Syntax(id: "java", name: "Java", extensions: ["java"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: ["\"\"\""],
               keywords: ["abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do",
                          "else", "enum", "extends", "final", "finally", "for", "goto", "if", "implements", "import",
                          "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "record",
                          "return", "sealed", "static", "strictfp", "super", "switch", "synchronized", "this", "throw",
                          "throws", "transient", "try", "var", "volatile", "while", "yield"],
               types: ["boolean", "byte", "char", "double", "float", "int", "long", "short", "void", "String", "Object",
                       "Integer", "List", "Map"],
               values: ["true", "false", "null"],
               patterns: [(.attribute, #"@\w+"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:(?:public|private|protected|static|abstract|final|sealed)\s+)*(?:class|interface|enum|record)\s+(\w+)"#),
                         OutlineRule(pattern: #"^[ \t]*(?:(?:public|private|protected|static|final|abstract|synchronized)\s+)+[\w<>\[\],]+\s+(\w+)\s*\("#, level: 1)]),

        Syntax(id: "kotlin", name: "Kotlin", extensions: ["kt", "kts"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: ["\"\"\""],
               keywords: ["as", "break", "by", "catch", "class", "companion", "constructor", "continue", "data", "do",
                          "else", "enum", "for", "fun", "if", "import", "in", "init", "interface", "internal", "is",
                          "lateinit", "object", "open", "override", "package", "private", "protected", "public", "return",
                          "sealed", "super", "suspend", "this", "throw", "try", "typealias", "val", "var", "when", "while"],
               types: ["Int", "Long", "Double", "Float", "Boolean", "String", "Char", "Unit", "Any", "Nothing", "List", "Map"],
               values: ["true", "false", "null"],
               patterns: [(.attribute, #"@\w+"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:\w+\s+)*(?:class|object|interface)\s+(\w+)"#),
                         OutlineRule(pattern: #"^[ \t]*(?:\w+\s+)*fun\s+(?:<[^>]*>\s*)?([\w.]+)"#, level: 1)]),

        Syntax(id: "go", name: "Go", extensions: ["go"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"],
               keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for",
                          "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select",
                          "struct", "switch", "type", "var"],
               commands: ["append", "cap", "close", "copy", "delete", "len", "make", "new", "panic", "print", "println",
                          "recover", "fmt"],
               types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16",
                       "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any"],
               values: ["true", "false", "nil", "iota"],
               outline: [OutlineRule(pattern: #"^type[ \t]+(\w+)"#),
                         OutlineRule(pattern: #"^func[ \t]+(?:\([^)]*\)[ \t]*)?(\w+)"#, level: 1)]),

        Syntax(id: "rust", name: "Rust", extensions: ["rs"],
               lineComment: "//", blockComment: ("/*", "*/"), quotes: ["\""],
               keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
                          "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
                          "return", "self", "Self", "static", "struct", "super", "trait", "type", "unsafe", "use", "where",
                          "while"],
               types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64",
                       "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "HashMap"],
               values: ["true", "false", "None", "Some", "Ok", "Err"],
               patterns: [(.command, #"\b\w+!"#), (.attribute, #"#!?\[[^\]\n]*\]"#), (.character, #"'(?:\\.|[^'\\\n])'"#),
                          (.variable, #"'[a-z_]\w*\b(?!')"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:pub(?:\([^)]*\))?\s+)?(?:struct|enum|trait|impl(?:<[^>]*>)?|mod)\s+([^\s{<]+(?:\s+for\s+[^\s{]+)?)"#),
                         OutlineRule(pattern: #"^[ \t]*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(\w+)"#, level: 1)]),

        Syntax(id: "ruby", name: "Ruby", extensions: ["rb", "rake", "gemspec"], fileNames: ["gemfile", "rakefile"],
               lineComment: "#", blockComment: ("=begin", "=end"), quotes: ["\"", "'"],
               keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
                          "ensure", "for", "if", "in", "module", "next", "not", "or", "redo", "rescue", "retry", "return",
                          "self", "super", "then", "undef", "unless", "until", "when", "while", "yield"],
               commands: ["puts", "print", "require", "require_relative", "attr_accessor", "attr_reader", "attr_writer",
                          "include", "extend", "raise", "lambda", "proc"],
               values: ["true", "false", "nil"],
               patterns: [(.variable, #"@{1,2}\w+|\$\w+"#), (.value, #"(?<![:\w]):\w+"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:class|module)[ \t]+([\w:]+)"#),
                         OutlineRule(pattern: #"^[ \t]*def[ \t]+([\w.?!=]+)"#, level: 1)]),

        Syntax(id: "sql", name: "SQL", extensions: ["sql"],
               lineComment: "--", blockComment: ("/*", "*/"), quotes: ["'", "\""],
               keywords: ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set",
                          "delete", "create", "table", "drop", "alter", "add", "column", "index", "view", "join", "inner",
                          "left", "right", "outer", "full", "on", "as", "group", "by", "order", "having", "limit", "offset",
                          "union", "all", "distinct", "case", "when", "then", "else", "end", "primary", "key", "foreign",
                          "references", "unique", "default", "exists", "in", "is", "like", "between", "asc", "desc",
                          "begin", "commit", "rollback", "transaction", "if", "with", "returning", "constraint", "database"],
               commands: ["count", "sum", "avg", "min", "max", "coalesce", "now", "lower", "upper", "length", "substr",
                          "concat", "cast", "round"],
               types: ["int", "integer", "bigint", "smallint", "varchar", "char", "text", "date", "datetime", "timestamp",
                       "boolean", "float", "double", "decimal", "numeric", "blob", "json", "serial", "real"],
               values: ["null", "true", "false"], caseInsensitive: true,
               outline: [OutlineRule(pattern: #"(?i)^[ \t]*create[ \t]+(?:or[ \t]+replace[ \t]+)?(?:table|view|index|function|procedure|trigger)[ \t]+(?:if[ \t]+not[ \t]+exists[ \t]+)?([\w."`]+)"#)]),

        Syntax(id: "yaml", name: "YAML", extensions: ["yml", "yaml"],
               lineComment: "#", lineCommentNeedsSpace: true, quotes: ["\"", "'"],
               values: ["true", "false", "null", "yes", "no", "on", "off", "~"],
               patterns: [(.variable, #"(?m)^[ \t]*(?:- )?[^\s:#][^:\n#]*(?=:(?:\s|$))"#), (.markup, #"(?m)^(?:---|\.\.\.)$"#),
                          (.attribute, #"[&*][\w-]+|![\w!/-]*"#)],
               outline: [OutlineRule(pattern: #"^([^\s:#][^:\n]*):"#)]),

        Syntax(id: "toml", name: "TOML", extensions: ["toml"],
               lineComment: "#", quotes: ["\"", "'"], multilineQuotes: ["\"\"\"", "'''"],
               values: ["true", "false"],
               patterns: [(.keyword, #"(?m)^[ \t]*\[\[?[^\]\n]+\]\]?"#), (.variable, #"(?m)^[ \t]*[\w.\-"']+(?=[ \t]*=)"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*\[\[?([^\]\n]+)\]\]?"#)]),

        Syntax(id: "ini", name: "INI", extensions: ["ini", "cfg", "conf", "properties", "env", "editorconfig", "gitconfig"],
               fileNames: [".env", ".editorconfig", ".gitconfig", ".npmrc"],
               lineComment: "#", quotes: ["\""],
               patterns: [(.comment, #"(?m)^[ \t]*;.*$"#), (.keyword, #"(?m)^[ \t]*\[[^\]\n]+\]"#),
                          (.variable, #"(?m)^[ \t]*[^\s=:#;\[][^=:\n]*?(?=[ \t]*[=:])"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*\[([^\]\n]+)\]"#)]),

        Syntax(id: "apache", name: "Apache", extensions: ["htaccess", "htpasswd"], fileNames: [".htaccess", "httpd.conf"],
               lineComment: "#", quotes: ["\""],
               patterns: [(.keyword, #"(?m)^[ \t]*[A-Z]\w+"#), (.markup, #"</?[A-Za-z]+[^>\n]*>"#),
                          (.variable, #"%\{[\w:]+\}|\$\d"#), (.value, #"\[[A-Z,=\d ]+\]"#)]),

        Syntax(id: "lua", name: "Lua", extensions: ["lua"],
               lineComment: "--", blockComment: ("--[[", "]]"), quotes: ["\"", "'"],
               keywords: ["and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if", "in", "local",
                          "not", "or", "repeat", "return", "then", "until", "while"],
               commands: ["print", "pairs", "ipairs", "require", "type", "tostring", "tonumber", "table", "string", "math"],
               values: ["true", "false", "nil"],
               outline: [OutlineRule(pattern: #"^[ \t]*(?:local[ \t]+)?function[ \t]+([\w.:]+)"#)]),

        Syntax(id: "perl", name: "Perl", extensions: ["pl", "pm", "t"],
               lineComment: "#", quotes: ["\"", "'"],
               keywords: ["my", "our", "local", "sub", "if", "elsif", "else", "unless", "while", "until", "for", "foreach",
                          "return", "last", "next", "redo", "use", "require", "package", "and", "or", "not", "eq", "ne",
                          "lt", "gt", "le", "ge"],
               commands: ["print", "printf", "say", "die", "warn", "open", "close", "push", "pop", "shift", "split", "join"],
               patterns: [(.variable, #"[$@%][\w:]+"#)],
               outline: [OutlineRule(pattern: #"^[ \t]*sub[ \t]+(\w+)"#), OutlineRule(pattern: #"^package[ \t]+([\w:]+)"#)]),

        Syntax(id: "r", name: "R", extensions: ["r", "rmd"],
               lineComment: "#", quotes: ["\"", "'"],
               keywords: ["if", "else", "repeat", "while", "function", "for", "in", "next", "break", "return"],
               commands: ["library", "require", "print", "cat", "c", "list", "data.frame", "paste", "length", "sum", "mean"],
               values: ["TRUE", "FALSE", "NULL", "NA", "Inf", "NaN"],
               outline: [OutlineRule(pattern: #"^[ \t]*([\w.]+)[ \t]*(?:<-|=)[ \t]*function"#)]),

        Syntax(id: "makefile", name: "Makefile", extensions: ["mk", "make"], fileNames: ["makefile", "gnumakefile"],
               lineComment: "#", quotes: ["\"", "'"],
               keywords: ["ifeq", "ifneq", "ifdef", "ifndef", "else", "endif", "include", "define", "endef", "export"],
               numbers: false,
               patterns: [(.variable, #"\$\([^)\n]+\)|\$\{[^}\n]+\}|\$[@<^?*]"#), (.command, #"(?m)^[\w.%/-]+(?=\s*:(?!=))"#)],
               outline: [OutlineRule(pattern: #"^([\w.%/-]+)[ \t]*:(?!=)"#)]),

        Syntax(id: "dockerfile", name: "Dockerfile", extensions: ["dockerfile"], fileNames: ["dockerfile", "containerfile"],
               lineComment: "#", quotes: ["\"", "'"],
               keywords: ["FROM", "RUN", "CMD", "LABEL", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT", "VOLUME", "USER",
                          "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK", "SHELL", "AS"],
               patterns: [(.variable, #"\$\{[^}\n]*\}|\$\w+"#)],
               outline: [OutlineRule(pattern: #"(?i)^FROM[ \t]+(\S+(?:[ \t]+AS[ \t]+\S+)?)"#)]),

        Syntax(id: "latex", name: "LaTeX", extensions: ["tex", "sty", "cls", "bib"],
               lineComment: "%", numbers: false,
               patterns: [(.keyword, #"\\[A-Za-z@]+\*?"#), (.attribute, #"[{}\[\]]"#), (.string, #"\$[^$\n]+\$"#)],
               outline: [OutlineRule(pattern: #"\\(?:part|chapter)\*?\{([^}]*)\}"#),
                         OutlineRule(pattern: #"\\section\*?\{([^}]*)\}"#, level: 1),
                         OutlineRule(pattern: #"\\subsection\*?\{([^}]*)\}"#, level: 2)]),

        Syntax(id: "diff", name: "Diff", extensions: ["diff", "patch"], numbers: false,
               patterns: [(.string, #"(?m)^\+.*$"#), (.keyword, #"(?m)^-.*$"#), (.command, #"(?m)^@@.*$"#),
                          (.comment, #"(?m)^(?:diff|index|\+\+\+|---) .*$"#)],
               outline: [OutlineRule(pattern: #"^\+\+\+ (?:b/)?(.+)$"#)]),

        Syntax(id: "csv", name: "CSV", extensions: ["csv", "tsv"], quotes: ["\""],
               patterns: [(.attribute, #"[,;\t]"#)]),

        Syntax(id: "log", name: L("Log File"), extensions: ["log"], numbers: false,
               patterns: [(.number, #"(?m)^\[?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}[^\s\]]*\]?"#),
                          (.keyword, #"\b(?:ERROR|FATAL|CRITICAL|Error|Fatal)\b"#), (.attribute, #"\b(?:WARN|WARNING|Warning)\b"#),
                          (.comment, #"\b(?:DEBUG|TRACE)\b"#), (.command, #"\b(?:INFO|NOTICE)\b"#)]),
    ]
}
