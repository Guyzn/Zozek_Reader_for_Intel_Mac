import SwiftUI

/// 章节列表视图：展示当前选中书籍的章节
struct MChapterListView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let book = playerVM.currentBook {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                    .padding()
                Divider()
                if let chapters = playerVM.currentDocument?.chapters {
                    List(selection: Binding<MChapter?>(
                        get: { playerVM.selectedChapter },
                        set: { chapter in
                            if let chapter = chapter {
                                playerVM.userSelectChapter(chapter, at: chapter.index)
                            }
                        }
                    )) {
                        ForEach(chapters) { chapter in
                            Text(chapter.title)
                                .lineLimit(2)
                                .tag(chapter)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Spacer()
                    Text("正在加载章节…")
                        .foregroundColor(Color.mSecondary)
                    Spacer()
                }
            } else {
                Spacer()
                Text("请先添加并选择一本书")
                    .foregroundColor(Color.mSecondary)
                Spacer()
            }
        }
    }
}
