import Foundation

/// The automatic-refresh intervals offered in Settings, and how the status strip words them.
public enum RefreshInterval {
    public static let choices: [Double] = [60, 120, 300, 600]
    public static let standard: Double = 60

    /// A stored preference outside the offered choices falls back to the standard minute.
    public static func validated(_ seconds: Double) -> Double {
        choices.contains(seconds) ? seconds : standard
    }

    /// "every minute", "every 2 minutes".
    public static func phrase(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes <= 1 ? "every minute" : "every \(minutes) minutes"
    }

    /// "1 minute", "5 minutes", for the Settings picker.
    public static func name(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// The countdown: "42s" under a minute, "4:05" from a minute up.
    public static func remaining(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
