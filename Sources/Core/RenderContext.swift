import Foundation

public enum Appearance: String, Sendable {
    case auto
    case light
    case dark
}

/// Limits applied to every preview so a hostile or gigantic file can never
/// produce an unbounded amount of work or an unbounded reply payload.
public struct PreviewLimits: Sendable {
    /// Bytes read from disk at most.
    public var maxBytes: Int
    /// Maximum nesting depth rendered for structured formats.
    public var maxDepth: Int
    /// Maximum number of nodes rendered in a tree.
    public var maxNodes: Int
    /// Maximum archive/folder entries listed.
    public var maxEntries: Int
    /// Maximum rows rendered per SQLite table.
    public var maxRows: Int
    /// Maximum decompressed bytes for gzip payloads.
    public var maxDecompressedBytes: Int
    /// Maximum code lines rendered.
    public var maxLines: Int

    public init(
        maxBytes: Int = 32 * 1024 * 1024,
        maxDepth: Int = 24,
        maxNodes: Int = 10_000,
        maxEntries: Int = 2_000,
        maxRows: Int = 200,
        maxDecompressedBytes: Int = 8 * 1024 * 1024,
        maxLines: Int = 20_000
    ) {
        self.maxBytes = maxBytes
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
        self.maxEntries = maxEntries
        self.maxRows = maxRows
        self.maxDecompressedBytes = maxDecompressedBytes
        self.maxLines = maxLines
    }

    public static let `default` = PreviewLimits()
}

/// Everything a renderer needs to produce a preview.
public struct RenderContext: Sendable {
    public var data: Data
    public var fileName: String
    public var contentTypeIdentifier: String
    public var appearance: Appearance
    public var limits: PreviewLimits
    /// True when the caller already knows the file on disk was larger than
    /// `limits.maxBytes`.
    public var wasTruncatedAtRead: Bool
    /// Original file URL when the preview is backed by a file on disk. Some
    /// adapters (SQLite, folders) use it to avoid copying large payloads.
    public var fileURL: URL?

    public init(
        data: Data,
        fileName: String,
        contentTypeIdentifier: String = "",
        appearance: Appearance = .auto,
        limits: PreviewLimits = .default,
        wasTruncatedAtRead: Bool = false,
        fileURL: URL? = nil
    ) {
        self.data = data
        self.fileName = fileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.appearance = appearance
        self.limits = limits
        self.wasTruncatedAtRead = wasTruncatedAtRead
        self.fileURL = fileURL
    }

    /// Lowercased extension without the leading dot.
    public var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    public var fileBaseName: String {
        (fileName as NSString).lastPathComponent
    }

    /// Decodes the payload as UTF-8, replacing invalid sequences. Latin-1 is
    /// used as a fallback for files that are valid text but not UTF-8.
    public var text: String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return ""
    }

    /// True when the payload looks like text rather than binary.
    public var isLikelyText: Bool {
        String(data: data, encoding: .utf8) != nil
    }
}

/// Result of rendering one preview.
public struct RenderedPreview: Sendable {
    /// Which adapter produced the output (shown in the debug footer).
    public let renderer: String
    /// Short human readable status, e.g. "12.4 KB • 350 lines".
    public let summary: String
    public let html: String
    /// True when the preview was capped by `PreviewLimits`.
    public let truncated: Bool
    /// Set when the preferred adapter failed and a fallback was used.
    public let notice: String?

    public init(renderer: String, summary: String, html: String, truncated: Bool = false, notice: String? = nil) {
        self.renderer = renderer
        self.summary = summary
        self.html = html
        self.truncated = truncated
        self.notice = notice
    }
}

public enum PreviewError: Error, LocalizedError {
    case unreadableFile(String)
    case fileTooLarge(bytes: Int, limit: Int)
    case binaryContent
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let reason): return "The file could not be read: \(reason)"
        case .fileTooLarge(let bytes, let limit):
            return "The file is \(Format.bytes(bytes)) which exceeds the \(Format.bytes(limit)) preview limit."
        case .binaryContent: return "The file does not contain readable text."
        case .malformed(let reason): return "The file is malformed: \(reason)"
        }
    }
}
