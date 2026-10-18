import Carbon
import Foundation

/// Registers the global ⌘⇧V hotkey through Carbon's `RegisterEventHotKey`,
/// which works from a sandboxed-free accessory app without any Accessibility permission.
final class HotKeyManager {
    var onHotKey: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyIdentifier: UInt32 = 1
    private static let signature: OSType = {
        "CLPB".utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }()

    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == HotKeyManager.signature, hotKeyID.id == manager.hotKeyIdentifier else {
                return OSStatus(eventNotHandledErr)
            }
            onMain { manager.onHotKey?() }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(), handler, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotKeyIdentifier)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return registerStatus == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit {
        unregister()
    }
}
