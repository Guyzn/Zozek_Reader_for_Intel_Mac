import SwiftUI

/// 阅读主视图：段落级渲染，支持朗读段落高亮、搜索词高亮和自动滚动
struct MReaderView: View {
    @ObservedObject var playerVM: PlayerViewModel

    var body: some View {
        InnerReaderView(playerVM: playerVM, ttsManager: playerVM.ttsManager)
    }
}

private struct InnerReaderView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var ttsManager: TTSManager
    @State private var displayedParagraphIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if let chapter = playerVM.selectedChapter {
                // 顶部进度指示（仅播放中显示）
                if ttsManager.playbackState != .stopped,
                   ttsManager.totalSentences > 0 {
                    ProgressView(value: Double(ttsManager.currentSentenceIndex),
                                 total: Double(max(ttsManager.totalSentences, 1)))
                        .tint(Color.mAccent.opacity(0.7))
                        .frame(height: 3)
                        .scaleEffect(x: 1, y: 0.7, anchor: .center)
                }

                // 段落列表 + 自动滚动
                // 使用 LazyVStack 替代 List，避免大章节一次性实例化所有段落视图
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(chapter.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                paragraphView(paragraph, paragraphIndex: index, chapter: chapter)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: ttsManager.currentSentenceIndex) { _ in
                        guard let chapter = playerVM.selectedChapter else { return }
                        let offset = ttsManager.currentGlobalOffset()
                        let newIdx = chapter.paragraphIndex(forGlobalOffset: offset)
                        if newIdx != displayedParagraphIndex {
                            displayedParagraphIndex = newIdx
                            proxy.scrollTo(newIdx, anchor: .center)
                        }
                    }
                    .onChange(of: playerVM.selectedChapter?.id) { _, _ in
                        displayedParagraphIndex = 0
                        proxy.scrollTo(0, anchor: .top)
                    }
                }

                Divider()

                MControlPanelView(playerVM: playerVM)
                    .padding()
                    .background(Color.mControlBackground)
            } else {
                Spacer()
                VStack {
                    Image(systemName: "book")
                        .font(.system(size: 48))
                        .foregroundColor(Color.mSecondary)
                    Text("选择左侧书籍开始阅读")
                        .foregroundColor(Color.mSecondary)
                        .padding(.top)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 单个段落的渲染视图
    private func paragraphView(_ text: String, paragraphIndex: Int, chapter: MChapter) -> some View {
        let isCurrent = paragraphIndex == displayedParagraphIndex && ttsManager.playbackState != .stopped
        return Text(highlightedParagraph(text, paragraphIndex: paragraphIndex))
            .font(.system(size: 16, weight: .regular, design: .serif))
            .lineSpacing(6)
            // 通过 Text 修饰符设置静态主色，避免 AttributedString 内部解析动态颜色
            .foregroundColor(Color.mPrimary)
            .padding(.horizontal)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color.mHighlightBackground : Color.clear)
            .cornerRadius(4)
    }

    /// 生成带搜索高亮和当前段落标记的 AttributedString
    /// 注意：不再在此设置任何文本前景色，全部交由外层 Text 修饰符处理，
    /// 以彻底避免 macOS 15 上 AttributedString 颜色解析触发递归。
    private func highlightedParagraph(_ text: String, paragraphIndex: Int) -> AttributedString {
        var attr = AttributedString(text)

        // 搜索词高亮（仅设置背景色）
        let query = playerVM.searchQuery
        if !query.isEmpty {
            let nsText = text as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)
            repeat {
                let found = nsText.range(of: query, options: .caseInsensitive, range: searchRange)
                guard found.location != NSNotFound else { break }
                let nextLocation = found.location + found.length
                defer { searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation) }
                if let swiftRange = Range(found, in: text),
                   let attrLower = AttributedString.Index(swiftRange.lowerBound, within: attr),
                   let attrUpper = AttributedString.Index(swiftRange.upperBound, within: attr) {
                    attr[attrLower..<attrUpper].backgroundColor = Color.mSearchHighlight
                }
            } while searchRange.location < nsText.length && searchRange.length > 0
        }

        return attr
    }
}
