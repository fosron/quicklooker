import XCTest
@testable import QuickLookCore

final class SyntaxLexerTests: XCTestCase {

    private func tokenize(_ source: String, language: SyntaxLexer.Language) -> [(String, String?)] {
        let lexer = SyntaxLexer(language: language)
        return source.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line in
            lexer.tokenize(String(line)).map { ($0.text, $0.tokenClass) }
        }
    }

    func testSwiftKeywordsAndStrings() {
        let tokens = tokenize("let name = \"world\" // greeting", language: SyntaxLexer.languages["swift"]!)
        let classes = Dictionary(tokens.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(classes["let"], "tok-keyword")
        XCTAssertEqual(classes["\"world\""], "tok-string")
        XCTAssertEqual(classes["// greeting"], "tok-comment")
    }

    func testPythonCommentsAndNumbers() {
        let tokens = tokenize("count = 42  # answer", language: SyntaxLexer.languages["python"]!)
        let classes = Dictionary(tokens.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(classes["42"], "tok-number")
        XCTAssertEqual(classes["# answer"], "tok-comment")
    }

    func testJavaScriptTemplateStrings() {
        let tokens = tokenize("const msg = `hi ${name}`;", language: SyntaxLexer.languages["javascript"]!)
        XCTAssertTrue(tokens.contains { $0.1 == "tok-keyword" && $0.0 == "const" })
        XCTAssertTrue(tokens.contains { $0.1 == "tok-string" && $0.0.contains("${name}") })
    }

    func testEscapedQuotesDoNotEndString() {
        let tokens = tokenize(#"let s = "a \" b" + x"#, language: SyntaxLexer.languages["swift"]!)
        XCTAssertTrue(tokens.contains { $0.1 == "tok-string" && $0.0.contains(#"\""#) })
    }

    func testUnterminatedStringConsumesLine() {
        let tokens = tokenize("let s = \"unterminated", language: SyntaxLexer.languages["swift"]!)
        XCTAssertEqual(tokens.last?.1, "tok-string")
        XCTAssertTrue(tokens.last?.0.hasSuffix("unterminated") == true)
    }

    func testLanguageDetectionByExtension() {
        XCTAssertEqual(SyntaxLexer.language(forExtension: "swift").id, "swift")
        XCTAssertEqual(SyntaxLexer.language(forExtension: "py").id, "python")
        XCTAssertEqual(SyntaxLexer.language(forExtension: "ts").id, "typescript")
        XCTAssertEqual(SyntaxLexer.language(forExtension: "rs").id, "rust")
        XCTAssertEqual(SyntaxLexer.language(forExtension: "cpp").id, "c")
        XCTAssertEqual(SyntaxLexer.language(forExtension: "unknown-ext").id, "generic")
        XCTAssertEqual(SyntaxLexer.language(forExtension: "csv").id, "plain")
    }

    func testTokenizingNeverLosesCharacters() {
        let sources = [
            ("sample.swift", "swift"),
            ("sample.py", "python"),
            ("sample.js", "javascript"),
        ]
        for (name, languageId) in sources {
            guard let source = try? Fixtures.text(name) else {
                return XCTFail("missing fixture \(name)")
            }
            let lexer = SyntaxLexer(language: SyntaxLexer.languages[languageId]!)
            let reconstructed = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { lexer.tokenize(String($0)).map(\.text).joined() }
                .joined(separator: "\n")
            XCTAssertEqual(reconstructed, source, "tokenizing \(name) changed the text")
        }
    }

    func testCodeRenderHasLineNumbers() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.swift"))
        XCTAssertEqual(preview.renderer, "Source")
        XCTAssertTrue(preview.html.contains("class=\"ln\""))
        XCTAssertTrue(preview.html.contains("tok-keyword\">let</span>"))
    }

    func testCodeRenderTruncatesLongFiles() throws {
        var limits = PreviewLimits.default
        limits.maxLines = 3
        let context = try Fixtures.context("sample.swift", limits: limits)
        let preview = try PreviewRenderer.render(context: context)
        XCTAssertTrue(preview.truncated)
        XCTAssertTrue(preview.html.contains("showing the first 3"))
    }

    func testCSVUsesPlainLexer() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("sample.csv"))
        XCTAssertEqual(preview.renderer, "Source")
        XCTAssertTrue(preview.summary.contains("Plain Text"))
    }
}
