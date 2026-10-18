import Foundation

/// What kind of thing a clipboard entry is. Drives rendering and the filter tabs.
enum ClipKind: String, CaseIterable, Codable, Sendable {
    case text
    case code
    case color
    case image

    var title: String {
        switch self {
        case .text: return "Text"
        case .code: return "Code"
        case .color: return "Color"
        case .image: return "Image"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        }
    }
}

/// A lightweight, in-memory representation of one history entry.
///
/// Text content is truncated to `Constants.inMemoryTextLimit`; the full payload stays in SQLite
/// and is fetched on demand when the item is pasted. Image pixels never live here — only file names.
struct ClipItem: Identifiable, Hashable, Sendable {
    let id: Int64
    var kind: ClipKind
    /// Truncated text content (empty for images).
    var content: String
    /// Lower-cased copy of `content` used for instant search.
    var searchText: String
    /// True when `content` was cut short and the full payload must be fetched from storage.
    var isTruncated: Bool
    /// Single-line preview shown in the list.
    var preview: String
    var contentHash: String
    /// File names (relative to the blobs directory) for image items.
    var imageFile: String?
    var thumbFile: String?
    var imageWidth: Int
    var imageHeight: Int
    /// Size of the original payload in bytes.
    var byteSize: Int
    /// Total character count of the full text payload.
    var characterCount: Int
    var sourceBundleID: String?
    var sourceAppName: String?
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    var isImage: Bool { kind == .image }

    /// A short human description used in subtitles and accessibility labels.
    var detailSummary: String {
        if isImage {
            return "\(imageWidth) × \(imageHeight) · \(ByteCountFormatter.compact(byteSize))"
        }
        let lines = max(1, content.reduce(into: 0) { if $1 == "\n" { $0 += 1 } } + (content.isEmpty ? 0 : 1))
        if lines > 1 {
            return "\(characterCount) chars · \(isTruncated ? "\(lines)+" : "\(lines)") lines"
        }
        return "\(characterCount) chars"
    }
}

/// A fresh capture coming off the pasteboard, before it has been persisted.
struct CapturedClip: Sendable {
    enum Payload: Sendable {
        case text(String, kind: ClipKind)
        case image(Data, uti: String)
    }

    let payload: Payload
    let sourceBundleID: String?
    let sourceAppName: String?
    let capturedAt: Date
}

extension ByteCountFormatter {
    static func compact(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Compact "time ago" rendering used in list subtitles.
enum RelativeTime {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        case ..<604_800: return "\(Int(seconds / 86_400))d ago"
        default: return dateFormatter.string(from: date)
        }
    }
}
