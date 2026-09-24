import Foundation

/// `.env` preview: parses `KEY=VALUE` lines, highlights comments and masks
/// values whose key looks like a secret. Masking happens in the renderer, so
/// the revealed markup is opt-in via a CSS only toggle.
public enum SecretsBuilder {

    public struct Entry: Equatable {
        public enum Kind: Equatable {
            case assignment
            case comment
            case blank
            case malformed
        }
        public let line: Int
        public let kind: Kind
        public let key: String
        public let value: String
        public let raw: String
        public let isSecret: Bool
    }

    public static func isSecretKey(_ key: String) -> Bool {
        SecretsMasking.isSecretKey(key)
    }

    /// Masks a value, keeping a short prefix for readability.
    public static func mask(_ value: String) -> String {
        SecretsMasking.mask(value)
    }

    public static func parse(text: String) -> [Entry] {
        var entries: [Entry] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                entries.append(Entry(line: index + 1, kind: .blank, key: "", value: "", raw: line, isSecret: false))
                continue
            }
            if trimmed.hasPrefix("#") {
                entries.append(Entry(line: index + 1, kind: .comment, key: "", value: "", raw: line, isSecret: false))
                continue
            }
            var body = trimmed
            var exported = false
            if body.hasPrefix("export ") {
                body = String(body.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
                exported = true
            }
            guard let equals = body.firstIndex(of: "=") else {
                entries.append(Entry(line: index + 1, kind: .malformed, key: body, value: "", raw: line, isSecret: false))
                continue
            }
            let key = String(body[..<equals]).trimmingCharacters(in: .whitespaces)
            var value = String(body[body.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if !exported, key.isEmpty {
                entries.append(Entry(line: index + 1, kind: .malformed, key: key, value: value, raw: line, isSecret: false))
                continue
            }
            value = unquote(value)
            entries.append(Entry(
                line: index + 1,
                kind: .assignment,
                key: key,
                value: value,
                raw: line,
                isSecret: isSecretKey(key)
            ))
        }
        return entries
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            let body = String(value.dropFirst().dropLast())
            return body
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if value.hasPrefix("'") && value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - Rendering

    public static func render(context: RenderContext) throws -> RenderedPreview {
        let entries = parse(text: context.text)
        let assignments = entries.filter { $0.kind == .assignment }
        let secretCount = assignments.filter { SecretsMasking.shouldMask(key: $0.key, value: $0.value) }.count

        // Only masked values are written to the document. The unmasked values
        // are never embedded in the HTML, so a preview can never leak them.
        var rows = ""
        for entry in entries {
            switch entry.kind {
            case .blank:
                continue
            case .comment:
                rows += row(entry, value: "<span class=\"tok-comment\">\(HTML.escape(entry.raw))</span>")
            case .malformed:
                rows += row(entry, value: "<span class=\"warn-text\">\(HTML.escape(entry.raw))</span>")
            case .assignment:
                let key = "<span class=\"env-key\">\(HTML.escape(entry.key))</span><span class=\"env-equals\">=</span>"
                if SecretsMasking.shouldMask(key: entry.key, value: entry.value) {
                    rows += row(entry, value: "\(key)<span class=\"masked-value tok-string\">\(HTML.escape(mask(entry.value)))\"</span>")
                } else {
                    rows += row(entry, value: "\(key)<span class=\"tok-string\">\(HTML.escape(entry.value))\"</span>")
                }
            }
        }

        var body = "<div class=\"env\">"
        body += "<div class=\"env-toolbar\"><span class=\"badge muted\">masked</span>"
        body += "<span class=\"meta\">\(Format.integer(assignments.count)) variables"
        if secretCount > 0 {
            body += " · \(Format.integer(secretCount)) likely secret\(secretCount == 1 ? "" : "s") hidden"
        }
        body += "</span></div>"
        body += "<div class=\"code env-code\"><pre>\(rows)</pre></div>"
        body += "</div>"

        let truncated = context.wasTruncatedAtRead
        var notice: String? = nil
        if secretCount > 0 {
            notice = "\(secretCount) value(s) matched secret naming patterns. Masked values are never included in the preview; open the file in a text editor to inspect them."
        }
        return RenderedPreview(
            renderer: "Environment",
            summary: "\(Format.integer(assignments.count)) variables · \(Format.bytes(context.data.count))",
            html: (notice.map { Document.notice($0) } ?? "") + body,
            truncated: truncated,
            notice: notice
        )
    }

    private static func row(_ entry: Entry, value: String) -> String {
        let number = "<span class=\"env-ln\">\(entry.line)</span>"
        return "<span class=\"env-line\">\(number)\(value)\n</span>"
    }
}
