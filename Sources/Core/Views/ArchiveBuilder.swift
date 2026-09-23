import Foundation

/// ZIP, tar and gzip listings plus folder browsing.
public enum ArchiveBuilder {

    public static func render(context: RenderContext) throws -> RenderedPreview {
        if context.fileURL?.hasDirectoryPath == true {
            return try renderFolder(context)
        }
        if let archive = try routeToArchive(context) {
            return archive
        }
        // Not an archive after all: treat as text.
        return try CodeBuilder.render(context: context)
    }

    @discardableResult
    private static func routeToArchive(_ context: RenderContext) throws -> RenderedPreview? {
        let ext = context.fileExtension
        switch ext {
        case "zip", "jar", "epub", "ipa", "xpi", "whl", "vsix", "apk":
            return try renderZIP(context)
        case "tar":
            return try renderTAR(context)
        case "gz", "gzip", "tgz":
            return try renderGZIP(context)
        default:
            break
        }
        if context.contentTypeIdentifier.hasSuffix("zip-archive") {
            return try renderZIP(context)
        }
        if context.contentTypeIdentifier.hasSuffix("tar-archive") {
            return try renderTAR(context)
        }
        if context.contentTypeIdentifier.hasSuffix("gzip") {
            return try renderGZIP(context)
        }
        return nil
    }

    // MARK: - ZIP

    static func renderZIP(_ context: RenderContext) throws -> RenderedPreview {
        let entries: [ZIPReader.Entry]
        do {
            entries = try ZIPReader.entries(in: context.data)
        } catch {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "ZIP",
                notice: "The archive could not be read (\(error.localizedDescription)). Showing raw source."
            )
        }

        let totalUncompressed = entries.reduce(0) { $0 + $1.uncompressedSize }
        let totalCompressed = entries.reduce(0) { $0 + $1.compressedSize }
        let visible = entries.prefix(context.limits.maxEntries)

        let rows = visible.map { entry -> [Document.Cell] in
            let depth = max(0, entry.name.components(separatedBy: "/").count - 2)
            let indent = String(repeating: "&nbsp;&nbsp;&nbsp;", count: depth)
            let icon = entry.isDirectory ? "📁" : iconFor(name: entry.name)
            let name = "\(indent)\(icon) \(HTML.escape(entry.name))"
            let ratio: String
            if entry.isDirectory || entry.uncompressedSize == 0 {
                ratio = "—"
            } else {
                ratio = Format.percent(1 - Double(entry.compressedSize) / Double(max(entry.uncompressedSize, 1)))
            }
            return [
                Document.Cell(html: name),
                Document.Cell(entry.isDirectory ? "—" : Format.bytes(entry.uncompressedSize), alignment: .right),
                Document.Cell(entry.isDirectory ? "—" : Format.bytes(entry.compressedSize), alignment: .right),
                Document.Cell(ratio, alignment: .right),
                Document.Cell(entry.modified.map { Format.date($0) } ?? "—"),
                Document.Cell(html: "<span class=\"meta\">\(HTML.escape(entry.methodName))</span>"),
            ]
        }

        var html = Document.cards([
            ("entries", Format.integer(entries.count)),
            ("uncompressed", Format.bytes(totalUncompressed)),
            ("compressed", Format.bytes(totalCompressed)),
            ("saved", totalUncompressed > 0 ? Format.percent(1 - Double(totalCompressed) / Double(totalUncompressed)) : "0%"),
        ])
        if let comment = ZIPReader.comment(in: context.data), !comment.isEmpty {
            html += Document.notice("Archive comment: \(comment)")
        }
        html += Document.tableScroll(
            headers: ["name", "size", "compressed", "saved", "modified", "method"],
            rows: rows
        )

        let truncated = entries.count > visible.count || context.wasTruncatedAtRead
        var notice: String? = nil
        if entries.count > visible.count {
            notice = "List limited to the first \(Format.integer(visible.count)) entries."
        }
        return RenderedPreview(
            renderer: "ZIP archive",
            summary: "\(Format.integer(entries.count)) entries · \(Format.bytes(context.data.count))",
            html: html,
            truncated: truncated,
            notice: notice
        )
    }

    // MARK: - TAR

    static func renderTAR(_ context: RenderContext) throws -> RenderedPreview {
        let entries: [TARReader.Entry]
        do {
            entries = try TARReader.entries(in: context.data)
        } catch {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "tar",
                notice: "The archive could not be read (\(error.localizedDescription)). Showing raw source."
            )
        }

        let visible = entries.prefix(context.limits.maxEntries)
        let totalSize = entries.reduce(0) { $0 + $1.size }

        var html = Document.cards([
            ("entries", Format.integer(entries.count)),
            ("total size", Format.bytes(totalSize)),
        ])
        html += tarTable(entries: Array(visible))
        let truncated = entries.count > visible.count || context.wasTruncatedAtRead
        return RenderedPreview(
            renderer: "tar archive",
            summary: "\(Format.integer(entries.count)) entries · \(Format.bytes(context.data.count))",
            html: html,
            truncated: truncated,
            notice: entries.count > visible.count ? "List limited to the first \(Format.integer(visible.count)) entries." : nil
        )
    }

    static func tarTable(entries: [TARReader.Entry]) -> String {
        let rows = entries.map { entry -> [Document.Cell] in
            let icon = entry.kind == .directory ? "📁" : iconFor(name: entry.name)
            let name = "\(icon) \(HTML.escape(entry.name))"
            let detail: String
            switch entry.kind {
            case .symlink, .hardlink:
                detail = "→ \(entry.linkTarget ?? entry.kind.rawValue)"
            case .directory:
                detail = "directory"
            case .file:
                detail = "file"
            case .other:
                detail = entry.kind.rawValue
            }
            return [
                Document.Cell(html: name),
                Document.Cell(entry.kind == .file ? Format.bytes(entry.size) : "—", alignment: .right),
                Document.Cell(html: "<span class=\"meta\">\(HTML.escape(detail))</span>"),
                Document.Cell(entry.modified.map { Format.date($0) } ?? "—"),
                Document.Cell(html: "<span class=\"meta\">\(HTML.escape(entry.mode))</span>"),
            ]
        }
        return Document.tableScroll(headers: ["name", "size", "kind", "modified", "mode"], rows: rows)
    }

    // MARK: - GZIP

    static func renderGZIP(_ context: RenderContext) throws -> RenderedPreview {
        let result: GZIPReader.Result
        do {
            result = try GZIPReader.decompress(context.data, maxBytes: context.limits.maxDecompressedBytes)
        } catch {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "GZIP",
                notice: "The archive could not be decompressed (\(error.localizedDescription)). Showing raw source."
            )
        }

        var cards: [(String, String)] = [
            ("decompressed", Format.bytes(result.data.count)),
            ("compressed", Format.bytes(context.data.count)),
            ("original size field", Format.bytes(result.originalSize)),
        ]
        if let name = result.info.originalName, !name.isEmpty {
            cards.append(("original name", name))
        }
        if let modified = result.info.modified, modified.timeIntervalSince1970 > 0 {
            cards.append(("modified", Format.date(modified)))
        }
        var html = Document.cards(cards)
        if let comment = result.info.comment, !comment.isEmpty {
            html += Document.notice("Archive comment: \(comment)")
        }

        // `file.tar.gz` is common: unpack the nested tar listing as well.
        if let entries = try? TARReader.entries(in: result.data), !entries.isEmpty {
            html += Document.section("tar entries", count: entries.count)
            html += tarTable(entries: Array(entries.prefix(context.limits.maxEntries)))
            return RenderedPreview(
                renderer: "GZIP archive",
                summary: "\(Format.bytes(context.data.count)) → \(Format.bytes(result.data.count)) tar · \(Format.integer(entries.count)) entries",
                html: html,
                truncated: result.truncated || entries.count > context.limits.maxEntries,
                notice: "The gzip payload is a tar archive; its entries are listed below."
            )
        }

        if let text = String(data: result.data, encoding: .utf8) {
            let language = SyntaxLexer.language(forExtension: guessedExtension(for: result.info.originalName ?? context.fileName))
            let (codeHTML, _, shown, truncated) = CodeBuilder.codeHTML(
                text: text,
                language: language,
                limits: context.limits
            )
            html += Document.section("content", count: shown)
            html += codeHTML
            return RenderedPreview(
                renderer: "GZIP archive",
                summary: "\(Format.bytes(context.data.count)) → \(Format.bytes(result.data.count)) text · \(Format.integer(shown)) lines",
                html: html,
                truncated: truncated || result.truncated,
                notice: result.truncated ? "The payload was truncated at \(Format.bytes(context.limits.maxDecompressedBytes))." : nil
            )
        }

        html += Document.section("content")
        html += "<div class=\"empty\">Binary payload (\(Format.bytes(result.data.count))) — not rendered.</div>"
        html += hexDump(result.data.prefix(2_048))
        return RenderedPreview(
            renderer: "GZIP archive",
            summary: "\(Format.bytes(context.data.count)) → \(Format.bytes(result.data.count)) binary",
            html: html,
            truncated: result.truncated,
            notice: result.truncated ? "The payload was truncated at \(Format.bytes(context.limits.maxDecompressedBytes))." : nil
        )
    }

    // MARK: - Folder browsing

    static func renderFolder(_ context: RenderContext) throws -> RenderedPreview {
        guard let url = context.fileURL else {
            throw PreviewError.unreadableFile("missing folder URL")
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )
        let sorted = contents.sorted { lhs, rhs in
            let lhsDirectory = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rhsDirectory = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if lhsDirectory != rhsDirectory {
                return lhsDirectory
            }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }

        let visible = sorted.prefix(context.limits.maxEntries)
        var rows: [[Document.Cell]] = []
        var directoryCount = 0
        var totalSize = 0
        for item in visible {
            let values = try? item.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            if isDirectory { directoryCount += 1 }
            let size = values?.fileSize ?? 0
            if !isDirectory { totalSize += size }
            let icon = isDirectory ? "📁" : iconFor(name: item.lastPathComponent)
            let isSymlink = values?.isSymbolicLink ?? false
            let name = "\(icon) \(HTML.escape(item.lastPathComponent))\(isSymlink ? " ↗" : "")"
            rows.append([
                Document.Cell(html: name),
                Document.Cell(isDirectory ? "—" : Format.bytes(size), alignment: .right),
                Document.Cell(values?.contentModificationDate.map { Format.date($0) } ?? "—"),
            ])
        }

        var html = Document.cards([
            ("items", Format.integer(sorted.count)),
            ("folders", Format.integer(directoryCount)),
            ("file size", Format.bytes(totalSize)),
        ])
        html += Document.tableScroll(headers: ["name", "size", "modified"], rows: rows)

        return RenderedPreview(
            renderer: "Folder",
            summary: "\(Format.integer(sorted.count)) items · \(Format.integer(directoryCount)) folders",
            html: html,
            truncated: sorted.count > visible.count,
            notice: sorted.count > visible.count ? "List limited to the first \(Format.integer(visible.count)) items." : nil
        )
    }

    // MARK: - Helpers

    static func iconFor(name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return "🅢"
        case "md", "markdown": return "📝"
        case "json", "jsonl", "yaml", "yml", "toml": return "⚙️"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff": return "🖼"
        case "mp3", "wav", "m4a", "aac": return "🎵"
        case "mp4", "mov", "mkv", "avi": return "🎬"
        case "pdf": return "📕"
        case "zip", "gz", "tar", "tgz": return "🗜"
        case "sqlite", "db": return "🗄"
        case "sh", "bash", "zsh": return "⌨️"
        default: return "📄"
        }
    }

    static func guessedExtension(for name: String) -> String {
        var ext = (name as NSString).pathExtension.lowercased()
        if ext == "gz" || ext == "gzip" {
            ext = ((name as NSString).deletingPathExtension as NSString).pathExtension.lowercased()
        }
        return ext
    }

    static func hexDump(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var html = "<div class=\"code\"><pre style=\"padding:0 14px\">"
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let lineBytes = Array(bytes[offset..<min(offset + 16, bytes.count)])
            let hex = lineBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = lineBytes.map { byte -> String in
                (byte >= 32 && byte < 127) ? String(UnicodeScalar(byte)) : "."
            }.joined()
            let address = String(format: "%08x", offset)
            html += "<span class=\"ln\">\(address)  \(hex.padding(toLength: 47, withPad: " ", startingAt: 0))  \(ascii)</span>"
            offset += 16
        }
        html += "</pre></div>"
        return html
    }
}
