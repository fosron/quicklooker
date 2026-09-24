import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import QuickLookCore

/// Data based Quick Look preview extension.
///
/// Reads the file through the sandbox scoped URL provided by Quick Look,
/// renders an HTML document with `PreviewRenderer` and returns it as a
/// formatted attachment. All processing happens locally.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let limits = PreviewLimits.default
        let fileName = url.lastPathComponent

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        var data = Data()
        var truncatedAtRead = false
        if exists && !isDirectory.boolValue {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let fileSize = (try? handle.seekToEnd()) ?? 0
            try handle.seek(toOffset: 0)
            let limit = UInt64(limits.maxBytes)
            data = try handle.read(upToCount: Int(min(fileSize, limit))) ?? Data()
            truncatedAtRead = Int64(fileSize) > Int64(limits.maxBytes)
            // `data` stays a straight prefix of the file. Renderers that need
            // bytes outside that window (the ZIP central directory) seek the
            // file through `fileURL` instead of reading a spliced buffer.
        }

        let contentType = UTType(filenameExtension: url.pathExtension)?.identifier ?? ""
        let context = RenderContext(
            data: data,
            fileName: fileName,
            contentTypeIdentifier: contentType,
            appearance: Self.currentAppearance,
            limits: limits,
            wasTruncatedAtRead: truncatedAtRead,
            fileURL: url,
            isDirectory: isDirectory.boolValue
        )

        let html = PreviewRenderer.renderHTML(context: context)
        let htmlData = Data(html.utf8)
        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 780, height: 560)
        ) { _ in
            htmlData
        }
        reply.stringEncoding = .utf8
        reply.title = fileName
        return reply
    }

    // MARK: - Appearance

    /// The extension is not an app, so `NSApp` is nil. `NSAppearance.current`
    /// still reflects the system (or the Quick Look panel) appearance; the
    /// generated CSS also follows `prefers-color-scheme` on its own.
    private static var currentAppearance: Appearance {
        appearance(for: NSAppearance.currentDrawing().name ?? NSApp?.effectiveAppearance.name)
    }

    private static func appearance(for name: NSAppearance.Name?) -> Appearance {
        switch name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            return .dark
        case .aqua, .vibrantLight, .accessibilityHighContrastAqua, .accessibilityHighContrastVibrantLight:
            return .light
        default:
            return .auto
        }
    }
}
