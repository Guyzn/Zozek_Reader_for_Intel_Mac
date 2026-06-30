import Foundation
import SwiftUI
import Combine

/// 睡眠定时选项
enum SleepTimerOption: CaseIterable, Identifiable, Equatable {
    case off
    case minutes15
    case minutes30
    case minutes60
    case custom(TimeInterval)

    var id: String { label }

    var label: String {
        switch self {
        case .off:             return "关闭"
        case .minutes15:       return "15 分钟"
        case .minutes30:       return "30 分钟"
        case .minutes60:       return "60 分钟"
        case .custom(let t):   return "\(Int(t / 60)) 分钟"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .off:             return nil
        case .minutes15:       return 15 * 60
        case .minutes30:       return 30 * 60
        case .minutes60:       return 60 * 60
        case .custom(let t):   return t
        }
    }

    static var allCases: [SleepTimerOption] {
        [.off, .minutes15, .minutes30, .minutes60]
    }
}

/// 搜索结果
struct SearchResult: Identifiable {
    let id = UUID()
    let chapterIndex: Int
    let chapterTitle: String
    let matchOffset: Int       // UTF-16 offset in chapter
    let context: String        // 前后 30 字上下文
    let highlightedRange: Range<String.Index>?
}

/// 播放器视图模型：协调朗读、章节推进、书签、搜索、睡眠定时、快捷键
@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var selectedChapter: MChapter?
    @Published var bookmarks: [MBookmark] = []
    @Published var errorMessage: MAlertMessage?

    /// 搜索结果
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var showSearchSheet: Bool = false

    /// 睡眠定时
    @Published var sleepTimerOption: SleepTimerOption = .off
    @Published var sleepRemaining: TimeInterval = 0

    /// 当前书籍与解析后的文档（对外只读）
    @Published private(set) var currentBook: Book?
    @Published private(set) var currentDocument: BookDocument?

    var ttsManager = TTSManager()

    /// 全局快捷键（从外部注入）
    let hotkeyManager = GlobalHotkeyManager()

    private var currentChapterIndex: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var searchDebounceCancellable: AnyCancellable?
    private var searchTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?

    /// 进度保存回调，由 MContentView 注入并转发到 LibraryViewModel
    var onSaveProgress: ((UUID, ReadingPosition) -> Void)?

    // MARK: - 初始化

    init() {
        ttsManager.chapterFinishedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.advanceToNextChapter() }
            .store(in: &cancellables)

        // 注册全局快捷键回调
        hotkeyManager.onTogglePlayPause = { [weak self] in
            DispatchQueue.main.async { self?.togglePlayPause() }
        }
        hotkeyManager.onNextSentence = { [weak self] in
            DispatchQueue.main.async { self?.nextSentence() }
        }
        hotkeyManager.onPreviousSentence = { [weak self] in
            DispatchQueue.main.async { self?.previousSentence() }
        }
        hotkeyManager.start()

        // App 即将退出时保存当前进度
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveCurrentProgressSync()
            }
            .store(in: &cancellables)
    }

    deinit {
        restoreTask?.cancel()
        searchTask?.cancel()
        searchDebounceCancellable?.cancel()
        timerCancellable?.cancel()
        hotkeyManager.stop()
    }

    // MARK: - 书籍 & 章节（单一入口，禁止外部直接调 setBook/selectChapter）

    /// 切换书籍的唯一入口。外部只需调此方法，内部自动处理进度恢复或从头开始。
    func setupForBook(_ book: Book, via libraryVM: LibraryViewModel) async {
        stopSpeaking()
        restoreTask?.cancel()

        guard let document = await libraryVM.openBook(book) else {
            currentBook = nil
            currentDocument = nil
            selectedChapter = nil
            return
        }

        currentBook = book
        currentDocument = document
        currentChapterIndex = 0
        selectedChapter = nil
        loadBookmarks()

        restoreTask = Task {
            await restoreOrStartFromBeginning(book: book, document: document)
        }
    }

    /// 用户手动切换章节（章节列表点击）
    func userSelectChapter(_ chapter: MChapter, at index: Int) {
        guard selectedChapter?.index != index else { return }
        // 先保存旧章节进度
        saveCurrentProgress()
        selectedChapter = chapter
        currentChapterIndex = index
        ttsManager.stop()
    }

    // MARK: - 播放控制

    func togglePlayPause() {
        guard selectedChapter != nil else { return }
        switch ttsManager.playbackState {
        case .stopped, .paused:
            playCurrentChapter()
        case .playing:
            ttsManager.pause()
            saveCurrentProgress()
        }
    }

    func stopSpeaking() {
        if ttsManager.playbackState != .stopped {
            saveCurrentProgress()
        }
        ttsManager.stop()
        cancelSleepTimer()
    }

    func nextSentence() {
        guard selectedChapter != nil else { return }
        if ttsManager.playbackState == .stopped {
            playCurrentChapter()
        } else {
            ttsManager.nextSentence()
        }
    }

    func previousSentence() {
        guard selectedChapter != nil, ttsManager.playbackState != .stopped else { return }
        ttsManager.previousSentence()
    }

    // MARK: - 书签

    func addBookmark() {
        guard let book = currentBook, let chapter = selectedChapter else { return }
        let offset = max(0, ttsManager.currentGlobalOffset())
        let snippet = makeSnippet(for: chapter, offset: offset)
        let bookmark = MBookmark(
            bookID: book.id,
            chapterIndex: chapter.index,
            characterOffset: offset,
            textSnippet: snippet
        )
        Task {
            do {
                try await StorageService.shared.saveBookmark(bookmark)
            } catch {
                errorMessage = MAlertMessage(text: "书签保存失败：\(error.localizedDescription)")
            }
            await loadBookmarksAsync()
        }
    }

    func removeBookmark(_ bookmark: MBookmark) {
        Task {
            do {
                try await StorageService.shared.deleteBookmark(id: bookmark.id)
            } catch {
                errorMessage = MAlertMessage(text: "书签删除失败：\(error.localizedDescription)")
            }
            await loadBookmarksAsync()
        }
    }

    func jumpToBookmark(_ bookmark: MBookmark) {
        guard let document = currentDocument else { return }
        guard let chapter = document.chapters.first(where: { $0.index == bookmark.chapterIndex }) else { return }
        saveCurrentProgress()
        selectedChapter = chapter
        currentChapterIndex = chapter.index
        ttsManager.speak(fromCharacterOffset: bookmark.characterOffset, text: chapter.content)
    }

    func bookmarksForCurrentBook() -> [MBookmark] {
        guard let book = currentBook else { return [] }
        return bookmarks.filter { $0.bookID == book.id }
            .sorted { $0.chapterIndex < $1.chapterIndex
                || ($0.chapterIndex == $1.chapterIndex && $0.characterOffset < $1.characterOffset) }
    }

    func updateBookmarkNote(bookmarkID: UUID, note: String) {
        Task {
            do {
                try await StorageService.shared.updateBookmarkNote(id: bookmarkID, note: note)
            } catch {
                errorMessage = MAlertMessage(text: "书签备注保存失败：\(error.localizedDescription)")
            }
            await loadBookmarksAsync()
        }
    }

    // MARK: - 睡眠定时

    func setSleepTimer(_ option: SleepTimerOption) {
        cancelSleepTimer()
        sleepTimerOption = option
        guard let seconds = option.seconds else { return }
        sleepRemaining = seconds

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.sleepRemaining -= 1
                if self.sleepRemaining <= 0 {
                    self.ttsManager.stop()
                    self.cancelSleepTimer()
                }
            }
    }

    func cancelSleepTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        sleepTimerOption = .off
        sleepRemaining = 0
    }

    /// 睡眠剩余时间格式化（mm:ss）
    var sleepRemainingFormatted: String {
        guard sleepRemaining > 0 else { return "" }
        let m = Int(sleepRemaining) / 60
        let s = Int(sleepRemaining) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - 文本搜索

    /// 搜索输入防抖：停止输入 300ms 后再执行全文搜索
    func searchQueryDidChange(_ query: String) {
        searchDebounceCancellable?.cancel()
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        searchDebounceCancellable = Just(query)
            .delay(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] debouncedQuery in
                self?.search(debouncedQuery)
            }
    }

    /// 取消正在进行的搜索（关闭搜索弹窗时调用）— 不清空 searchQuery 以保持高亮
    func cancelSearch() {
        searchTask?.cancel()
        searchDebounceCancellable?.cancel()
        searchResults = []
        isSearching = false
        // 注意: 不清空 searchQuery，保持搜索词在阅读区的高亮
    }

    /// 清空搜索高亮
    func clearSearchHighlight() {
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    func search(_ query: String) {
        searchTask?.cancel()
        searchDebounceCancellable?.cancel()
        guard let document = currentDocument, !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchQuery = query

        let chapters = document.chapters
        let capturedQuery = query

        searchTask = Task.detached {
            var results: [SearchResult] = []

            for chapter in chapters {
                guard !Task.isCancelled else { break }
                let content = chapter.content
                var searchStart = content.startIndex

                while let range = content[searchStart...].range(of: capturedQuery, options: .caseInsensitive) {
                    guard !Task.isCancelled else { break }
                    let nsRange = NSRange(range, in: content)
                    let context = Self.buildContext(around: range, in: content, radius: 30)
                    results.append(SearchResult(
                        chapterIndex: chapter.index,
                        chapterTitle: chapter.title,
                        matchOffset: nsRange.location,
                        context: context,
                        highlightedRange: range
                    ))
                    searchStart = range.upperBound
                    if results.count >= 100 { break }
                }
                if Task.isCancelled || results.count >= 100 { break }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    func jumpToSearchResult(_ result: SearchResult) {
        guard let document = currentDocument else { return }
        guard let chapter = document.chapters.first(where: { $0.index == result.chapterIndex }) else { return }
        saveCurrentProgress()
        selectedChapter = chapter
        currentChapterIndex = chapter.index
        showSearchSheet = false
        // 不清空 searchQuery，保持搜索高亮在阅读区
        ttsManager.speak(fromCharacterOffset: result.matchOffset, text: chapter.content)
    }

    /// 搜索上下文构建（nonisolated 静态方法，可在任意线程安全调用）
    private nonisolated static func buildContext(around range: Range<String.Index>, in text: String, radius: Int) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -min(radius, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: min(radius, text.distance(from: range.upperBound, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
        let before = text[lower..<range.lowerBound]
        let after = text[range.upperBound..<upper]
        let display = before + "【" + text[range] + "】" + after
        return String(display)
    }

    // MARK: - 进度持久化

    /// 保存当前阅读进度（章节索引 + 句索引 → ReadingPosition）
    func saveCurrentProgress() {
        guard let book = currentBook,
              let chapter = selectedChapter,
              ttsManager.totalSentences > 0 else { return }
        let offset = ttsManager.currentGlobalOffset()
        let position = ReadingPosition(
            chapterIndex: chapter.index,
            paragraphIndex: 0,
            characterOffset: offset
        )
        onSaveProgress?(book.id, position)
    }

    /// 同步保存（App 退出时用，不阻塞主线程）
    private func saveCurrentProgressSync() {
        guard let book = currentBook,
              let chapter = selectedChapter,
              ttsManager.totalSentences > 0 else { return }
        let offset = ttsManager.currentGlobalOffset()
        let position = ReadingPosition(
            chapterIndex: chapter.index,
            paragraphIndex: 0,
            characterOffset: offset
        )
        // 直接启动一个非 MainActor 的 Task 写盘，不阻塞当前线程
        let callback = onSaveProgress
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                callback?(book.id, position)
            }
        }
    }

    /// 恢复阅读进度：定位到上次的章节和句子，不自动播放
    private func restoreOrStartFromBeginning(book: Book, document: BookDocument) async {
        if let position = book.readingPosition,
           !Task.isCancelled,
           let chapter = document.chapters.first(where: { $0.index == position.chapterIndex }) {
            selectedChapter = chapter
            currentChapterIndex = chapter.index
            let sentenceIndex = ttsManager.sentenceIndex(forCharacterOffset: position.characterOffset, in: chapter.content)
            ttsManager.prepareForRestore(text: chapter.content, sentenceIndex: sentenceIndex)
        } else if !Task.isCancelled, let firstChapter = document.chapters.first {
            selectedChapter = firstChapter
            currentChapterIndex = 0
        }
    }

    // MARK: - 私有方法

    private func playCurrentChapter() {
        guard let chapter = selectedChapter else { return }
        ttsManager.speak(text: chapter.content)
    }

    private func advanceToNextChapter() {
        guard let document = currentDocument else { return }
        let nextIndex = currentChapterIndex + 1
        guard nextIndex < document.chapters.count else { return }
        saveCurrentProgress()
        let nextChapter = document.chapters[nextIndex]
        selectedChapter = nextChapter
        currentChapterIndex = nextIndex
        ttsManager.speak(text: nextChapter.content)
    }

    private func loadBookmarks() {
        Task { await loadBookmarksAsync() }
    }

    private func loadBookmarksAsync() async {
        guard let book = currentBook else {
            bookmarks = []
            return
        }
        bookmarks = await StorageService.shared.bookmarks(for: book.id)
    }

    private func makeSnippet(for chapter: MChapter, offset: Int) -> String {
        let content = chapter.content
        let utf16Length = content.utf16.count
        guard offset >= 0, offset < utf16Length else { return chapter.snippet }
        let start = String.Index(utf16Offset: offset, in: content)
        let end = String.Index(utf16Offset: min(offset + 80, utf16Length), in: content)
        let text = String(content[start..<end])
        return text.isEmpty ? chapter.snippet : text
    }

}
