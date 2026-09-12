public struct PullGesture: Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled, momentum, unphased }
    public private(set) var distance: Double = 0
    public private(set) var tracking = false
    public let threshold: Double
    public var armed: Bool { tracking && distance >= threshold }

    public init(threshold: Double = 70) { self.threshold = threshold }

    public mutating func cancel() { distance = 0; tracking = false }

    /// The gesture must start at the top; reaching it mid-scroll never arms a pull.
    @discardableResult
    public mutating func handle(phase: Phase, dx: Double = 0, dy: Double = 0,
                                atTop: Bool, eligible: Bool) -> Bool {
        guard eligible else { cancel(); return false }
        switch phase {
        case .began:
            cancel()
            tracking = atTop && abs(dy) >= abs(dx) && dy >= 0
            if tracking { distance = max(0, dy) }
        case .changed:
            guard tracking, atTop, abs(dx) <= max(abs(dy), 1) else { cancel(); return false }
            distance = max(0, distance + dy)
        case .ended:
            let refresh = armed && atTop
            cancel()
            return refresh
        case .cancelled, .momentum, .unphased:
            cancel()
        }
        return false
    }
}
