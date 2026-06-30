import SwiftUI

/// 文本搜索结果视图：显示所有章节中的关键词匹配，点击跳转
struct SearchResultView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @State private var query: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.mSecondary)
                TextField("搜索关键词…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { playerVM.search(query) }
                    .onChange(of: query) { _, newQuery in
                        playerVM.searchQueryDidChange(newQuery)
                    }
                Button("搜索") { playerVM.search(query) }
                    .disabled(query.isEmpty)
            }
            .padding()

            Divider()

            // 结果列表
            if playerVM.isSearching {
                Spacer()
                ProgressView("搜索中…")
                Spacer()
            } else if playerVM.searchResults.isEmpty && !query.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass").font(.title).foregroundColor(Color.mSecondary)
                    Text("未找到「\(query)」").foregroundColor(Color.mSecondary)
                }
                Spacer()
            } else if playerVM.searchResults.isEmpty {
                Spacer()
                Text("输入关键词开始搜索").foregroundColor(Color.mSecondary)
                Spacer()
            } else {
                Text("找到 \(playerVM.searchResults.count) 条结果")
                    .font(.caption)
                    .foregroundColor(Color.mSecondary)
                    .padding(.horizontal)
                    .padding(.top, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(playerVM.searchResults) { result in
                            Button(action: {
                                playerVM.jumpToSearchResult(result)
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("第 \(result.chapterIndex + 1) 章 · \(result.chapterTitle)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.mPrimary)
                                    Text(result.context)
                                        .font(.caption)
                                        .lineLimit(3)
                                        .foregroundColor(Color.mSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
        .onDisappear {
            playerVM.cancelSearch()
        }
    }
}
