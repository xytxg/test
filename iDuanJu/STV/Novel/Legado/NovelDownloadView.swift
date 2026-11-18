import SwiftUI

struct NovelDownloadView: View {
    let book: NovelBook
    var chapter: Int = 0
    @Environment(\.dismiss) private var dismiss
    @AppStorage("novel.prefetch") private var prefetch = 3
    private let loader = NovelWebLoader.shared
    private let store = NovelStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        NovelBookRow(title: book.title, author: book.author ?? "", kind: "已缓存 \(store.cachedCount(book)) / \(book.chapters.count) 章", cover: book.coverURL)
                        if let state = loader.downloadStates[book.id] {
                            ProgressView(value: Double(state.completed), total: Double(max(1, state.total)))
                            Text("本次 \(state.completed)/\(state.total) · 失败 \(state.failures)").font(.caption).foregroundStyle(STVTheme.secondary)
                            if !state.message.isEmpty { Text(state.message).font(.caption).foregroundStyle(state.failures > 0 ? .red : STVTheme.secondary) }
                            if state.active { Button("暂停下载", role: .destructive) { loader.stopDownload(book) }.buttonStyle(.bordered) }
                        }
                    }.novelPanel()
                    VStack(alignment: .leading, spacing: 14) {
                        Label("离线下载", systemImage: "arrow.down.circle").font(NovelStyle.title)
                        HStack(spacing: 12) {
                            Button("缓存后 50 章") { loader.download(book, from: chapter, count: 50) }.frame(maxWidth: .infinity)
                            Button("缓存后 200 章") { loader.download(book, from: chapter, count: 200) }.frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).controlSize(.large)
                        Button { loader.download(book, from: 0, count: nil) } label: {
                            Text("下载全本 / 继续未完成下载").frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.borderedProminent)
                    }.novelPanel().disabled(loader.downloadStates[book.id]?.active == true)
                    VStack(alignment: .leading, spacing: 14) {
                        Label("提前缓存", systemImage: "bolt").font(NovelStyle.title)
                        Picker("提前缓存", selection: $prefetch) {
                            Text("关闭").tag(0); Text("3 章").tag(3); Text("10 章").tag(10); Text("20 章").tag(20)
                        }.pickerStyle(.segmented)
                        Text("阅读时自动预取后续章节，减少翻页等待。").font(.caption).foregroundStyle(STVTheme.secondary)
                    }.novelPanel()
                    Label("保持应用前台下载。已缓存章节可断网阅读，暂停或中断后可继续，已完成章节不会重复请求。", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(STVTheme.secondary)
                }.padding(NovelStyle.inset)
            }
            .novelScreen()
            .navigationTitle("缓存与下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { NovelBackButton { dismiss() } } }
        }
    }
}
