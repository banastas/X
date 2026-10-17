import Foundation

/// Decides when a rising unread count deserves a notification. X's title loses its "(N)" prefix
/// for a moment on every reload, so a naive "higher than last time" rule fires on each refresh.
/// Readings taken while a page is loading are ignored, and while the app is in the background a
/// lower count never lowers the baseline: only a count above what the person already knew counts.
public struct UnreadTracker: Sendable {
    /// The count the person is taken to know about; nil until the first steady reading.
    public private(set) var baseline: Int?

    public init() {}

    /// "3" → 3, "20+" → 20, nil → 0.
    public static func count(from badge: String?) -> Int {
        badge.flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "+"))) } ?? 0
    }

    /// True when this reading should post a notification.
    public mutating func update(count: Int, loading: Bool, inBackground: Bool) -> Bool {
        guard !loading else { return false }
        guard let known = baseline else { baseline = count; return false }
        if count > known {
            baseline = count
            return inBackground
        }
        if !inBackground { baseline = count }
        return false
    }

    /// The person brought the app forward and can see the badge: whatever it shows is known.
    public mutating func seen(count: Int, loading: Bool) {
        if !loading { baseline = count }
    }
}
