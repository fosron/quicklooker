import SwiftUI
import QuickLookCore

/// Describes one supported preview family shown in the setup window.
struct PreviewFeature: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let extensions: String

    static let all: [PreviewFeature] = [
        PreviewFeature(
            id: "json",
            symbol: "curlybraces",
            title: "JSON tree & JSON Lines",
            detail: "Collapsible JSON tree; each JSONL record rendered separately.",
            extensions: ".json, .jsonl, .ndjson"
        ),
        PreviewFeature(
            id: "yaml",
            symbol: "list.bullet.indent",
            title: "YAML & TOML",
            detail: "Parsed structure with inferred types and line numbers; source fallback.",
            extensions: ".yaml, .yml, .toml"
        ),
        PreviewFeature(
            id: "env",
            symbol: "key.horizontal",
            title: "Environment files",
            detail: "KEY=VALUE parsing with likely secrets masked and comment highlighting.",
            extensions: ".env"
        ),
        PreviewFeature(
            id: "sqlite",
            symbol: "cylinder.split.1x2",
            title: "SQLite databases",
            detail: "Read-only table, index and schema browser with a bounded row preview.",
            extensions: ".sqlite, .sqlite3, .db"
        ),
        PreviewFeature(
            id: "markdown",
            symbol: "text.alignleft",
            title: "Markdown",
            detail: "Rendered headings, lists, tables, quotes and highlighted code fences.",
            extensions: ".md, .markdown, .mdx"
        ),
        PreviewFeature(
            id: "code",
            symbol: "chevron.left.forwardslash.chevron.right",
            title: "Source code",
            detail: "Syntax highlighting for Swift, Python, JS/TS, Go, Rust, C/C++ and more.",
            extensions: ".swift, .py, .js, .ts, .go, .rs, .c, .h, .cpp, ..."
        ),
        PreviewFeature(
            id: "package",
            symbol: "shippingbox",
            title: "package.json",
            detail: "Name, version, scripts and dependency tables in a single summary.",
            extensions: "package.json"
        ),
        PreviewFeature(
            id: "composer",
            symbol: "cube",
            title: "Composer manifests",
            detail: "composer.json metadata, authors and require tables; composer.lock package list.",
            extensions: "composer.json, composer.lock"
        ),
        PreviewFeature(
            id: "compose",
            symbol: "shippingbox.and.arrow.backward",
            title: "Docker Compose",
            detail: "Services with images, builds, ports, volumes, dependencies and masked environment values.",
            extensions: "docker-compose*.yml, compose*.yaml"
        ),
        PreviewFeature(
            id: "archive",
            symbol: "doc.zipper",
            title: "Archives & folders",
            detail: "ZIP, tar and gzip listings, gzip payload preview, folder browsing.",
            extensions: ".zip, .tar, .gz, .tgz"
        ),
    ]
}

struct SetupView: View {
    @State private var isEnabled: Bool? = nil
    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statusCard
                instructions
                featureList
                footerNote
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(width: 620, height: 660)
        .task { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .refreshExtensionStatus)) { _ in
            Task { await refreshStatus() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("QuickLooker")
                    .font(.system(size: 22, weight: .semibold))
                Text("Rich Quick Look previews for code and data files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                SystemSettings.openQuickLookExtensions()
            } label: {
                Text("Open Settings")
            }
            .controlSize(.regular)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isChecking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: isEnabled == true ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 20))
                .foregroundStyle(isEnabled == true ? Color.green : Color.orange)
        }
    }

    private var statusTitle: String {
        if isChecking { return "Checking extension status…" }
        switch isEnabled {
        case true: return "Extension enabled"
        case false: return "Extension not enabled yet"
        default: return "Extension status unknown"
        }
    }

    private var statusDetail: String {
        if isEnabled == false {
            return "Enable QuickLooker in System Settings → General → Login Items & Extensions → Quick Look."
        }
        return "All processing happens on this Mac. Nothing is uploaded."
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enable the extension")
                .font(.system(size: 13, weight: .semibold))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(step)
                        .font(.system(size: 12))
                }
            }
            Text("After enabling, press the space bar on any supported file in Finder to see the preview. You can quit this app afterwards.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var steps: [String] {
        [
            "Open System Settings → General → Login Items & Extensions.",
            "Scroll to Quick Look and press the info button.",
            "Turn on QuickLooker.",
            "Quit and reopen Finder if previews do not appear immediately.",
        ]
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Supported files")
                .font(.system(size: 13, weight: .semibold))
            ForEach(PreviewFeature.all) { feature in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 13))
                        .frame(width: 18)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(feature.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(feature.extensions)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("QuickLooker never modifies your files, never connects to the network and collects no data. Databases are opened read-only; archives are decompressed in memory with size limits.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status

    @MainActor
    private func refreshStatus() async {
        isChecking = true
        let enabled = ExtensionStatus.isEnabled
        isEnabled = enabled
        isChecking = false
    }
}
