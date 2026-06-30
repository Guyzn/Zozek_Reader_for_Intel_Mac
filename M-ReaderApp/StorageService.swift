import Foundation

/// 存储操作错误类型 — 不再静默吞错，上层自行决定处理策略
enum StorageError: Error, LocalizedError {
    case directoryCreationFailed(Error)
    case encodeFailed(Error)
    case writeFailed(Error)
    case readFailed(Error)
    case decodeFailed(Error)
    case noApplicationSupport

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let e): return "无法创建数据目录：\(e.localizedDescription)"
        case .encodeFailed(let e): return "数据编码失败：\(e.localizedDescription)"
        case .writeFailed(let e): return "写入磁盘失败：\(e.localizedDescription)"
        case .readFailed(let e): return "读取数据失败：\(e.localizedDescription)"
        case .decodeFailed(let e): return "数据解析失败：\(e.localizedDescription)"
        case .noApplicationSupport: return "无法访问 Application Support 目录"
        }
    }
}

/// 书架本地 JSON 持久化服务，使用 actor 保证并发安全
actor LibraryStorageService {
    private let libraryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("NovelReader")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        libraryURL = folder.appendingPathComponent("library.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [Book] {
        guard let data = try? Data(contentsOf: libraryURL) else { return [] }
        return (try? decoder.decode([Book].self, from: data)) ?? []
    }

    func save(_ books: [Book]) throws {
        let data = try encoder.encode(books)
        try data.write(to: libraryURL, options: .atomic)
    }
}

/// 书签持久化服务，使用 actor 保证并发安全
actor StorageService {
    static let shared = StorageService()

    private let bookmarkFilename = "bookmarks.json"

    private init() {}

    private func ensureAppSupport() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.noApplicationSupport
        }
        let folder = appSupport.appendingPathComponent("M-ReaderApp", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw StorageError.directoryCreationFailed(error)
        }
        return folder
    }

    // MARK: - 书签 CRUD

    func loadBookmarks() -> [MBookmark] {
        guard let folder = try? ensureAppSupport() else { return [] }
        let fileURL = folder.appendingPathComponent(bookmarkFilename)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([MBookmark].self, from: data)) ?? []
    }

    func saveBookmark(_ bookmark: MBookmark) throws {
        var all = loadBookmarks()
        all.append(bookmark)
        try writeBookmarks(all)
    }

    func deleteBookmark(id: UUID) throws {
        var all = loadBookmarks()
        all.removeAll { $0.id == id }
        try writeBookmarks(all)
    }

    func bookmarks(for bookID: UUID) -> [MBookmark] {
        loadBookmarks().filter { $0.bookID == bookID }
    }

    func saveAllBookmarks(_ bookmarks: [MBookmark]) throws {
        try writeBookmarks(bookmarks)
    }

    func updateBookmarkNote(id: UUID, note: String) throws {
        var all = loadBookmarks()
        if let idx = all.firstIndex(where: { $0.id == id }) {
            all[idx].note = note
            try writeBookmarks(all)
        }
    }

    private func writeBookmarks(_ bookmarks: [MBookmark]) throws {
        let folder = try ensureAppSupport()
        let fileURL = folder.appendingPathComponent(bookmarkFilename)
        let data: Data
        do {
            data = try JSONEncoder().encode(bookmarks)
        } catch {
            throw StorageError.encodeFailed(error)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StorageError.writeFailed(error)
        }
    }
}
