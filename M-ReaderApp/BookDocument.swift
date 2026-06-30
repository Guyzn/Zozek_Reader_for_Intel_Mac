import Foundation

/// 统一解析结果结构体：包含标题、章节列表、偏移映射与全文
struct BookDocument {
    let title: String
    let chapters: [MChapter]
    /// 按章节索引 → UTF-16 起始偏移 的映射表，供 TTS 全局定位用
    let chapterOffsetMap: [Int: Int]
    /// 全文所有内容拼接（按章节顺序），供 TTS 连续朗读
    let fullText: String

    init(title: String, chapters: [MChapter], chapterOffsetMap: [Int: Int], fullText: String) {
        self.title = title
        self.chapters = chapters
        self.chapterOffsetMap = chapterOffsetMap
        self.fullText = fullText
    }

    /// 从章节列表快速构造 BookDocument，自动计算 offsetMap 和 fullText
    init(title: String, chapters: [MChapter]) {
        self.title = title
        self.chapters = chapters
        var map: [Int: Int] = [:]
        var offset: Int = 0
        for chapter in chapters {
            map[chapter.index] = offset
            offset += chapter.content.utf16.count
        }
        self.chapterOffsetMap = map
        self.fullText = chapters.map { $0.content }.joined()
    }
}
