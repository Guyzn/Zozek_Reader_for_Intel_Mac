import Foundation

/// EPUB 解析器：使用系统 ditto 解压，解析 OPF、NCX / nav.xhtml 获取目录与正文
final class EPUBParser: BookParserProtocol {

    func parse(url: URL) throws -> BookDocument {
        NSLog("[阻只读书] EPUBParser.parse(url:) 开始: \(url.path)")

        // Sandbox 子进程不继承安全域访问：先把文件复制到 app 可访问的临时目录
        let inputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MReaderApp_EPUB_Input_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        let tempInputURL = inputDir.appendingPathComponent("input.epub")
        do {
            try FileManager.default.copyItem(at: url, to: tempInputURL)
            NSLog("[阻只读书] EPUB 已复制到临时目录: \(tempInputURL.path)")
        } catch {
            throw EPUBParserError.unzipFailed("复制 EPUB 到临时目录失败: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: inputDir) }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MReaderApp_EPUB_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1. 使用系统 ditto 解压 EPUB（操作临时副本，避免子进程无安全域访问）
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", tempInputURL.path, workDir.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw EPUBParserError.unzipFailed("进程启动失败: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorPipe.fileHandleForReading.closeFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "未知错误"
            NSLog("[阻只读书] EPUB ditto 解压失败，status=\(process.terminationStatus): \(errMsg)")
            throw EPUBParserError.unzipFailed(errMsg)
        }
        errorPipe.fileHandleForReading.closeFile()

        // 2. 读取 container.xml 获取 OPF 路径
        let containerURL = workDir.appendingPathComponent("META-INF/container.xml")
        let containerXML = try String(contentsOf: containerURL, encoding: .utf8)
        guard let opfRelativePath = extractOPFPath(from: containerXML) else {
            throw EPUBParserError.opfNotFound
        }
        let opfURL = workDir.appendingPathComponent(opfRelativePath)
        let baseDir = opfURL.deletingLastPathComponent()
        let opfXML = try String(contentsOf: opfURL, encoding: .utf8)

        // 3. 解析 OPF 的 manifest 与 spine
        let manifest = extractManifest(from: opfXML)
        let spineIds = extractSpine(from: opfXML)

        // 4. 尝试解析 NCX 或 nav.xhtml 目录
        let ncxURL = findNCX(in: opfXML, baseDir: baseDir)
        let navURL = findNav(in: opfXML, manifest: manifest, baseDir: baseDir)
        let tocEntries = parseTOC(ncxURL: ncxURL, navURL: navURL, baseDir: baseDir)

        // 5. 按 spine 顺序读取正文，并与目录条目匹配
        var chapters: [MChapter] = []
        var globalIndex = 0
        for id in spineIds {
            guard let href = manifest[id] else { continue }
            let fileURL = baseDir.appendingPathComponent(href)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let html = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let plainText = htmlToPlainText(html)

            let matchedEntry = tocEntries.first { entry in
                let entryName = entry.href.components(separatedBy: "#").first ?? entry.href
                return href == entryName || href.hasSuffix(entryName)
            }

            if let entry = matchedEntry {
                chapters.append(MChapter(title: entry.label, content: plainText, index: globalIndex))
                globalIndex += 1
            } else if !plainText.isEmpty {
                chapters.append(MChapter(title: "正文 \(globalIndex + 1)", content: plainText, index: globalIndex))
                globalIndex += 1
            }
        }

        let title = url.deletingPathExtension().lastPathComponent
        NSLog("[阻只读书] EPUBParser.parse 完成: \(chapters.count) 章")
        return BookDocument(title: title, chapters: chapters)
    }

    // MARK: - 错误类型

    enum EPUBParserError: LocalizedError {
        case unzipFailed(String)
        case opfNotFound
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let detail): return "解压失败：\(detail)"
            case .opfNotFound: return "EPUB 内找不到 OPF 文件"
            case .parseFailed: return "EPUB 解析失败"
            }
        }
    }

    // MARK: - OPF 解析

    private func extractOPFPath(from xml: String) -> String? {
        let pattern = #"<rootfile[^>]+full-path="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
    }

    private func extractManifest(from xml: String) -> [String: String] {
        var result: [String: String] = [:]
        // 先提取每个 <item ...> 标签，再从中独立解析 id 和 href，兼容任意属性顺序
        let itemPattern = #"<item\b[^>]*>"#
        let idPattern = #"id="([^"]+)""#
        let hrefPattern = #"href="([^"]+)""#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: []),
              let idRegex = try? NSRegularExpression(pattern: idPattern, options: []),
              let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: []) else { return result }

        let itemMatches = itemRegex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
        for itemMatch in itemMatches {
            guard let tagRange = Range(itemMatch.range, in: xml) else { continue }
            let tag = String(xml[tagRange])
            guard let idMatch = idRegex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag)),
                  let idRange = Range(idMatch.range(at: 1), in: tag),
                  let hrefMatch = hrefRegex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag)),
                  let hrefRange = Range(hrefMatch.range(at: 1), in: tag) else { continue }
            let id = String(tag[idRange])
            let href = String(tag[hrefRange])
            result[id] = href
        }
        return result
    }

    private func extractSpine(from xml: String) -> [String] {
        var result: [String] = []
        let pattern = #"<itemref[^>]+idref="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return result }
        let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            guard let range = Range(match.range(at: 1), in: xml) else { continue }
            result.append(String(xml[range]))
        }
        return result
    }

    // MARK: - 目录解析

    private struct TOCEntry {
        let label: String
        let href: String
    }

    private func findNCX(in opfXML: String, baseDir: URL) -> URL? {
        let pattern = #"<item[^>]+media-type="application/x-dtbncx\+xml"[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: opfXML, options: [], range: NSRange(opfXML.startIndex..., in: opfXML)) else { return nil }
        guard let tagRange = Range(match.range, in: opfXML) else { return nil }
        let tag = String(opfXML[tagRange])
        let hrefPattern = #"href="([^"]+)""#
        guard let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: []),
              let hrefMatch = hrefRegex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(hrefMatch.range(at: 1), in: tag) else { return nil }
        return baseDir.appendingPathComponent(String(tag[range]))
    }

    private func findNav(in opfXML: String, manifest: [String: String], baseDir: URL) -> URL? {
        for (id, href) in manifest {
            if id.lowercased().contains("nav") || href.lowercased().contains("toc") || href.lowercased().contains("nav") {
                return baseDir.appendingPathComponent(href)
            }
        }
        return nil
    }

    private func parseTOC(ncxURL: URL?, navURL: URL?, baseDir: URL) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        if let ncxURL = ncxURL, let xml = try? String(contentsOf: ncxURL, encoding: .utf8) {
            entries = parseNCX(xml: xml)
        }
        if entries.isEmpty, let navURL = navURL, let html = try? String(contentsOf: navURL, encoding: .utf8) {
            entries = parseNavHTML(html: html)
        }
        return entries
    }

    private func parseNCX(xml: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        let labelPattern = #"<navLabel>\s*<text>([^<]+)</text>\s*</navLabel>"#
        let srcPattern = #"<content[^>]+src="([^"]+)""#

        guard let labelRegex = try? NSRegularExpression(pattern: labelPattern, options: [.dotMatchesLineSeparators]),
              let srcRegex = try? NSRegularExpression(pattern: srcPattern, options: []) else { return entries }

        let labelMatches = labelRegex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
        let srcMatches = srcRegex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))

        let count = min(labelMatches.count, srcMatches.count)
        for i in 0..<count {
            guard let labelRange = Range(labelMatches[i].range(at: 1), in: xml),
                  let srcRange = Range(srcMatches[i].range(at: 1), in: xml) else { continue }
            let label = String(xml[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let src = String(xml[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(TOCEntry(label: label, href: src))
        }
        return entries
    }

    private func parseNavHTML(html: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        let pattern = #"<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return entries }
        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        for match in matches {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { continue }
            let label = String(html[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let href = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(TOCEntry(label: label, href: href))
        }
        return entries
    }

    // MARK: - HTML 转纯文本

    private func htmlToPlainText(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</(p|div|h[1-6]|li|br|tr)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&amp;": "&",
            "&quot;": "\"", "&apos;": "'", "&#160;": " "
        ]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        text = components.filter { !$0.isEmpty }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parse(data: Data, filename: String) throws -> BookDocument {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MReaderApp_EPUB_\(UUID().uuidString).epub")
        try data.write(to: tempURL)
        NSLog("[阻只读书] EPUBParser.parse(data:) 已写入临时文件: \(tempURL.path)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try parse(url: tempURL)
    }
}
