import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var section = SectionKind.history
    @State private var sourceID = ""
    @State private var query = ""
    @State private var confirmClear = false
    @State private var resumeRoute: DetailRoute?

    private enum SectionKind: String, CaseIterable {
        case history = "继续观看"
        case favorites = "我的收藏"
    }

    private var items: [LibraryItem] {
        let records = section == .history ? app.history : app.favorites
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { item in
            (sourceID.isEmpty || item.sourceID == sourceID)
                && (word.isEmpty || item.card.title.localizedCaseInsensitiveContains(word))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("资料库", selection: $section) {
                    ForEach(SectionKind.allCases, id: \.self) { kind in Text(kind.rawValue).tag(kind) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("library-section")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            if items.isEmpty { empty.listRowBackground(Color.clear) }
            ForEach(items) { item in
                let source = app.sources.first { $0.id == item.sourceID }
                if let source, source.isEnabled {
                    NavigationLink { DetailView(card: item.card, source: source) } label: { row(item, source: source) }
                        .contextMenu {
                            if section == .history {
                                Button("继续播放", systemImage: "play.fill") { resumeRoute = DetailRoute(source: source, card: item.card) }
                            }
                            Button(deleteTitle, systemImage: "trash", role: .destructive) { delete([item.id]) }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if section == .history {
                                Button("继续播放", systemImage: "play.fill") { resumeRoute = DetailRoute(source: source, card: item.card) }.tint(.accentColor)
                            }
                        }
                } else {
                    row(item, source: source)
                        .contextMenu {
                            Button(deleteTitle, systemImage: "trash", role: .destructive) { delete([item.id]) }
                        }
                }
            }
            .onDelete { offsets in delete(Set(offsets.map { items[$0].id })) }
        }
        .navigationTitle("资料库")
        .searchable(text: $query, prompt: "搜索播放记录和收藏")
        .navigationDestination(item: $resumeRoute) { route in DetailView(card: route.card, source: route.source, resumeOnOpen: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("内容源", selection: $sourceID) {
                        Text("全部内容源").tag("")
                        ForEach(app.sources) { source in Text(source.name).tag(source.id) }
                    }
                    if section == .history && !items.isEmpty {
                        Button("清除当前列表", systemImage: "trash", role: .destructive) { confirmClear = true }
                    }
                } label: {
                    Image(systemName: sourceID.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("筛选与管理资料库")
            }
        }
        .confirmationDialog("清除这 \(items.count) 条观看记录？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除观看记录", role: .destructive) { delete(Set(items.map(\.id))) }
        }
        .onChange(of: app.sources.map(\.id)) { _, ids in
            if !sourceID.isEmpty, !ids.contains(sourceID) { sourceID = "" }
        }
    }

    private var deleteTitle: String { section == .history ? "删除观看记录" : "取消收藏" }

    private func delete(_ ids: Set<String>) {
        withAnimation { app.deleteLibraryItems(ids, history: section == .history) }
    }

    @ViewBuilder private var empty: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if !sourceID.isEmpty {
            ContentUnavailableView("该源暂无\(section.rawValue)记录", systemImage: "line.3.horizontal.decrease")
        } else if section == .history {
            ContentUnavailableView("暂无观看记录", systemImage: "clock", description: Text("已播放的内容会出现在这里。"))
        } else {
            ContentUnavailableView("暂无收藏", systemImage: "heart", description: Text("在内容详情中点按收藏即可添加。"))
        }
    }

    private func row(_ item: LibraryItem, source: SourceEntry?) -> some View {
        let subtitle = source.map { $0.isEnabled ? $0.name : "\($0.name) · 已停用" } ?? "内容源已移除"
        return HStack(spacing: 14) {
            ArtworkView(reference: item.card.poster)
                .frame(width: 55, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.card.title).font(.headline).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                if section == .history {
                    Text([item.episodeName, item.seconds?.playbackTime].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if item.progress > 0 {
                        ProgressView(value: item.progress)
                            .tint(.accentColor)
                            .frame(maxWidth: 210)
                            .accessibilityLabel("观看进度")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
