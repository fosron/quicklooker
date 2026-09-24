import XCTest
@testable import QuickLookCore

final class ArchiveTests: XCTestCase {

    func testZIPListsEntries() throws {
        let entries = try ZIPReader.entries(in: Fixtures.data("sample.zip"))
        let names = entries.map(\.name)
        XCTAssertTrue(names.contains("README.md"))
        XCTAssertTrue(names.contains("src/main.swift"))
        XCTAssertTrue(names.contains("src/util/helper.py"))
        XCTAssertTrue(names.contains("data/random.bin"))
        XCTAssertEqual(entries.count, 5)
    }

    func testZIPEntryMetadata() throws {
        let entries = try ZIPReader.entries(in: Fixtures.data("sample.zip"))
        guard let readme = entries.first(where: { $0.name == "README.md" }) else {
            return XCTFail("README.md missing")
        }
        XCTAssertEqual(readme.method, 8)
        XCTAssertGreaterThan(readme.uncompressedSize, 0)
        XCTAssertGreaterThan(readme.compressedSize, 0)
        XCTAssertNotNil(readme.modified)
        XCTAssertEqual(readme.methodName, "deflate")
        XCTAssertFalse(readme.isDirectory)
    }

    func testZIPRenderListsEntriesAndTotals() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.zip"))
        XCTAssertEqual(preview.renderer, "ZIP archive")
        XCTAssertTrue(preview.html.contains("README.md"))
        XCTAssertTrue(preview.html.contains("entries"))
        XCTAssertTrue(preview.html.contains("deflate"))
    }

    func testZIPRejectsNonArchive() {
        let data = Data("not an archive at all".utf8)
        XCTAssertThrowsError(try ZIPReader.entries(in: data))
    }

    func testZIP64IsRejected() throws {
        // Build a ZIP64 EOCD style record by hand: classic EOCD with 0xFFFF sentinel.
        var data = Data()
        data.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // disk numbers
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // entries on disk
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // total entries
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // size
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // offset
        data.append(contentsOf: [0x00, 0x00]) // comment length
        XCTAssertThrowsError(try ZIPReader.entries(in: data)) { error in
            guard case ZIPReader.ArchiveError.zip64Unsupported = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTARListsEntries() throws {
        let entries = try TARReader.entries(in: Fixtures.data("sample.tar"))
        let names = entries.map(\.name)
        XCTAssertEqual(names.count, 3)
        XCTAssertTrue(names.contains("notes.txt"))
        XCTAssertTrue(names.contains("config/app.yaml"))
        XCTAssertTrue(names.contains("config/nested/deep.toml"))
    }

    func testTAREntryMetadata() throws {
        let entries = try TARReader.entries(in: Fixtures.data("sample.tar"))
        guard let notes = entries.first(where: { $0.name == "notes.txt" }) else {
            return XCTFail("notes.txt missing")
        }
        XCTAssertEqual(notes.size, 16)
        XCTAssertEqual(notes.kind, .file)
        XCTAssertEqual(notes.mode, "644")
        XCTAssertNotNil(notes.modified)
    }

    func testTARRender() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.tar"))
        XCTAssertEqual(preview.renderer, "tar archive")
        XCTAssertTrue(preview.html.contains("notes.txt"))
        XCTAssertTrue(preview.html.contains("deep.toml"))
    }

    func testTARRejectsNonArchive() {
        XCTAssertThrowsError(try TARReader.entries(in: Data("nope".utf8)))
    }

    func testSparseTarIsRejected() {
        var data = Data(repeating: 0, count: 1024)
        let magic = Array("ustar".utf8)
        data.replaceSubrange(257..<262, with: magic)
        data[156] = UInt8(ascii: "S")
        XCTAssertThrowsError(try TARReader.entries(in: data)) { error in
            guard case TARReader.ArchiveError.sparseUnsupported = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testGZIPDecompressesText() throws {
        let result = try GZIPReader.decompress(try Fixtures.data("sample.txt.gz"), maxBytes: 1_000_000)
        let text = String(data: result.data, encoding: .utf8)
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("line one") == true)
        XCTAssertEqual(result.info.originalName, "sample.txt")
        XCTAssertFalse(result.truncated)
    }

    func testGZIPRespectsDecompressionLimit() throws {
        let result = try GZIPReader.decompress(try Fixtures.data("big.txt.gz"), maxBytes: 64 * 1024)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.data.count, 64 * 1024)
    }

    func testGZIPRejectsNonGzip() {
        XCTAssertThrowsError(try GZIPReader.decompress(Data("plain".utf8), maxBytes: 1024))
    }

    func testGZIPRenderShowsTextContent() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.txt.gz"))
        XCTAssertEqual(preview.renderer, "GZIP archive")
        XCTAssertTrue(preview.html.contains("line one"))
        XCTAssertTrue(preview.html.contains("sample.txt"))
    }

    func testTarGzListsNestedTarEntries() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.tar.gz"))
        XCTAssertEqual(preview.renderer, "GZIP archive")
        XCTAssertTrue(preview.html.contains("notes.txt"))
        XCTAssertTrue(preview.html.contains("tar entries"))
    }

    // MARK: - Regression tests

    func testGZIPWithHeaderRunningToTheEndDoesNotCrash() {
        // Magic + deflate flag, then a name/comment that runs to the very end.
        var data = Data([0x1F, 0x8B, 0x08, 0x18])
        data.append(Data(repeating: 0, count: 6)) // mtime, xfl, os
        data.append(Data("name".utf8))
        data.append(0)
        data.append(Data(repeating: 0x41, count: 3))
        // Header (with the NUL terminated name) reaches within 8 bytes of the end.
        XCTAssertThrowsError(try GZIPReader.decompress(data, maxBytes: 1024))
    }

    func testTARBase256SizeIsDecoded() throws {
        // GNU base-256 large size field: 0x80 marker + big endian value.
        var header = [UInt8](repeating: 0, count: 512)
        let name = Array("huge.bin".utf8)
        header.replaceSubrange(0..<name.count, with: name)
        header[100] = 0x30; header[101] = 0x30; header[102] = 0x30; header[103] = 0x30
        // The size field is 12 bytes; a base-256 value has 11 value bytes and
        // a 0x80 marker (the previous bytes are implicitly 0xFF for negatives).
        let size: Int = 9_000_000_000
        var encoded = [UInt8](repeating: 0, count: 12)
        let valueBytes = Self.base256(size)
        encoded.replaceSubrange(4..<12, with: valueBytes)
        header.replaceSubrange(124..<136, with: encoded)
        header[156] = UInt8(ascii: "0")
        let magic = Array("ustar".utf8)
        header.replaceSubrange(257..<262, with: magic)
        // Two zero blocks terminate the archive.
        let data = Data(header) + Data(repeating: 0, count: 1024)

        let entries = try TARReader.entries(in: data)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "huge.bin")
        XCTAssertEqual(entries[0].size, 9_000_000_000)
    }

    func testZIPEntriesReadFromFileForLargeArchives() throws {
        // Build a ZIP larger than a typical read window without loading it.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlp-large-\(UUID().uuidString).zip")
        defer {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlp-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }
        try Data("hello".utf8).write(to: sourceDir.appendingPathComponent("hello.txt"))
        try Data(repeating: 0x42, count: 10 * 1024 * 1024).write(to: sourceDir.appendingPathComponent("big.bin"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", url.path, "hello.txt", "big.bin"]
        process.currentDirectoryURL = sourceDir
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "zip command failed")

        // The renderer uses the seek path whenever the payload was truncated,
        // so the reader never needs the tail in memory.
        let entries = try ZIPReader.entries(fileURL: url)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.name == "hello.txt" })
        XCTAssertTrue(entries.contains { $0.name == "big.bin" })
    }

    /// GNU base-256 encoding: high bit marks the field, value is big endian.
    static func base256(_ value: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 8)
        var remaining = value
        for index in stride(from: 7, through: 1, by: -1) {
            bytes[index] = UInt8(remaining & 0xFF)
            remaining >>= 8
        }
        bytes[0] = UInt8(remaining & 0x7F) | 0x80
        return bytes
    }

    func testZIPTruncatedPayloadUsesFileSeek() throws {
        // A payload larger than the read limit must not be treated as a
        // complete archive: the render context is truncated and the reader
        // seeks the real file for the central directory.
        let url = Fixtures.url("sample.zip")
        let full = try Fixtures.data("sample.zip")
        // Prefix only, mimicking what the provider hands over for a big file.
        let prefix = full.prefix(200)
        var limits = PreviewLimits.default
        _ = limits
        let context = RenderContext(
            data: Data(prefix),
            fileName: "sample.zip",
            wasTruncatedAtRead: true,
            fileURL: url
        )
        XCTAssertEqual(PreviewRenderer.detectFormat(context), .archive)
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertEqual(preview.renderer, "ZIP archive")
        XCTAssertTrue(preview.html.contains("README.md"))
    }

    func testTarTruncationIsReported() throws {
        let url = Fixtures.url("sample.tar")
        let full = try Fixtures.data("sample.tar")
        let context = RenderContext(
            data: full.prefix(1024),
            fileName: "sample.tar",
            wasTruncatedAtRead: true,
            fileURL: url
        )
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertEqual(preview.renderer, "tar archive")
        XCTAssertTrue(preview.truncated)
        XCTAssertTrue(preview.html.contains("may end early"))
    }

    func testZipWithoutExtensionIsRoutedToArchive() throws {
        let data = try Fixtures.data("sample.zip")
        let context = RenderContext(data: data, fileName: "archive")
        XCTAssertEqual(PreviewRenderer.detectFormat(context), .archive)
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertEqual(preview.renderer, "ZIP archive")
    }

    func testFolderListing() throws {
        let folder = Fixtures.directory
        let context = RenderContext(data: Data(), fileName: folder.lastPathComponent, fileURL: folder)
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertEqual(preview.renderer, "Folder")
        XCTAssertTrue(preview.html.contains("sample.zip"))
        XCTAssertTrue(preview.html.contains("package.json"))
    }

    func testFolderTruncatesLongListings() throws {
        var limits = PreviewLimits.default
        limits.maxEntries = 2
        let folder = Fixtures.directory
        let context = RenderContext(data: Data(), fileName: folder.lastPathComponent, limits: limits, fileURL: folder)
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertTrue(preview.truncated)
        XCTAssertNotNil(preview.notice)
    }
}
