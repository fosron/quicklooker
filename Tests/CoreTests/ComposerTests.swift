import XCTest
@testable import QuickLookCore

final class ComposerTests: XCTestCase {

    // MARK: - Detection

    func testComposerJSONDetectedByFileName() {
        let ctx = RenderContext(data: Data("{}".utf8), fileName: "composer.json")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .composerJSON)
    }

    func testComposerLockDetectedByFileName() {
        let ctx = RenderContext(data: Data("{}".utf8), fileName: "composer.lock")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .composerLock)
    }

    func testRegularJSONIsNotTreatedAsComposer() {
        let ctx = RenderContext(data: Data(#"{"a": 1}"#.utf8), fileName: "data.json")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .json)
    }

    // MARK: - composer.json

    func testManifestMetadataCards() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("composer.json"))
        XCTAssertEqual(preview.renderer, "composer.json")
        XCTAssertTrue(preview.html.contains("fosron/quicklooker-fixture"))
        XCTAssertTrue(preview.html.contains("library"))
        XCTAssertTrue(preview.html.contains("MIT, Apache-2.0"))
        XCTAssertTrue(preview.html.contains("stable"))
    }

    func testManifestAuthors() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("composer.json"))
        XCTAssertTrue(preview.html.contains("Ada Lovelace"))
        XCTAssertTrue(preview.html.contains("ada@example.com"))
        XCTAssertTrue(preview.html.contains("Developer"))
        XCTAssertTrue(preview.html.contains("Grace Hopper"))
    }

    func testManifestRequireTables() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("composer.json"))
        XCTAssertTrue(preview.html.contains("symfony/console"))
        XCTAssertTrue(preview.html.contains("^6.4"))
        XCTAssertTrue(preview.html.contains("monolog/monolog"))
        XCTAssertTrue(preview.html.contains("require-dev"))
        XCTAssertTrue(preview.html.contains("phpunit/phpunit"))
        XCTAssertTrue(preview.html.contains("suggest"))
        XCTAssertTrue(preview.html.contains("ext-intl"))
    }

    func testManifestAutoloadAndScripts() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("composer.json"))
        XCTAssertTrue(preview.html.contains("Autoload"))
        XCTAssertTrue(preview.html.contains("Fosron"))
        XCTAssertTrue(preview.html.contains("phpstan analyse"))
    }

    func testManifestSummary() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("composer.json"))
        XCTAssertTrue(preview.summary.contains("4 require"))
        XCTAssertTrue(preview.summary.contains("2 require-dev"))
        XCTAssertTrue(preview.summary.contains("2 authors"))
    }

    func testManifestInvalidJSONFallsBackToSource() throws {
        let ctx = RenderContext(data: Data("{oops".utf8), fileName: "composer.json")
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "composer.json")
        XCTAssertNotNil(preview.notice)
        XCTAssertTrue(preview.html.contains("class=\"code\""))
    }

    // MARK: - composer.lock

    func testLockListsPackages() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("composer.lock"))
        XCTAssertEqual(preview.renderer, "composer.lock")
        XCTAssertTrue(preview.html.contains("monolog/monolog"))
        XCTAssertTrue(preview.html.contains("3.5.0"))
        XCTAssertTrue(preview.html.contains("symfony/console"))
        XCTAssertTrue(preview.html.contains("phpunit/phpunit"))
        XCTAssertTrue(preview.html.contains("packages-dev"))
        XCTAssertTrue(preview.html.contains("2.6.0"))
    }

    func testLockSummaryCounts() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("composer.lock"))
        XCTAssertTrue(preview.summary.contains("2 packages"))
        XCTAssertTrue(preview.summary.contains("1 dev"))
    }

    func testLockInvalidJSONFallsBackToSource() throws {
        let ctx = RenderContext(data: Data("not json".utf8), fileName: "composer.lock")
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "composer.lock")
        XCTAssertNotNil(preview.notice)
    }
}
