import XCTest
@testable import QuickLookCore

final class SecretsTests: XCTestCase {

    private let sample = """
    # Application settings
    APP_NAME=QuickLooker
    DEBUG=true

    # Secrets below should be masked
    DATABASE_PASSWORD=hunter2-super-secret
    API_KEY=sk-live-1234567890abcdef
    GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz
    AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG

    NORMAL_VALUE=plain
    QUOTED="hello world"
    export EXPORTED=value
    """

    func testParsesAssignments() {
        let entries = SecretsBuilder.parse(text: sample)
        let assignments = entries.filter { $0.kind == .assignment }
        XCTAssertEqual(assignments.count, 9)
        XCTAssertEqual(assignments.first?.key, "APP_NAME")
        XCTAssertEqual(assignments.first?.value, "QuickLooker")
    }

    func testCommentsArePreserved() {
        let entries = SecretsBuilder.parse(text: sample)
        let comments = entries.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 2)
    }

    func testExportPrefixIsStripped() {
        let entries = SecretsBuilder.parse(text: "export FOO=bar")
        XCTAssertEqual(entries.first?.key, "FOO")
        XCTAssertEqual(entries.first?.value, "bar")
    }

    func testQuotedValuesAreUnquoted() {
        let entries = SecretsBuilder.parse(text: #"QUOTED="hello world""#)
        XCTAssertEqual(entries.first?.value, "hello world")
    }

    func testSecretKeyDetection() {
        XCTAssertTrue(SecretsBuilder.isSecretKey("DATABASE_PASSWORD"))
        XCTAssertTrue(SecretsBuilder.isSecretKey("API_KEY"))
        XCTAssertTrue(SecretsBuilder.isSecretKey("github_token"))
        XCTAssertTrue(SecretsBuilder.isSecretKey("AWS_SECRET_ACCESS_KEY"))
        XCTAssertTrue(SecretsBuilder.isSecretKey("SESSION_ID"))
        XCTAssertTrue(SecretsBuilder.isSecretKey("STRIPE_KEY"))
        XCTAssertTrue(SecretsBuilder.isSecretKey("SSH_PRIVATE_KEY"))
        XCTAssertTrue(SecretsBuilder.isSecretKey("clientSecret"))
        XCTAssertFalse(SecretsBuilder.isSecretKey("APP_NAME"))
        XCTAssertFalse(SecretsBuilder.isSecretKey("DEBUG"))
        XCTAssertFalse(SecretsBuilder.isSecretKey("AUTHOR"))
        XCTAssertFalse(SecretsBuilder.isSecretKey("KEYBOARD_LAYOUT"))
        XCTAssertFalse(SecretsBuilder.isSecretKey("MONKEY_PATCH"))
    }

    func testCredentialURLsMaskOnlyThePassword() {
        let masked = SecretsMasking.mask("postgres://admin:hunter2@db.example.com:5432/app")
        XCTAssertEqual(masked, "postgres://admin:••••••@db.example.com:5432/app")
        XCTAssertFalse(masked.contains("hunter2"))
    }

    func testVariableReferencesToSecretsAreMasked() {
        XCTAssertTrue(SecretsMasking.shouldMask(key: "DB_URL", value: "${DB_PASSWORD}"))
        XCTAssertTrue(SecretsMasking.shouldMask(key: "DB_URL", value: "$API_KEY"))
        XCTAssertFalse(SecretsMasking.shouldMask(key: "APP_ENV", value: "${APP_ENV}"))
        XCTAssertEqual(SecretsMasking.mask("${DB_PASSWORD}"), "${••••••}")
    }

    func testMaskingKeepsShortPrefixOnly() {
        let masked = SecretsBuilder.mask("sk-live-1234567890abcdef")
        XCTAssertTrue(masked.hasPrefix("sk-"))
        XCTAssertFalse(masked.contains("1234567890"))
        XCTAssertEqual(SecretsBuilder.mask("abc"), "•••")
    }

    func testRenderMasksSecretsByDefault() throws {
        let ctx = RenderContext(data: Data(sample.utf8), fileName: ".env")
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "Environment")
        XCTAssertFalse(preview.html.contains("hunter2-super-secret"))
        XCTAssertFalse(preview.html.contains("sk-live-1234567890abcdef"))
        XCTAssertTrue(preview.html.contains("masked"))
        XCTAssertTrue(preview.html.contains("DATABASE_PASSWORD"))
    }

    func testPreviewNeverEmbedsUnmaskedSecrets() throws {
        let ctx = RenderContext(data: Data(sample.utf8), fileName: ".env")
        let preview = try PreviewRenderer.render(context: ctx)
        // Neither the masked nor the unmasked variant may contain the secret.
        XCTAssertFalse(preview.html.contains("hunter2-super-secret"))
        XCTAssertFalse(preview.html.contains("ghp_abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(preview.html.contains("wJalrXUtnFEMI"))
        XCTAssertTrue(preview.html.contains("hidden"))
    }

    func testDotEnvNameDetection() {
        let ctx = RenderContext(data: Data("A=1".utf8), fileName: ".env.local")
        XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .env)
    }

    func testEscapesHTMLInValues() throws {
        let text = "SECRET_TOKEN=<img src=x onerror=alert(1)>"
        let ctx = RenderContext(data: Data(text.utf8), fileName: ".env")
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertFalse(preview.html.contains("<img src=x"))
        // Only a short prefix survives masking, and it is escaped.
        XCTAssertTrue(preview.html.contains("&lt;im"))
        XCTAssertFalse(preview.html.contains("onerror"))
    }
}
