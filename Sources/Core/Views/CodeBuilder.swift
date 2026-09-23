import Foundation

/// Source code preview with a line number gutter and adaptive theming.
public enum CodeBuilder {

    public static func render(context: RenderContext) throws -> RenderedPreview {
        let language = SyntaxLexer.language(forExtension: context.fileExtension)
        guard context.isLikelyText else {
            throw PreviewError.binaryContent
        }
        let text = context.text
        let (html, lineCount, shown, truncated) = codeHTML(
            text: text,
            language: language,
            limits: context.limits
        )
        var summary = "\(language.displayName) · \(Format.integer(shown)) lines · \(Format.bytes(context.data.count))"
        if truncated {
            summary += " (of \(Format.integer(lineCount)))"
        }
        return RenderedPreview(
            renderer: "Source",
            summary: summary,
            html: html,
            truncated: truncated || context.wasTruncatedAtRead
        )
    }

    /// Renders source as a syntax highlighted block. Returns the HTML, the
    /// total line count and how many lines were rendered.
    public static func codeHTML(
        text: String,
        language: SyntaxLexer.Language,
        limits: PreviewLimits
    ) -> (html: String, totalLines: Int, shownLines: Int, truncated: Bool) {
        let allLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let limit = max(1, limits.maxLines)
        let truncated = allLines.count > limit
        let visible = truncated ? allLines.prefix(limit) : allLines[...]

        let lexer = SyntaxLexer(language: language)
        var body = ""
        for line in visible {
            let segments = lexer.tokenize(String(line))
            var lineHTML = ""
            for segment in segments {
                let escaped = HTML.escape(segment.text)
                if let cls = segment.tokenClass {
                    lineHTML += "<span class=\"\(cls)\">\(escaped)</span>"
                } else {
                    lineHTML += escaped
                }
            }
            body += "<span class=\"ln\">\(lineHTML)\n</span>"
        }
        var html = "<div class=\"code\"><pre>\(body)</pre></div>"
        if truncated {
            html += "<div class=\"more\">— showing the first \(Format.integer(limit)) of \(Format.integer(allLines.count)) lines —</div>"
        }
        return (html, allLines.count, visible.count, truncated)
    }

    /// Used by other adapters when their structured parse fails: renders the
    /// raw source with syntax highlighting plus an explanatory notice.
    static func fallbackPreview(
        context: RenderContext,
        renderer: String,
        language: String? = nil,
        notice: String
    ) throws -> RenderedPreview {
        guard context.isLikelyText else {
            throw PreviewError.binaryContent
        }
        let resolved = language.map { SyntaxLexer.languages[$0] ?? SyntaxLexer.generic }
            ?? SyntaxLexer.language(forExtension: context.fileExtension)
        let (html, _, shown, truncated) = codeHTML(
            text: context.text,
            language: resolved,
            limits: context.limits
        )
        return RenderedPreview(
            renderer: renderer,
            summary: "source fallback · \(Format.integer(shown)) lines",
            html: Document.notice(notice) + html,
            truncated: truncated || context.wasTruncatedAtRead,
            notice: notice
        )
    }
}
