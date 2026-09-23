import Foundation

/// Line oriented TOML parser covering the common configuration subset:
/// `[table]`, `[[array of tables]]`, dotted keys, inline tables, arrays,
/// basic / literal strings, numbers, booleans and dates.
public struct TOMLParser {

    public struct ParseResult: Sendable {
        public let value: ValueNode?
        public let typeHints: [String: String]
        public let tableCount: Int
        public let lineCount: Int
        public let failure: String?
    }

    private let text: String

    public init(text: String) {
        self.text = text
    }

    public func parse() -> ParseResult {
        var root: [String: ValueNode] = [:]
        var currentPath: [String] = []
        var typeHints: [String: String] = [:]
        var tableCount = 0
        var failure: String?

        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < rawLines.count {
            let raw = rawLines[index]
            let lineNumber = index + 1
            index += 1
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[[") {
                guard let name = extractHeaderName(line, prefix: "[[", suffix: "]]") else {
                    failure = "line \(lineNumber): malformed array table header"
                    break
                }
                let path = splitDottedKey(name)
                guard !path.isEmpty else {
                    failure = "line \(lineNumber): empty array table name"
                    break
                }
                tableCount += 1
                appendArrayTableElement(path: path, root: &root)
                currentPath = path
                continue
            }
            if line.hasPrefix("[") {
                guard let name = extractHeaderName(line, prefix: "[", suffix: "]") else {
                    failure = "line \(lineNumber): malformed table header"
                    break
                }
                let path = splitDottedKey(name)
                guard !path.isEmpty else {
                    failure = "line \(lineNumber): empty table name"
                    break
                }
                tableCount += 1
                ensureTable(path: path, root: &root)
                currentPath = path
                continue
            }

            guard let equals = findTopLevelEquals(line) else {
                failure = "line \(lineNumber): expected \"key = value\""
                break
            }
            let keyPart = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            var valuePart = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            let keyPath = splitDottedKey(keyPart)
            if keyPath.isEmpty {
                failure = "line \(lineNumber): empty key"
                break
            }

            // Multi line arrays: keep consuming while brackets are unbalanced.
            var guardCount = 0
            while !isBalanced(valuePart), index < rawLines.count, guardCount < 512 {
                let continuation = stripComment(rawLines[index]).trimmingCharacters(in: .whitespaces)
                index += 1
                guardCount += 1
                valuePart += "\n" + continuation
            }
            if !isBalanced(valuePart) {
                failure = "line \(lineNumber): unbalanced array or inline table"
                break
            }

            let fullPath = currentPath + keyPath
            let node = parseValue(valuePart, path: fullPath.joined(separator: "."), hints: &typeHints)
            setValue(node, path: currentPath + keyPath, root: &root)
        }

        return ParseResult(
            value: failure == nil ? .object(sortedEntries(root)) : nil,
            typeHints: typeHints,
            tableCount: tableCount,
            lineCount: rawLines.count,
            failure: failure
        )
    }

    // MARK: - Tree helpers

    private func sortedEntries(_ dictionary: [String: ValueNode]) -> [(String, ValueNode)] {
        dictionary.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ($0, dictionary[$0]!) }
    }

    private func ensureTable(path: [String], root: inout [String: ValueNode]) {
        guard !path.isEmpty else { return }
        if path.count == 1 {
            if root[path[0]] == nil {
                root[path[0]] = .object([])
            }
            return
        }
        var child = root[path[0]] ?? .object([])
        if case .object(var entries) = child {
            var nested: [String: ValueNode] = [:]
            for (key, value) in entries { nested[key] = value }
            ensureTable(path: Array(path.dropFirst()), root: &nested)
            entries = sortedEntries(nested)
            child = .object(entries)
            root[path[0]] = child
        }
    }

    private func appendArrayTableElement(path: [String], root: inout [String: ValueNode]) {
        guard let head = path.first else { return }
        if path.count == 1 {
            if case .array(var items) = root[head] ?? .array([]) {
                items.append(.object([]))
                root[head] = .array(items)
            } else {
                root[head] = .array([.object([])])
            }
            return
        }
        var child = root[head] ?? .object([])
        if case .object(var entries) = child {
            var nested: [String: ValueNode] = [:]
            for (key, value) in entries { nested[key] = value }
            appendArrayTableElement(path: Array(path.dropFirst()), root: &nested)
            entries = sortedEntries(nested)
            child = .object(entries)
            root[head] = child
        }
    }

    private func setValue(_ node: ValueNode, path: [String], root: inout [String: ValueNode]) {
        guard let head = path.first else { return }
        if path.count == 1 {
            root[head] = node
            return
        }
        var child = root[head] ?? .object([])
        if case .object(var entries) = child {
            var nested: [String: ValueNode] = [:]
            for (key, value) in entries { nested[key] = value }
            setValue(node, path: Array(path.dropFirst()), root: &nested)
            entries = sortedEntries(nested)
            child = .object(entries)
            root[head] = child
        } else if case .array(var items) = child {
            if case .object(var last) = items.last ?? .object([]) {
                var nested: [String: ValueNode] = [:]
                for (key, value) in last { nested[key] = value }
                setValue(node, path: Array(path.dropFirst()), root: &nested)
                last = sortedEntries(nested)
                items[items.count - 1] = .object(last)
                root[head] = .array(items)
            }
        }
    }

    // MARK: - Values

    private func parseValue(_ text: String, path: String, hints: inout [String: String]) -> ValueNode {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"\"\"") || value.hasPrefix("'''") {
            hints[path] = "string"
            let delimiter = value.hasPrefix("\"\"\"") ? "\"\"\"" : "'''"
            let body = value.hasPrefix(delimiter) && value.hasSuffix(delimiter) && value.count >= 6
                ? String(value.dropFirst(3).dropLast(3))
                : String(value.dropFirst(3))
            return .string(body)
        }
        if value.hasPrefix("\"") {
            hints[path] = "string"
            return .string(unescapeBasic(value))
        }
        if value.hasPrefix("'") {
            hints[path] = "string"
            let body = value.count >= 2 && value.hasSuffix("'") ? String(value.dropFirst().dropLast()) : String(value.dropFirst())
            return .string(body)
        }
        if value.hasPrefix("[") {
            hints[path] = "array"
            let inner = String(value.dropFirst().dropLast())
            let parts = splitTopLevel(inner)
            var items: [ValueNode] = []
            for (offset, part) in parts.enumerated() {
                let itemPath = "\(path)[\(offset)]"
                items.append(parseValue(part, path: itemPath, hints: &hints))
            }
            return .array(items)
        }
        if value.hasPrefix("{") {
            hints[path] = "table"
            let inner = String(value.dropFirst().dropLast())
            var entries: [(String, ValueNode)] = []
            for part in splitTopLevel(inner) {
                guard let equals = findTopLevelEquals(part) else { continue }
                let key = splitDottedKey(String(part[..<equals]).trimmingCharacters(in: .whitespaces)).joined(separator: ".")
                let itemPath = "\(path).\(key)"
                let childValue = String(part[part.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                entries.append((key, parseValue(childValue, path: itemPath, hints: &hints)))
            }
            return .object(entries)
        }

        switch value {
        case "true":
            hints[path] = "bool"
            return .boolean(true)
        case "false":
            hints[path] = "bool"
            return .boolean(false)
        default:
            break
        }

        if value.range(of: #"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:\d{2})?)?$"#, options: .regularExpression) != nil {
            hints[path] = "date"
            return .string(value)
        }
        if value.range(of: #"^\d{2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil {
            hints[path] = "time"
            return .string(value)
        }
        if let integer = parseInteger(value) {
            hints[path] = "int"
            return .number(String(integer))
        }
        if let double = Double(value.replacingOccurrences(of: "_", with: "")), value.contains(".") || value.lowercased().contains("e") {
            hints[path] = "float"
            return .number(Format.number(double))
        }
        hints[path] = "string"
        return .string(value)
    }

    private func parseInteger(_ text: String) -> Int64? {
        let cleaned = text.replacingOccurrences(of: "_", with: "")
        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") {
            return Int64(cleaned.dropFirst(2), radix: 16)
        }
        if cleaned.hasPrefix("0o") || cleaned.hasPrefix("0O") {
            return Int64(cleaned.dropFirst(2), radix: 8)
        }
        if cleaned.hasPrefix("0b") || cleaned.hasPrefix("0B") {
            return Int64(cleaned.dropFirst(2), radix: 2)
        }
        return Int64(cleaned)
    }

    private func unescapeBasic(_ text: String) -> String {
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
                case "u", "U":
                    var hex = ""
                    let count = next == "u" ? 4 : 8
                    for _ in 0..<count {
                        guard let digit = iterator.next() else { break }
                        hex.append(digit)
                    }
                    if let scalar = UInt32(hex, radix: 16), let unicode = UnicodeScalar(scalar) {
                        result.append(Character(unicode))
                    } else {
                        result.append("\\\(next)")
                    }
                default:
                    result.append(next)
                }
            } else {
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Lexing helpers

    private func stripComment(_ line: String) -> String {
        var quote: Character?
        var result = ""
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if let activeQuote = quote {
                result.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "#" { break }
            if character == "\"" || character == "'" {
                quote = character
            }
            result.append(character)
        }
        return result
    }

    private func extractHeaderName(_ line: String, prefix: String, suffix: String) -> String? {
        guard line.hasPrefix(prefix), line.hasSuffix(suffix), line.count >= prefix.count + suffix.count else {
            return nil
        }
        return String(line.dropFirst(prefix.count).dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    }

    func splitDottedKey(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                    parts.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
            case ".":
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        parts.append(current)
        return parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func findTopLevelEquals(_ text: String) -> String.Index? {
        var quote: Character?
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else {
                switch character {
                case "\"", "'":
                    quote = character
                case "[", "{":
                    depth += 1
                case "]", "}":
                    depth -= 1
                case "=" where depth == 0:
                    return index
                default:
                    break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var depth = 0
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
            case "\n":
                current.append(" ")
            default:
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current)
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func isBalanced(_ text: String) -> Bool {
        var quote: Character?
        var depth = 0
        for character in text {
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
            case "[", "{":
                depth += 1
            case "]", "}":
                depth -= 1
            default:
                break
            }
        }
        return depth <= 0
    }
}
