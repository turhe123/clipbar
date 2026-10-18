import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum StorageError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)

    var description: String {
        switch self {
        case .open(let message): return "Could not open database: \(message)"
        case .prepare(let message): return "Could not prepare statement: \(message)"
        case .step(let message): return "Statement failed: \(message)"
        }
    }
}

/// Thin, dependency-free SQLite3 layer. All access is serialised on a private queue,
/// so the API is safe to call from any thread.
final class StorageManager: @unchecked Sendable {
    enum UpsertResult: Sendable {
        case inserted(ClipItem)
        case bumped(ClipItem)
    }

    let directory: URL
    let imageStore: ImageStore
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "\(Constants.bundleIdentifier).storage", qos: .userInitiated)

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        imageStore = ImageStore(blobsDirectory: directory.appendingPathComponent("Blobs", isDirectory: true))

        let path = directory.appendingPathComponent("clipbar.sqlite").path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw StorageError.open(message)
        }
        db = handle
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute(Self.schema)
    }

    deinit {
        sqlite3_close(db)
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        preview TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL UNIQUE,
        image_file TEXT,
        thumb_file TEXT,
        image_width INTEGER NOT NULL DEFAULT 0,
        image_height INTEGER NOT NULL DEFAULT 0,
        byte_size INTEGER NOT NULL DEFAULT 0,
        char_count INTEGER NOT NULL DEFAULT 0,
        source_bundle_id TEXT,
        source_app_name TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_items_order ON items(is_pinned DESC, updated_at DESC);
    """

    private static let selectColumns = """
    id, kind, substr(content, 1, \(Constants.inMemoryTextLimit)), preview, content_hash, image_file, thumb_file,
    image_width, image_height, byte_size, char_count, source_bundle_id, source_app_name, is_pinned, created_at, updated_at
    """

    // MARK: Public API

    func allItems() -> [ClipItem] {
        queue.sync {
            (try? query("SELECT \(Self.selectColumns) FROM items ORDER BY is_pinned DESC, updated_at DESC")) ?? []
        }
    }

    func item(id: Int64) -> ClipItem? {
        queue.sync { fetch(id: id) }
    }

    /// Full text payload for an item (may be large; only call when pasting).
    func fullContent(id: Int64) -> String? {
        queue.sync {
            (try? query("SELECT content FROM items WHERE id = ?", bind: [.int(id)]) { stmt in
                Self.columnText(stmt, 0) ?? ""
            })?.first
        }
    }

    /// Inserts a new item, or — when an identical payload already exists — bumps it to the top.
    func upsert(_ captured: CapturedClip) -> UpsertResult? {
        queue.sync {
            do {
                switch captured.payload {
                case .text(let text, let kind):
                    let hash = "t:" + ContentHasher.sha256(text)
                    if let existing = existingID(hash: hash) {
                        try bump(id: existing, captured: captured)
                        return fetch(id: existing).map(UpsertResult.bumped)
                    }
                    let id = try insert(
                        kind: kind, content: text, preview: ContentClassifier.makePreview(from: text), hash: hash,
                        image: nil, byteSize: text.utf8.count, charCount: text.count, captured: captured
                    )
                    try prune()
                    return fetch(id: id).map(UpsertResult.inserted)

                case .image(let data, let uti):
                    let hash = "i:" + ContentHasher.sha256(data)
                    if let existing = existingID(hash: hash) {
                        try bump(id: existing, captured: captured)
                        return fetch(id: existing).map(UpsertResult.bumped)
                    }
                    let stored = try imageStore.store(data: data, uti: uti, hash: String(hash.dropFirst(2)))
                    let id = try insert(
                        kind: .image, content: "", preview: "Image \(stored.width) × \(stored.height)", hash: hash,
                        image: stored, byteSize: stored.byteSize, charCount: 0, captured: captured
                    )
                    try prune()
                    return fetch(id: id).map(UpsertResult.inserted)
                }
            } catch {
                NSLog("ClipBar storage error: \(error)")
                return nil
            }
        }
    }

    /// Moves an item to the top of the history (used after pasting from the panel).
    func touch(id: Int64) -> ClipItem? {
        queue.sync {
            try? run("UPDATE items SET updated_at = ? WHERE id = ?", bind: [.double(Date().timeIntervalSince1970), .int(id)])
            return fetch(id: id)
        }
    }

    func setPinned(id: Int64, _ pinned: Bool) -> ClipItem? {
        queue.sync {
            try? run("UPDATE items SET is_pinned = ? WHERE id = ?", bind: [.int(pinned ? 1 : 0), .int(id)])
            try? prune()
            return fetch(id: id)
        }
    }

    func delete(id: Int64) {
        queue.sync {
            let files = (try? query("SELECT image_file, thumb_file FROM items WHERE id = ?", bind: [.int(id)]) { stmt in
                [Self.columnText(stmt, 0), Self.columnText(stmt, 1)].compactMap { $0 }
            })?.flatMap { $0 } ?? []
            try? run("DELETE FROM items WHERE id = ?", bind: [.int(id)])
            imageStore.delete(files: files)
        }
    }

    func clearUnpinned() {
        queue.sync {
            let files = (try? query("SELECT image_file, thumb_file FROM items WHERE is_pinned = 0") { stmt in
                [Self.columnText(stmt, 0), Self.columnText(stmt, 1)].compactMap { $0 }
            })?.flatMap { $0 } ?? []
            try? run("DELETE FROM items WHERE is_pinned = 0")
            imageStore.delete(files: files)
        }
    }

    /// Deletes blob files on disk that no row references any more.
    func removeOrphanedBlobs() {
        queue.async {
            let referenced = (try? self.query("SELECT image_file, thumb_file FROM items WHERE image_file IS NOT NULL") { stmt in
                [Self.columnText(stmt, 0), Self.columnText(stmt, 1)].compactMap { $0 }
            })?.flatMap { $0 } ?? []
            self.imageStore.pruneOrphans(keeping: Set(referenced))
        }
    }

    // MARK: Internals (always on `queue`)

    private func existingID(hash: String) -> Int64? {
        (try? query("SELECT id FROM items WHERE content_hash = ?", bind: [.text(hash)]) { sqlite3_column_int64($0, 0) })?.first
    }

    private func bump(id: Int64, captured: CapturedClip) throws {
        try run(
            "UPDATE items SET updated_at = ?, source_bundle_id = ?, source_app_name = ? WHERE id = ?",
            bind: [.double(captured.capturedAt.timeIntervalSince1970), .optionalText(captured.sourceBundleID), .optionalText(captured.sourceAppName), .int(id)]
        )
    }

    private func insert(kind: ClipKind, content: String, preview: String, hash: String, image: ImageStore.StoredImage?,
                        byteSize: Int, charCount: Int, captured: CapturedClip) throws -> Int64 {
        let now = captured.capturedAt.timeIntervalSince1970
        try run(
            """
            INSERT INTO items (kind, content, preview, content_hash, image_file, thumb_file, image_width, image_height,
                               byte_size, char_count, source_bundle_id, source_app_name, is_pinned, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
            """,
            bind: [
                .text(kind.rawValue), .text(content), .text(preview), .text(hash),
                .optionalText(image?.imageFile), .optionalText(image?.thumbFile),
                .int(Int64(image?.width ?? 0)), .int(Int64(image?.height ?? 0)),
                .int(Int64(byteSize)), .int(Int64(charCount)),
                .optionalText(captured.sourceBundleID), .optionalText(captured.sourceAppName),
                .double(now), .double(now),
            ]
        )
        return sqlite3_last_insert_rowid(db)
    }

    /// Enforces the ring buffer: unpinned rows beyond `Constants.maxItems` are removed along with their blobs.
    private func prune() throws {
        struct Victim { let id: Int64; let files: [String] }
        let victims = try query(
            "SELECT id, image_file, thumb_file FROM items WHERE is_pinned = 0 ORDER BY updated_at DESC LIMIT -1 OFFSET ?",
            bind: [.int(Int64(Constants.maxItems))]
        ) { stmt in
            Victim(id: sqlite3_column_int64(stmt, 0), files: [Self.columnText(stmt, 1), Self.columnText(stmt, 2)].compactMap { $0 })
        }
        guard !victims.isEmpty else { return }
        for victim in victims {
            try run("DELETE FROM items WHERE id = ?", bind: [.int(victim.id)])
        }
        imageStore.delete(files: victims.flatMap(\.files))
    }

    private func fetch(id: Int64) -> ClipItem? {
        (try? query("SELECT \(Self.selectColumns) FROM items WHERE id = ?", bind: [.int(id)]))?.first
    }

    private func query(_ sql: String, bind: [Binding] = []) throws -> [ClipItem] {
        try query(sql, bind: bind, map: Self.item(from:))
    }

    private static func item(from stmt: OpaquePointer) -> ClipItem {
        let content = columnText(stmt, 2) ?? ""
        let charCount = Int(sqlite3_column_int64(stmt, 10))
        return ClipItem(
            id: sqlite3_column_int64(stmt, 0),
            kind: ClipKind(rawValue: columnText(stmt, 1) ?? "") ?? .text,
            content: content,
            searchText: content.lowercased(),
            isTruncated: charCount > content.count,
            preview: columnText(stmt, 3) ?? "",
            contentHash: columnText(stmt, 4) ?? "",
            imageFile: columnText(stmt, 5),
            thumbFile: columnText(stmt, 6),
            imageWidth: Int(sqlite3_column_int64(stmt, 7)),
            imageHeight: Int(sqlite3_column_int64(stmt, 8)),
            byteSize: Int(sqlite3_column_int64(stmt, 9)),
            characterCount: charCount,
            sourceBundleID: columnText(stmt, 11),
            sourceAppName: columnText(stmt, 12),
            isPinned: sqlite3_column_int64(stmt, 13) != 0,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15))
        )
    }

    // MARK: SQLite plumbing

    enum Binding {
        case int(Int64)
        case double(Double)
        case text(String)
        case optionalText(String?)
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw StorageError.step(message)
        }
    }

    private func prepare(_ sql: String, bind: [Binding]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw StorageError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        for (offset, value) in bind.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(statement, index, v)
            case .double(let v): sqlite3_bind_double(statement, index, v)
            case .text(let v): sqlite3_bind_text(statement, index, v, -1, sqliteTransient)
            case .optionalText(let v):
                if let v { sqlite3_bind_text(statement, index, v, -1, sqliteTransient) } else { sqlite3_bind_null(statement, index) }
            }
        }
        return statement
    }

    private func run(_ sql: String, bind: [Binding] = []) throws {
        let statement = try prepare(sql, bind: bind)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query<T>(_ sql: String, bind: [Binding] = [], map: (OpaquePointer) -> T) throws -> [T] {
        let statement = try prepare(sql, bind: bind)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(map(statement))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw StorageError.step(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }
}
