import AppKit

// Entry point. `LSUIElement` in Info.plist hides the Dock icon for the bundled app; the explicit
// activation policy below keeps the bare binary behaving the same way during development.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
