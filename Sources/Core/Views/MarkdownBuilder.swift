import Foundation

/// Renders a practical Markdown subset to HTML: headings, paragraphs, ordered
/// and unordered lists (including task lists), fenced code blocks, blockquotes,
/// horizontal rules, tables and the usual inline markup.
public enum MarkdownBuilder {

    public static func render(context: RenderContext) throws -> RenderedPreview {
        let renderer = MarkdownRenderer(text: context.text, limits: context.limits)
        let body = renderer.render()
        return RenderedPreview(
            renderer: "Markdown",
            summary: "\(Format.integer(renderer.headingCount)) headings · \(Format.integer(renderer.lineCount)) lines",
            html: "<div class=\"markdown\">\(body)</div>",
            truncated: renderer.truncated || context.wasTruncatedAtRead,
            notice: context.wasTruncatedAtRead ? "Only the first \(Format.bytes(context.limits.maxBytes)) of this file were read." : nil
        )
    }
}

public final class MarkdownRenderer {

    private let lines: [String]
    private let limits: PreviewLimits
    private var index = 0
    private(set) var headingCount = 0
    private(set) var truncated = false

    public var lineCount: Int { lines.count }

    public init(text: String, limits: PreviewLimits = .default) {
        self.lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.limits = limits
    }

    public func render() -> String {
        var html = ""
        while index < lines.count {
            if html.count > 4_000_000 {
                truncated = true
                html += "<div class=\"notice\"><span>ℹ️</span><span>Preview truncated.</span></div>"
                break
            }
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if isFence(trimmed) {
                html += renderCodeBlock()
                continue
            }

            if trimmed.hasPrefix("<!--") {
                while index < lines.count, !lines[index].contains("-->") { index += 1 }
                index = min(index + 1, lines.count)
                continue
            }

            if let heading = headingLevel(trimmed) {
                headingCount += 1
                let text = String(trimmed.dropFirst(heading.count)).trimmingCharacters(in: .whitespaces)
                html += "<h\(heading.level)>\(inline(text))</h\(heading.level)>"
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                html += "<hr>"
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                html += renderBlockquote()
                continue
            }

            if trimmed.hasPrefix("|"), isTableHeader(at: index) {
                html += renderTable()
                continue
            }

            if isListMarker(trimmed) {
                html += renderList(indent: indentWidth(line))
                continue
            }

            html += renderParagraph()
        }
        return html
    }

    // MARK: - Blocks

    private func renderParagraph() -> String {
        var collected: [String] = []
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isFence(trimmed) || headingLevel(trimmed) != nil
                || isHorizontalRule(trimmed) || trimmed.hasPrefix(">") || isListMarker(trimmed)
                || (trimmed.hasPrefix("|") && isTableHeader(at: index)) {
                break
            }
            collected.append(trimmed)
            index += 1
        }
        let text = collected.joined(separator: "\n")
        return "<p>\(inline(text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
    }

    private func renderBlockquote() -> String {
        var collected: [String] = []
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            collected.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }
        let nested = MarkdownRenderer(text: collected.joined(separator: "\n"), limits: limits)
        return "<blockquote>\(nested.render())</blockquote>"
    }

    private func renderCodeBlock() -> String {
        let opening = lines[index]
        let fence = opening.trimmingCharacters(in: .whitespaces)
        let marker = fence.hasPrefix("```") ? "```" : "~~~"
        let info = String(fence.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        let languageId = info.split(separator: " ").first.map { String($0).lowercased() } ?? ""
        index += 1

        var body: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                index += 1
                break
            }
            body.append(line)
            index += 1
        }

        let language: SyntaxLexer.Language
        if languageId.isEmpty {
            language = SyntaxLexer.plain
        } else {
            language = SyntaxLexer.languages[languageId] ?? SyntaxLexer.language(forExtension: languageId)
        }
        let lexer = SyntaxLexer(language: language)
        var highlighted = ""
        for line in body {
            for segment in lexer.tokenize(line) {
                let escaped = HTML.escape(segment.text)
                if let cls = segment.tokenClass {
                    highlighted += "<span class=\"\(cls)\">\(escaped)</span>"
                } else {
                    highlighted += escaped
                }
            }
            highlighted += "\n"
        }
        let label = languageId.isEmpty ? "" : "<div class=\"meta\" style=\"margin-bottom:4px\">\(HTML.escape(language.displayName))</div>"
        return "\(label)<pre><code>\(highlighted)</code></pre>"
    }

    private func renderList(indent: Int) -> String {
        var html = ""
        var listType: String? = nil
        var openIndent = indent

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard isListMarker(trimmed) else { break }
            let lineIndent = indentWidth(line)
            if lineIndent < openIndent {
                break
            }
            if lineIndent > openIndent {
                html += renderList(indent: lineIndent)
                continue
            }
            let ordered = isOrderedMarker(trimmed)
            let type = ordered ? "ol" : "ul"
            if listType != type {
                if let listType { html += "</\(listType)>" }
                html += "<\(type)>"
                listType = type
            }
            let (content, task) = stripListMarker(trimmed)
            let inlineContent = inline(content)
            if let task {
                html += "<li class=\"task\">\(task ? "☑" : "☐") \(inlineContent)</li>"
            } else {
                html += "<li>\(inlineContent)</li>"
            }
            index += 1
        }
        if let listType { html += "</\(listType)>" }
        return html
    }

    private func isTableHeader(at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard separator.hasPrefix("|") || separator.contains("-") else { return false }
        let cells = splitRow(separator)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let cleaned = cell.trimmingCharacters(in: .whitespaces)
            return cleaned.count >= 1 && cleaned.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func renderTable() -> String {
        let headerCells = splitRow(lines[index])
        index += 2
        var html = "<table><thead><tr>"
        for cell in headerCells {
            html += "<th>\(inline(cell.trimmingCharacters(in: .whitespaces)))</th>"
        }
        html += "</tr></thead><tbody>"
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { break }
            let cells = splitRow(line)
            html += "<tr>"
            for cellIndex in 0..<headerCells.count {
                let cell = cellIndex < cells.count ? cells[cellIndex] : ""
                html += "<td>\(inline(cell.trimmingCharacters(in: .whitespaces)))</td>"
            }
            html += "</tr>"
            index += 1
        }
        html += "</tbody></table>"
        return html
    }

    // MARK: - Inline

    func inline(_ text: String) -> String {
        var output = HTML.escape(text)

        // Protect inline code spans before the other rules run.
        var codeSpans: [String] = []
        while let start = output.range(of: "`") {
            guard let end = output.range(of: "`", range: start.upperBound..<output.endIndex) else { break }
            let body = String(output[start.upperBound..<end.lowerBound])
            let placeholder = "\u{0001}\(codeSpans.count)\u{0001}"
            codeSpans.append("<code>\(body)</code>")
            output = output.replacingCharacters(in: start.lowerBound..<end.upperBound, with: placeholder)
            if codeSpans.count > 500 { break }
        }

        output = replace(pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#, in: output) { groups in
            "<img src=\"\(groups[1])\" alt=\"\(groups[0])\">"
        }
        output = replace(pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#, in: output) { groups in
            let url = groups[1]
            if url.hasPrefix("http://") || url.hasPrefix("https://") || url.hasPrefix("mailto:") {
                return "<a href=\"\(url)\">\(groups[0])</a>"
            }
            return "\(groups[0]) (\(url))"
        }
        output = replace(pattern: #"\*\*([^*]+)\*\*"#, in: output) { "<strong>\($0[0])</strong>" }
        output = replace(pattern: #"__([^_]+)__"#, in: output) { "<strong>\($0[0])</strong>" }
        output = replace(pattern: #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, in: output) { "<em>\($0[0])</em>" }
        output = replace(pattern: #"(?<![\w_])_([^_\n]+)_(?![\w_])"#, in: output) { "<em>\($0[0])</em>" }
        output = replace(pattern: #"~~([^~]+)~~"#, in: output) { "<del>\($0[0])</del>" }
        output = replace(pattern: #"==([^=]+)=="#, in: output) { "<mark>\($0[0])</mark>" }

        for (offset, span) in codeSpans.enumerated() {
            output = output.replacingOccurrences(of: "\u{0001}\(offset)\u{0001}", with: span)
        }
        return output
    }

    private func replace(pattern: String, in text: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = ""
        var lastEnd = text.startIndex
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let full = Range(match.range, in: text) else { return }
            result += text[lastEnd..<full.lowerBound]
            var groups: [String] = []
            for group in 1..<match.numberOfRanges {
                if let groupRange = Range(match.range(at: group), in: text) {
                    groups.append(String(text[groupRange]))
                } else {
                    groups.append("")
                }
            }
            result += transform(groups)
            lastEnd = full.upperBound
        }
        result += text[lastEnd...]
        return result
    }

    // MARK: - Marker helpers

    func headingLevel(_ line: String) -> (level: Int, count: Int)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let after = line.dropFirst(hashes)
        guard after.isEmpty || after.hasPrefix(" ") || after.hasPrefix("#") else { return nil }
        return (hashes, hashes)
    }

    func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" } || stripped.allSatisfy { $0 == "_" }
    }

    func isListMarker(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
        guard let regex = try? NSRegularExpression(pattern: #"^\d+[.)]\s"#) else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    func isOrderedMarker(_ line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^\d+[.)]\s"#) else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    func stripListMarker(_ line: String) -> (content: String, task: Bool?) {
        var content = line
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            content = String(line.dropFirst(2))
        } else if let regex = try? NSRegularExpression(pattern: #"^\d+[.)]\s"#) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, range: range), let swiftRange = Range(match.range, in: line) {
                content = String(line[swiftRange.upperBound...])
            }
        }
        if content.hasPrefix("[ ] ") || content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
            let checked = !content.hasPrefix("[ ]")
            return (String(content.dropFirst(4)), checked)
        }
        return (content, nil)
    }

    func indentWidth(_ line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 }
            else if character == "\t" { width += 4 }
            else { break }
        }
        return width
    }

    func splitRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line.trimmingCharacters(in: .whitespaces) {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        if let first = cells.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            cells.removeFirst()
        }
        if let last = cells.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            cells.removeLast()
        }
        return cells
    }
}
