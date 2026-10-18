import AppKit
import SwiftUI

/// Native About window mirroring the Animi pattern: banner, creator credit, prominent support button.
@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "About \(Constants.appName)"
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 360, height: 470))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    private let gradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.10, blue: 0.45), Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.13, green: 0.83, blue: 0.93)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                gradient
                    .overlay(
                        RadialGradient(colors: [Color.white.opacity(0.28), .clear], center: .init(x: 0.3, y: 0.2), startRadius: 0, endRadius: 220)
                    )
                    .frame(height: 118)
                appIcon
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                    .offset(y: 38)
            }
            .padding(.bottom, 38)

            VStack(spacing: 6) {
                Text(Constants.appName)
                    .font(.system(size: 22, weight: .semibold))
                Text("v\(Constants.version) · Universal Clipboard Manager for macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 2) {
                    Text("Created & designed by")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link(Constants.creatorName, destination: Constants.creatorProfileURL)
                        .font(.callout.weight(.semibold))
                }
                .padding(.top, 10)

                Text("Open source under the MIT License · Built with Swift, AppKit & SwiftUI")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(Constants.supportURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                        Text("Support \(Constants.creatorName)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.13, green: 0.83, blue: 0.93)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.13, green: 0.83, blue: 0.93).opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Button {
                    NSWorkspace.shared.open(Constants.githubRepoURL)
                } label: {
                    Text("View on GitHub")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.18)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            VStack(spacing: 4) {
                Text("Downloads are “pay what you want” — $0 is fine. Thank you for using \(Constants.appName)!")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("Copyright © 2026 \(Constants.creatorName)")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10.5))
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: 360)
    }

    private var appIcon: some View {
        Group {
            if let icon = NSApp.applicationIconImage, Bundle.main.bundleURL.pathExtension == "app" {
                Image(nsImage: icon).resizable()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient)
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
