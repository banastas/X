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
    /// An X link in text from another app (Services, a dropped link): bare "x.com/…" gets
    /// https, http is upgraded, and anything that isn't an X address is refused.
    public static func xLink(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }
        if !value.contains("://") { value = "https://" + value }
        guard var components = URLComponents(string: value) else { return nil }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        guard let url = components.url, isX(url) else { return nil }
        return url
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
