import AppKit
import SwiftUI

/// The whole Spotlight-style bar: search, filter tabs, list + preview, footer.
struct ClipboardBarView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let controller: PanelController?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.4)
            filterTabs
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.focusToken) { searchFocused = true }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .regular))
                .focused($searchFocused)
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            if viewModel.isMonitoringPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18), in: Capsule())
            }
            KeyCap("esc")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: Filter tabs

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(ClipFilter.allCases) { filter in
                let active = viewModel.filter == filter
                Button {
                    viewModel.filter = filter
                } label: {
                    HStack(spacing: 5) {
                        Text(filter.title)
                        Text("\(viewModel.count(for: filter))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(active ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.7))
                    }
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(active ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("\(filter.title)  ⌘\(filter.shortcutDigit)")
            }
            Spacer()
            Text(viewModel.filtered.count == viewModel.totalCount
                 ? "\(viewModel.totalCount) items"
                 : "\(viewModel.filtered.count) of \(viewModel.totalCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.filtered.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                itemList
                    .frame(maxWidth: .infinity)
                Divider().opacity(0.4)
                PreviewPane(item: viewModel.selectedItem, imageStore: viewModel.imageStore)
                    .frame(width: 262)
            }
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.filtered.enumerated()), id: \.element.id) { index, item in
                        ClipItemRow(item: item, isSelected: index == viewModel.selectedIndex, imageStore: viewModel.imageStore)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                viewModel.selectedIndex = index
                                controller?.activate(item, paste: true)
                            }
                            .onTapGesture {
                                viewModel.selectedIndex = index
                            }
                            .contextMenu { rowContextMenu(for: item) }
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.selectedIndex) {
                if let item = viewModel.selectedItem {
                    proxy.scrollTo(item.id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(for item: ClipItem) -> some View {
        Button("Paste") { controller?.activate(item, paste: true) }
        Button("Copy only") { controller?.activate(item, paste: false) }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
        Button("Delete", role: .destructive) { viewModel.delete(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.query.isEmpty ? "Nothing here yet" : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(viewModel.query.isEmpty
                 ? "Copy something and it will show up here. ClipBar keeps your last \(Constants.maxItems) items."
                 : "Try a shorter query or another tab.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            FooterHint(keys: "↑↓", label: "Navigate")
            FooterHint(keys: "↩", label: PasteHelper.isAccessibilityTrusted ? "Paste" : "Copy")
            FooterHint(keys: "⌘P", label: "Pin")
            FooterHint(keys: "⌘⌫", label: "Delete")
            FooterHint(keys: "⇥", label: "Tabs")
            Spacer()
            Button {
                controller?.openSupportPage()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Support")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(colors: [Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.13, green: 0.83, blue: 0.93)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
                .shadow(color: Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .help("Support the developer on Ko-fi")
            .accessibilityLabel("Support the developer")
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }
}

// MARK: - Row

struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let imageStore: ImageStore

    var body: some View {
        HStack(spacing: 10) {
            appIcon
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview.isEmpty ? " " : item.preview)
                    .font(item.kind == .code ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(45))
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.title): \(item.preview)")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let app = item.sourceAppName, !app.isEmpty { parts.append(app) }
        parts.append(RelativeTime.string(from: item.updatedAt))
        parts.append(item.detailSummary)
        return parts.joined(separator: " · ")
    }

    private var appIcon: some View {
        Group {
            if let icon = IconCache.shared.icon(forBundleID: item.sourceBundleID) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app")
            }
        }
        .frame(width: 20, height: 20)
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .color:
            ColorSwatch(text: item.content, size: 22)
        case .image:
            if let file = item.thumbFile, let thumb = imageStore.thumbnail(named: file) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
            } else {
                KindBadge(kind: .image)
            }
        case .code, .text:
            KindBadge(kind: item.kind)
        }
    }
}

struct KindBadge: View {
    let kind: ClipKind

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ColorSwatch: View {
    let text: String
    var size: CGFloat = 22

    var body: some View {
        let parsed = ContentClassifier.parseColor(text)
        let color = parsed.map { Color(red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) } ?? .gray
        ZStack {
            Checkerboard()
                .clipShape(Circle())
            Circle().fill(color)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: color.opacity(0.5), radius: 3)
        .accessibilityLabel("Color swatch \(text)")
    }
}

/// Transparency backdrop so alpha colors read correctly.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 4
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var column = 0
                while x < size.width {
                    let shade = (row + column) % 2 == 0 ? 0.85 : 0.55
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: shade)))
                    x += cell
                    column += 1
                }
                y += cell
                row += 1
            }
        }
    }
}

// MARK: - Preview pane

struct PreviewPane: View {
    let item: ClipItem?
    let imageStore: ImageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                ScrollView {
                    previewBody(for: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                Divider().opacity(0.4)
                metadata(for: item)
            } else {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func previewBody(for item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            VStack(alignment: .leading, spacing: 8) {
                if let file = item.thumbFile, let thumb = imageStore.thumbnail(named: file) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: Constants.thumbnailMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
                } else {
                    KindBadge(kind: .image)
                }
                Text("\(item.imageWidth) × \(item.imageHeight) px · PNG")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .color:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ColorSwatch(text: item.content, size: 44)
                    Text(item.content.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let parsed = ContentClassifier.parseColor(item.content) {
                    Text(colorDescription(parsed))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        case .code:
            Text(item.content)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
        case .text:
            Text(item.content)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
        }
    }

    private func colorDescription(_ color: ParsedColor) -> String {
        let r = Int((color.red * 255).rounded()), g = Int((color.green * 255).rounded()), b = Int((color.blue * 255).rounded())
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let rgb = color.alpha < 1 ? "rgba(\(r), \(g), \(b), \(String(format: "%.2f", color.alpha)))" : "rgb(\(r), \(g), \(b))"
        return "\(hex)\n\(rgb)"
    }

    private func metadata(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let icon = IconCache.shared.icon(forBundleID: item.sourceBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(item.sourceAppName ?? "Unknown app")
                    .lineLimit(1)
                Spacer()
                Text(item.kind.title)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            Text("\(item.detailSummary) · \(RelativeTime.string(from: item.updatedAt))\(item.isTruncated ? " · preview truncated" : "")")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Small pieces

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct FooterHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            KeyCap(keys)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}
