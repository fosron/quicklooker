import Foundation

/// Escapes untrusted content before it is embedded in generated HTML.
///
/// Every value that originates from a previewed file must pass through one of
/// these helpers. Quick Look renders the reply HTML with scripting disabled,
/// but escaping is still required to prevent malformed markup and to keep the
/// generated document well formed.
public enum HTML {
    /// Escapes text content (`&`, `<`, `>`).
    public static func escape(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count + 16)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\0": out += "\\0"
            default: out.append(character)
            }
        }
        return out
    }

    /// Escapes a string for use inside a double-quoted HTML attribute.
    public static func escapeAttribute(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count + 16)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Escapes a value that is meant to be rendered inside a `<pre>` block.
    public static func escapePre(_ text: String) -> String {
        escape(text)
    }
}
