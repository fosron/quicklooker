import Foundation

/// JSON and JSON Lines previews.
public enum JSONBuilder {

    public static func render(context: RenderContext) throws -> RenderedPreview {
        if looksLikeJSONLines(context) {
            return try renderJSONLines(context)
        }
        return try renderSingleJSON(context)
    }

    static func looksLikeJSONLines(_ context: RenderContext) -> Bool {
        let ext = context.fileExtension
        if ext == "jsonl" || ext == "ndjson" {
            return true
        }
        if context.contentTypeIdentifier.contains("jsonl") {
            return true
        }
        let text = context.text
        var newlines = 0
        var counted = 0
        for character in text {
            if character == "\n" {
                newlines += 1
            }
            counted += 1
            if counted > 1_000_000 {
                break
            }
        }
        return newlines >= 3
    }

    // MARK: - Single JSON document

    static func renderSingleJSON(_ context: RenderContext) throws -> RenderedPreview {
        let root: ValueNode
        do {
            root = try ValueNode.fromJSONData(context.data)
        } catch {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "JSON",
                notice: "The file is not valid JSON (\(errorSummary(error))). Showing syntax highlighted source."
            )
        }

        let nodes = root.nodeCount
        var renderer = TreeRenderer(options: TreeRenderer.Options(
            maxDepth: context.limits.maxDepth,
            nodeLimit: context.limits.maxNodes
        ))
        let treeHTML = renderer.render(root)
        let truncated = renderer.didOverflow || context.wasTruncatedAtRead
        let summary = "\(Format.integer(nodes)) values · \(Format.bytes(context.data.count))"
        return RenderedPreview(
            renderer: "JSON tree",
            summary: summary,
            html: context.wasTruncatedAtRead
                ? Document.notice("Only the first \(Format.bytes(context.limits.maxBytes)) of this file were read.") + treeHTML
                : treeHTML,
            truncated: truncated
        )
    }

    // MARK: - JSON Lines

    static func renderJSONLines(_ context: RenderContext) throws -> RenderedPreview {
        let text = context.text
        let allLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var records: [String] = []
        var failed = 0
        var unread = 0
        for (index, line) in allLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if records.count >= context.limits.maxEntries {
                unread = allLines.count - index
                break
            }
            records.append(String(line))
        }

        guard !records.isEmpty else {
            return RenderedPreview(
                renderer: "JSON Lines",
                summary: "no records",
                html: "<div class=\"empty\">No JSON records found.</div>"
            )
        }

        var html = ""
        for (index, record) in records.enumerated() {
            guard let data = record.data(using: .utf8),
                  let node = try? ValueNode.fromJSONData(data) else {
                failed += 1
                html += """
                <div class="tree"><div class="node"><details><summary><div class="line">\
                <span class="index">#\(index + 1)</span>\
                <span class="count">unparseable line</span></div></summary>\
                <div class="children"><div class="leaf"><div class="line">\(HTML.escape(record))</div></div></div>\
                </details></div></div>
                """
                continue
            }
            let renderer = TreeRenderer(options: TreeRenderer.Options(
                maxDepth: context.limits.maxDepth,
                nodeLimit: max(64, context.limits.maxNodes / max(1, records.count))
            ))
            var recordHTML = renderer.render(node, rootKey: "#\(index + 1)")
            if index < records.count - 1 {
                recordHTML += "<div class=\"record-separator\"></div>"
            }
            html += recordHTML
        }

        var notice: String? = nil
        if failed > 0 {
            notice = "\(failed) line(s) could not be parsed as JSON."
        }
        if unread > 0 {
            notice = (notice.map { $0 + " " } ?? "") + "Preview limited to the first \(Format.integer(records.count)) records."
        }
        let truncated = context.wasTruncatedAtRead || unread > 0
        let summary = "\(Format.integer(records.count)) records · \(Format.bytes(context.data.count))"
        return RenderedPreview(
            renderer: "JSON Lines",
            summary: summary,
            html: html,
            truncated: truncated,
            notice: notice
        )
    }

    static func errorSummary(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return String(describing: decodingError)
        }
        let nsError = error as NSError
        return nsError.localizedDescription
    }
}
