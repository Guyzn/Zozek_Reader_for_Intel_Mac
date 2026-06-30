import Foundation

/// TXT 文件解析器：识别多种章节标题格式并切分章节
final class TXTParser: BookParserProtocol {

    /// 支持的章节标题正则（按优先级排序）。
    /// 注意：不匹配纯数字行（如 "2024"、"3.14"），这些常见于页码/日期。
    static let chapterPatterns: [String] = [
        "^第[\\s]*[0-9一二三四五六七八九十百千万亿零〇]+[\\s]*[章卷回集话].*$",
        "^Chapter[\\s]+[0-9IVXLC]+.*$",
        "^[0-9]+[\\.\\、\\s][\\s]*\\S.*$",
        "^[一二三四五六七八九十百千万亿]+[\\、\\s][\\s]*\\S.*$"
    ]

    func parse(url: URL) throws -> BookDocument {
        NSLog("[阻只读书] TXTParser.parse(url:) 开始: \(url.path)")
        let content = try readContent(from: url)
        let title = url.deletingPathExtension().lastPathComponent
        let chapters = splitChapters(from: content)
        NSLog("[阻只读书] TXTParser.parse(url:) 完成: \(chapters.count) 章")
        return BookDocument(title: title, chapters: chapters)
    }

    func parse(data: Data, filename: String) throws -> BookDocument {
        NSLog("[阻只读书] TXTParser.parse(data:) 开始: \(filename), \(data.count) bytes")
        let content = try readContent(from: data)
        let title = (filename as NSString).deletingPathExtension
        let chapters = splitChapters(from: content)
        NSLog("[阻只读书] TXTParser.parse(data:) 完成: \(chapters.count) 章")
        return BookDocument(title: title, chapters: chapters)
    }

    // MARK: - 从内存 Data 解码（不需要文件 URL）

    private func readContent(from data: Data) throws -> String {
        NSLog("[阻只读书] TXTParser.readContent(from Data): \(data.count) bytes")
        // 尝试 UTF-8
        if let content = decodeStreaming(data: data, encoding: .utf8) {
            return content
        }

        // 尝试 GB18030
        let gbEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let content = decodeStreaming(data: data, encoding: gbEncoding) {
            return content
        }

        throw NSError(
            domain: "TXTParser", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "无法识别文本编码，已尝试 UTF-8 和 GB18030"]
        )
    }

    // MARK: - 流式逐行容错读取

    /// 尝试用 UTF-8 / GB18030 编码打开文件。
    /// 采用流式逐行解码，坏行静默跳过，不会因中间乱码而整文件失败。
    /// 编码回退链：UTF-8 → GB18030（GB18030 是 GBK 超集，无需再回退 GBK）
    private func readContent(from url: URL) throws -> String {
        NSLog("[阻只读书] TXTParser.readContent: \(url.path)")
        let data = try Data(contentsOf: url)
        NSLog("[阻只读书] TXTParser 读取数据大小: \(data.count) bytes")

        // 尝试 UTF-8
        if let content = decodeStreaming(data: data, encoding: .utf8) {
            return content
        }

        // 尝试 GB18030 — GBK 的超集
        let gbEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let content = decodeStreaming(data: data, encoding: gbEncoding) {
            return content
        }

        throw NSError(
            domain: "TXTParser", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "无法识别文本编码，已尝试 UTF-8 和 GB18030"]
        )
    }

    /// 将 raw bytes 按换行切分，逐行解码。跳过无法解码的行，保留可读内容。
    /// 如果超过一半的行解码失败，返回 nil（视为编码错误）
    private func decodeStreaming(data: Data, encoding: String.Encoding) -> String? {
        let chunks = splitBytesByNewlines(data)
        var lines: [String] = []
        var successCount = 0

        for chunk in chunks {
            if let line = String(data: chunk, encoding: encoding) {
                lines.append(line)
                successCount += 1
            }
            // 坏行静默跳过，不做任何处理
        }

        // 无任何可解码行 → 编码不匹配
        guard successCount > 0 else { return nil }

        // 成功率低于 50% 且总行数超过 3 → 编码可能不匹配
        let total = chunks.count
        if total > 3, successCount * 2 < total {
            return nil
        }

        return lines.joined(separator: "\n")
    }

    /// 按 \n / \r\n / \r 切分 raw bytes。空行也保留为单独 chunk。
    private func splitBytesByNewlines(_ data: Data) -> [Data] {
        let lf = UInt8(ascii: "\n")
        let cr = UInt8(ascii: "\r")
        var chunks: [Data] = []
        var start = data.startIndex
        var i = data.startIndex

        while i < data.endIndex {
            let byte = data[i]
            if byte == lf {
                chunks.append(data[start..<i])
                i += 1
                start = i
            } else if byte == cr {
                chunks.append(data[start..<i])
                i += 1
                // 跳过 CRLF 中的 LF
                if i < data.endIndex, data[i] == lf {
                    i += 1
                }
                start = i
            } else {
                i += 1
            }
        }

        // 最后一段（文件不以换行结尾时）
        if start < data.endIndex {
            chunks.append(data[start...])
        }

        return chunks
    }

    // MARK: - 章节切分

    /// 将全文切分为章节
    func splitChapters(from text: String) -> [MChapter] {
        let lines = text.components(separatedBy: .newlines)
        var chapters: [MChapter] = []
        var currentTitle = "前言"
        var currentLines: [String] = []
        var chapterIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isChapterTitle(trimmed) {
                let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty || chapterIndex == 0 {
                    chapters.append(MChapter(title: currentTitle, content: body, index: chapterIndex))
                    chapterIndex += 1
                }
                currentTitle = trimmed
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            chapters.append(MChapter(title: currentTitle, content: body, index: chapterIndex))
        }

        if chapters.isEmpty {
            chapters.append(MChapter(title: "全文", content: text, index: 0))
        }

        return chapters
    }

    /// 判断单行文本是否符合章节标题特征
    func isChapterTitle(_ text: String) -> Bool {
        guard !text.isEmpty, text.count < 200 else { return false }
        for pattern in Self.chapterPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}
