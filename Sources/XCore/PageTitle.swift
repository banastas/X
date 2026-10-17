import Foundation

/// X prefixes its document title with the unread notification count, as in "(3) Home / X".
public enum PageTitle {
    /// The Dock badge for a title, such as "3" or "20+", or nil when nothing is unread.
    public static func badge(_ title: String?) -> String? {
        guard let match = prefix(title) else { return nil }
        let count = String(match.dropFirst().dropLast())
        return count.trimmingCharacters(in: CharacterSet(charactersIn: "+")) == "0" ? nil : count
    }

    /// The title without its unread count, or "X" when nothing else remains.
    public static func text(_ title: String?) -> String {
        guard let title else { return "X" }
        let rest = prefix(title).map { String(title.dropFirst($0.count)) } ?? title
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "X" : trimmed
    }

    private static func prefix(_ title: String?) -> Substring? {
        guard let title, let match = title.prefixMatch(of: /\(\d{1,4}\+?\)/) else { return nil }
        return match.output
    }
}
