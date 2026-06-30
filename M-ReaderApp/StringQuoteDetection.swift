import Foundation
import SwiftUI

extension String {
    var isWrappedInQuotes: Bool {
        (hasPrefix("\"") && hasSuffix("\"")) ||
        (hasPrefix("\u{201C}") && hasSuffix("\u{201D}")) ||  // ""
        (hasPrefix("\u{300C}") && hasSuffix("\u{300D}"))      // 「」
    }

    /// 去除两端引号后的纯文本
    var strippingQuotes: String {
        guard count >= 2 else { return self }
        if isWrappedInQuotes {
            return String(self.dropFirst().dropLast())
        }
        return self
    }
}

// MARK: - 静态颜色调色板（规避 macOS 15 NSDynamicNamedColor 递归崩溃）
//
// 说明：macOS 15.7.4 上 SwiftUI 的语义色/系统色在特定修饰链中会触发
// colorUsingColorSpace: → bestMatchFromAppearancesWithNames: 无限递归。
// 此处全部使用硬编码 sRGB 静态色，彻底切断动态颜色解析路径。
// 当前为浅色模式配色；后续若需深色适配，可改为按 NSApp.effectiveAppearance 选择。

extension Color {
    /// 主强调色（替代 .accentColor）
    static let mAccent = Color(.sRGB, red: 0.0, green: 0.48, blue: 1.0, opacity: 1.0)

    /// 次要文本色（替代 .secondary）
    static let mSecondary = Color(.sRGB, red: 0.4, green: 0.4, blue: 0.4, opacity: 1.0)

    /// 主文本色（替代 .primary）
    static let mPrimary = Color(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1.0)

    /// 控制背景色（替代 NSColor.controlBackgroundColor）
    static let mControlBackground = Color(.sRGB, red: 0.95, green: 0.95, blue: 0.95, opacity: 1.0)

    /// 分隔线色（替代 NSColor.separatorColor）
    static let mSeparator = Color(.sRGB, red: 0.85, green: 0.85, blue: 0.85, opacity: 1.0)

    /// 朗读段落高亮背景（替代 Color.yellow.opacity(0.15)）
    static let mHighlightBackground = Color(.sRGB, red: 1.0, green: 1.0, blue: 0.0, opacity: 0.15)

    /// 搜索匹配高亮背景（替代 Color.orange.opacity(0.4)）
    static let mSearchHighlight = Color(.sRGB, red: 1.0, green: 0.6, blue: 0.0, opacity: 0.4)

    /// 橙色文本/图标（替代 Color.orange）
    static let mOrange = Color(.sRGB, red: 1.0, green: 0.5, blue: 0.0, opacity: 1.0)

    /// 加载遮罩黑色半透明（替代 Color.black.opacity(0.15)）
    static let mDimOverlay = Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 0.15)

    /// 快捷键说明键帽背景（替代 Color.gray.opacity(0.15)）
    static let mKeyBackground = Color(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
}
