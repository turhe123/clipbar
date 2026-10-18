import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum ClipFilter: String, CaseIterable, Identifiable {
    case all, text, code, colors, images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .code: return "Code"
        case .colors: return "Colors"
        case .images: return "Images"
        }
    }

    var kind: ClipKind? {
        switch self {
        case .all: return nil
        case .text: return .text
        case .code: return .code
        case .colors: return .color
        case .images: return .image
        }
    }

    /// ⌘1 … ⌘5
    var shortcutDigit: Int { (ClipFilter.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// Source of truth for the floating bar. Lives on the main actor; storage work is pushed off-thread by the app delegate.
@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { applyFilter(keepSelection: false) }
    }
    @Published var filter: ClipFilter = .all {
        didSet { applyFilter(keepSelection: false) }
    }
    @Published private(set) var filtered: [ClipItem] = []
    @Published var selectedIndex: Int = 0
    @Published var isMonitoringPaused = false
    /// Bumped every time the panel is shown so the search field re-grabs focus.
    @Published var focusToken: Int = 0

    private(set) var allItems: [ClipItem] = []
    let storage: StorageManager
    let imageStore: ImageStore
    private let monitor: PasteboardMonitor

    init(storage: StorageManager, monitor: PasteboardMonitor) {
        self.storage = storage
        self.imageStore = storage.imageStore
        self.monitor = monitor
    }

    // MARK: Derived state

    var selectedItem: ClipItem? {
        guard filtered.indices.contains(selectedIndex) else { return nil }
        return filtered[selectedIndex]
    }

    var totalCount: Int { allItems.count }

    func count(for filter: ClipFilter) -> Int {
        guard let kind = filter.kind else { return allItems.count }
        return allItems.reduce(into: 0) { if $1.kind == kind { $0 += 1 } }
    }

    // MARK: Loading & updates

    func reload() {
        allItems = storage.allItems()
        applyFilter(keepSelection: true)
    }

    func prepareForShow() {
        query = ""
        selectedIndex = 0
        focusToken += 1
    }

    func apply(_ result: StorageManager.UpsertResult) {
        switch result {
        case .inserted(let item), .bumped(let item):
            replace(item)
        }
    }

    private func replace(_ item: ClipItem) {
        allItems.removeAll { $0.id == item.id }
        allItems.append(item)
        sortAll()
        enforceInMemoryLimit()
        applyFilter(keepSelection: true)
    }

    private func sortAll() {
        allItems.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Mirrors the SQLite prune so the in-memory list never grows past the ring buffer.
    private func enforceInMemoryLimit() {
        var unpinnedSeen = 0
        allItems.removeAll { item in
            guard !item.isPinned else { return false }
            unpinnedSeen += 1
            return unpinnedSeen > Constants.maxItems
        }
    }

    private func applyFilter(keepSelection: Bool) {
        let previousID = keepSelection ? selectedItem?.id : nil
        var candidates = allItems
        if let kind = filter.kind {
            candidates = candidates.filter { $0.kind == kind }
        }
        let fuzzy = FuzzyMatcher.Query(query.trimmingCharacters(in: .whitespaces))
        if fuzzy.isEmpty {
            filtered = candidates
        } else {
            filtered = candidates
                .compactMap { item -> (ClipItem, Int)? in
                    let haystack = item.isImage ? item.preview.lowercased() + " " + (item.sourceAppName?.lowercased() ?? "") : item.searchText
                    guard let score = FuzzyMatcher.score(fuzzy, in: haystack) else { return nil }
                    return (item, score + (item.isPinned ? 50 : 0))
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        if let previousID, let index = filtered.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = filtered.isEmpty ? 0 : min(selectedIndex, filtered.count - 1)
        }
    }

    // MARK: Navigation

    func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
    }

    func selectFirst() { selectedIndex = 0 }
    func selectLast() { selectedIndex = max(0, filtered.count - 1) }

    func cycleFilter(by delta: Int) {
        let cases = ClipFilter.allCases
        let index = cases.firstIndex(of: filter) ?? 0
        filter = cases[(index + delta + cases.count) % cases.count]
    }

    // MARK: Actions

    /// Writes an item to the system pasteboard and moves it to the top of the history.
    func copyToPasteboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if item.isImage {
            if let file = item.imageFile, let data = imageStore.imageData(named: file) {
                pasteboard.setData(data, forType: .png)
            }
        } else {
            let text = item.isTruncated ? (storage.fullContent(id: item.id) ?? item.content) : item.content
            pasteboard.setString(text, forType: .string)
        }
        monitor.ignoreCurrentChange()
        if let touched = storage.touch(id: item.id) {
            replace(touched)
        }
    }

    func togglePin(_ item: ClipItem) {
        if let updated = storage.setPinned(id: item.id, !item.isPinned) {
            replace(updated)
            if let index = filtered.firstIndex(where: { $0.id == updated.id }) { selectedIndex = index }
        }
    }

    func delete(_ item: ClipItem) {
        storage.delete(id: item.id)
        allItems.removeAll { $0.id == item.id }
        let previous = selectedIndex
        applyFilter(keepSelection: false)
        selectedIndex = filtered.isEmpty ? 0 : min(previous, filtered.count - 1)
    }

    func clearUnpinned() {
        storage.clearUnpinned()
        reload()
    }

    func setMonitoringPaused(_ paused: Bool) {
        monitor.isPaused = paused
        isMonitoringPaused = paused
    }
}
