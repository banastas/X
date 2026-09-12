public struct PullGesture: Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled, momentum, unphased }
    public private(set) var distance: Double = 0
    public private(set) var tracking = false
    public let threshold: Double
    public var armed: Bool { tracking && distance >= threshold }
    public static let wheelIdleInterval: Double = 0.35
    private var lastWheelTime: Double?
    public var usesWheel: Bool { lastWheelTime != nil }

    public init(threshold: Double = 70) { self.threshold = threshold }

    public mutating func cancel() { distance = 0; tracking = false; lastWheelTime = nil }

    /// Wheels have no release event. Treat a pause as release, preserving a rejected
    /// burst until it ends so scrolling up to the top cannot become a pull mid-burst.
    public mutating func handleWheel(dx: Double = 0, dy: Double, now: Double,
                                     atTop: Bool, eligible: Bool) {
        let beginning = lastWheelTime.map { now - $0 >= Self.wheelIdleInterval } ?? true
        if beginning { cancel() }
        lastWheelTime = now
        guard eligible, atTop, dy > 0, abs(dx) <= abs(dy) else {
            distance = 0; tracking = false
            return
        }
        if beginning { tracking = true }
        if tracking { distance += dy }
    }

    @discardableResult
    public mutating func finishWheelIfIdle(now: Double, atTop: Bool, eligible: Bool) -> Bool {
        guard let lastWheelTime, now - lastWheelTime >= Self.wheelIdleInterval else { return false }
        let refresh = armed && atTop && eligible
        cancel()
        return refresh
    }

    /// The gesture must start at the top; reaching it mid-scroll never arms a pull.
    @discardableResult
    public mutating func handle(phase: Phase, dx: Double = 0, dy: Double = 0,
                                atTop: Bool, eligible: Bool) -> Bool {
        guard eligible else { cancel(); return false }
        // Changing input devices cannot inherit an unfinished wheel pull.
        if lastWheelTime != nil { cancel() }
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
