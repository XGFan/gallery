import Foundation

/// Where the library lives.
///
/// There is no login flow and no credential storage: the backend sits behind
/// tinyauth with a LAN/easytier IP bypass, so on a trusted network the client
/// just talks to it. See docs/adr/0004.
enum AppConfig {
    static let defaultBaseURL = URL(string: "https://gallery.test4x.com")!

    private static let overrideKey = "gallery.baseURL"

    /// An override is useful for pointing the simulator at a locally running
    /// backend; absent one, production is the default.
    static var baseURL: URL {
        get {
            guard let raw = UserDefaults.standard.string(forKey: overrideKey),
                  let url = URL(string: raw)
            else { return defaultBaseURL }
            return url
        }
        set { UserDefaults.standard.set(newValue.absoluteString, forKey: overrideKey) }
    }
}
