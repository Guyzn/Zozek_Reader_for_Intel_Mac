import Foundation

/// 章节模型：标题、纯文本内容与在书中的索引
struct MChapter: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var index: Int

    /// 非空段落文本数组（init 中预计算）
    let paragraphs: [String]
    /// 每个段落对应的 UTF-16 起始偏移（init 中预计算）
    private let paragraphOffsets: [Int]

    init(id: UUID = UUID(), title: String, content: String, index: Int) {
        self.id = id
        self.title = title
        self.content = content
        self.index = index
        (self.paragraphs, self.paragraphOffsets) = MChapter.computeParagraphsAndOffsets(from: content)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        index = try container.decode(Int.self, forKey: .index)
        (self.paragraphs, self.paragraphOffsets) = MChapter.computeParagraphsAndOffsets(from: content)
    }

    /// 用于书签展示的前 120 个字符摘要
    var snippet: String {
        let prefix = content.prefix(120)
        return prefix.isEmpty ? "（空章节）" : String(prefix) + (content.count > 120 ? "…" : "")
    }

    /// 根据全局 UTF-16 offset 定位当前段落的 0-based 索引
    func paragraphIndex(forGlobalOffset offset: Int) -> Int {
        guard !paragraphOffsets.isEmpty else { return 0 }
        for (i, off) in paragraphOffsets.enumerated() {
            if offset < off { return max(0, i - 1) }
        }
        return paragraphs.count - 1
    }

    // MARK: - Private Helpers

    private static func computeParagraphsAndOffsets(from content: String) -> ([String], [Int]) {
        let rawLines = content.components(separatedBy: "\n")
        var ps: [String] = []
        var offs: [Int] = []
        var cursor = 0
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                ps.append(trimmed)
                offs.append(cursor)
            }
            cursor += line.utf16.count + 1  // +1 for "\n"
        }
        return (ps, offs)
    }
}
