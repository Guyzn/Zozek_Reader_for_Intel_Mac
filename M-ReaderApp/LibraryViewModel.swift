import Foundation
import SwiftUI

/// 书架视图模型：管理书籍列表、导入、持久化与最近打开
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var selectedBook: Book?
    @Published var selectedBookID: UUID?
    @Published var isLoading = false
    @Published var errorMessage: MAlertMessage?

    private let libraryStorage = LibraryStorageService()
    private let fileManager = FileManager.default

    /// App 容器内 Books 目录（~/Library/Containers/.../Data/Application Support/M-ReaderApp/Books/）
    private var booksDirectoryURL: URL {
        let appSupport = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("M-ReaderApp", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 根据 Book 推导容器内副本路径（命名规则：<id.uuidString>.<fileType.rawValue>）
    private func localFileURL(for book: Book) -> URL {
        booksDirectoryURL
            .appendingPathComponent("\(book.id.uuidString).\(book.fileType.rawValue)")
    }

    init() {
        Task { books = await libraryStorage.load() }
    }

    /// 通过文件 URL 添加一本书。
    /// 必须在 NSOpenPanel 回调的同步上下文中调用，
    /// 在 URL 的临时沙盒授权失效前完成文件读取。
    func addBook(from url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["epub", "txt", "docx"].contains(ext) else {
            errorMessage = MAlertMessage(text: "不支持的文件格式：\(url.pathExtension)")
            return
        }

        // NSOpenPanel 返回的 URL 需要显式启动安全域访问才能在沙盒下读取
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            NSLog("[阻只读书] addBook 同步读取文件成功: \(url.lastPathComponent), \(data.count) bytes")
            addBook(data: data, filename: url.lastPathComponent, originalURL: url)
        } catch {
            let nsError = error as NSError
            NSLog("[阻只读书] addBook 同步读取文件失败: \(nsError.domain) code=\(nsError.code)")
            errorMessage = MAlertMessage(text: "无法读取文件：\(error.localizedDescription)\n(domain: \(nsError.domain), code: \(nsError.code))")
        }
    }

    /// 从内存 Data 添加书籍，保存副本到 App 容器内，不再依赖 bookmark。
    /// - Parameters:
    ///   - data: 文件内容（已在 NSOpenPanel 回调中同步读取）
    ///   - filename: 原始文件名（含扩展名）
    ///   - originalURL: 原始文件 URL（忽略，不再用于 bookmark）
    func addBook(data: Data, filename: String, originalURL: URL) {
        isLoading = true
        let ext = (filename as NSString).pathExtension.lowercased()

        let format: BookFormat
        switch ext {
        case "epub": format = .epub
        case "txt": format = .txt
        case "docx": format = .docx
        default: format = .txt
        }

        // 先在同步段把文件写入 App 容器 Books 目录
        let bookID = UUID()
        let localURL = booksDirectoryURL.appendingPathComponent("\(bookID.uuidString).\(ext)")
        let writeResult: Result<Void, Error>
        do {
            try data.write(to: localURL, options: .atomic)
            NSLog("[阻只读书] 文件已写入容器: \(localURL.path)")
            writeResult = .success(())
        } catch {
            NSLog("[阻只读书] 文件写入容器失败: \(error)")
            writeResult = .failure(error)
        }

        // 从内存 Data 解析，不需要文件访问权限
        let parseResult: Result<BookDocument, Error>
        do {
            let parser = try BookParserFactory.parser(forFilename: filename)
            let document = try parser.parse(data: data, filename: filename)
            NSLog("[阻只读书] parse(data:) 完成，章节数: \(document.chapters.count)")
            parseResult = .success(document)
        } catch {
            parseResult = .failure(error)
        }

        Task {
            defer { isLoading = false }

            // 文件写入失败，直接报错
            if case .failure(let error) = writeResult {
                self.errorMessage = MAlertMessage(text: "无法保存文件副本：\(error.localizedDescription)")
                return
            }

            switch parseResult {
            case .failure(let error):
                let nsError = error as NSError
                NSLog("[阻只读书] 解析失败: \(error), domain=\(nsError.domain), code=\(nsError.code)")
                self.errorMessage = MAlertMessage(text: "解析失败：\(error.localizedDescription)\n(domain: \(nsError.domain), code: \(nsError.code))")
                // 解析失败，删除已写入的副本
                try? fileManager.removeItem(at: localURL)

            case .success(let document):
                let totalWords = document.fullText.count
                let book = Book(
                    id: bookID,
                    title: document.title,
                    author: nil,
                    bookmarkData: Data(),       // 不再使用 bookmark
                    fileType: format,
                    addedDate: Date(),
                    lastOpenedDate: Date(),
                    readingPosition: nil,
                    totalChapters: document.chapters.count,
                    totalWords: totalWords,
                    coverImageData: nil
                )

                // 去重：基于 title + fileType
                let isDuplicate = books.contains {
                    $0.title == book.title && $0.fileType == book.fileType
                }

                if !isDuplicate {
                    books.append(book)
                    selectedBook = book
                } else if let existing = books.first(where: { $0.title == book.title && $0.fileType == book.fileType }),
                          let idx = books.firstIndex(where: { $0.id == existing.id }) {
                    var updated = existing
                    updated.lastOpenedDate = Date()
                    updated.totalChapters = document.chapters.count
                    updated.totalWords = totalWords
                    books[idx] = updated
                    selectedBook = updated
                }

                try? await libraryStorage.save(books)
                await loadRecentFilesAsync()
            }
        }
    }

    /// 打开书籍，优先从 App 容器副本读取；旧书（有 bookmarkData）尝试解析书签作为兜底
    func openBook(_ book: Book) async -> BookDocument? {
        let localURL = localFileURL(for: book)

        // 优先：直接读容器内的副本（App 永久有权限）
        if fileManager.fileExists(atPath: localURL.path) {
            do {
                let parser = try BookParserFactory.parser(for: localURL)
                let document = try parser.parse(url: localURL)
                NSLog("[阻只读书] openBook 从容器副本打开成功: \(localURL.lastPathComponent)")
                return document
            } catch {
                NSLog("[阻只读书] openBook 容器副本解析失败，尝试书签兜底: \(error)")
                // 容器文件损坏，继续尝试书签
            }
        }

        // 兜底：旧书可能仍有有效的 security-scoped bookmark（升级前添加的）
        guard let resolved = SecurityScopedBookmarkService.resolve(book.bookmarkData) else {
            errorMessage = MAlertMessage(text: "找不到书籍文件（副本已丢失且书签无效）：\(book.title)")
            return nil
        }

        let url = resolved.url
        do {
            let document: BookDocument
            if resolved.isStale {
                NSLog("[阻只读书] openBook bookmark 已过期，尝试直接读取")
            }
            document = try SecurityScopedBookmarkService.access(url) {
                let parser = try BookParserFactory.parser(for: url)
                return try parser.parse(url: url)
            }
            // 读取成功，把文件复制到容器，下次不再依赖书签
            copyFileToBooksDirectory(from: url, for: book)
            return document
        } catch {
            errorMessage = MAlertMessage(text: "打开书籍失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 把原始文件复制到容器 Books 目录（用于旧 bookmark 升级）
    private func copyFileToBooksDirectory(from url: URL, for book: Book) {
        let destURL = localFileURL(for: book)
        guard !fileManager.fileExists(atPath: destURL.path) else { return }
        do {
            try fileManager.copyItem(at: url, to: destURL)
            NSLog("[阻只读书] 旧书已复制到容器: \(destURL.lastPathComponent)")
        } catch {
            NSLog("[阻只读书] 旧书复制到容器失败（非致命）: \(error)")
        }
    }

    /// 更新阅读进度并持久化
    func updateProgress(bookID: UUID, position: ReadingPosition) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].readingPosition = position
        books[idx].lastOpenedDate = Date()
        Task {
            try? await libraryStorage.save(books)
        }
    }

    /// 删除一本书及其容器内的副本文件
    func removeBook(id: UUID) {
        // 先删除容器内的副本文件
        if let book = books.first(where: { $0.id == id }) {
            let localURL = localFileURL(for: book)
            try? fileManager.removeItem(at: localURL)
            NSLog("[阻只读书] 已删除容器副本: \(localURL.lastPathComponent)")
        }

        books.removeAll { $0.id == id }
        if selectedBook?.id == id {
            selectedBook = nil
            selectedBookID = nil
        }
        Task {
            let all = await StorageService.shared.loadBookmarks()
            let filtered = all.filter { $0.bookID != id }
            do {
                try await StorageService.shared.saveAllBookmarks(filtered)
            } catch {
                errorMessage = MAlertMessage(text: "书签清理失败：\(error.localizedDescription)")
            }
            try? await libraryStorage.save(books)
            await loadRecentFilesAsync()
        }
    }

    /// 打开最近文件：直接加入书架（若已存在则选中）
    func openRecentFile(at url: URL) {
        addBook(from: url)
    }

    /// 加载最近打开文件列表（基于书架的 lastOpenedDate）
    func loadRecentFiles() {
        Task { await loadRecentFilesAsync() }
    }

    func loadRecentFilesAsync() async {
        // 基于书架的 lastOpenedDate 排序，最多 10 本
        let sorted = books
            .filter { $0.lastOpenedDate != nil }
            .sorted { ($0.lastOpenedDate ?? .distantPast) > ($1.lastOpenedDate ?? .distantPast) }
            .prefix(10)
        recentBooks = Array(sorted)
    }

    /// 立即持久化当前书架（Open Recent 菜单清除最近记录时用）
    func saveBooks() async {
        try? await libraryStorage.save(books)
    }

    @Published var recentBooks: [Book] = []
}
