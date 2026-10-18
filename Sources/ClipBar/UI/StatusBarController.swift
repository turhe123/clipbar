import AppKit
import ServiceManagement

/// Menu-bar presence: the only persistent UI of an `LSUIElement` app.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let viewModel: ClipboardViewModel
    private let panelController: PanelController
    private let aboutWindow = AboutWindowController()

    private let pauseItem = NSMenuItem(title: "Pause Monitoring", action: #selector(togglePause), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Enable Auto-Paste (Accessibility)…", action: #selector(requestAccessibility), keyEquivalent: "")

    init(viewModel: ClipboardViewModel, panelController: PanelController) {
        self.viewModel = viewModel
        self.panelController = panelController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: Constants.appName)
            button.image?.isTemplate = true
            button.toolTip = "\(Constants.appName) — ⌘⇧V"
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let open = NSMenuItem(title: "Open \(Constants.appName)", action: #selector(openPanel), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(open)
        menu.addItem(.separator())

        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Clear Unpinned History…", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(.separator())

        menu.addItem(launchAtLoginItem)
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "About \(Constants.appName)", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(openReleases), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "View on GitHub", action: #selector(openGitHub), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "♥ Support the Developer", action: #selector(openSupport), keyEquivalent: ""))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit \(Constants.appName)", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        return menu
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.title = viewModel.isMonitoringPaused ? "Resume Monitoring" : "Pause Monitoring"
        pauseItem.state = viewModel.isMonitoringPaused ? .on : .off
        launchAtLoginItem.state = launchAtLoginEnabled ? .on : .off
        launchAtLoginItem.isEnabled = Bundle.main.bundleIdentifier != nil
        accessibilityItem.state = PasteHelper.isAccessibilityTrusted ? .on : .off
        accessibilityItem.title = PasteHelper.isAccessibilityTrusted ? "Auto-Paste Enabled" : "Enable Auto-Paste (Accessibility)…"
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: Actions

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func togglePause() {
        viewModel.setMonitoringPaused(!viewModel.isMonitoringPaused)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All unpinned items and their images will be deleted. Pinned items are kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.clearUnpinned()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change Launch at Login"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func requestAccessibility() {
        if PasteHelper.isAccessibilityTrusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            PasteHelper.requestAccessibility()
        }
    }

    @objc private func showAbout() {
        aboutWindow.show()
    }

    @objc private func openReleases() { NSWorkspace.shared.open(Constants.releasesURL) }
    @objc private func openGitHub() { NSWorkspace.shared.open(Constants.githubRepoURL) }
    @objc private func openSupport() { NSWorkspace.shared.open(Constants.supportURL) }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
