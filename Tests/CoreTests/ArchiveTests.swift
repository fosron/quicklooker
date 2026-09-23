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
