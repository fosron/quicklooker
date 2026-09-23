import Foundation

/// Structured summary for `package.json` files.
public enum PackageBuilder {

    public static func render(context: RenderContext) throws -> RenderedPreview {
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: context.data, options: []) as? [String: Any] else {
                return try CodeBuilder.fallbackPreview(
                    context: context,
                    renderer: "package.json",
                    language: "json",
                    notice: "The file does not contain a JSON object. Showing syntax highlighted source."
                )
            }
            object = parsed
        } catch {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "package.json",
                language: "json",
                notice: "The file is not valid JSON. Showing syntax highlighted source."
            )
        }

        var html = ""
        var cards: [(label: String, value: String)] = []
        if let name = string(object["name"]) { cards.append(("name", name)) }
        if let version = string(object["version"]) { cards.append(("version", version)) }
        if let license = string(object["license"]) { cards.append(("license", license)) }
        if let type = string(object["type"]) { cards.append(("module type", type)) }
        if let privateFlag = object["private"] as? Bool { cards.append(("private", privateFlag ? "yes" : "no")) }
        if let author = string(object["author"]) {
            cards.append(("author", author))
        } else if let authorObject = object["author"] as? [String: Any], let name = string(authorObject["name"]) {
            cards.append(("author", name))
        }
        if let engines = object["engines"] as? [String: Any] {
            let text = engines.keys.sorted().compactMap { key -> String? in
                guard let value = string(engines[key]) else { return nil }
                return "\(key) \(value)"
            }.joined(separator: ", ")
            if !text.isEmpty { cards.append(("engines", text)) }
        }
        if let description = string(object["description"]) {
            cards.append(("description", description))
        }
        if !cards.isEmpty {
            html += Document.cards(cards)
        }

        if let homepage = string(object["homepage"]) {
            html += Document.section("Links")
            html += Document.keyValueList([("homepage", homepage)])
        }
        if let keywords = object["keywords"] as? [String], !keywords.isEmpty {
            html += Document.section("Keywords")
            html += "<div>" + keywords.map { "<span class=\"badge muted\">\(HTML.escape($0))</span>" }.joined(separator: " ") + "</div>"
        }

        if let scripts = object["scripts"] as? [String: Any], !scripts.isEmpty {
            let rows = scripts.keys.sorted().map { key -> [Document.Cell] in
                [Document.Cell(key), Document.Cell(html: "<code>\(HTML.escape(string(scripts[key]) ?? ""))</code>")]
            }
            html += Document.section("Scripts", count: scripts.count)
            html += Document.table(headers: ["script", "command"], rows: rows)
        }

        let dependencyGroups: [(String, [String: Any]?, Bool)] = [
            ("dependencies", object["dependencies"] as? [String: Any], false),
            ("devDependencies", object["devDependencies"] as? [String: Any], true),
            ("peerDependencies", object["peerDependencies"] as? [String: Any], false),
            ("optionalDependencies", object["optionalDependencies"] as? [String: Any], false),
        ]
        for (title, group, collapsed) in dependencyGroups {
            guard let group, !group.isEmpty else { continue }
            let rows = group.keys.sorted().map { key -> [Document.Cell] in
                [Document.Cell(key), Document.Cell(html: "<code>\(HTML.escape(string(group[key]) ?? ""))</code>")]
            }
            let table = Document.table(headers: ["package", "range"], rows: rows)
            html += Document.section(title, count: group.count)
            if collapsed && group.count > 12 {
                html += "<details><summary class=\"meta\">show \(Format.integer(group.count)) packages</summary>\(table)</details>"
            } else {
                html += table
            }
        }

        if let repository = repositoryURL(object["repository"]) {
            html += Document.section("Repository")
            html += "<div class=\"mono meta\">\(HTML.escape(repository))</div>"
        }

        let dependencyCount = (object["dependencies"] as? [String: Any])?.count ?? 0
        let devCount = (object["devDependencies"] as? [String: Any])?.count ?? 0
        let scriptCount = (object["scripts"] as? [String: Any])?.count ?? 0
        var summary = "\(Format.integer(dependencyCount)) dependencies · \(Format.integer(devCount)) dev"
        if scriptCount > 0 { summary += " · \(Format.integer(scriptCount)) scripts" }

        return RenderedPreview(
            renderer: "package.json",
            summary: summary,
            html: html
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func repositoryURL(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let object = value as? [String: Any] { return string(object["url"]) }
        return nil
    }
}
