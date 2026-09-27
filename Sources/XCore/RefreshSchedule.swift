/// Deterministic scheduler. Callers supply monotonic time and independent pause reasons.
public struct RefreshSchedule: Sendable {
    public var enabled: Bool
    public private(set) var eligible = false
    public private(set) var loading = false
    public private(set) var deadline: Double?
    public private(set) var retryAt: Double?
    public private(set) var failures = 0
    public private(set) var manualRetryRequired = false
    private var quietUntil: Double = 0
    private var lastInteraction = -Double.infinity
    public let interval: Double
    /// While the reader is scrolled away from the top of the feed, a due refresh waits
    /// until this long has passed without interaction, so it does not yank the page mid-read.
    public let readingIdle: Double

    public init(enabled: Bool = true, interval: Double = 60, readingIdle: Double = 120) {
        self.enabled = enabled
        self.interval = interval
        self.readingIdle = readingIdle
    }

    public mutating func setEligible(_ value: Bool, now: Double) {
        guard value != eligible else { return }
        eligible = value
        deadline = value && !loading ? now + interval : nil
    }

    public mutating func setEnabled(_ value: Bool, now: Double) {
        enabled = value
        deadline = value && eligible && !loading ? now + interval : nil
    }

    public mutating func postpone(now: Double) {
        if let retryAt { self.retryAt = max(retryAt, now + interval) }
        deadline = eligible && !loading ? now + interval : nil
    }

    /// Direct input (scrolling, pointer, keys) defers an overdue refresh for five seconds.
    public mutating func interacted(now: Double) {
        quietUntil = now + 5
        lastInteraction = now
    }

    public mutating func begin() -> Bool {
        guard !loading else { return false }
        loading = true
        deadline = nil
        retryAt = nil
        manualRetryRequired = false
        return true
    }

    public mutating func succeeded(now: Double) {
        loading = false
        failures = 0
        retryAt = nil
        manualRetryRequired = false
        deadline = eligible ? now + interval : nil
    }

    /// A navigation ended without replacing the page, such as one that became a download.
    public mutating func cancelled(now: Double) {
        loading = false
        deadline = eligible ? now + interval : nil
    }

    public mutating func failed(now: Double, retryAfter: Double? = nil, requiresManual: Bool = false) {
        loading = false
        deadline = nil
        failures += 1
        manualRetryRequired = requiresManual
        let delay = retryAfter ?? min(300, 120 * pow2(min(failures - 1, 2)))
        retryAt = requiresManual ? nil : now + max(1, delay)
    }

    public mutating func suspendRetry() { retryAt = nil }

    public func isDue(now: Double, mayRetry: Bool, reading: Bool = false) -> Bool {
        guard enabled, !loading, !manualRetryRequired, now >= quietUntil else { return false }
        if let retryAt { return mayRetry && now >= retryAt }
        guard eligible, let deadline, now >= deadline else { return false }
        return !reading || now >= lastInteraction + readingIdle
    }

    private func pow2(_ exponent: Int) -> Double { Double(1 << exponent) }
}
