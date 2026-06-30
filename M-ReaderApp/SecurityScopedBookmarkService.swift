import Foundation

/// 安全域书签操作错误
enum BookmarkError: Error {
    case creationFailed
    case resolutionFailed
    case staleAndUnrecoverable
}

/// 安全域书签服务：创建、解析、访问包装与刷新
struct SecurityScopedBookmarkService {
    /// 创建书签（导入时调用）
    /// 调用方需确保 url 处于可访问状态；本方法不会自行 stop/start 安全域访问。
    static func create(for url: URL) throws -> Data {
        return try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// 解析书签，返回 URL 和是否已失效（stale）
    static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            return nil
        }
    }

    /// 安全访问包装器：自动 start/stop
    @discardableResult
    static func access<T>(_ url: URL, action: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }
        return try action()
    }

    /// 尝试刷新 stale bookmark
    static func refresh(_ oldData: Data) -> Data? {
        guard let (url, _) = resolve(oldData) else { return nil }
        return try? create(for: url)
    }
}
