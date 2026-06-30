import Foundation
import AppKit

/// 全局快捷键管理器：注册 Space（播放/暂停）和 →（下一句）全局热键。
///
/// 使用 NSEvent.addGlobalMonitorForEvents 监听系统级按键，
/// 需要用户在 系统设置 → 隐私与安全性 → 辅助功能 中授权本 App。
///
/// 同时注册 localMonitor 防止 App 聚焦时全局热键与本地输入冲突。
final class GlobalHotkeyManager {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    /// 播放/暂停切换
    var onTogglePlayPause: (() -> Void)?

    /// 下一句
    var onNextSentence: (() -> Void)?

    /// 上一句
    var onPreviousSentence: (() -> Void)?

    func start() {
        // 全局监听：App 在后台时捕获按键
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // 本地监听：App 在前台时也能捕获，且优先级高于全局
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event -> NSEvent? in
            guard let self else { return event }
            // 先判断是否需要拦截：若是热键且不在输入框中，则处理并阻止事件继续传递
            if self.shouldSuppressKeyEvent(event) {
                self.handleKeyEvent(event)
                return nil
            }
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// 判断是否为已注册的热键组合之一，同时检查当前第一响应者
    private func shouldSuppressKeyEvent(_ event: NSEvent) -> Bool {
        let modifierFree = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        guard modifierFree else { return false }

        // 如果当前焦点在文本输入控件中，不拦截，保证输入框正常工作
        if let responder = NSApp.keyWindow?.firstResponder {
            if responder is NSTextView || responder is NSTextField {
                return false
            }
            // 检查是否为 NSTextView 的子视图（SwiftUI 中 TextField 的底层实现）
            if let view = responder as? NSView {
                if view.className.contains("FieldEditor") || view.className.contains("NSTextView") {
                    return false
                }
            }
        }

        if event.keyCode == 49 { return true }   // Space
        if event.keyCode == 124 || event.keyCode == 123 { return true }  // Arrow keys
        return false
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        // 仅在无 Command/Control/Option 修饰时处理，避免与系统快捷键冲突
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { return }

        switch event.keyCode {
        case 49:   // Space — 播放/暂停
            DispatchQueue.main.async { [weak self] in
                self?.onTogglePlayPause?()
            }
        case 124:  // Right Arrow → 下一句
            DispatchQueue.main.async { [weak self] in
                self?.onNextSentence?()
            }
        case 123:  // Left Arrow ← 上一句
            DispatchQueue.main.async { [weak self] in
                self?.onPreviousSentence?()
            }
        default:
            break
        }
    }

    deinit {
        stop()
    }
}
