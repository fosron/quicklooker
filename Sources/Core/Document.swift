import Foundation

/// Header / footer / small building blocks shared by every adapter.
public enum Document {

    public struct Badge {
        public enum Kind { case normal, muted, warn }
        public let text: String
        public let kind: Kind
        public init(_ text: String, kind: Kind = .normal) {
            self.text = text
            self.kind = kind
        }
    }

    /// Renders the sticky top bar: file name, renderer summary and badges.
    public static func header(title: String, subtitle: String, badges: [Badge]) -> String {
        var parts: [String] = []
        parts.append("<span class=\"title\">\(HTML.escape(title))</span>")
        let badgeHTML = badges.map { badge -> String in
            let kind: String
            switch badge.kind {
            case .normal: kind = ""
            case .muted: kind = " muted"
            case .warn: kind = " warn"
            }
            return "<span class=\"badge\(kind)\">\(HTML.escape(badge.text))</span>"
        }.joined()
        parts.append(badgeHTML)
        parts.append("<span class=\"spacer\"></span>")
        if !subtitle.isEmpty {
            parts.append("<span class=\"meta\">\(HTML.escape(subtitle))</span>")
        }
        return parts.joined()
    }

    public static func footer(renderer: String, note: String?, truncated: Bool) -> String {
        var pieces: [String] = []
        if let note, !note.isEmpty {
            pieces.append(HTML.escape(note))
        }
        if truncated {
            pieces.append("Preview truncated — open the file in an app for the full content.")
        }
        pieces.append("\(HTML.escape(renderer)) · QuickLooker · processed on device")
        return pieces.joined(separator: " · ")
    }

    /// Creates a full HTML page ready to hand to `QLPreviewReply`.
    public static func page(context: RenderContext, preview: RenderedPreview) -> String {
        var badges: [Badge] = []
        if preview.truncated {
            badges.append(Badge("truncated", kind: .warn))
        }
        let header = header(
            title: context.fileBaseName,
            subtitle: preview.summary,
            badges: badges
        )
        let footer = footer(renderer: preview.renderer, note: preview.notice, truncated: preview.truncated)
        return StyleSheet.document(
            title: context.fileBaseName,
            appearance: context.appearance,
            header: header,
            body: preview.html,
            footer: footer
        )
    }

    /// Standard error card used when a file cannot be previewed.
    public static func errorPage(context: RenderContext, message: String, detail: String? = nil) -> String {
        var body = """
        <div class="error">
        <span class="glyph">⚠️</span>
        <div>
        <div style="font-weight:600">Unable to preview this file</div>
        <div class="message">\(HTML.escape(message))</div>
        """
        if let detail {
            body += "<pre class=\"raw\" style=\"margin-top:8px\">\(HTML.escape(detail))</pre>"
        }
        body += "</div></div>"
        let header = header(title: context.fileBaseName, subtitle: "", badges: [Badge("unavailable", kind: .warn)])
        return StyleSheet.document(
            title: context.fileBaseName,
            appearance: context.appearance,
            header: header,
            body: body,
            footer: footer(renderer: "error", note: nil, truncated: false)
        )
    }

    /// Empty state for zero-byte or whitespace-only files.
    public static func emptyPage(context: RenderContext) -> String {
        let header = header(title: context.fileBaseName, subtitle: "0 bytes", badges: [Badge("empty", kind: .muted)])
        return StyleSheet.document(
            title: context.fileBaseName,
            appearance: context.appearance,
            header: header,
            body: "<div class=\"empty\">This file is empty.</div>",
            footer: footer(renderer: "empty", note: nil, truncated: false)
        )
    }

    /// Notice banner used when a primary adapter fell back to raw output.
    public static func notice(_ text: String) -> String {
        "<div class=\"notice\"><span>ℹ️</span><span>\(HTML.escape(text))</span></div>"
    }

    /// Simple two column key/value list.
    public static func keyValueList(_ pairs: [(String, String)]) -> String {
        var html = "<div class=\"kv\">"
        for (key, value) in pairs {
            html += "<div class=\"k\">\(HTML.escape(key))</div><div>\(HTML.escape(value))</div>"
        }
        html += "</div>"
        return html
    }

    /// Card grid summary.
    public static func cards(_ items: [(label: String, value: String)]) -> String {
        guard !items.isEmpty else { return "" }
        var html = "<div class=\"cards\">"
        for item in items {
            html += """
            <div class="card"><div class="label">\(HTML.escape(item.label))</div>\
            <div class="value">\(HTML.escape(item.value))</div></div>
            """
        }
        html += "</div>"
        return html
    }

    public static func section(_ title: String, count: Int? = nil) -> String {
        var text = HTML.escape(title)
        if let count {
            text += " <span class=\"meta\">(\(Format.integer(count)))</span>"
        }
        return "<div class=\"section\">\(text)</div>"
    }

    /// Table built from a header row and string cells. Cells may contain
    /// pre-escaped markup flagged with `isHTML`.
    public static func table(headers: [String], rows: [[Cell]]) -> String {
        table(headers: headers, rows: rows, scrollable: false)
    }

    /// Table with a bounded height so huge listings stay navigable.
    public static func tableScroll(headers: [String], rows: [[Cell]]) -> String {
        table(headers: headers, rows: rows, scrollable: true)
    }

    private static func table(headers: [String], rows: [[Cell]], scrollable: Bool) -> String {
        guard !rows.isEmpty else {
            return "<div class=\"empty\">Nothing to list.</div>"
        }
        var html = "<div class=\"table-scroll\(scrollable ? " bounded" : "")\"><table class=\"grid\"><thead><tr>"
        for header in headers {
            html += "<th>\(HTML.escape(header))</th>"
        }
        html += "</tr></thead><tbody>"
        for row in rows {
            html += "<tr>"
            for cell in row {
                let cls = cell.alignment == .right ? " class=\"num\"" : ""
                if cell.isHTML {
                    html += "<td\(cls)>\(cell.text)</td>"
                } else {
                    html += "<td\(cls)>\(HTML.escape(cell.text))</td>"
                }
            }
            html += "</tr>"
        }
        html += "</tbody></table></div>"
        return html
    }

    public struct Cell {
        public enum Alignment { case left, right }
        public let text: String
        public let isHTML: Bool
        public let alignment: Alignment

        public init(_ text: String, alignment: Alignment = .left) {
            self.text = text
            self.isHTML = false
            self.alignment = alignment
        }

        public init(html: String, alignment: Alignment = .left) {
            self.text = html
            self.isHTML = true
            self.alignment = alignment
        }

        public static func right(_ text: String) -> Cell {
            Cell(text, alignment: .right)
        }
    }
}
