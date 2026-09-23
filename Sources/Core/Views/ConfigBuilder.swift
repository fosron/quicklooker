import Foundation

/// YAML and TOML previews. Both try a real parse and fall back to syntax
/// highlighted source when the document cannot be understood.
public enum ConfigBuilder {

    // MARK: - YAML

    public static func renderYAML(context: RenderContext) throws -> RenderedPreview {
        let text = context.text
        var parser = YAMLParser(text: text)
        let result = parser.parse()

        guard result.failure == nil, let value = result.value else {
            let detail = result.failure.map { "line \(result.failureLine ?? 0): \($0)" } ?? "unknown parse error"
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "YAML",
                language: "yaml",
                notice: "The document could not be parsed (\(detail)). Showing syntax highlighted source."
            )
        }

        let typeHints = result.typeHints
        let keyLines = result.keyLines
        let renderer = TreeRenderer(options: TreeRenderer.Options(
            keyRendererWithPath: { path, key, _ in
                var html = "<span class=\"key\">\(HTML.escape(key))</span><span class=\"colon\">:</span> "
                if let line = keyLines[path] {
                    html = "<span class=\"count\">\(line)</span> " + html
                }
                return html
            },
            valueComment: { path, node in
                guard !node.isContainer else { return nil }
                return typeHints[path]
            },
            maxDepth: context.limits.maxDepth,
            nodeLimit: context.limits.maxNodes
        ))
        let treeHTML = renderer.render(value)

        var notice: String? = nil
        if let readNotice = context.wasTruncatedAtRead ? "Only the first \(Format.bytes(context.limits.maxBytes)) of this file were read." : nil {
            notice = readNotice
        }
        return RenderedPreview(
            renderer: "YAML",
            summary: "\(Format.integer(value.nodeCount)) values · \(Format.integer(result.lineCount)) lines",
            html: (notice.map { Document.notice($0) } ?? "") + treeHTML,
            truncated: renderer.didOverflow || context.wasTruncatedAtRead,
            notice: notice
        )
    }

    // MARK: - TOML

    public static func renderTOML(context: RenderContext) throws -> RenderedPreview {
        let result = TOMLParser(text: context.text).parse()
        if let failure = result.failure {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "TOML",
                language: "toml",
                notice: "The document could not be parsed (\(failure)). Showing syntax highlighted source."
            )
        }

        let typeHints = result.typeHints
        let renderer = TreeRenderer(options: TreeRenderer.Options(
            valueComment: { path, node in
                guard !node.isContainer else { return nil }
                return typeHints[path]
            },
            maxDepth: context.limits.maxDepth,
            nodeLimit: context.limits.maxNodes
        ))
        let treeHTML = renderer.render(result.value ?? .object([]))
        return RenderedPreview(
            renderer: "TOML",
            summary: "\(Format.integer(result.tableCount)) tables · \(Format.integer(result.lineCount)) lines",
            html: treeHTML,
            truncated: renderer.didOverflow || context.wasTruncatedAtRead,
            notice: context.wasTruncatedAtRead ? "Only the first \(Format.bytes(context.limits.maxBytes)) of this file were read." : nil
        )
    }
}
