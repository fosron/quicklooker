import Foundation

/// Docker Compose preview: service oriented summary for `docker-compose*.yml`,
/// `compose.yml` and their `.dev` / `.override` variants.
public enum DockerComposeBuilder {

    public static func render(context: RenderContext) throws -> RenderedPreview {
        var parser = YAMLParser(text: context.text)
        let result = parser.parse()

        guard result.failure == nil, let root = result.value else {
            let detail = result.failure.map { "line \(result.failureLine ?? 0): \($0)" } ?? "unknown parse error"
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "Docker Compose",
                language: "yaml",
                notice: "The file could not be parsed (\(detail)). Showing syntax highlighted source."
            )
        }
        guard case .object(let entries) = root else {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "Docker Compose",
                language: "yaml",
                notice: "The document root is not a mapping. Showing syntax highlighted source."
            )
        }

        let rootEntries = Dictionary(entries, uniquingKeysWith: { first, _ in first })
        guard let servicesNode = rootEntries["services"], case .object(let services) = servicesNode else {
            return try CodeBuilder.fallbackPreview(
                context: context,
                renderer: "Docker Compose",
                language: "yaml",
                notice: "No `services` mapping found. Showing syntax highlighted source."
            )
        }

        var html = ""
        html += summaryCards(root: rootEntries, services: services, context: context)

        if let profiles = rootEntries["profiles"], case .array(let items) = profiles {
            html += Document.section("profiles")
            html += "<div>" + items.map { node -> String in
                if case .string(let value) = node { return "<span class=\"badge muted\">\(HTML.escape(value))</span>" }
                return ""
            }.joined(separator: " ") + "</div>"
        }

        html += Document.section("services", count: services.count)
        for (name, serviceNode) in services {
            html += serviceCard(name: name, node: serviceNode)
        }

        html += namedSection("volumes", node: rootEntries["volumes"])
        html += namedSection("networks", node: rootEntries["networks"])
        html += namedSection("secrets", node: rootEntries["secrets"])
        html += namedSection("configs", node: rootEntries["configs"])

        if context.wasTruncatedAtRead {
            html = Document.notice("Only the first \(Format.bytes(context.limits.maxBytes)) of this file were read.") + html
        }
        let truncated = context.wasTruncatedAtRead
        let summary = "\(Format.integer(services.count)) services · \(Format.integer(rootEntries["volumes"]?.childCount ?? 0)) volumes"
        return RenderedPreview(renderer: "Docker Compose", summary: summary, html: html, truncated: truncated)
    }

    // MARK: - Summary

    private static func summaryCards(
        root: [String: ValueNode],
        services: [(String, ValueNode)],
        context: RenderContext
    ) -> String {
        var cards: [(label: String, value: String)] = [
            ("services", Format.integer(services.count)),
        ]
        if let projectName = stringValue(root["name"]) {
            cards.insert(("project", projectName), at: 0)
        }
        let version = stringValue(root["version"])
        if let version {
            cards.append(("compose version", version))
        }
        for key in ["volumes", "networks", "secrets", "configs"] {
            let count = root[key]?.childCount ?? 0
            if count > 0 {
                cards.append((key, Format.integer(count)))
            }
        }
        let images = services.compactMap { _, node -> String? in
            guard case .object(let fields) = node else { return nil }
            return stringValue(fields.first(where: { $0.0 == "image" })?.1)
        }
        let built = services.count - images.count
        if built > 0 {
            cards.append(("built locally", Format.integer(built)))
        }
        return Document.cards(cards)
    }

    // MARK: - Services

    private static func serviceCard(name: String, node: ValueNode) -> String {
        guard case .object(let fields) = node else {
            return Document.section(name) + "<div class=\"empty\">No service definition.</div>"
        }
        let map = Dictionary(fields, uniquingKeysWith: { first, _ in first })

        var html = "<div class=\"card\" style=\"margin-bottom:12px\">"
        var title = "<div class=\"value\" style=\"font-size:14px\">\(HTML.escape(name))</div>"

        if let image = stringValue(map["image"]) {
            title += " <code style=\"font-size:11px\">\(HTML.escape(image))</code>"
        } else if map["build"] != nil {
            title += " <span class=\"badge\">build</span>"
        }
        if let profiles = map["profiles"], case .array(let items) = profiles {
            for item in items {
                if case .string(let profile) = item {
                    title += " <span class=\"badge muted\">profile: \(HTML.escape(profile))</span>"
                }
            }
        }
        html += title

        var details: [(String, String)] = []
        if let build = map["build"] {
            switch build {
            case .string(let value):
                details.append(("build", value))
            case .object(let buildFields):
                let buildMap = Dictionary(buildFields, uniquingKeysWith: { first, _ in first })
                var text = stringValue(buildMap["context"]) ?? "."
                if let dockerfile = stringValue(buildMap["dockerfile"]) {
                    text += " · Dockerfile: \(dockerfile)"
                }
                if let target = stringValue(buildMap["target"]) {
                    text += " · target: \(target)"
                }
                details.append(("build", text))
            default:
                break
            }
        }
        if let containerName = stringValue(map["container_name"]) {
            details.append(("container", containerName))
        }
        if let command = commandText(map["command"]) {
            details.append(("command", command))
        }
        if let entrypoint = commandText(map["entrypoint"]) {
            details.append(("entrypoint", entrypoint))
        }
        if let restart = stringValue(map["restart"]) {
            details.append(("restart", restart))
        }
        if let healthcheck = map["healthcheck"], case .object(let checkFields) = healthcheck {
            let checkMap = Dictionary(checkFields, uniquingKeysWith: { first, _ in first })
            var text = commandText(checkMap["test"]) ?? "configured"
            if let interval = stringValue(checkMap["interval"]) {
                text += " every \(interval)"
            }
            details.append(("healthcheck", text))
        }
        if let dependsOn = map["depends_on"] {
            details.append(("depends on", listText(dependsOn)))
        }
        if let ports = map["ports"] {
            details.append(("ports", listText(ports)))
        }
        if let expose = map["expose"] {
            details.append(("expose", listText(expose)))
        }
        if let volumes = map["volumes"] {
            details.append(("volumes", listText(volumes)))
        }
        if let networks = map["networks"] {
            details.append(("networks", listText(networks)))
        }
        if let labels = map["labels"] {
            details.append(("labels", listText(labels)))
        }
        if let deploy = map["deploy"], case .object(let deployFields) = deploy {
            let deployMap = Dictionary(deployFields, uniquingKeysWith: { first, _ in first })
            if let replicas = numberValue(deployMap["replicas"]) {
                details.append(("replicas", replicas))
            }
            if let resources = deployMap["resources"], case .object(let resourceFields) = resources {
                let resourceMap = Dictionary(resourceFields, uniquingKeysWith: { first, _ in first })
                for key in ["limits", "reservations"] {
                    if let limit = resourceMap[key], case .object(let limitFields) = limit {
                        let text = limitFields.map { "\($0.0)=\(inlineScalar($0.1))" }.joined(separator: ", ")
                        details.append((key, text))
                    }
                }
            }
        }
        if let user = stringValue(map["user"]) {
            details.append(("user", user))
        }
        if let workingDir = stringValue(map["working_dir"]) {
            details.append(("working dir", workingDir))
        }

        if !details.isEmpty {
            html += "<div style=\"margin-top:8px\">"
            html += Document.keyValueList(details)
            html += "</div>"
        }

        html += environmentTable(map["environment"])
        html += environmentFileTable(map["env_file"])
        html += "</div>"
        return html
    }

    private static func environmentTable(_ node: ValueNode?) -> String {
        guard let node else { return "" }
        var pairs: [(String, String)] = []
        switch node {
        case .object(let entries):
            for (key, value) in entries {
                pairs.append((key, inlineScalar(value)))
            }
        case .array(let items):
            for item in items {
                if case .string(let text) = item {
                    let parts = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    pairs.append((String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : ""))
                }
            }
        default:
            return ""
        }
        guard !pairs.isEmpty else { return "" }
        pairs.sort { $0.0.localizedStandardCompare($1.0) == .orderedAscending }

        var secretCount = 0
        let rows = pairs.map { key, value -> [Document.Cell] in
            if SecretsMasking.isSecretKey(key) {
                secretCount += 1
                return [
                    Document.Cell(html: "<span class=\"key\">\(HTML.escape(key))</span>"),
                    Document.Cell(html: "<span class=\"masked-value tok-string\">\(HTML.escape(SecretsMasking.mask(value)))\"</span>"),
                ]
            }
            return [
                Document.Cell(html: "<span class=\"key\">\(HTML.escape(key))</span>"),
                Document.Cell(html: "<span class=\"tok-string\">\(HTML.escape(value))\"</span>"),
            ]
        }
        var html = "<div class=\"section\">environment <span class=\"meta\">(\(pairs.count))</span>"
        if secretCount > 0 {
            html += " <span class=\"badge muted\">\(secretCount) masked</span>"
        }
        html += "</div>"
        html += Document.table(headers: ["variable", "value"], rows: rows)
        return html
    }

    private static func environmentFileTable(_ node: ValueNode?) -> String {
        guard let node else { return "" }
        let files = listText(node)
        guard !files.isEmpty else { return "" }
        return "<div class=\"section\">env_file</div><div class=\"mono meta\">\(HTML.escape(files))</div>"
    }

    // MARK: - Named resources

    private static func namedSection(_ title: String, node: ValueNode?) -> String {
        guard let node, case .object(let entries) = node, !entries.isEmpty else { return "" }
        var html = Document.section(title, count: entries.count)
        html += "<div>" + entries.map { name, _ in
            "<span class=\"badge muted\">\(HTML.escape(name))</span>"
        }.joined(separator: " ") + "</div>"
        return html
    }

    // MARK: - Node helpers

    private static func stringValue(_ node: ValueNode?) -> String? {
        guard case .string(let value)? = node else { return nil }
        return value
    }

    private static func numberValue(_ node: ValueNode?) -> String? {
        switch node {
        case .number(let value): return value
        case .string(let value): return value
        default: return nil
        }
    }

    /// Renders a scalar or a short list as a single line.
    private static func listText(_ node: ValueNode) -> String {
        switch node {
        case .array(let items):
            return items.map(inlineScalar).joined(separator: ", ")
        default:
            return inlineScalar(node)
        }
    }

    /// Renders a command that may be a string or a list of arguments.
    private static func commandText(_ node: ValueNode?) -> String? {
        guard let node else { return nil }
        switch node {
        case .array(let items):
            return items.map(inlineScalar).joined(separator: " ")
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    private static func inlineScalar(_ node: ValueNode) -> String {
        switch node {
        case .string(let value): return value
        case .number(let value): return value
        case .boolean(let value): return value ? "true" : "false"
        case .null: return "null"
        case .other(let value): return value
        case .array(let items): return items.map(inlineScalar).joined(separator: ", ")
        case .object(let entries): return entries.map { "\($0.0)=\(inlineScalar($0.1))" }.joined(separator: ", ")
        }
    }
}
