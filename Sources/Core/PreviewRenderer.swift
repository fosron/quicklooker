import Foundation
import UniformTypeIdentifiers

/// Public entry point: decides which adapter handles a file and produces both
/// the `RenderedPreview` model and the final HTML document.
public enum PreviewRenderer {

    public enum Format: String, Sendable {
        case empty
        case packageJSON
        case composerJSON
        case composerLock
        case dockerCompose
        case json
        case jsonLines
        case sqlite
        case env
        case yaml
        case toml
        case markdown
        case archive
        case folder
        case code
        case text
    }

    // MARK: - Routing

    public static func detectFormat(_ context: RenderContext) -> Format {
        if context.fileURL?.hasDirectoryPath == true {
            return .folder
        }
        if context.data.isEmpty {
            return .empty
        }

        let name = context.fileBaseName.lowercased()
        let ext = context.fileExtension
        let type = context.contentTypeIdentifier.lowercased()

        if ext == "gz" || ext == "gzip" {
            return .archive
        }
        if name == "package.json" {
            return .packageJSON
        }
        if name == "composer.json" {
            return .composerJSON
        }
        if name == "composer.lock" {
            return .composerLock
        }
        if isComposeFileName(name) {
            return .dockerCompose
        }
        if name == ".env" || name.hasSuffix(".env") || ext == "env" || name.hasPrefix(".env.") {
            return .env
        }
        if ext == "jsonl" || ext == "ndjson" {
            return .jsonLines
        }

        let prefix = Array(context.data.prefix(16))

        if prefix.starts(with: [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65]) { // "SQLite"
            return .sqlite
        }
        if prefix.starts(with: [0x50, 0x4B, 0x03, 0x04])
            || prefix.starts(with: [0x50, 0x4B, 0x05, 0x06])
            || prefix.starts(with: [0x50, 0x4B, 0x07, 0x08]) {
            return .archive
        }
        if prefix.starts(with: [0x1F, 0x8B]) {
            return .archive
        }
        if prefix.count >= 262, String(bytes: prefix[257..<262], encoding: .utf8)?.hasPrefix("ustar") == true {
            return .archive
        }

        if type.contains("zip-archive") || type.contains("gzip") || type.contains("tar-archive") {
            return .archive
        }
        if ext == "zip" || ext == "jar" || ext == "epub" || ext == "ipa" || ext == "xpi" || ext == "whl" || ext == "vsix" || ext == "apk" {
            return .archive
        }
        if ext == "tar" || ext == "tgz" {
            return .archive
        }
        if ext == "sqlite" || ext == "sqlite3" || ext == "db" || type.contains("sqlite") || type.contains("database") {
            return .sqlite
        }
        if type.contains("comma-separated") {
            return .text
        }

        if ext == "json" || type.contains("public.json") {
            if context.data.first == UInt8(ascii: "{") || context.data.first == UInt8(ascii: "[") {
                return .json
            }
            return guessFromContent(context)
        }
        if ext.isEmpty {
            return guessFromContent(context)
        }
        if ext == "yaml" || ext == "yml" || type.contains("yaml") {
            return .yaml
        }
        if ext == "toml" {
            return .toml
        }
        if ext == "md" || ext == "markdown" || ext == "mdx" || context.fileBaseName.lowercased() == "readme" {
            return .markdown
        }
        if SyntaxLexer.language(forExtension: ext).id != "generic" {
            return .code
        }

        return guessFromContent(context)
    }

    /// Matches `compose.yml`, `docker-compose.yml` and any dotted variant such
    /// as `docker-compose.dev.yml`, `compose.override.yaml` or
    /// `docker-compose.prod.yml`.
    static func isComposeFileName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        guard lowered.hasSuffix(".yml") || lowered.hasSuffix(".yaml") else { return false }
        let base = (lowered as NSString).deletingPathExtension
        return base == "compose"
            || base == "docker-compose"
            || base.hasPrefix("docker-compose.")
            || base.hasPrefix("compose.")
    }

    /// Content based fallback for extensionless or mislabelled files.
    static func guessFromContent(_ context: RenderContext) -> Format {
        guard let text = String(data: context.data.prefix(65_536), encoding: .utf8) else {
            return .code
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if looksLikeJSON(trimmed) {
                return .json
            }
        }
        if JSONBuilder.looksLikeJSONLines(text: trimmed) {
            return .jsonLines
        }
        let lines = trimmed.split(separator: "\n")
        var yamlVotes = 0
        var envVotes = 0
        var considered = 0
        for line in lines.prefix(40) {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            if candidate.isEmpty || candidate.hasPrefix("#") { continue }
            considered += 1
            if candidate.contains(": ") || candidate.hasSuffix(":") { yamlVotes += 1 }
            let parts = candidate.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2,
               parts[0].range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
               !parts[0].contains(" ") {
                envVotes += 1
            }
        }
        if considered > 0, envVotes == considered, envVotes >= 2 {
            return .env
        }
        if considered > 0, yamlVotes >= 2, Double(yamlVotes) / Double(considered) >= 0.6 {
            return .yaml
        }
        return .code
    }

    static func looksLikeJSON(_ text: String) -> Bool {
        guard text.hasPrefix("{") || text.hasPrefix("[") else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    // MARK: - Rendering

    public static func render(context: RenderContext) throws -> RenderedPreview {
        let format = detectFormat(context)
        switch format {
        case .empty:
            return RenderedPreview(
                renderer: "Empty file",
                summary: "0 bytes",
                html: "<div class=\"empty\">This file is empty.</div>"
            )
        case .packageJSON:
            return try PackageBuilder.render(context: context)
        case .composerJSON, .composerLock:
            return try ComposerBuilder.render(context: context)
        case .dockerCompose:
            return try DockerComposeBuilder.render(context: context)
        case .json:
            return try JSONBuilder.render(context: context)
        case .jsonLines:
            return try JSONBuilder.render(context: context)
        case .sqlite:
            if let url = context.fileURL, !url.hasDirectoryPath, FileManager.default.fileExists(atPath: url.path) {
                return try SQLiteBuilder.render(context: context, fileURL: url)
            }
            return try SQLiteBuilder.renderInMemory(context)
        case .env:
            return try SecretsBuilder.render(context: context)
        case .yaml:
            return try ConfigBuilder.renderYAML(context: context)
        case .toml:
            return try ConfigBuilder.renderTOML(context: context)
        case .markdown:
            return try MarkdownBuilder.render(context: context)
        case .archive, .folder:
            return try ArchiveBuilder.render(context: context)
        case .code:
            return try CodeBuilder.render(context: context)
        case .text:
            return try CodeBuilder.render(context: context)
        }
    }

    /// Full HTML document ready for `QLPreviewReply`.
    public static func renderHTML(context: RenderContext) -> String {
        do {
            let preview = try render(context: context)
            return Document.page(context: context, preview: preview)
        } catch {
            return Document.errorPage(
                context: context,
                message: error.localizedDescription,
                detail: nil
            )
        }
    }

    /// Detected format name, used by tests and the debug footer.
    public static func formatName(_ context: RenderContext) -> String {
        detectFormat(context).rawValue
    }
}
