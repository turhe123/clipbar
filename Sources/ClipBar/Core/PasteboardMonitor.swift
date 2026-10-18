import AppKit
import Foundation
import UniformTypeIdentifiers

/// Watches `NSPasteboard.general` with a cheap, low-frequency background timer.
///
/// The hot path only compares `changeCount` and returns — the actual pasteboard read happens on
/// the main thread, and hashing/thumbnailing happens on the ingestion queue owned by the app delegate.
final class PasteboardMonitor {
    /// Called on the main thread with every new capture.
    var onCapture: (@MainActor (CapturedClip) -> Void)?

    private let pasteboard = NSPasteboard.general
    private let queue = DispatchQueue(label: "\(Constants.bundleIdentifier).monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private let lock = NSLock()
    private var _isPaused = false

    var isPaused: Bool {
        get { lock.withLock { _isPaused } }
        set { lock.withLock { _isPaused = newValue } }
    }

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + Constants.pollInterval, repeating: Constants.pollInterval, leeway: Constants.pollLeeway)
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Call right after ClipBar itself writes to the pasteboard so that write isn't re-captured.
    func ignoreCurrentChange() {
        lock.withLock { lastChangeCount = pasteboard.changeCount }
    }

    // MARK: Polling

    private func tick() {
        let current = pasteboard.changeCount
        let changed: Bool = lock.withLock {
            guard current != lastChangeCount else { return false }
            lastChangeCount = current
            return true
        }
        guard changed, !isPaused else { return }
        onMain { [weak self] in self?.readPasteboard(expectedChangeCount: current) }
    }

    @MainActor
    private func readPasteboard(expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return } // superseded; next tick will pick it up
        guard let types = pasteboard.types, !types.isEmpty else { return }

        // Privacy markers: password managers and transient/auto-generated data.
        if types.contains(where: { Constants.privacyPasteboardTypes.contains($0.rawValue) }) { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier
        let appName = frontmost?.localizedName

        guard let payload = extractPayload(types: types, sourceBundleID: bundleID) else { return }
        let clip = CapturedClip(payload: payload, sourceBundleID: bundleID, sourceAppName: appName, capturedAt: Date())
        onCapture?(clip)
    }

    private func extractPayload(types: [NSPasteboard.PasteboardType], sourceBundleID: String?) -> CapturedClip.Payload? {
        let hasPNG = types.contains(.png)
        let hasTIFF = types.contains(.tiff)
        let hasImage = hasPNG || hasTIFF

        var text = pasteboard.string(forType: .string)
        if text == nil, types.contains(.fileURL) {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            if !urls.isEmpty { text = urls.map(\.path).joined(separator: "\n") }
        }
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Prefer the image unless the text is "real" content (e.g. spreadsheet cells also ship a TIFF snapshot).
        let textIsSubstantial = !trimmedText.isEmpty && !(trimmedText.count < 2_048 && !trimmedText.contains("\n") && trimmedText.contains("://"))
        if hasImage && (trimmedText.isEmpty || !textIsSubstantial) {
            if hasPNG, let data = pasteboard.data(forType: .png), !data.isEmpty {
                return .image(data, uti: UTType.png.identifier)
            }
            if hasTIFF, let data = pasteboard.data(forType: .tiff), !data.isEmpty {
                return .image(data, uti: UTType.tiff.identifier)
            }
        }

        guard var content = text, !trimmedText.isEmpty else { return nil }
        if content.count > Constants.maxCapturedTextLength {
            content = String(content.prefix(Constants.maxCapturedTextLength))
        }
        let kind = ContentClassifier.classify(text: content, sourceBundleID: sourceBundleID)
        return .text(content, kind: kind)
    }
}
