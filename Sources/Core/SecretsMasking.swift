import Foundation

/// Environment value masking shared by the `.env` preview and the Docker
/// Compose preview. Masked values are never written into a preview document.
public enum SecretsMasking {

    /// Keys containing one of these fragments are treated as secrets.
    public static let secretPatterns: [String] = [
        "password", "passwd", "pwd", "secret", "token", "api_key", "apikey",
        "api-key", "access_key", "accesskey", "private", "credential", "auth",
        "session", "cookie", "salt", "signature", "bearer", "cert", "dsn",
        "webhook", "encryption", "passphrase", "client_id", "client_secret",
    ]

    public static func isSecretKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return secretPatterns.contains { lowered.contains($0) }
    }

    /// Masks a value, keeping a short prefix for readability.
    public static func mask(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        if trimmed.count <= 3 {
            return String(repeating: "•", count: max(3, trimmed.count))
        }
        if trimmed.count < 12 {
            return "••••••"
        }
        let prefix = trimmed.prefix(3)
        return "\(prefix)••••••••••"
    }
}
