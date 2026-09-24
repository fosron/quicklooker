import Foundation

/// Environment value masking shared by the `.env`, Docker Compose and database
/// previews. Masked values are never written into a preview document.
public enum SecretsMasking {

    /// Exact tokens (after splitting on `_`, `-`, `.` and camelCase) that mark
    /// a key as holding a secret.
    public static let secretTokens: Set<String> = [
        "password", "passwd", "pwd", "secret", "secrets", "token", "tokens",
        "auth", "authentication", "authorization", "bearer", "credential",
        "credentials", "privatekey", "accesskey", "salt", "signature",
        "session", "cookie", "cert", "dsn", "webhook", "passphrase",
        "encryption", "clientsecret",
    ]

    /// Token patterns used as a prefix match, which catches `TOKEN_ID`,
    /// `SECRET2` and similar suffixed names.
    private static let prefixTokens: [String] = [
        "secret", "token", "passwd", "password", "apikey", "accesskey",
        "credential",
    ]

    /// Fragments that only ever appear in credential names.
    private static let fragments: [String] = ["secret", "password", "passwd"]

    /// Splits an identifier such as `DATABASE_PASSWORD` or `clientSecret` into
    /// lowercased tokens so matching does not rely on substrings: `AUTHOR`
    /// no longer matches `auth`.
    static func tokens(of key: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var previousWasUppercase = false
        for character in key {
            if character.isLetter || character.isNumber {
                if character.isUppercase, previousWasUppercase == false, !current.isEmpty {
                    tokens.append(current.lowercased())
                    current = ""
                }
                current.append(character)
                previousWasUppercase = true
            } else {
                if !current.isEmpty {
                    tokens.append(current.lowercased())
                    current = ""
                }
                previousWasUppercase = false
            }
        }
        if !current.isEmpty {
            tokens.append(current.lowercased())
        }
        return tokens
    }

    public static func isSecretKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        if fragments.contains(where: { lowered.contains($0) }) {
            return true
        }
        let tokens = tokens(of: key)
        for (index, token) in tokens.enumerated() {
            if secretTokens.contains(token) {
                return true
            }
            if prefixTokens.contains(where: { token.hasPrefix($0) }) {
                return true
            }
            // Compound names: API_KEY, SECRET_KEY, SSH_PRIVATE_KEY, STRIPE_KEY.
            if token == "key" {
                let previous = index > 0 ? tokens[index - 1] : nil
                if previous == "api" || previous == "private" || previous == "public"
                    || previous == "signing" || previous == "encryption" || previous == "access" {
                    return true
                }
                // Any other `something_key` name is treated as a secret too.
                if index > 0, previous != "monkey", previous != "turkey" {
                    return true
                }
            }
        }
        return false
    }

    /// True when a value must not be shown verbatim: the key looks secret, the
    /// value embeds credentials (`postgres://user:pass@host`) or it expands a
    /// secret variable (`${DB_PASSWORD}`).
    public static func shouldMask(key: String, value: String) -> Bool {
        if isSecretKey(key) { return true }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("@"), maskCredentialURL(trimmed) != nil { return true }
        if let name = variableReference(trimmed), isSecretKey(name) { return true }
        return false
    }

    /// Masks a value, keeping a short prefix for readability.
    public static func mask(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        if let masked = maskCredentialURL(trimmed) {
            return masked
        }
        if let name = variableReference(trimmed), isSecretKey(name) {
            return "${••••••}"
        }
        if trimmed.count <= 3 {
            return String(repeating: "•", count: max(3, trimmed.count))
        }
        if trimmed.count < 12 {
            return "••••••"
        }
        let prefix = trimmed.prefix(3)
        return "\(prefix)••••••••••"
    }

    /// Rewrites `scheme://user:password@host` to `scheme://user:••••@host`.
    static func maskCredentialURL(_ value: String) -> String? {
        guard let schemeRange = value.range(of: "://") else { return nil }
        let authorityStart = schemeRange.upperBound
        guard let at = value[authorityStart...].firstIndex(of: "@"),
              let colon = value[authorityStart..<at].firstIndex(of: ":") else {
            return nil
        }
        return String(value[..<colon]) + ":••••••" + String(value[at...])
    }

    /// Returns the variable name when the value is a `$NAME` / `${NAME}`.
    static func variableReference(_ value: String) -> String? {
        guard value.count >= 2, value.hasPrefix("$") else { return nil }
        if value.hasPrefix("${"), value.hasSuffix("}") {
            let name = value.dropFirst(2).dropLast()
            return name.isEmpty ? nil : String(name)
        }
        let name = value.dropFirst()
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return String(name)
    }
}
