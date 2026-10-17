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
    /// X serves feed images at reduced sizes. Ask its media host for the original instead.
    public static func fullSizeImage(_ url: URL) -> URL {
        guard url.scheme == "https", url.host?.lowercased() == "pbs.twimg.com", url.path.hasPrefix("/media/"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "name" }
        items.append(URLQueryItem(name: "name", value: "orig"))
        components.queryItems = items
        return components.url ?? url
    }
}
