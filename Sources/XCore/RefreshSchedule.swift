/// Deterministic scheduler. Callers supply monotonic time and independent pause reasons.
public struct RefreshSchedule: Sendable {
    public var enabled: Bool
    public private(set) var eligible = false
    public private(set) var loading = false
    public private(set) var deadline: Double?
    public private(set) var retryAt: Double?
    public private(set) var failures = 0
    public private(set) var manualRetryRequired = false
    private var scrollUntil: Double = 0
    public let interval: Double

    public init(enabled: Bool = true, interval: Double = 60) {
        self.enabled = enabled
        self.interval = interval
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

    public mutating func scrolled(now: Double) { scrollUntil = now + 5 }

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

    public mutating func failed(now: Double, retryAfter: Double? = nil, requiresManual: Bool = false) {
        loading = false
        deadline = nil
        failures += 1
        manualRetryRequired = requiresManual
        let delay = retryAfter ?? min(300, 120 * pow2(min(failures - 1, 2)))
        retryAt = requiresManual ? nil : now + max(1, delay)
    }

    public mutating func suspendRetry() { retryAt = nil }

    public func isDue(now: Double, mayRetry: Bool) -> Bool {
        guard enabled, !loading, !manualRetryRequired, now >= scrollUntil else { return false }
        if let retryAt { return mayRetry && now >= retryAt }
        return eligible && deadline.map { now >= $0 } == true
    }

    private func pow2(_ exponent: Int) -> Double { Double(1 << exponent) }
}
