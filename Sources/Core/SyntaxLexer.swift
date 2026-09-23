import Foundation

/// Lightweight, dependency free syntax highlighter.
///
/// The lexer is line based: comments, strings, numbers, keywords and
/// attributes are recognised with regular expressions. It is intentionally a
/// subset — the goal is a pleasant preview, not a compiler grade parser.
public struct SyntaxLexer {

    public struct Language: Sendable {
        public let id: String
        public let displayName: String
        public let keywords: Set<String>
        public let types: Set<String>
        public let lineComment: String?
        public let blockComment: (String, String)?
        public let strings: [String]
        public let highlightAttributes: Bool
    }

    public struct Segment: Equatable {
        public let text: String
        /// CSS class such as `tok-keyword`, or `nil` for plain text.
        public let tokenClass: String?
    }

    // MARK: - Language registry

    public static let plain = Language(
        id: "plain",
        displayName: "Plain Text",
        keywords: [],
        types: [],
        lineComment: nil,
        blockComment: nil,
        strings: [],
        highlightAttributes: false
    )

    public static let generic = Language(
        id: "generic",
        displayName: "Source",
        keywords: [],
        types: [],
        lineComment: "//",
        blockComment: ("/*", "*/"),
        strings: ["\"", "'"],
        highlightAttributes: false
    )

    public static let languages: [String: Language] = [
        "swift": Language(
            id: "swift",
            displayName: "Swift",
            keywords: ["associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is", "lazy", "let", "nil", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while", "actor", "any", "some", "each", "borrowing", "consuming"],
            types: ["Bool", "Character", "Data", "Date", "Dictionary", "Double", "Error", "Float", "Int", "Int8", "Int16", "Int32", "Int64", "Optional", "Result", "Set", "String", "UInt", "URL", "UUID", "Void", "Array", "AnyObject", "Any"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            strings: ["\""],
            highlightAttributes: true
        ),
        "python": Language(
            id: "python",
            displayName: "Python",
            keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield", "match", "case", "self", "cls"],
            types: ["bool", "bytes", "dict", "float", "frozenset", "int", "list", "object", "set", "str", "tuple", "type", "Exception", "ValueError", "TypeError", "KeyError"],
            lineComment: "#",
            blockComment: nil,
            strings: ["\"\"\"", "'''", "\"", "'"],
            highlightAttributes: true
        ),
        "javascript": Language(
            id: "javascript",
            displayName: "JavaScript",
            keywords: ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "get", "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield", "as"],
            types: ["Array", "Boolean", "Date", "Error", "Function", "JSON", "Map", "Math", "Number", "Object", "Promise", "RegExp", "Set", "String", "Symbol", "WeakMap"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            strings: ["\"", "'", "`"],
            highlightAttributes: false
        ),
        "typescript": Language(
            id: "typescript",
            displayName: "TypeScript",
            keywords: ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "keyof", "let", "namespace", "never", "new", "null", "of", "private", "protected", "public", "readonly", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "unknown", "var", "void", "while", "yield", "satisfies"],
            types: ["Array", "Boolean", "Date", "Error", "Function", "JSON", "Map", "Math", "Number", "Object", "Promise", "Record", "RegExp", "Set", "String", "Symbol", "Partial", "Readonly"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            strings: ["\"", "'", "`"],
            highlightAttributes: false
        ),
        "go": Language(
            id: "go",
            displayName: "Go",
            keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "nil", "true", "false", "iota"],
            types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            strings: ["\"", "`"],
            highlightAttributes: false
        ),
        "rust": Language(
            id: "rust",
            displayName: "Rust",
            keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while", "union", "macro_rules"],
            types: ["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "String", "u8", "u16", "u32", "u64", "u128", "usize", "Option", "Result", "Vec", "Box", "HashMap", "HashSet"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            strings: ["\"", "r#\""],
            highlightAttributes: true
        ),
        "c": Language(
            id: "c",
            displayName: "C / C++",
            keywords: ["auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for", "goto", "if", "inline", "register", "restrict", "return", "sizeof", "static", "struct", "switch", "typedef", "union", "volatile", "while", "class", "namespace", "template", "typename", "public", "private", "protected", "virtual", "override", "new", "delete", "nullptr", "true", "false", "using", "try", "catch", "throw", "constexpr", "noexcept", "operator", "friend", "this", "const_cast", "static_cast", "dynamic_cast"],
            types: ["bool", "char", "double", "float", "int", "long", "short", "signed", "unsigned", "void", "size_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "string", "vector", "map", "set", "unique_ptr", "shared_ptr", "std"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            strings: ["\"", "'"],
            highlightAttributes: true
        ),
        "java": Language(
            id: "java",
            displayName: "Java / Kotlin",
            keywords: ["abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "fun", "goto", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "val", "var", "void", "volatile", "while", "object", "when", "data", "suspend", "null", "true", "false"],
            types: ["boolean", "byte", "char", "double", "float", "int", "long", "short", "String", "Integer", "Double", "Boolean", "List", "Map", "Set", "Unit", "Any"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            strings: ["\"\"\"", "\""],
            highlightAttributes: true
        ),
        "ruby": Language(
            id: "ruby",
            displayName: "Ruby",
            keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "require", "attr_accessor", "attr_reader"],
            types: ["Array", "Hash", "Integer", "Float", "String", "Symbol", "Proc", "Lambda"],
            lineComment: "#",
            blockComment: nil,
            strings: ["\"", "'"],
            highlightAttributes: true
        ),
        "shell": Language(
            id: "shell",
            displayName: "Shell",
            keywords: ["case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "select", "then", "until", "while", "time", "local", "return", "export", "readonly", "source", "alias", "set", "unset", "exit", "echo", "printf", "cd", "sudo", "eval", "exec", "shift", "trap", "test"],
            types: [],
            lineComment: "#",
            blockComment: nil,
            strings: ["\"", "'", "`"],
            highlightAttributes: true
        ),
        "css": Language(
            id: "css",
            displayName: "CSS",
            keywords: ["important", "media", "supports", "keyframes", "import", "charset", "font-face", "page", "namespace", "layer", "container"],
            types: [],
            lineComment: nil,
            blockComment: ("/*", "*/"),
            strings: ["\"", "'"],
            highlightAttributes: true
        ),
        "sql": Language(
            id: "sql",
            displayName: "SQL",
            keywords: ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "index", "view", "trigger", "drop", "alter", "add", "column", "join", "inner", "left", "right", "outer", "full", "on", "group", "by", "order", "having", "limit", "offset", "union", "all", "distinct", "as", "and", "or", "not", "null", "is", "in", "between", "like", "exists", "case", "when", "then", "else", "end", "primary", "key", "foreign", "references", "unique", "default", "constraint", "autoincrement", "with", "recursive", "returning", "conflict", "do", "nothing"],
            types: ["integer", "text", "real", "blob", "numeric", "varchar", "int", "bigint", "boolean", "timestamp", "date", "json", "jsonb", "uuid", "serial", "decimal", "char"],
            lineComment: "--",
            blockComment: ("/*", "*/"),
            strings: ["'", "\""],
            highlightAttributes: false
        ),
        "yaml": Language(
            id: "yaml",
            displayName: "YAML",
            keywords: ["true", "false", "null", "yes", "no", "on", "off", "~"],
            types: [],
            lineComment: "#",
            blockComment: nil,
            strings: ["\"", "'"],
            highlightAttributes: false
        ),
        "toml": Language(
            id: "toml",
            displayName: "TOML",
            keywords: ["true", "false"],
            types: [],
            lineComment: "#",
            blockComment: nil,
            strings: ["\"\"\"", "'''", "\"", "'"],
            highlightAttributes: false
        ),
        "markdown": Language(
            id: "markdown",
            displayName: "Markdown",
            keywords: [],
            types: [],
            lineComment: nil,
            blockComment: nil,
            strings: ["`", "\""],
            highlightAttributes: false
        ),
        "json": Language(
            id: "json",
            displayName: "JSON",
            keywords: ["true", "false", "null"],
            types: [],
            lineComment: nil,
            blockComment: nil,
            strings: ["\""],
            highlightAttributes: false
        ),
    ]

    /// Maps a lowercased file extension to a language.
    public static func language(forExtension ext: String) -> Language {
        switch ext {
        case "swift": return languages["swift"]!
        case "py", "pyw", "pyi": return languages["python"]!
        case "js", "mjs", "cjs", "jsx": return languages["javascript"]!
        case "ts", "tsx", "mts", "cts": return languages["typescript"]!
        case "go": return languages["go"]!
        case "rs": return languages["rust"]!
        case "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "hxx", "m", "mm": return languages["c"]!
        case "java", "kt", "kts", "scala": return languages["java"]!
        case "rb", "rake", "gemspec": return languages["ruby"]!
        case "sh", "bash", "zsh", "fish", "command": return languages["shell"]!
        case "css", "scss", "less": return languages["css"]!
        case "sql": return languages["sql"]!
        case "yaml", "yml": return languages["yaml"]!
        case "toml": return languages["toml"]!
        case "md", "markdown", "mdx": return languages["markdown"]!
        case "json", "jsonl", "ndjson", "geojson", "lock": return languages["json"]!
        case "txt", "text", "log", "csv", "tsv", "env", "conf", "cfg", "ini", "properties", "lock", "gitignore", "dockerfile": return plain
        default: return generic
        }
    }

    // MARK: - Tokenizing

    private let language: Language
    private let numberRegex = try? NSRegularExpression(pattern: #"\b(0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(\.[\d_]+)?([eE][+-]?[\d_]+)?)\b"#)

    public init(language: Language) {
        self.language = language
    }

    /// Tokenizes a single line of source code.
    public func tokenize(_ line: String) -> [Segment] {
        var segments: [Segment] = []
        var plain = ""
        var index = line.startIndex

        func flushPlain() {
            if !plain.isEmpty {
                segments.append(Segment(text: plain, tokenClass: nil))
                plain = ""
            }
        }
        func emit(_ text: String, _ cls: String?) {
            flushPlain()
            if let cls {
                segments.append(Segment(text: text, tokenClass: cls))
            } else {
                plain += text
            }
        }

        while index < line.endIndex {
            let remainder = String(line[index...])

            if let lineComment = language.lineComment, remainder.hasPrefix(lineComment) {
                emit(remainder, "tok-comment")
                index = line.endIndex
                continue
            }

            if let (open, close) = language.blockComment, remainder.hasPrefix(open) {
                let body = remainder
                if let closeRange = body.range(of: close, range: body.index(body.startIndex, offsetBy: open.count)..<body.endIndex) {
                    let token = String(body[..<closeRange.upperBound])
                    emit(token, "tok-comment")
                    index = line.index(index, offsetBy: token.count)
                } else {
                    emit(body, "tok-comment")
                    index = line.endIndex
                }
                continue
            }

            var matchedString = false
            for delimiter in language.strings where remainder.hasPrefix(delimiter) {
                var cursor = remainder.index(remainder.startIndex, offsetBy: delimiter.count)
                var body = ""
                var escaped = false
                var terminated = false
                while cursor < remainder.endIndex {
                    let character = remainder[cursor]
                    if escaped {
                        body.append(character)
                        escaped = false
                    } else if character == "\\" {
                        body.append(character)
                        escaped = true
                    } else if remainder[cursor...].hasPrefix(delimiter) {
                        cursor = remainder.index(cursor, offsetBy: delimiter.count)
                        terminated = true
                        break
                    } else {
                        body.append(character)
                    }
                    cursor = remainder.index(after: cursor)
                }
                let consumed = String(remainder[..<cursor])
                emit(consumed, "tok-string")
                index = line.index(index, offsetBy: consumed.count)
                matchedString = true
                _ = terminated
                _ = body
                break
            }
            if matchedString { continue }

            if let numberRegex {
                let range = NSRange(index..<line.endIndex, in: line)
                if let match = numberRegex.firstMatch(in: line, range: range), match.range.location == range.location, match.range.length > 0,
                   let swiftRange = Range(match.range, in: line) {
                    emit(String(line[swiftRange]), "tok-number")
                    index = swiftRange.upperBound
                    continue
                }
            }

            let character = line[index]
            if character.isLetter || character == "_" {
                var end = line.index(after: index)
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" {
                    end = line.index(after: end)
                }
                let word = String(line[index..<end])
                let after = nextNonSpace(after: end, in: line)
                if language.keywords.contains(word) {
                    emit(word, "tok-keyword")
                } else if language.types.contains(word) {
                    emit(word, "tok-type")
                } else if language.highlightAttributes, after == ":" {
                    emit(word, "tok-attribute")
                } else if word.count > 1, word == word.uppercased(), word.rangeOfCharacter(from: .letters) != nil {
                    emit(word, "tok-attribute")
                } else {
                    emit(word, nil)
                }
                index = end
                continue
            }

            if "@#".contains(character), language.highlightAttributes {
                var end = line.index(after: index)
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" {
                    end = line.index(after: end)
                }
                emit(String(line[index..<end]), "tok-attribute")
                index = end
                continue
            }

            emit(String(character), nil)
            index = line.index(after: index)
        }

        flushPlain()
        return segments
    }

    private func nextNonSpace(after index: String.Index, in line: String) -> Character? {
        var cursor = index
        while cursor < line.endIndex {
            if line[cursor] != " " { return line[cursor] }
            cursor = line.index(after: cursor)
        }
        return nil
    }
}
