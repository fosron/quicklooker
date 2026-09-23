import Foundation

/// Minimal block style YAML parser covering the subset used by configuration
/// files: nested mappings, sequences, flow collections, block scalars and
/// YAML 1.1 style scalar typing. Anything it cannot confidently parse is
/// reported so callers can fall back to a text rendering.
public struct YAMLParser {

    public struct ParseResult: Sendable {
        public let value: ValueNode?
        /// Inferred scalar type per node path, e.g. "string", "int", "bool".
        public let typeHints: [String: String]
        /// Line numbers (1 based) of the top level entries of mappings/sequences.
        public let keyLines: [String: Int]
        public let documentCount: Int
        public let lineCount: Int
        public let failure: String?
        public let failureLine: Int?
    }

    private struct Line {
        let number: Int
        let indent: Int
        let content: String
    }

    private let lines: [Line]
    private var typeHints: [String: String] = [:]
    private var keyLines: [String: Int] = [:]
    private var failure: String?
    private var failureLine: Int?

    public init(text: String) {
        var result: [Line] = []
        var insideBlockScalarIndent: Int?
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            let indent = line.prefix { $0 == " " }.count
            let content = String(line.dropFirst(indent).replacingOccurrences(of: "\t", with: "    "))
            if let blockIndent = insideBlockScalarIndent {
                if content.isEmpty || indent > blockIndent {
                    continue
                }
                insideBlockScalarIndent = nil
            }
            result.append(Line(number: index + 1, indent: indent, content: content))
        }
        self.lines = result
    }

    // MARK: - Entry point

    public mutating func parse() -> ParseResult {
        var index = 0

        // Leading document markers are treated as noise for the common single
        // document case.
        while index < lines.count, lines[index].content.hasPrefix("---") {
            index += 1
        }
        let value = parseBlock(at: &index, indent: -1, path: "")
        if failure == nil {
            while index < lines.count, lines[index].content.hasPrefix("...") {
                index += 1
            }
            if index < lines.count {
                var cursor = index
                while cursor < lines.count {
                    let candidate = lines[cursor]
                    if !candidate.content.isEmpty, !candidate.content.hasPrefix("#") {
                        fail("unexpected content at line \(candidate.number)", line: candidate.number)
                        break
                    }
                    cursor += 1
                }
            }
        }
        return ParseResult(
            value: failure == nil ? value : nil,
            typeHints: typeHints,
            keyLines: keyLines,
            documentCount: 1,
            lineCount: lines.count,
            failure: failure,
            failureLine: failureLine
        )
    }

    private func path(_ base: String, _ component: String) -> String {
        base.isEmpty ? component : "\(base).\(component)"
    }

    // MARK: - Block parsing

    private mutating func parseBlock(at index: inout Int, indent: Int, path basePath: String) -> ValueNode? {
        var entries: [(String, ValueNode)] = []
        var items: [ValueNode] = []
        var isSequence = false
        var isMapping = false
        var containerIndent: Int?

        while index < lines.count {
            let line = lines[index]
            let content = line.content

            if content.isEmpty || content.hasPrefix("#") {
                index += 1
                continue
            }
            let lineIndent = line.indent
            if lineIndent <= indent {
                break
            }
            if let containerIndent, lineIndent < containerIndent {
                break
            }
            if containerIndent == nil || (containerIndent! < lineIndent) {
                if containerIndent == nil {
                    containerIndent = lineIndent
                } else if lineIndent > containerIndent! {
                    fail("unexpected indentation", line: line.number)
                    return nil
                }
            }

            if isMapping, content.hasPrefix("- ") || content == "-" {
                fail("mixed mapping and sequence entries", line: line.number)
                return nil
            }
            if isSequence, !(content.hasPrefix("- ") || content == "-") {
                fail("mixed sequence and mapping entries", line: line.number)
                return nil
            }

            if content.hasPrefix("- ") || content == "-" {
                isSequence = true
                let itemIndent = lineIndent
                let remainder = content == "-" ? "" : String(content.dropFirst(2))
                let itemIndex = index
                index += 1
                let itemPath = "\(basePath)[\(items.count)]"
                if !remainder.isEmpty, let (key, value) = splitKeyValue(remainder) {
                    var inlineEntries: [(String, ValueNode)] = []
                    let keyPath = path(itemPath, key)
                    keyLines[keyPath] = line.number
                    if let value {
                        inlineEntries.append((key, parseInline(value, path: keyPath, lineNumber: line.number)))
                    } else {
                        let nestedIndent = nextIndent(after: itemIndex)
                        let childIndent = nestedIndent ?? itemIndent
                        let nested = parseBlock(at: &index, indent: childIndent - 1, path: keyPath)
                        inlineEntries.append((key, nested ?? .null))
                    }
                    // Additional mapping entries aligned with the item content.
                    let contentIndent = itemIndent + 2
                    while index < lines.count {
                        let next = lines[index]
                        if next.content.isEmpty || next.content.hasPrefix("#") {
                            index += 1
                            continue
                        }
                        guard next.indent == contentIndent, let (key, value) = splitKeyValue(next.content) else { break }
                        let keyPath2 = path(itemPath, key)
                        keyLines[keyPath2] = next.number
                        index += 1
                        if let value {
                            inlineEntries.append((key, parseInline(value, path: keyPath2, lineNumber: next.number)))
                        } else {
                            let nestedIndent = nextIndent(after: index - 1) ?? (contentIndent + 1)
                            let nested = parseBlock(at: &index, indent: nestedIndent - 1, path: keyPath2)
                            inlineEntries.append((key, nested ?? .null))
                        }
                    }
                    items.append(.object(inlineEntries))
                } else if !remainder.isEmpty {
                    items.append(parseScalar(remainder, path: itemPath, lineNumber: line.number))
                } else {
                    let nestedIndent = nextIndent(after: itemIndex) ?? (itemIndent + 1)
                    let nested = parseBlock(at: &index, indent: nestedIndent - 1, path: itemPath)
                    items.append(nested ?? .null)
                }
                continue
            }

            guard let (key, value) = splitKeyValue(content) else {
                fail("expected a \"key: value\" mapping entry", line: line.number)
                return nil
            }
            isMapping = true
            let keyPath = path(basePath, key)
            keyLines[keyPath] = line.number
            index += 1
            if let value {
                entries.append((key, parseInline(value, path: keyPath, lineNumber: line.number)))
            } else {
                var childIndent = nextIndent(after: index - 1)
                if childIndent == nil || childIndent! <= lineIndent {
                    childIndent = -1
                    entries.append((key, .null))
                    typeHints[keyPath] = "null"
                    continue
                }
                let nested = parseBlock(at: &index, indent: childIndent! - 1, path: keyPath)
                entries.append((key, nested ?? .null))
            }
        }

        if failure != nil { return nil }
        if isSequence { return .array(items) }
        if isMapping { return .object(entries) }
        return nil
    }

    private func nextIndent(after index: Int) -> Int? {
        var cursor = index + 1
        while cursor < lines.count {
            let line = lines[cursor]
            if line.content.isEmpty || line.content.hasPrefix("#") {
                cursor += 1
                continue
            }
            return line.indent
        }
        return nil
    }

    // MARK: - Inline values

    private mutating func parseInline(_ text: String, path: String, lineNumber: Int) -> ValueNode {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") || trimmed.hasPrefix(">") {
            typeHints[path] = "block"
            return .string("<block scalar>")
        }
        if trimmed.hasPrefix("[") {
            typeHints[path] = "array"
            let inner = balancedInner(trimmed, open: "[", close: "]")
            let parts = splitTopLevel(inner)
            var items: [ValueNode] = []
            for (offset, part) in parts.enumerated() {
                let itemPath = "\(path)[\(offset)]"
                items.append(parseScalar(part, path: itemPath, lineNumber: lineNumber))
            }
            return .array(items)
        }
        if trimmed.hasPrefix("{") {
            typeHints[path] = "map"
            let inner = balancedInner(trimmed, open: "{", close: "}")
            let parts = splitTopLevel(inner)
            var entries: [(String, ValueNode)] = []
            for part in parts {
                guard let (key, value) = splitKeyValue(part) else {
                    entries.append((part.trimmingCharacters(in: .whitespaces), .null))
                    continue
                }
                let keyPath = self.path(path, key)
                entries.append((key, parseInline(value ?? "null", path: keyPath, lineNumber: lineNumber)))
            }
            return .object(entries)
        }
        return parseScalar(trimmed, path: path, lineNumber: lineNumber)
    }

    private mutating func parseScalar(_ text: String, path: String, lineNumber: Int) -> ValueNode {
        var scalar = text
        if let range = scalar.range(of: " #") {
            scalar = String(scalar[..<range.lowerBound])
        }
        scalar = stripTagsAndAnchors(scalar.trimmingCharacters(in: .whitespaces))
        if scalar.isEmpty {
            typeHints[path] = "null"
            return .null
        }

        if scalar.hasPrefix("\"") {
            typeHints[path] = "string"
            return .string(unescapeDouble(scalar))
        }
        if scalar.hasPrefix("'") {
            typeHints[path] = "string"
            let body = scalar.hasPrefix("'") && scalar.hasSuffix("'") && scalar.count >= 2
                ? String(scalar.dropFirst().dropLast())
                : String(scalar.dropFirst())
            return .string(body.replacingOccurrences(of: "''", with: "'"))
        }

        switch scalar.lowercased() {
        case "null", "~":
            typeHints[path] = "null"
            return .null
        case "true", "yes", "on":
            typeHints[path] = "bool"
            return .boolean(true)
        case "false", "no", "off":
            typeHints[path] = "bool"
            return .boolean(false)
        default:
            break
        }

        if let integer = Int(scalar) {
            typeHints[path] = "int"
            return .number(String(integer))
        }
        if scalar.contains(".") || scalar.lowercased().contains("e"),
           let double = Double(scalar), double.isFinite {
            typeHints[path] = "float"
            return .number(scalar)
        }
        if isDateLike(scalar) {
            typeHints[path] = "date"
            return .string(scalar)
        }
        typeHints[path] = "string"
        return .string(scalar)
    }

    private func isDateLike(_ text: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:\d{2})?)?$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func stripTagsAndAnchors(_ text: String) -> String {
        var result = text
        while result.hasPrefix("!") || result.hasPrefix("&") {
            guard let space = result.firstIndex(of: " ") else { break }
            result = String(result[result.index(after: space)...])
        }
        if result.hasPrefix("*") { return result }
        return result
    }

    private func unescapeDouble(_ text: String) -> String {
        let body = text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2
            ? String(text.dropFirst().dropLast())
            : String(text.dropFirst())
        var result = ""
        var iterator = body.makeIterator()
        while let character = iterator.next() {
            if character == "\\", let next = iterator.next() {
                switch next {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default: result.append(next)
                }
            } else {
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Key/value splitting

    /// Splits `key: value` on the first top level colon followed by a space or
    /// the end of the line. Returns `nil` when the text is not a mapping entry.
    func splitKeyValue(_ text: String) -> (String, String?)? {
        var depth = 0
        var quote: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let current = quote {
                if character == current {
                    if current == "'" {
                        let next = text.index(after: index)
                        if next < text.endIndex, text[next] == "'" {
                            index = text.index(after: next)
                            continue
                        }
                    }
                    quote = nil
                }
            } else {
                switch character {
                case "\"", "'":
                    quote = character
                case "[", "{":
                    depth += 1
                case "]", "}":
                    depth -= 1
                case ":":
                    let next = text.index(after: index)
                    if depth == 0, next >= text.endIndex || text[next] == " " || text[next] == "\t" {
                        let key = String(text[..<index]).trimmingCharacters(in: .whitespaces)
                        let value = String(text[next...]).trimmingCharacters(in: .whitespaces)
                        return (unquoteKey(key), value.isEmpty ? nil : value)
                    }
                default:
                    break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func unquoteKey(_ key: String) -> String {
        if key.count >= 2, key.hasPrefix("\""), key.hasSuffix("\"") {
            return unescapeDouble(key)
        }
        if key.count >= 2, key.hasPrefix("'"), key.hasSuffix("'") {
            return String(key.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return key
    }

    private func balancedInner(_ text: String, open: Character, close: Character) -> String {
        guard text.hasPrefix(String(open)), text.hasSuffix(String(close)), text.count >= 2 else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }

    private func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var quote: Character?
        var current = ""
        for character in text {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[", "{":
                depth += 1
                current.append(character)
            case "]", "}":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current)
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private mutating func fail(_ message: String, line: Int) {
        if failure == nil {
            failure = message
            failureLine = line
        }
    }
}
