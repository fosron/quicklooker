import XCTest
@testable import QuickLookCore

final class ConfigFormatTests: XCTestCase {

    // MARK: - YAML

    func testYAMLStructure() {
        var parser = YAMLParser(text: "name: quicklook\nversion: 2.1.0\nenabled: true\n")
        let result = parser.parse()
        XCTAssertNil(result.failure)
        guard case .object(let entries)? = result.value else {
            return XCTFail("expected object root")
        }
        XCTAssertEqual(entries.map(\.0), ["name", "version", "enabled"])
    }

    func testYAMLSequenceAndNesting() {
        let text = """
        tags:
          - fast
          - local
        server:
          host: 127.0.0.1
          port: 8080
        """
        var parser = YAMLParser(text: text)
        let result = parser.parse()
        XCTAssertNil(result.failure)
        guard case .object(let root)? = result.value,
              let tags = root.first(where: { $0.0 == "tags" })?.1,
              case .array(let items) = tags,
              let server = root.first(where: { $0.0 == "server" })?.1,
              case .object(let serverEntries) = server else {
            return XCTFail("unexpected structure")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(serverEntries.count, 2)
    }

    func testYAMLTypeHints() {
        let text = "count: 3\nratio: 0.75\nflag: false\nlabel: hello\nnothing: null\n"
        var parser = YAMLParser(text: text)
        let result = parser.parse()
        XCTAssertEqual(result.typeHints["count"], "int")
        XCTAssertEqual(result.typeHints["ratio"], "float")
        XCTAssertEqual(result.typeHints["flag"], "bool")
        XCTAssertEqual(result.typeHints["label"], "string")
        XCTAssertEqual(result.typeHints["nothing"], "null")
    }

    func testYAMLFlowCollections() {
        let text = "logging: { level: info, format: json }\nports: [1, 2, 3]\n"
        var parser = YAMLParser(text: text)
        let result = parser.parse()
        XCTAssertNil(result.failure)
        guard case .object(let root)? = result.value,
              let logging = root.first(where: { $0.0 == "logging" })?.1,
              case .object(let loggingEntries) = logging,
              let ports = root.first(where: { $0.0 == "ports" })?.1,
              case .array(let portItems) = ports else {
            return XCTFail("unexpected structure")
        }
        XCTAssertEqual(loggingEntries.count, 2)
        XCTAssertEqual(portItems.count, 3)
    }

    func testYAMLQuotedScalars() {
        var parser = YAMLParser(text: #"name: "hello world"\nsingle: 'it''s fine'"#.replacingOccurrences(of: "\\n", with: "\n"))
        let result = parser.parse()
        guard case .object(let root)? = result.value else {
            return XCTFail("expected object")
        }
        XCTAssertEqual(root[0].1, .string("hello world"))
        XCTAssertEqual(root[1].1, .string("it's fine"))
    }

    func testYAMLCommentsIgnored() {
        var parser = YAMLParser(text: "# header\nkey: value  # trailing\n")
        let result = parser.parse()
        XCTAssertNil(result.failure)
        guard case .object(let root)? = result.value else {
            return XCTFail("expected object")
        }
        XCTAssertEqual(root.count, 1)
        XCTAssertEqual(root[0].1, .string("value"))
    }

    func testYAMLSequenceOfMappings() {
        let text = """
        products:
          - name: Hammer
            sku: 738
          - name: Nail
            sku: 284
        """
        var parser = YAMLParser(text: text)
        let result = parser.parse()
        XCTAssertNil(result.failure)
        guard case .object(let root)? = result.value,
              let products = root.first(where: { $0.0 == "products" })?.1,
              case .array(let items) = products else {
            return XCTFail("unexpected structure")
        }
        XCTAssertEqual(items.count, 2)
        guard case .object(let first) = items[0] else { return XCTFail("expected mapping item") }
        XCTAssertEqual(first.map(\.0), ["name", "sku"])
    }

    func testYAMLFixtureRenders() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.yaml"))
        XCTAssertEqual(preview.renderer, "YAML")
        XCTAssertTrue(preview.html.contains("127.0.0.1"))
        XCTAssertTrue(preview.html.contains("int"))
    }

    func testYAMLMalformedFallsBackToSource() throws {
        let context = RenderContext(data: Data("key: value\n- item\n".utf8), fileName: "bad.yaml")
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertEqual(preview.renderer, "YAML")
        XCTAssertNotNil(preview.notice)
        XCTAssertTrue(preview.html.contains("class=\"code\""))
    }

    // MARK: - TOML

    func testTOMLTablesAndValues() {
        let text = """
        title = "QuickLook"
        port = 8080

        [database]
        server = "localhost"
        ports = [8001, 8002]
        """
        let result = TOMLParser(text: text).parse()
        XCTAssertNil(result.failure)
        guard case .object(let root)? = result.value else {
            return XCTFail("expected object")
        }
        let keys = root.map(\.0)
        XCTAssertTrue(keys.contains("title"))
        XCTAssertTrue(keys.contains("database"))
        XCTAssertEqual(result.tableCount, 1)
    }

    func testTOMLArrayOfTables() {
        let text = """
        [[products]]
        name = "Hammer"

        [[products]]
        name = "Nail"
        """
        let result = TOMLParser(text: text).parse()
        guard case .object(let root)? = result.value,
              let products = root.first(where: { $0.0 == "products" })?.1,
              case .array(let items) = products else {
            return XCTFail("expected array of tables")
        }
        XCTAssertEqual(items.count, 2)
    }

    func testTOMLTypeHints() {
        let text = "count = 3\nratio = 0.5\nflag = true\nname = \"x\"\nwhen = 2024-05-01T10:00:00Z\n"
        let result = TOMLParser(text: text).parse()
        XCTAssertEqual(result.typeHints["count"], "int")
        XCTAssertEqual(result.typeHints["ratio"], "float")
        XCTAssertEqual(result.typeHints["flag"], "bool")
        XCTAssertEqual(result.typeHints["name"], "string")
        XCTAssertEqual(result.typeHints["when"], "date")
    }

    func testTOMLDottedKeys() {
        let result = TOMLParser(text: "server.host = \"localhost\"\nserver.port = 8080\n").parse()
        guard case .object(let root)? = result.value,
              let server = root.first(where: { $0.0 == "server" })?.1,
              case .object(let entries) = server else {
            return XCTFail("expected nested object")
        }
        XCTAssertEqual(entries.map(\.0), ["host", "port"])
    }

    func testTOMLMultiLineArray() {
        let text = """
        ports = [
          8001,
          8002,
        ]
        """
        let result = TOMLParser(text: text).parse()
        XCTAssertNil(result.failure)
        guard case .object(let root)? = result.value,
              let ports = root.first(where: { $0.0 == "ports" })?.1,
              case .array(let items) = ports else {
            return XCTFail("expected array")
        }
        XCTAssertEqual(items.count, 2)
    }

    func testTOMLFixtureRenders() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.toml"))
        XCTAssertEqual(preview.renderer, "TOML")
        XCTAssertTrue(preview.html.contains("database"))
        XCTAssertTrue(preview.html.contains("Hammer"))
    }

    func testTOMLMalformedFallsBackToSource() throws {
        let context = RenderContext(data: Data("this is not toml at all\n".utf8), fileName: "bad.toml")
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertEqual(preview.renderer, "TOML")
        XCTAssertNotNil(preview.notice)
    }

    // MARK: - Format detection

    func testDetectionByExtension() throws {
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("sample.yaml")), .yaml)
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("sample.toml")), .toml)
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("sample.jsonl")), .jsonLines)
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("package.json")), .packageJSON)
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("sample.env")), .env)
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("sample.md")), .markdown)
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("sample.zip")), .archive)
        XCTAssertEqual(PreviewRenderer.detectFormat(try Fixtures.context("sample.swift")), .code)
    }
}
