import AppKit
import ApplicationServices
import Carbon

/// Optional "paste into the frontmost app" support. Requires the Accessibility permission;
/// when it isn't granted ClipBar silently falls back to copy-only.
enum PasteHelper {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the system Accessibility dialog (only shows once per app signature).
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Posts a synthetic ⌘V key press to the system event stream.
    static func sendPasteKeystroke() {
        guard isAccessibilityTrusted, let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
