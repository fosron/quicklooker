import XCTest
@testable import QuickLookCore

final class JSONTests: XCTestCase {

    private func context(_ text: String, name: String = "sample.json") -> RenderContext {
        RenderContext(data: Data(text.utf8), fileName: name)
    }

    func testDetectsJSONFormat() {
        XCTAssertEqual(PreviewRenderer.detectFormat(context(#"{"a": 1}"#)), .json)
    }

    func testPrettyPrintedJSONStaysATree() {
        let pretty = """
        {
          "name": "qlp",
          "nested": {
            "count": 3
          },
          "tags": ["a", "b"]
        }
        """
        XCTAssertEqual(PreviewRenderer.detectFormat(context(pretty)), .json)
        let preview = try? PreviewRenderer.render(context: context(pretty))
        XCTAssertEqual(preview?.renderer, "JSON tree")
    }

    func testExtensionlessJSONLinesStillDetected() {
        let lines = "{\"id\": 1}\n{\"id\": 2}\n{\"id\": 3}\n"
        let ctx = RenderContext(data: Data(lines.utf8), fileName: "events")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .jsonLines)
    }

    func testTreeRenderContainsKeysAndValues() throws {
        let ctx = context(#"{"name": "qlp", "count": 3, "ok": true, "none": null}"#)
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "JSON tree")
        XCTAssertTrue(preview.html.contains("<span class=\"key\">name</span>"))
        XCTAssertTrue(preview.html.contains("qlp"))
        XCTAssertTrue(preview.html.contains("tok-number\">3</span>"))
        XCTAssertTrue(preview.html.contains("tok-boolean\">true</span>"))
        XCTAssertTrue(preview.html.contains("tok-null\">null</span>"))
    }

    func testArrayRenderShowsItemCount() throws {
        let preview = try PreviewRenderer.render(context: context("[1, 2, 3]"))
        XCTAssertTrue(preview.html.contains("3 items"))
    }

    func testEscapesUntrustedContent() throws {
        let payload = #"{"x": "<script>alert(1)</script>"}"#
        let preview = try PreviewRenderer.render(context: context(payload))
        XCTAssertFalse(preview.html.contains("<script>alert(1)</script>"))
        XCTAssertTrue(preview.html.contains("&lt;script&gt;"))
    }

    func testMalformedJSONFallsBackToSource() throws {
        let preview = try PreviewRenderer.render(context: context(#"{"broken": }"#))
        XCTAssertEqual(preview.renderer, "JSON")
        XCTAssertNotNil(preview.notice)
        XCTAssertTrue(preview.html.contains("tok-"))
    }

    func testJSONLinesDetectedByExtension() {
        let ctx = context("{\"a\": 1}\n{\"a\": 2}\n{\"a\": 3}\n", name: "data.jsonl")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .jsonLines)
    }

    func testJSONLinesRendersEachRecord() throws {
        let text = "{\"id\": 1}\n{\"id\": 2}\n{\"id\": 3}\n"
        let preview = try PreviewRenderer.render(context: context(text, name: "rows.jsonl"))
        XCTAssertEqual(preview.renderer, "JSON Lines")
        XCTAssertTrue(preview.html.contains("#1"))
        XCTAssertTrue(preview.html.contains("#3"))
    }

    func testJSONLinesReportsUnparseableLines() throws {
        let text = "{\"id\": 1}\nnot json\n{\"id\": 3}\n"
        let preview = try PreviewRenderer.render(context: context(text, name: "rows.jsonl"))
        XCTAssertNotNil(preview.notice)
        XCTAssertTrue(preview.notice?.contains("could not be parsed") == true)
    }

    func testEmptyFileProducesEmptyPreview() {
        let ctx = RenderContext(data: Data(), fileName: "empty.json")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .empty)
    }

    func testDeepNestingRespectsDepthLimit() throws {
        var text = ""
        for _ in 0..<80 { text += "[" }
        text += "1"
        for _ in 0..<80 { text += "]" }
        var limits = PreviewLimits.default
        limits.maxDepth = 8
        let ctx = RenderContext(data: Data(text.utf8), fileName: "deep.json", limits: limits)
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertTrue(preview.truncated)
    }

    func testNodeBudgetTruncatesHugeDocuments() throws {
        let items = (0..<5_000).map { "\"k\($0)\": \($0)" }.joined(separator: ",")
        var limits = PreviewLimits.default
        limits.maxNodes = 100
        let ctx = RenderContext(data: Data("{\(items)}".utf8), fileName: "big.json", limits: limits)
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertTrue(preview.truncated)
        XCTAssertTrue(preview.html.contains("Preview limited"))
    }

    func testPageHTMLIsCompleteDocument() {
        let html = PreviewRenderer.renderHTML(context: context(#"{"a": 1}"#))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("prefers-color-scheme"))
        XCTAssertTrue(html.contains("</html>"))
    }
}
