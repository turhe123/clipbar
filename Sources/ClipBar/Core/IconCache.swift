import AppKit

/// Resolves and caches small app icons for source bundle identifiers.
@MainActor
final class IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let missing = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Unknown app")

    private init() {
        cache.countLimit = 64
    }

    func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return missing }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return missing }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        cache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}
