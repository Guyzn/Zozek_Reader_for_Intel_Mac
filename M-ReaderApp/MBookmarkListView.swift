import SwiftUI

/// 书签列表视图：展示当前书籍的所有书签，点击可跳转，支持备注编辑
struct MBookmarkListView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @State private var editingBookmark: MBookmark?
    @State private var noteText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Text("书签")
                .font(.headline)
                .padding()
            Divider()

            let bookmarks = playerVM.bookmarksForCurrentBook()
            if bookmarks.isEmpty {
                Spacer()
                Text(playerVM.selectedChapter == nil ? "未选择书籍" : "暂无书签")
                    .foregroundColor(Color.mSecondary)
                Spacer()
            } else {
                List {
                    ForEach(bookmarks) { bookmark in
                        bookmarkRow(bookmark)
                    }
                    .onDelete { indexSet in
                        let toDelete = indexSet.compactMap { bookmarks[$0] }
                        toDelete.forEach { playerVM.removeBookmark($0) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $editingBookmark) { bookmark in
            noteEditorSheet(for: bookmark)
        }
    }

    // MARK: - 书签行

    private func bookmarkRow(_ bookmark: MBookmark) -> some View {
        HStack {
            Button(action: { playerVM.jumpToBookmark(bookmark) }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(bookmark.chapterIndex + 1) 章")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(bookmark.textSnippet)
                        .font(.caption)
                        .lineLimit(3)
                        .foregroundColor(Color.mSecondary)
                    HStack(spacing: 6) {
                        Text(bookmark.createdAt, style: .date)
                            .font(.caption2)
                            .foregroundColor(Color.mSecondary)
                        if !bookmark.note.isEmpty {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundColor(Color.mAccent)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                noteText = bookmark.note
                editingBookmark = bookmark
            }) {
                Image(systemName: bookmark.note.isEmpty ? "square.and.pencil" : "pencil.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(bookmark.note.isEmpty ? "添加备注" : "编辑备注")
        }
        .contextMenu {
            Button("编辑备注") {
                noteText = bookmark.note
                editingBookmark = bookmark
            }
            Divider()
            Button("删除") {
                playerVM.removeBookmark(bookmark)
            }
        }
    }

    // MARK: - 备注编辑 Sheet

    private func noteEditorSheet(for bookmark: MBookmark) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑书签备注")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("书签摘要")
                    .font(.caption)
                    .foregroundColor(Color.mSecondary)
                Text(bookmark.textSnippet)
                    .font(.caption)
                    .lineLimit(3)
                    .padding(8)
                    .background(Color.mControlBackground)
                    .cornerRadius(6)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("备注")
                    .font(.caption)
                    .foregroundColor(Color.mSecondary)
                TextEditor(text: $noteText)
                    .font(.body)
                    .frame(minHeight: 100)
                    .border(Color.mSeparator.opacity(0.5), width: 1)
                    .cornerRadius(4)
            }
            .padding()

            Spacer()

            Divider()
            HStack {
                Button("取消") {
                    noteText = ""
                    editingBookmark = nil
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("保存") {
                    playerVM.updateBookmarkNote(bookmarkID: bookmark.id, note: noteText)
                    editingBookmark = nil
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(noteText == bookmark.note)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }
}
