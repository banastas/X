import Foundation

public enum NavigationPolicy {
    public static func isX(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.port == nil || url.port == 443 else { return false }
        return ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(url.host?.lowercased() ?? "")
    }
    public static func isHome(_ url: URL?) -> Bool {
        isX(url) && url?.path == "/home"
    }
    public static func isAuthentication(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https" else { return false }
        return ["accounts.google.com", "appleid.apple.com"].contains(url.host?.lowercased() ?? "")
    }
    public static func mayOpenExternally(_ url: URL) -> Bool {
        ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }
}
