import XCTest
@testable import QuickLookCore

final class DockerComposeTests: XCTestCase {

    // MARK: - Detection

    func testComposeFileNamesAreDetected() {
        let names = [
            "docker-compose.yml",
            "docker-compose.yaml",
            "docker-compose.dev.yml",
            "docker-compose.override.yml",
            "docker-compose.prod.yml",
            "compose.yml",
            "compose.yaml",
            "compose.dev.yml",
            "Docker-Compose.YML",
        ]
        for name in names {
            let ctx = RenderContext(data: Data("services: {}\n".utf8), fileName: name)
            XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .dockerCompose, "\(name) should be compose")
        }
    }

    func testOtherYAMLFilesAreNotCompose() {
        for name in ["config.yaml", "docker.yml", "composer.yml", "services.yml"] {
            let ctx = RenderContext(data: Data("key: value\n".utf8), fileName: name)
            XCTAssertEqual(PreviewRenderer.detectFormat(ctx), .yaml, "\(name) should stay YAML")
        }
    }

    // MARK: - Services

    func testServiceSummaryCards() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("docker-compose.yml"))
        XCTAssertEqual(preview.renderer, "Docker Compose")
        XCTAssertTrue(preview.html.contains("quicklooker-stack"))
        XCTAssertEqual(preview.summary, "3 services · 2 volumes")
        XCTAssertTrue(preview.html.contains(">services</div><div class=\"value\">3</div>"))
        XCTAssertTrue(preview.html.contains(">volumes</div><div class=\"value\">2</div>"))
        XCTAssertTrue(preview.html.contains(">networks</div><div class=\"value\">2</div>"))
    }

    func testServiceImagesAndBuild() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("docker-compose.yml"))
        XCTAssertTrue(preview.html.contains("nginx:1.25-alpine"))
        XCTAssertTrue(preview.html.contains("postgres:16"))
        XCTAssertTrue(preview.html.contains("Dockerfile.dev"))
        XCTAssertTrue(preview.html.contains("built locally"))
    }

    func testPortsVolumesAndDependencies() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("docker-compose.yml"))
        XCTAssertTrue(preview.html.contains("8080:80"))
        XCTAssertTrue(preview.html.contains("8443:443"))
        XCTAssertTrue(preview.html.contains("./site:/usr/share/nginx/html:ro"))
        XCTAssertTrue(preview.html.contains("static:/var/www/static"))
        XCTAssertTrue(preview.html.contains("depends on"))
        XCTAssertTrue(preview.html.contains("api"))
    }

    func testServiceMetadata() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("docker-compose.yml"))
        XCTAssertTrue(preview.html.contains("unless-stopped"))
        XCTAssertTrue(preview.html.contains("php-fpm -F"))
        XCTAssertTrue(preview.html.contains("/entrypoint.sh"))
        XCTAssertTrue(preview.html.contains("1000:1000"))
        XCTAssertTrue(preview.html.contains("/app"))
        XCTAssertTrue(preview.html.contains("curl -f http://localhost/health"))
        XCTAssertTrue(preview.html.contains("replicas"))
        XCTAssertTrue(preview.html.contains("profile: dev"))
    }

    func testApiKeyStyleVariablesAreMasked() {
        XCTAssertTrue(SecretsMasking.shouldMask(key: "STRIPE_KEY", value: "sk_test_1234567890"))
        XCTAssertTrue(SecretsMasking.shouldMask(key: "DATABASE_URL", value: "postgres://u:p@host/db"))
        XCTAssertFalse(SecretsMasking.shouldMask(key: "LOG_LEVEL", value: "debug"))
    }

    func testEnvironmentValuesAreMasked() throws {
        let preview = try PreviewRenderer.render(context: try PreviewFixtureContext())
        XCTAssertTrue(preview.html.contains("NGINX_HOST"))
        XCTAssertTrue(preview.html.contains("example.com"))
        // Secrets must never appear unmasked in the preview document.
        XCTAssertFalse(preview.html.contains("sk-live-0123456789abcdef"))
        XCTAssertFalse(preview.html.contains("hunter2"))
        XCTAssertFalse(preview.html.contains("super-secret-password"))
        XCTAssertFalse(preview.html.contains("sk_test_abcdefghijklmnop"))
        XCTAssertTrue(preview.html.contains("masked"))
    }

    func testEnvironmentListFormIsParsed() throws {
        let preview = try PreviewRenderer.render(context: try PreviewFixtureContext())
        XCTAssertTrue(preview.html.contains("APP_ENV"))
        XCTAssertTrue(preview.html.contains("dev"))
        XCTAssertTrue(preview.html.contains("APP_DEBUG"))
    }

    func testEnvFileList() throws {
        let preview = try PreviewRenderer.render(context: try PreviewFixtureContext())
        XCTAssertTrue(preview.html.contains("env_file"))
        XCTAssertTrue(preview.html.contains(".env.local"))
    }

    func testTopLevelResources() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("docker-compose.yml"))
        XCTAssertTrue(preview.html.contains(">volumes</div>"))
        XCTAssertTrue(preview.html.contains(">networks</div>"))
        XCTAssertTrue(preview.html.contains("db-data"))
        XCTAssertTrue(preview.html.contains("frontend"))
        XCTAssertTrue(preview.html.contains("backend"))
        XCTAssertTrue(preview.html.contains(">secrets</div>"))
        XCTAssertTrue(preview.html.contains("tls_cert"))
    }

    func testOverrideVariantRendersIndependently() throws {
        let preview = try PreviewRenderer.render(context: try Fixtures.context("docker-compose.dev.yml"))
        XCTAssertEqual(preview.renderer, "Docker Compose")
        XCTAssertTrue(preview.html.contains("3000:80"))
        XCTAssertTrue(preview.html.contains("DEBUG"))
        XCTAssertTrue(preview.summary.contains("1 services"))
    }

    func testMissingServicesFallsBackToSource() throws {
        let ctx = RenderContext(data: Data("version: '3.9'\nnetworks:\n  a:\n".utf8), fileName: "docker-compose.yml")
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "Docker Compose")
        XCTAssertNotNil(preview.notice)
        XCTAssertTrue(preview.html.contains("class=\"code\""))
    }

    func testMalformedComposeFallsBackToSource() throws {
        let ctx = RenderContext(data: Data("services:\n\tbroken: [\n".utf8), fileName: "compose.yml")
        let preview = try PreviewRenderer.render(context: ctx)
        XCTAssertEqual(preview.renderer, "Docker Compose")
        XCTAssertNotNil(preview.notice)
    }

    // MARK: - Helpers

    /// Uses the committed compose fixture.
    private func PreviewFixtureContext() throws -> RenderContext {
        try Fixtures.context("docker-compose.yml")
    }
}
