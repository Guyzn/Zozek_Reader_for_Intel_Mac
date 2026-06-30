import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 主界面：三栏布局（书架/章节列表/阅读与朗读控制）、搜索弹窗、全局快捷键
struct MContentView: View {
    @EnvironmentObject private var menubarManager: MenubarManager
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @StateObject private var playerVM = PlayerViewModel()
    @State private var showingOpenPanel = false
    @State private var selectedSidebarTab = SidebarTab.library
    @State private var showHotkeysGuide = false

    enum SidebarTab: String, CaseIterable, Identifiable {
        case library = "书架"
        case bookmarks = "书签"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .library: return "books.vertical"
            case .bookmarks: return "bookmark"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 180)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingOpenPanel = true }) {
                            Label("打开", systemImage: "plus")
                        }
                    }
                }
        } content: {
            MChapterListView(libraryVM: libraryVM, playerVM: playerVM)
                .frame(minWidth: 200)
        } detail: {
            MReaderView(playerVM: playerVM)
                .frame(minWidth: 400)
        }
        .sheet(isPresented: $showingOpenPanel) {
            MOpenBookSheet { data, filename, originalURL in
                libraryVM.addBook(data: data, filename: filename, originalURL: originalURL)
            }
        }
        .sheet(isPresented: $playerVM.showSearchSheet) {
            SearchResultView(playerVM: playerVM)
        }
        .sheet(isPresented: $showHotkeysGuide) {
            HotkeysGuideView()
        }
        // 应用命令总线（替代 NotificationCenter）
        .onReceive(AppCommandBus.shared.openBook) { _ in
            showingOpenPanel = true
        }
        .onReceive(AppCommandBus.shared.togglePlayPause) { _ in
            playerVM.togglePlayPause()
        }
        .onReceive(AppCommandBus.shared.nextSentence) { _ in
            playerVM.nextSentence()
        }
        .onReceive(AppCommandBus.shared.previousSentence) { _ in
            playerVM.previousSentence()
        }
        .onReceive(AppCommandBus.shared.openSearch) { _ in
            playerVM.showSearchSheet = true
        }
        .onReceive(AppCommandBus.shared.showHotkeysGuide) { _ in
            showHotkeysGuide = true
        }
        .onAppear {
            menubarManager.attach(playerVM.ttsManager)
            libraryVM.loadRecentFiles()
            playerVM.onSaveProgress = { bookID, position in
                libraryVM.updateProgress(bookID: bookID, position: position)
            }
        }
        .onChange(of: libraryVM.selectedBook) { _, newBook in
            guard let book = newBook else { return }
            Task {
                await playerVM.setupForBook(book, via: libraryVM)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .alert(item: $libraryVM.errorMessage) { message in
            Alert(title: Text("提示"), message: Text(message.text), dismissButton: .default(Text("确定")))
        }
        .overlay {
            if libraryVM.isLoading {
                ZStack {
                    Color.mDimOverlay
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.2)
                        Text("正在解析文档…").font(.callout).foregroundColor(Color.mSecondary)
                    }
                    .padding(28)
                    .background(Color.mControlBackground, in: RoundedRectangle(cornerRadius: 12))
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            switch selectedSidebarTab {
            case .library:
                MLibraryView(libraryVM: libraryVM, playerVM: playerVM)
            case .bookmarks:
                MBookmarkListView(playerVM: playerVM)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let accepted = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard error == nil else { return }

                // NSItemProvider 对 fileURL 类型可能返回 URL 或 Data 表示的 URL
                let url: URL?
                if let u = item as? URL {
                    url = u
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                guard let resolvedURL = url else { return }

                // 拖拽来源的文件 URL 通常是 security-scoped，必须在读取前启动访问
                let started = resolvedURL.startAccessingSecurityScopedResource()
                defer {
                    if started { resolvedURL.stopAccessingSecurityScopedResource() }
                }

                do {
                    let data = try Data(contentsOf: resolvedURL)
                    NSLog("[阻只读书] handleDrop 同步读取成功: \(resolvedURL.lastPathComponent), \(data.count) bytes")
                    DispatchQueue.main.async {
                        libraryVM.addBook(data: data, filename: resolvedURL.lastPathComponent, originalURL: resolvedURL)
                    }
                } catch {
                    let nsError = error as NSError
                    NSLog("[阻只读书] handleDrop 读取失败: \(nsError.domain) code=\(nsError.code)")
                    DispatchQueue.main.async {
                        libraryVM.errorMessage = MAlertMessage(text: "无法读取文件：\(error.localizedDescription)")
                    }
                }
            }
        }
        return accepted
    }
}

// MARK: - Alert 包装类型

struct MAlertMessage: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - 文件选择弹窗

struct MOpenBookSheet: View {
    /// 回调参数：(文件内容 Data, 文件名, 原始 URL 用于创建 bookmark)
    let onSelect: (Data, String, URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("选择 TXT / EPUB / DOCX 书籍").font(.headline).padding()
            Button("选择文件") {
                let panel = NSOpenPanel()
                var contentTypes: [UTType] = [.plainText]
                if let epubType = UTType(filenameExtension: "epub") { contentTypes.append(epubType) }
                if let docxType = UTType(filenameExtension: "docx") { contentTypes.append(docxType) }
                panel.allowedContentTypes = contentTypes
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false

                let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
                if let window = window {
                    panel.beginSheetModal(for: window) { result in
                        guard result == .OK, let url = panel.url else { return }

                        // 在回调同步上下文中立即读取文件内容（此时沙盒临时授权有效）
                        do {
                            let data = try Data(contentsOf: url)
                            NSLog("[阻只读书] MOpenBookSheet 同步读取成功: \(url.lastPathComponent), \(data.count) bytes")
                            onSelect(data, url.lastPathComponent, url)
                            dismiss()
                        } catch {
                            let nsError = error as NSError
                            NSLog("[阻只读书] MOpenBookSheet 读取文件失败: domain=\(nsError.domain), code=\(nsError.code)")
                            // 读取失败时也 dismiss，让上层显示错误
                            dismiss()
                        }
                    }
                }
            }
            .padding()
            Button("取消") { dismiss() }.padding(.bottom)
        }
        .frame(width: 320, height: 180)
    }
}

// MARK: - 快捷键说明弹窗

struct HotkeysGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("快捷键说明").font(.title2).bold()
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HotkeyRow(key: "Space", action: "播放 / 暂停")
                HotkeyRow(key: "→", action: "下一句")
                HotkeyRow(key: "←", action: "上一句")
                HotkeyRow(key: "⌘F", action: "搜索文本")
                HotkeyRow(key: "⌘O", action: "打开书籍")
            }
            .frame(width: 240)
            Divider()
            Text("提示：使用全局快捷键前，请先在 系统设置 → 隐私与安全性 → 辅助功能 中授权「阻只读书」。")
                .font(.caption)
                .foregroundColor(Color.mSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 280)
            Button("关闭") { dismiss() }.padding(.top)
        }
        .padding()
        .frame(width: 340)
    }
}

struct HotkeyRow: View {
    let key: String
    let action: String
    var body: some View {
        HStack {
            Text(key)
                .fontWeight(.semibold)
                .frame(width: 50, alignment: .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.mKeyBackground))
            Text(action)
                .foregroundColor(Color.mSecondary)
            Spacer()
        }
    }
}
