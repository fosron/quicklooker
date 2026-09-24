import XCTest
import SQLite3
@testable import QuickLookCore

final class MarkdownTests: XCTestCase {

    private func render(_ text: String) -> RenderedPreview {
        let context = RenderContext(data: Data(text.utf8), fileName: "doc.md")
        return try! PreviewRenderer.render(context: context)
    }

    func testHeadings() {
        let html = render("# One\n## Two\n### Three").html
        XCTAssertTrue(html.contains("<h1>One</h1>"))
        XCTAssertTrue(html.contains("<h2>Two</h2>"))
        XCTAssertTrue(html.contains("<h3>Three</h3>"))
    }

    func testParagraphAndInlineStyles() {
        let html = render("A **bold** and _italic_ and `code` and ~~gone~~.").html
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
        XCTAssertTrue(html.contains("<del>gone</del>"))
    }

    func testLinksAndImages() {
        let html = render("[docs](https://example.com) and ![alt](https://example.com/i.png)").html
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">docs</a>"))
        // Remote images are not fetched; the source is shown as a placeholder.
        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("https://example.com/i.png"))
    }

    func testLocalImagesRender() {
        let html = render("![diagram](./assets/diagram.png)").html
        XCTAssertTrue(html.contains("<img src=\"./assets/diagram.png\" alt=\"diagram\">"))
    }

    func testQuoteInURLCannotBreakOutOfAttribute() {
        let html = render(#"[click](https://x.test/?a=&quot;onmouseover=&quot;alert(1))"#).html
        XCTAssertFalse(html.contains("<a href=\"https://x.test/?a=\"onmouseover"))
        XCTAssertTrue(html.contains("onmouseover"))
    }

    func testListsAndTaskItems() {
        let html = render("- one\n- two\n\n1. first\n2. second\n\n- [x] done\n- [ ] todo").html
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<li>one</li>"))
        XCTAssertTrue(html.contains("☑ done"))
        XCTAssertTrue(html.contains("☐ todo"))
    }

    func testFencedCodeBlockIsHighlighted() {
        let html = render("```swift\nlet x = 1\n```").html
        XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("tok-keyword"))
        XCTAssertTrue(html.contains("Swift"))
    }

    func testBlockquoteAndRule() {
        let html = render("> quoted text\n\n---").html
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("quoted text"))
        XCTAssertTrue(html.contains("<hr>"))
    }

    func testTable() {
        let html = render("| A | B |\n| - | - |\n| 1 | 2 |").html
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>A</th>"))
        XCTAssertTrue(html.contains("<td>2</td>"))
    }

    func testEscapesRawHTML() {
        let html = render("<script>alert(1)</script>").html
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testFixtureRendersAllBlocks() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.md"))
        XCTAssertEqual(preview.renderer, "Markdown")
        XCTAssertTrue(preview.html.contains("<h1>QuickLooker</h1>"))
        XCTAssertTrue(preview.html.contains("<blockquote>"))
        XCTAssertTrue(preview.html.contains("<table>"))
        XCTAssertTrue(preview.html.contains("tok-keyword"))
    }
}

final class PackageJSONTests: XCTestCase {

    func testExtractsMetadata() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("package.json"))
        XCTAssertEqual(preview.renderer, "package.json")
        XCTAssertTrue(preview.html.contains("quicklooker-fixture"))
        XCTAssertTrue(preview.html.contains("2.3.1"))
        XCTAssertTrue(preview.html.contains("MIT"))
        XCTAssertTrue(preview.html.contains("Test Author"))
    }

    func testScriptsAndDependencyTables() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("package.json"))
        XCTAssertTrue(preview.html.contains("swift build"))
        XCTAssertTrue(preview.html.contains("left-pad"))
        XCTAssertTrue(preview.html.contains("^1.3.0"))
        XCTAssertTrue(preview.html.contains("devDependencies"))
        XCTAssertTrue(preview.html.contains("typescript"))
    }

    func testSummaryCounts() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("package.json"))
        XCTAssertTrue(preview.summary.contains("2 dependencies"))
        XCTAssertTrue(preview.summary.contains("1 dev"))
        XCTAssertTrue(preview.summary.contains("2 scripts"))
    }

    func testInvalidPackageJSONFallsBack() throws {
        let context = RenderContext(data: Data("{oops".utf8), fileName: "package.json")
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertEqual(preview.renderer, "package.json")
        XCTAssertNotNil(preview.notice)
    }
}

final class SQLiteTests: XCTestCase {

    private var databaseURL: URL!

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlp-test-\(UUID().uuidString).sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let statements = [
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT, created_at TEXT)",
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER REFERENCES users(id), total REAL)",
            "CREATE INDEX idx_orders_user ON orders(user_id)",
            "CREATE VIEW active_users AS SELECT * FROM users WHERE email IS NOT NULL",
            "INSERT INTO users (name, email, created_at) VALUES ('ada', 'ada@example.com', '2024-01-01')",
            "INSERT INTO users (name, email, created_at) VALUES ('grace', NULL, '2024-01-02')",
            "INSERT INTO orders (user_id, total) VALUES (1, 12.5), (2, 99.0)",
        ]
        for sql in statements {
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: databaseURL)
    }

    private func context() throws -> RenderContext {
        RenderContext(
            data: try Data(contentsOf: databaseURL),
            fileName: databaseURL.lastPathComponent,
            fileURL: databaseURL
        )
    }

    func testOpensReadOnly() throws {
        let database = try SQLiteDatabase(path: databaseURL.path)
        defer { database.close() }
        XCTAssertEqual(try database.objects().filter { $0.kind == "table" }.count, 2)
    }

    func testListsTablesViewsAndIndexes() throws {
        let database = try SQLiteDatabase(path: databaseURL.path)
        defer { database.close() }
        let objects = try database.objects()
        XCTAssertTrue(objects.contains { $0.name == "users" && $0.kind == "table" })
        XCTAssertTrue(objects.contains { $0.name == "orders" && $0.kind == "table" })
        XCTAssertTrue(objects.contains { $0.name == "active_users" && $0.kind == "view" })
        let indexes = try database.indexes(table: "orders")
        XCTAssertTrue(indexes.contains { $0.name == "idx_orders_user" })
    }

    func testColumnMetadata() throws {
        let database = try SQLiteDatabase(path: databaseURL.path)
        defer { database.close() }
        let columns = try database.columns(table: "users")
        XCTAssertEqual(columns.map(\.name), ["id", "name", "email", "created_at"])
        XCTAssertEqual(columns[0].type, "INTEGER")
        XCTAssertTrue(columns[0].isPrimaryKey)
        XCTAssertTrue(columns[1].notNull)
        XCTAssertFalse(columns[2].notNull)
    }

    func testRowPreviewIsBounded() throws {
        let database = try SQLiteDatabase(path: databaseURL.path)
        defer { database.close() }
        let preview = try database.preview(table: "users", limit: 1)
        XCTAssertEqual(preview.rows.count, 1)
        XCTAssertEqual(preview.totalRows, 2)
        XCTAssertEqual(preview.columns, ["id", "name", "email", "created_at"])
    }

    func testRenderShowsSchemaAndRows() throws {
        let ctx = try context()
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "SQLite")
        XCTAssertTrue(preview.html.contains("users"))
        XCTAssertTrue(preview.html.contains("idx_orders_user"))
        XCTAssertTrue(preview.html.contains("ada@example.com"))
        XCTAssertTrue(preview.html.contains("PRIMARY KEY"))
        XCTAssertEqual(preview.summary, "2 tables · 1 views · 16 KB")
        let page = PreviewRenderer.renderHTML(context: ctx)
        XCTAssertTrue(page.contains("2 tables · 1 views"))
    }

    func testRowLimitIsRespected() throws {
        var limits = PreviewLimits.default
        limits.maxRows = 1
        let ctx = RenderContext(
            data: try Data(contentsOf: databaseURL),
            fileName: databaseURL.lastPathComponent,
            limits: limits,
            fileURL: databaseURL
        )
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertTrue(preview.html.contains("Showing 1 of 2 rows"))
    }

    func testFixtureDatabasePreviews() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.sqlite"))
        XCTAssertEqual(preview.renderer, "SQLite")
        XCTAssertTrue(preview.html.contains("users"))
        XCTAssertTrue(preview.html.contains("active_users"))
        XCTAssertTrue(preview.html.contains("idx_users_name"))
        XCTAssertTrue(preview.html.contains("ada@example.com"))
    }

    func testDbExtensionIsDetectedAsSQLite() throws {
        let ctx = try Fixtures.context("sample.db")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .sqlite)
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "SQLite")
    }

    func testRecursiveViewDoesNotHang() throws {
        // A view that would run forever must be cut off by the query deadline.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlp-recursive-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        sqlite3_exec(handle, "CREATE TABLE seed (id INTEGER PRIMARY KEY)", nil, nil, nil)
        sqlite3_exec(handle, "INSERT INTO seed (id) VALUES (1)", nil, nil, nil)
        let view = """
        CREATE VIEW cosmic AS
        WITH RECURSIVE counter(n) AS (
            SELECT 1 UNION ALL SELECT n + 1 FROM counter
        )
        SELECT n FROM counter
        """
        XCTAssertEqual(sqlite3_exec(handle, view, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)

        let context = RenderContext(
            data: try Data(contentsOf: url),
            fileName: url.lastPathComponent,
            fileURL: url
        )
        let start = Date()
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertEqual(preview.renderer, "SQLite")
        XCTAssertTrue(preview.html.contains("cosmic"))
    }

    func testNonDatabaseIsRejected() {
        let data = Data("this is not sqlite".utf8)
        XCTAssertFalse(SQLiteDatabase.isValidDatabase(data: data))
    }

    func testWriteAttemptFailsOnReadOnlyHandle() throws {
        let database = try SQLiteDatabase(path: databaseURL.path)
        defer { database.close() }
        // The handle is opened read-only, so DDL must fail.
        XCTAssertThrowsError(try database.preview(table: "no_such_table", limit: 5))
    }
}
