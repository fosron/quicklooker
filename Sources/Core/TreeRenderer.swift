import Foundation

/// Format independent representation of a structured document.
public indirect enum ValueNode: Sendable {
    case object([(String, ValueNode)])
    case array([ValueNode])
    case string(String)
    case number(String)
    case boolean(Bool)
    case null
    case other(String)

    public var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default: return false
        }
    }

    public var childCount: Int {
        switch self {
        case .object(let entries): return entries.count
        case .array(let items): return items.count
        default: return 0
        }
    }

    /// Total number of nodes including self.
    public var nodeCount: Int {
        switch self {
        case .object(let entries):
            return 1 + entries.reduce(0) { $0 + $1.1.nodeCount }
        case .array(let items):
            return 1 + items.reduce(0) { $0 + $1.nodeCount }
        default:
            return 1
        }
    }
}

extension ValueNode: Equatable {
    public static func == (lhs: ValueNode, rhs: ValueNode) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case let (.string(a), .string(b)):
            return a == b
        case let (.number(a), .number(b)):
            return a == b
        case let (.boolean(a), .boolean(b)):
            return a == b
        case let (.other(a), .other(b)):
            return a == b
        case let (.array(a), .array(b)):
            return a == b
        case let (.object(a), .object(b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default:
            return false
        }
    }
}

public extension ValueNode {
    /// Builds a node tree from a `JSONSerialization` value.
    static func fromJSON(_ value: Any) -> ValueNode {
        switch value {
        case let dictionary as [String: Any]:
            let keys = dictionary.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return .object(keys.map { ($0, fromJSON(dictionary[$0] as Any)) })
        case let array as [Any]:
            return .array(array.map(fromJSON))
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            if CFNumberIsFloatType(number) {
                return .number(Format.number(number.doubleValue))
            }
            return .number(String(number.int64Value))
        case is NSNull:
            return .null
        default:
            return .other(String(describing: value))
        }
    }

    static func fromJSONData(_ data: Data, options: JSONSerialization.ReadingOptions = [.fragmentsAllowed]) throws -> ValueNode {
        let object = try JSONSerialization.jsonObject(with: data, options: options)
        return fromJSON(object)
    }
}

/// Renders `ValueNode` trees as collapsible HTML.
public final class TreeRenderer {
    public struct Options: Sendable {
        /// Renders the key / index prefix. Return `nil` for a bare value.
        public var keyRenderer: (@Sendable (String, ValueNode) -> String?)?
        /// Path aware variant of `keyRenderer`. `path` uses `key` and `[i]`
        /// components, e.g. `server.ports[0]`.
        public var keyRendererWithPath: (@Sendable (String, String, ValueNode) -> String?)?
        /// Optional trailing annotation for a leaf value (e.g. a type hint).
        public var valueComment: (@Sendable (String, ValueNode) -> String?)?
        public var maxDepth: Int
        public var nodeLimit: Int
        /// Label used for arrays/objects in summaries, e.g. "items".
        public var itemLabel: String
        public var itemLabelSingular: String

        public init(
            keyRenderer: (@Sendable (String, ValueNode) -> String?)? = nil,
            keyRendererWithPath: (@Sendable (String, String, ValueNode) -> String?)? = nil,
            valueComment: (@Sendable (String, ValueNode) -> String?)? = nil,
            maxDepth: Int = 24,
            nodeLimit: Int = 10_000,
            itemLabel: String = "items",
            itemLabelSingular: String = "item"
        ) {
            self.keyRenderer = keyRenderer
            self.keyRendererWithPath = keyRendererWithPath
            self.valueComment = valueComment
            self.maxDepth = maxDepth
            self.nodeLimit = nodeLimit
            self.itemLabel = itemLabel
            self.itemLabelSingular = itemLabelSingular
        }

        func label(for count: Int) -> String {
            "\(count) \(count == 1 ? itemLabelSingular : itemLabel)"
        }
    }

    private let options: Options
    private var budget: Int
    private var overflowed = false

    public init(options: Options) {
        self.options = options
        self.budget = options.nodeLimit
    }

    public var didOverflow: Bool { overflowed }

    public static func typeClass(for node: ValueNode) -> String {
        switch node {
        case .string: return "tok-string"
        case .number: return "tok-number"
        case .boolean: return "tok-boolean"
        case .null: return "tok-null"
        case .other: return "tok-punctuation"
        case .array, .object: return "tok-punctuation"
        }
    }

    public static func inlineValue(_ node: ValueNode) -> String {
        switch node {
        case .string(let value):
            return "<span class=\"tok-string\">\(HTML.escape(quoted(value)))</span>"
        case .number(let value):
            return "<span class=\"tok-number\">\(HTML.escape(value))</span>"
        case .boolean(let value):
            return "<span class=\"tok-boolean\">\(value ? "true" : "false")</span>"
        case .null:
            return "<span class=\"tok-null\">null</span>"
        case .other(let value):
            return "<span class=\"tok-punctuation\">\(HTML.escape(value))</span>"
        case .array(let items):
            return "<span class=\"count\">[\(items.count) \(items.count == 1 ? "item" : "items")]</span>"
        case .object(let entries):
            return "<span class=\"count\">{\(entries.count) \(entries.count == 1 ? "key" : "keys")}</span>"
        }
    }

    /// Quotes a string value for display, keeping it single line.
    public static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public func render(_ node: ValueNode) -> String {
        render(node, rootKey: nil)
    }

    /// Renders a tree whose top level entry carries an optional label, used by
    /// JSON Lines records to show their record number.
    public func render(_ node: ValueNode, rootKey: String?) -> String {
        var html = "<div class=\"tree\">"
        html += renderNode(node, key: rootKey, path: rootKey ?? "", depth: 0)
        html += "</div>"
        if overflowed {
            let message = "Preview limited to \(Format.integer(options.nodeLimit)) values"
            html += "<div class=\"more\">— \(HTML.escape(message)) —</div>"
        }
        return html
    }

    private func renderNode(_ node: ValueNode, key: String?, path: String, depth: Int) -> String {
        if budget <= 0 {
            overflowed = true
            return truncatedRow()
        }
        budget -= 1

        if node.isContainer {
            if depth >= options.maxDepth {
                overflowed = true
                return "<div class=\"node\"><div class=\"line\">\(prefix(key: key, path: path, node: node))\(collapsedMarker(for: node))</div></div>"
            }
            return containerHTML(node, key: key, path: path, depth: depth)
        }

        let keyHTML = prefix(key: key, path: path, node: node)
        var commentHTML = ""
        if let comment = options.valueComment?(path, node) {
            commentHTML = "<span class=\"count\">\(HTML.escape(comment))</span>"
        }
        let leaf = "<div class=\"leaf\"><div class=\"line\">\(keyHTML)\(Self.inlineValue(node))\(commentHTML)</div></div>"
        return leaf
    }

    private func containerHTML(_ node: ValueNode, key: String?, path: String, depth: Int) -> String {
        let children: [ValueNode]
        let indices: [String]
        let isArray: Bool
        switch node {
        case .object(let entries):
            children = entries.map { $0.1 }
            indices = entries.map { $0.0 }
            isArray = false
        case .array(let items):
            children = items
            indices = items.indices.map { "\($0)" }
            isArray = true
        default:
            return ""
        }

        let countLabel = options.label(for: node.childCount)
        var summary = "<div class=\"line\">\(prefix(key: key, path: path, node: node))"
        if children.isEmpty {
            summary += "<span class=\"count\">(empty)</span>"
        } else {
            summary += "<span class=\"count\">\(HTML.escape(countLabel))</span>"
        }
        summary += "</div>"

        if children.isEmpty {
            return "<div class=\"node\">\(summary)</div>"
        }

        var inner = ""
        var rendered = 0
        for (index, child) in children.enumerated() {
            if budget <= 0 {
                overflowed = true
                inner += truncatedRow(remaining: children.count - rendered)
                break
            }
            let childPath: String
            if isArray {
                childPath = "\(path)[\(indices[index])]"
            } else if path.isEmpty {
                childPath = indices[index]
            } else {
                childPath = "\(path).\(indices[index])"
            }
            let displayKey = isArray ? "[\(indices[index])]" : indices[index]
            inner += renderNode(child, key: displayKey, path: childPath, depth: depth + 1)
            rendered += 1
        }

        return """
        <div class="node"><details open><summary>\(summary)</summary><div class="children">\(inner)</div></details></div>
        """
    }

    private func prefix(key: String?, path: String, node: ValueNode) -> String {
        guard let key else { return "" }
        if let rendered = options.keyRendererWithPath?(path, key, node) {
            return rendered
        }
        if let rendered = options.keyRenderer?(key, node) {
            return rendered
        }
        if key.hasPrefix("#") {
            return "<span class=\"index\">\(HTML.escape(key))</span> "
        }
        if key.hasPrefix("[") {
            return "<span class=\"index\">\(HTML.escape(key))</span><span class=\"colon\">:</span> "
        }
        return "<span class=\"key\">\(HTML.escape(key))</span><span class=\"colon\">:</span> "
    }

    private func collapsedMarker(for node: ValueNode) -> String {
        "<span class=\"count\">⋯ \(HTML.escape(options.label(for: node.childCount)))</span>"
    }

    private func truncatedRow(remaining: Int? = nil) -> String {
        if let remaining, remaining > 0 {
            return "<div class=\"leaf\"><div class=\"line more\">… \(Format.integer(remaining)) more</div></div>"
        }
        return "<div class=\"leaf\"><div class=\"line more\">…</div></div>"
    }
}
