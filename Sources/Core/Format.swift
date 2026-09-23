import Foundation

/// Small formatting helpers shared by every renderer.
public enum Format {
    public static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }

    public static func bytes(_ count: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(count)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 {
            return "\(Int(value)) \(units[unit])"
        }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = value < 10 ? 1 : 0
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        return "\(number) \(units[unit])"
    }

    public static func integer(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    /// Renders a POSIX timestamp as an ISO-like local date string.
    public static func date(timeIntervalSince1970 timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    public static func date(_ value: Date) -> String {
        date(timeIntervalSince1970: value.timeIntervalSince1970)
    }

    /// Compact relative description, e.g. "3 days ago".
    public static func relativeDate(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Truncates a long identifier in the middle, "abcdef…xyz123".
    public static func ellipsizeMiddle(_ text: String, limit: Int = 64) -> String {
        guard text.count > limit, limit > 8 else { return text }
        let half = (limit - 1) / 2
        let prefix = text.prefix(half)
        let suffix = text.suffix(limit - half - 1)
        return "\(prefix)…\(suffix)"
    }

    /// Renders a double without a trailing ".0" for whole numbers.
    public static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}
