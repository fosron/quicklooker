import Foundation
import XCTest
@testable import QuickLookCore

/// Locates the committed fixture files from either the SwiftPM or the Xcode
/// test bundle.
enum Fixtures {

    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["QLP_FIXTURES"] {
            return URL(fileURLWithPath: override)
        }
        var candidates: [URL] = []
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/CoreTests/Fixtures"))
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return candidates[0]
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func context(_ name: String, limits: PreviewLimits = .default) throws -> RenderContext {
        let url = self.url(name)
        return RenderContext(
            data: try data(name),
            fileName: name,
            contentTypeIdentifier: "",
            limits: limits,
            fileURL: url
        )
    }
}
