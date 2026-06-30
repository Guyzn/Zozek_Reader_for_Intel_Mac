import Foundation

/// 书签模型：记录所属书籍 ID、章节索引、字符偏移与摘要
struct MBookmark: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var bookID: UUID
    var chapterIndex: Int
    var characterOffset: Int
    var textSnippet: String
    var createdAt: Date
    var note: String

    init(id: UUID = UUID(), bookID: UUID, chapterIndex: Int, characterOffset: Int, textSnippet: String, createdAt: Date = Date(), note: String = "") {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.characterOffset = characterOffset
        self.textSnippet = textSnippet
        self.createdAt = createdAt
        self.note = note
    }
}
