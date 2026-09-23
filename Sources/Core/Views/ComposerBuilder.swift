import Foundation

/// Structured summary for PHP Composer manifests: `composer.json` (and the
/// installed package set in `composer.lock`).
public enum ComposerBuilder {

    public static func render(context: RenderContext) throws -> RenderedPreview {
        let isLock = context.fileBaseName.lowercased() == "composer.lock"

        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: context.data, options: []) as? [String: Any] else {
                return try fallback(context, notice: "The file does not contain a JSON object. Showing syntax highlighted source.")
            }
            object = parsed
        } catch {
            return try fallback(context, notice: "The file is not valid JSON. Showing syntax highlighted source.")
        }

        return isLock ? renderLock(object: object, context: context) : renderManifest(object: object, context: context)
    }

    private static func fallback(_ context: RenderContext, notice: String) throws -> RenderedPreview {
        try CodeBuilder.fallbackPreview(
            context: context,
            renderer: context.fileBaseName.lowercased() == "composer.lock" ? "composer.lock" : "composer.json",
            language: "json",
            notice: notice
        )
    }

    // MARK: - composer.json

    private static func renderManifest(object: [String: Any], context: RenderContext) -> RenderedPreview {
        var html = ""
        var cards: [(label: String, value: String)] = []
        if let name = string(object["name"]) { cards.append(("name", name)) }
        if let description = string(object["description"]) { cards.append(("description", description)) }
        if let type = string(object["type"]) { cards.append(("type", type)) }
        if let license = licenseText(object["license"]) { cards.append(("license", license)) }
        if let stability = string(object["minimum-stability"]) { cards.append(("minimum stability", stability)) }
        if let preferStable = object["prefer-stable"] as? Bool { cards.append(("prefer stable", preferStable ? "yes" : "no")) }
        if let homepage = string(object["homepage"]) { cards.append(("homepage", homepage)) }
        if let version = string(object["version"]) { cards.append(("version", version)) }
        if !cards.isEmpty {
            html += Document.cards(cards)
        }

        let authors = authorList(object["authors"])
        if !authors.isEmpty {
            html += Document.section("Authors", count: authors.count)
            html += Document.table(
                headers: ["name", "email", "role"],
                rows: authors.map { [Document.Cell($0.name), Document.Cell($0.email), Document.Cell($0.role)] }
            )
        }

        if let keywords = object["keywords"] as? [String], !keywords.isEmpty {
            html += Document.section("Keywords")
            html += "<div>" + keywords.map { "<span class=\"badge muted\">\(HTML.escape($0))</span>" }.joined(separator: " ") + "</div>"
        }

        let dependencyGroups: [(String, [String: Any]?)] = [
            ("require", object["require"] as? [String: Any]),
            ("require-dev", object["require-dev"] as? [String: Any]),
            ("suggest", object["suggest"] as? [String: Any]),
            ("conflict", object["conflict"] as? [String: Any]),
            ("replace", object["replace"] as? [String: Any]),
            ("provide", object["provide"] as? [String: Any]),
        ]
        for (title, group) in dependencyGroups {
            guard let group, !group.isEmpty else { continue }
            html += Document.section(title, count: group.count)
            html += dependencyTable(group)
        }

        if let autoload = object["autoload"] as? [String: Any], !autoload.isEmpty {
            html += Document.section("Autoload")
            html += "<details open><summary class=\"meta\">namespaces</summary><pre class=\"raw\">\(HTML.escape(prettyJSON(autoload)))</pre></details>"
        }

        if let scripts = object["scripts"] as? [String: Any], !scripts.isEmpty {
            html += Document.section("Scripts", count: scripts.count)
            html += Document.table(
                headers: ["script", "command"],
                rows: scripts.keys.sorted().map { key -> [Document.Cell] in
                    [Document.Cell(key), Document.Cell(html: "<code>\(HTML.escape(scriptText(scripts[key])) )</code>")]
                }
            )
        }

        if let support = object["support"] as? [String: Any], !support.isEmpty {
            html += Document.section("Support")
            html += Document.keyValueList(
                support.keys.sorted().compactMap { key in
                    string(support[key]).map { (key, $0) }
                }
            )
        }

        if let extra = object["extra"] as? [String: Any], !extra.isEmpty {
            html += Document.section("Extra")
            html += "<pre class=\"raw\">\(HTML.escape(prettyJSON(extra)))</pre>"
        }

        let requireCount = (object["require"] as? [String: Any])?.count ?? 0
        let requireDevCount = (object["require-dev"] as? [String: Any])?.count ?? 0
        var summary = "\(Format.integer(requireCount)) require · \(Format.integer(requireDevCount)) require-dev"
        if !authors.isEmpty {
            summary += " · \(Format.integer(authors.count)) author\(authors.count == 1 ? "" : "s")"
        }
        return RenderedPreview(renderer: "composer.json", summary: summary, html: html)
    }

    // MARK: - composer.lock

    private static func renderLock(object: [String: Any], context: RenderContext) -> RenderedPreview {
        let packages = (object["packages"] as? [[String: Any]]) ?? []
        let devPackages = (object["packages-dev"] as? [[String: Any]]) ?? []

        var cards: [(label: String, value: String)] = [
            ("installed", Format.integer(packages.count + devPackages.count)),
            ("packages", Format.integer(packages.count)),
            ("packages-dev", Format.integer(devPackages.count)),
        ]
        if let pluginAPI = string(object["plugin-api-version"]) { cards.append(("plugin api", pluginAPI)) }
        if let contentHash = string(object["content-hash"]) { cards.append(("content hash", String(contentHash.prefix(16)) + "…")) }
        var html = Document.cards(cards)

        html += packageSection(title: "packages", packages: packages, collapsed: false)
        html += packageSection(title: "packages-dev", packages: devPackages, collapsed: true)

        let summary = "\(Format.integer(packages.count)) packages · \(Format.integer(devPackages.count)) dev · \(Format.bytes(context.data.count))"
        return RenderedPreview(renderer: "composer.lock", summary: summary, html: html)
    }

    private static func packageSection(title: String, packages: [[String: Any]], collapsed: Bool) -> String {
        guard !packages.isEmpty else { return "" }
        let rows = packages
            .sorted { string($0["name"])?.localizedStandardCompare(string($1["name"]) ?? "") == .orderedAscending }
            .map { package -> [Document.Cell] in
                let name = string(package["name"]) ?? "?"
                let version = string(package["version"]) ?? ""
                let description = string(package["description"]) ?? ""
                let requires = (package["require"] as? [String: Any])?.count ?? 0
                return [
                    Document.Cell(html: "<span class=\"key\">\(HTML.escape(name))</span>"),
                    Document.Cell(html: "<code>\(HTML.escape(version))</code>"),
                    Document.Cell(html: "<span class=\"meta\">\(HTML.escape(requires > 0 ? "\(requires) deps" : ""))</span>"),
                    Document.Cell(html: "<span class=\"meta\">\(HTML.escape(description))</span>"),
                ]
            }
        let table = Document.tableScroll(headers: ["package", "version", "requires", "description"], rows: rows)
        let section = Document.section(title, count: packages.count)
        if collapsed && packages.count > 12 {
            return section + "<details><summary class=\"meta\">show \(Format.integer(packages.count)) packages</summary>\(table)</details>"
        }
        return section + table
    }

    // MARK: - Helpers

    private struct Author {
        let name: String
        let email: String
        let role: String
    }

    private static func authorList(_ value: Any?) -> [Author] {
        if let text = value as? String {
            return [Author(name: text, email: "", role: "")]
        }
        guard let list = value as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let name = string(entry["name"]) else { return nil }
            return Author(
                name: name,
                email: string(entry["email"]) ?? "",
                role: string(entry["role"]) ?? ""
            )
        }
    }

    private static func dependencyTable(_ group: [String: Any]) -> String {
        let rows = group.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { key -> [Document.Cell] in
            [Document.Cell(key), Document.Cell(html: "<code>\(HTML.escape(string(group[key]) ?? ""))</code>")]
        }
        return Document.table(headers: ["package", "constraint"], rows: rows)
    }

    private static func licenseText(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let list = value as? [String] { return list.joined(separator: ", ") }
        return nil
    }

    private static func scriptText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let list = value as? [String] { return list.joined(separator: " && ") }
        if let object = value as? [String: Any] { return prettyJSON(object) }
        return ""
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func prettyJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
