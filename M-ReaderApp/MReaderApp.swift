import SwiftUI
import AppKit
import Combine

/// 应用级命令总线：替代 NotificationCenter，让菜单命令与 View 通过 Combine 解耦
@MainActor
final class AppCommandBus: ObservableObject {
    static let shared = AppCommandBus()

    let openBook = PassthroughSubject<Void, Never>()
    let togglePlayPause = PassthroughSubject<Void, Never>()
    let nextSentence = PassthroughSubject<Void, Never>()
    let previousSentence = PassthroughSubject<Void, Never>()
    let openSearch = PassthroughSubject<Void, Never>()
    let showHotkeysGuide = PassthroughSubject<Void, Never>()

    private init() {}
}

@main
struct MReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// LibraryViewModel 提升到 App 层，以便 Open Recent 菜单操作
    @StateObject private var libraryVM = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            MContentView()
                .environmentObject(appDelegate.menubarManager)
                .environmentObject(libraryVM)
        }
        .windowToolbarStyle(.unified)
        .commands {
            // 文件菜单
            CommandGroup(after: .appInfo) {
                Button("打开书籍…") {
                    AppCommandBus.shared.openBook.send()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // 最近打开
            CommandMenu("最近打开") {
                OpenRecentMenuView(libraryVM: libraryVM)
            }

            // 播放控制
            CommandMenu("播放") {
                Button("播放/暂停") {
                    AppCommandBus.shared.togglePlayPause.send()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("下一句") {
                    AppCommandBus.shared.nextSentence.send()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("上一句") {
                    AppCommandBus.shared.previousSentence.send()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Divider()

                Button("搜索…") {
                    AppCommandBus.shared.openSearch.send()
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // 帮助菜单 — 快捷键说明
            CommandGroup(after: .help) {
                Button("快捷键说明") {
                    AppCommandBus.shared.showHotkeysGuide.send()
                }
            }
        }
    }
}

// MARK: - Open Recent 菜单视图（动态生成）

struct OpenRecentMenuView: View {
    @ObservedObject var libraryVM: LibraryViewModel

    var body: some View {
        Group {
            if libraryVM.recentBooks.isEmpty {
                Text("无最近文件")
                    .foregroundColor(Color.mSecondary)
            } else {
                ForEach(libraryVM.recentBooks) { book in
                    Button(book.title) {
                        libraryVM.selectedBook = book
                    }
                }
                Divider()
                Button("清除最近记录") {
                    for book in libraryVM.recentBooks {
                        var updated = book
                        updated.lastOpenedDate = nil
                        if let idx = libraryVM.books.firstIndex(where: { $0.id == book.id }) {
                            libraryVM.books[idx] = updated
                        }
                    }
                    Task {
                        await libraryVM.saveBooks()
                        await libraryVM.loadRecentFilesAsync()
                    }
                }
            }
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menubarManager = MenubarManager()

    func applicationDidFinishLaunching(_ notification: Notification) {}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {}
}

// MARK: - MenubarManager

/// 菜单栏状态项管理器
@MainActor
final class MenubarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var observedManager: TTSManager? {
        didSet { setupObserver() }
    }
    private var updateWorkItem: DispatchWorkItem?

    init() { createStatusItem() }

    func attach(_ ttsManager: TTSManager) { self.observedManager = ttsManager }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "阻只读书"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    private func setupObserver() {
        cancellables.removeAll()
        guard let ttsManager = observedManager else { return }
        ttsManager.$highlightedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.scheduleTitleUpdate(with: text)
            }
            .store(in: &cancellables)
    }

    private func scheduleTitleUpdate(with text: String) {
        updateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateTitle(with: text)
        }
        updateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func updateTitle(with text: String) {
        statusItem?.button?.title = text.isEmpty ? "阻只读书" : String(text.prefix(15))
    }

    @objc private func statusItemClicked() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    deinit {
        cancellables.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
