import Foundation

/// DOCX 文件解析器 — 用系统内置 ditto 解压 + SAX 流式 XMLParser，避免大文件卡死
final class DOCXParser: BookParserProtocol {

    enum DOCXParserError: LocalizedError {
        case unzipFailed(String)
        case documentNotFound
        var errorDescription: String? {
            switch self {
            case .unzipFailed(let detail): return "解压失败：\(detail)"
            case .documentNotFound: return "DOCX 内找不到 word/document.xml"
            }
        }
    }

    func parse(url: URL) throws -> BookDocument {
        NSLog("[阻只读书] DOCXParser.parse 开始: \(url.path)")

        // Sandbox 子进程不继承安全域访问：先把文件复制到 app 可访问的临时目录
        let inputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MReaderApp_DOCX_Input_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        let tempInputURL = inputDir.appendingPathComponent("input.docx")
        do {
            try FileManager.default.copyItem(at: url, to: tempInputURL)
            NSLog("[阻只读书] DOCX 已复制到临时目录: \(tempInputURL.path)")
        } catch {
            throw DOCXParserError.unzipFailed("复制 DOCX 到临时目录失败: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: inputDir) }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MReaderApp_DOCX_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1. 用 ditto 解压临时副本
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", tempInputURL.path, workDir.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw DOCXParserError.unzipFailed("进程启动失败: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorPipe.fileHandleForReading.closeFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "未知错误"
            NSLog("[阻只读书] DOCX ditto 解压失败，status=\(process.terminationStatus): \(errMsg)")
            throw DOCXParserError.unzipFailed(errMsg)
        }
        errorPipe.fileHandleForReading.closeFile()

        // 2. 读取 word/document.xml
        let documentURL = workDir.appendingPathComponent("word/document.xml")
        guard FileManager.default.fileExists(atPath: documentURL.path) else {
            throw DOCXParserError.documentNotFound
        }
        let documentData: Data
        do {
            documentData = try Data(contentsOf: documentURL)
        } catch {
            throw DOCXParserError.unzipFailed("读取 document.xml 失败: \(error.localizedDescription)")
        }

        // 3. SAX 流式解析
        let delegate = DOCXChapterDelegate()
        let parser = XMLParser(data: documentData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        let parseSucceeded = parser.parse()

        if let parseError = parser.parserError {
            NSLog("[阻只读书] DOCX SAX 解析失败，尝试兜底提取: \(parseError.localizedDescription)")
        }

        var chapters = delegate.chapters
        let currentTitle = delegate.currentTitle
        let currentLines = delegate.currentLines
        var chapterIndex = delegate.chapterIndex

        // 保存最后一章
        let lastBody = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if parseSucceeded, (!lastBody.isEmpty || chapters.isEmpty) {
            chapters.append(MChapter(title: currentTitle, content: lastBody, index: chapterIndex))
            chapterIndex += 1
        }

        // 解析失败 或 无有效章节划分时，整篇作为一章
        if !parseSucceeded || chapters.isEmpty || chapters.allSatisfy({ $0.title == "正文" || $0.title == "全文" }) {
            let allText = extractAllParagraphs(from: documentURL)
            if !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapters = [MChapter(title: "全文", content: allText, index: 0)]
            }
        }

        // 兜底
        let hasContent = chapters.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !hasContent {
            let fallback = extractAllParagraphs(from: documentURL)
            if !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapters = [MChapter(title: "全文", content: fallback, index: 0)]
            }
        }

        let bookTitle = url.deletingPathExtension().lastPathComponent
        NSLog("[阻只读书] DOCXParser.parse 完成: \(chapters.count) 章")
        return BookDocument(title: bookTitle, chapters: chapters)
    }

    func parse(data: Data, filename: String) throws -> BookDocument {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MReaderApp_DOCX_\(UUID().uuidString).docx")
        try data.write(to: tempURL)
        NSLog("[阻只读书] DOCXParser.parse(data:) 已写入临时文件: \(tempURL.path)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try parse(url: tempURL)
    }

    /// 快速提取全部段落文本（无标题模式回退 / 兜底）
    private func extractAllParagraphs(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let delegate = DOCXPlainTextDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.parse()
        return delegate.paragraphs.joined(separator: "\n\n")
    }
}

// MARK: - SAX 解析代理（章节模式）

final class DOCXChapterDelegate: NSObject, XMLParserDelegate {
    var chapters: [MChapter] = []
    var currentTitle = "正文"
    var currentLines: [String] = []
    var chapterIndex = 0
    var firstParagraph = true

    private var currentParaText = ""
    private var isCurrentHeading = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch elementName {
        case "p":
            currentParaText = ""
            isCurrentHeading = false
        case "pStyle":
            if let val = attributes["val"] ?? attributes["w:val"],
               val.lowercased().hasPrefix("heading") {
                isCurrentHeading = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "p" else { return }

        let text = currentParaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if isCurrentHeading {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty || chapterIndex == 0 {
                chapters.append(MChapter(title: currentTitle, content: body, index: chapterIndex))
                chapterIndex += 1
            }
            currentTitle = text
            currentLines = []
            firstParagraph = false
        } else {
            currentLines.append(text)
            if firstParagraph {
                currentTitle = text
                firstParagraph = false
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentParaText += string
    }
}

// MARK: - SAX 解析代理（纯文本模式，用于回退）

final class DOCXPlainTextDelegate: NSObject, XMLParserDelegate {
    var paragraphs: [String] = []
    private var currentText = ""
    private var inParagraph = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "p" {
            inParagraph = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "p" {
            let t = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { paragraphs.append(t) }
            inParagraph = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inParagraph { currentText += string }
    }
}
