import Foundation

/// Which copies of the app update themselves. Only a published build carries a feed
/// (scripts/release.sh adds SUFeedURL), so a copy someone builds from source never offers
/// to replace itself. A published copy updates only once installed in an Applications folder.
public enum UpdatePolicy {
    public static func runsUpdater(bundlePath: String, feedURL: String?, homeDirectory: String) -> Bool {
        guard let feedURL, let url = URL(string: feedURL), url.scheme == "https", url.host != nil else { return false }
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return ["/Applications/", home + "/Applications/"].contains { bundlePath.hasPrefix($0) }
    }
}
