import Foundation

/// 书籍解析器协议：统一接口，支持 TXT / EPUB / DOCX
protocol BookParserProtocol {
    /// 从文件 URL 解析（保留向后兼容，主要用于从 bookmark 重新打开）
    func parse(url: URL) throws -> BookDocument

    /// 从内存 Data 解析，避免跨 async 边界传递文件 URL
    /// - Parameters:
    ///   - data: 文件内容
    ///   - filename: 原始文件名（用于判断类型和标题）
    /// - Returns: 解析后的文档
    func parse(data: Data, filename: String) throws -> BookDocument
}

/// 解析器工厂：根据文件扩展名返回对应解析器实例
enum BookParserFactory {
    static func parser(for url: URL) throws -> any BookParserProtocol {
        let ext = url.pathExtension.lowercased()
        NSLog("[阻只读书] BookParserFactory 创建 parser: ext=\(ext), path=\(url.path)")
        switch ext {
        case "txt": return TXTParser()
        case "epub": return EPUBParser()
        case "docx": return DOCXParser()
        default: throw BookParserError.unsupportedFormat(url.pathExtension)
        }
    }

    /// 根据文件名扩展名创建解析器
    static func parser(forFilename filename: String) throws -> any BookParserProtocol {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "txt": return TXTParser()
        case "epub": return EPUBParser()
        case "docx": return DOCXParser()
        default: throw BookParserError.unsupportedFormat(ext)
        }
    }
}

/// 解析器错误类型
enum BookParserError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "不支持的格式：\(ext)"
        }
    }
}
