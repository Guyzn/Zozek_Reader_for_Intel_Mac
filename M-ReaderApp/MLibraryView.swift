import SwiftUI

/// 书架视图：展示已添加的书籍列表
struct MLibraryView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel

    var body: some View {
        List(selection: Binding<Book?>(
            get: { libraryVM.selectedBook },
            set: { book in
                libraryVM.selectedBook = book
                libraryVM.selectedBookID = book?.id
            }
        )) {
            if libraryVM.books.isEmpty {
                Text("点击 + 或拖入 TXT/EPUB/DOCX 书籍")
                    .foregroundColor(Color.mSecondary)
            } else {
                ForEach(libraryVM.books) { book in
                    HStack {
                        Image(systemName: bookIcon(for: book.fileType))
                        VStack(alignment: .leading) {
                            Text(book.title)
                                .lineLimit(1)
                            Text("\(book.totalChapters) 章")
                                .font(.caption)
                                .foregroundColor(Color.mSecondary)
                        }
                    }
                    .tag(book)
                    .contextMenu {
                        Button("删除") {
                            libraryVM.removeBook(id: book.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func bookIcon(for format: BookFormat) -> String {
        switch format {
        case .epub: return "doc.zipper"
        case .txt:  return "doc.text"
        case .docx: return "doc.richtext"
        }
    }
}
