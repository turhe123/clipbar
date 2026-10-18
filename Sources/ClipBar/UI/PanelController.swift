import AppKit
import Carbon
import SwiftUI

/// Owns the floating panel, positions it like Spotlight, and routes keyboard shortcuts to the view model.
@MainActor
final class PanelController {
    let panel: FloatingPanel
    let viewModel: ClipboardViewModel

    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var isPresented = false

    init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Constants.panelSize))

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: Constants.panelSize))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: ClipboardBarView(viewModel: viewModel, controller: self))
        hosting.frame = effectView.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        effectView.addSubview(hosting)
        panel.contentView = effectView

        panel.onResignKey = { [weak self] in
            // Defer so a click inside the panel that briefly shuffles responders doesn't dismiss it.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPresented, !self.panel.isKeyWindow else { return }
                self.hide()
            }
        }
        panel.onCancel = { [weak self] in self?.hide() }
    }

    // MARK: Presentation

    func toggle() {
        isPresented ? hide() : show()
    }

    func show() {
        guard !isPresented else { return }
        isPresented = true
        viewModel.reload()
        viewModel.prepareForShow()
        positionPanel()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installMonitors()
        // The hosting view needs a run-loop turn before SwiftUI focus can land in the text field.
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.focusToken += 1
        }
    }

    func hide() {
        guard isPresented else { return }
        isPresented = false
        removeMonitors()
        panel.orderOut(nil)
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = Constants.panelSize
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - visible.height * 0.16
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    // MARK: Actions

    /// Copies the selected item and, when Accessibility is granted and `paste` is true, pastes it into the previous app.
    func activateSelected(paste: Bool) {
        guard let item = viewModel.selectedItem else { return }
        activate(item, paste: paste)
    }

    func activate(_ item: ClipItem, paste: Bool) {
        hide()
        viewModel.copyToPasteboard(item)
        guard paste, PasteHelper.isAccessibilityTrusted else { return }
        // Give the previous key window a beat to regain focus before the synthetic ⌘V lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            PasteHelper.sendPasteKeystroke()
        }
    }

    func openSupportPage() {
        NSWorkspace.shared.open(Constants.supportURL)
    }

    // MARK: Event monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented else { return event }
            return self.handle(keyEvent: event) ? nil : event
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            onMain { self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(keyEvent event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let hasShift = flags.contains(.shift)
        let key = Int(event.keyCode)

        switch key {
        case kVK_Escape:
            hide()
            return true
        case kVK_UpArrow:
            hasCommand ? viewModel.selectFirst() : viewModel.moveSelection(by: -1)
            return true
        case kVK_DownArrow:
            hasCommand ? viewModel.selectLast() : viewModel.moveSelection(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelected(paste: !hasOption)
            return true
        case kVK_Tab:
            viewModel.cycleFilter(by: hasShift ? -1 : 1)
            return true
        case kVK_Delete where hasCommand:
            if let item = viewModel.selectedItem { viewModel.delete(item) }
            return true
        case kVK_PageUp:
            viewModel.selectFirst()
            return true
        case kVK_PageDown:
            viewModel.selectLast()
            return true
        default:
            break
        }

        guard hasCommand, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch characters {
        case "p":
            if let item = viewModel.selectedItem { viewModel.togglePin(item) }
            return true
        case "w":
            hide()
            return true
        case "1", "2", "3", "4", "5":
            if let digit = Int(characters), ClipFilter.allCases.indices.contains(digit - 1) {
                viewModel.filter = ClipFilter.allCases[digit - 1]
            }
            return true
        default:
            return false
        }
    }
}
