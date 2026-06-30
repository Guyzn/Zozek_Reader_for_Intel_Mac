import Foundation

/// 书籍格式枚举
enum BookFormat: String, Codable, CaseIterable {
    case txt
    case epub
    case docx
}

/// 阅读位置：章节 + 段落（保留字段）+ 章节内字符偏移
struct ReadingPosition: Codable, Hashable {
    let chapterIndex: Int
    let paragraphIndex: Int
    let characterOffset: Int
}

/// 书籍模型：包含元数据、安全域书签与阅读进度
struct Book: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String?
    var bookmarkData: Data
    let fileType: BookFormat
    let addedDate: Date
    var lastOpenedDate: Date?
    var readingPosition: ReadingPosition?
    var totalChapters: Int
    var totalWords: Int
    var coverImageData: Data?

    /// 尝试从安全域书签解析文件 URL（运行时便利属性，不参与持久化）
    var resolvedURL: URL? {
        SecurityScopedBookmarkService.resolve(bookmarkData)?.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Book, rhs: Book) -> Bool {
        lhs.id == rhs.id
    }
}
