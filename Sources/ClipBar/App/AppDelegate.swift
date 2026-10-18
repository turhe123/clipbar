import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var storage: StorageManager!
    private var viewModel: ClipboardViewModel!
    private var panelController: PanelController!
    private var statusBar: StatusBarController!
    private let monitor = PasteboardMonitor()
    private let hotKey = HotKeyManager()
    private let ingestQueue = DispatchQueue(label: "\(Constants.bundleIdentifier).ingest", qos: .utility)

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(Constants.appName, isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            storage = try StorageManager(directory: Self.applicationSupportDirectory)
        } catch {
            let alert = NSAlert()
            alert.messageText = "\(Constants.appName) could not open its database"
            alert.informativeText = "\(error)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        storage.removeOrphanedBlobs()

        viewModel = ClipboardViewModel(storage: storage, monitor: monitor)
        viewModel.reload()
        panelController = PanelController(viewModel: viewModel)
        statusBar = StatusBarController(viewModel: viewModel, panelController: panelController)

        monitor.onCapture = { [weak self] clip in self?.ingest(clip) }
        monitor.start()

        hotKey.onHotKey = { [weak self] in self?.panelController.toggle() }
        if !hotKey.register() {
            NSLog("ClipBar: failed to register the global ⌘⇧V hotkey")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotKey.unregister()
    }

    private func ingest(_ clip: CapturedClip) {
        let storage = self.storage!
        ingestQueue.async { [weak self] in
            guard let result = storage.upsert(clip) else { return }
            onMain { self?.viewModel.apply(result) }
        }
    }
}
