import SwiftUI

@MainActor
final class CatalogModel: ObservableObject {
    @Published var cards: [Card] = []
    @Published var filters: [SourceFilter] = []
    @Published var selection: [String: String] = [:]
    @Published var busy = false
    @Published var error: String?
    @Published var nextCursor: String?
    var runtime: SourceRuntime?
    private var query = ""
    private var generation = UUID()
    func start(_ source: SourceEntry, app: AppModel) async {
        runtime?.close(); runtime = nil
        let gen = UUID(); generation = gen
        cards = []; filters = []; selection = [:]; busy = true; error = nil
        do {
            let engine = try await app.makeRuntime(source)
            guard generation == gen, !Task.isCancelled else { engine.close(); return }
            runtime = engine
            do { filters = try decode([SourceFilter].self, await engine.invoke("filters")) }
            catch { filters = [] }
            for filter in filters { selection[filter.key] = filter.default ?? filter.options.first?.value ?? "" }
            busy = false
            await load(query: "", reset: true)
        } catch { if generation == gen { self.error = error.localizedDescription; busy = false } }
    }
    func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
    func load(query: String, reset: Bool) async {
        guard !busy, let runtime else { return }
        if !reset && nextCursor == nil { return }
        busy = true; error = nil
        let gen = generation
        if reset { cards = []; nextCursor = nil; self.query = query }
        defer { if generation == gen { busy = false } }
        var request: [String: Any] = ["filters": selection, "query": self.query]
        if !reset, let nextCursor { request["cursor"] = nextCursor }
        do {
            let result = try await runtime.invoke(self.query.isEmpty ? "list" : "search", request)
            let page = try decode(CatalogPage.self, result)
            guard generation == gen, !Task.isCancelled else { return }
            var seen = Set(cards.map(\.id))
            cards += page.items.filter { seen.insert($0.id).inserted }
            nextCursor = page.nextCursor
        } catch { if generation == gen, !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}

struct CatalogView: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var catalog = CatalogModel()
    @State private var search = ""
    @State private var showSources = false
    @State private var screenshotDetail = false
    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 180), spacing: 14)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("你的故事，随时开场").font(.title2.bold())
                        Text(app.selected?.name ?? "添加一个内容源，开始浏览")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.rectangle.fill").font(.system(size: 34)).foregroundStyle(.tint)
                }.padding(.top, 12)
                if !catalog.filters.isEmpty && search.isEmpty {
                    ForEach(catalog.filters) { filter in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filter.options) { option in
                                    Button {
                                        guard !catalog.busy else { return }
                                        catalog.selection[filter.key] = option.value
                                        Task { await catalog.load(query: "", reset: true) }
                                    } label: {
                                        Text(option.label).font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .background(catalog.selection[filter.key] == option.value ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: Capsule())
                                            .foregroundStyle(catalog.selection[filter.key] == option.value ? Color.white : Color.primary)
                                    }.buttonStyle(.plain).disabled(catalog.busy)
                                }
                            }
                        }
                    }
                }
                if app.selected == nil {
                    ContentUnavailableView { Label("还没有内容源", systemImage: "externaldrive.badge.plus") } description: { Text("导入 .webox.js 文件，或粘贴源链接。") } actions: { Button("添加源") { showSources = true }.buttonStyle(.borderedProminent) }
                } else {
                    HStack { Text(search.isEmpty ? "精选内容" : "搜索结果").font(.headline); Spacer(); Text("\(catalog.cards.count) 部").font(.caption).foregroundStyle(.secondary) }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(catalog.cards) { card in
                            if let source = app.selected {
                                NavigationLink { DetailView(card: card, source: source) } label: { PosterCard(card: card) }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let error = catalog.error {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark").font(.title2)
                            Text(error).font(.subheadline).multilineTextAlignment(.center)
                            Button("重新加载") { Task { await catalog.load(query: search, reset: catalog.cards.isEmpty) } }.buttonStyle(.bordered)
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if catalog.cards.isEmpty && !catalog.busy {
                        ContentUnavailableView("没有找到内容", systemImage: "magnifyingglass", description: Text("换个关键词，或切换分类试试。"))
                    }
                    if catalog.busy { ProgressView("正在加载源…").frame(maxWidth: .infinity).padding() }
                    else if catalog.nextCursor != nil {
                        Button("加载更多") { Task { await catalog.load(query: search, reset: false) } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .navigationTitle("发现")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(app.sources) { source in Button(source.name) { app.selectedID = source.id; app.persist() } }
                    Button("管理内容源", systemImage: "slider.horizontal.3") { showSources = true }
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .searchable(text: $search, prompt: "搜索剧名、关键词")
        .onSubmit(of: .search) { Task { await catalog.load(query: search, reset: true) } }
        .onChange(of: search) { _, value in if value.isEmpty { Task { await catalog.load(query: "", reset: true) } } }
        .task(id: app.selectedID + (app.selected?.version ?? "") + (app.selected?.origin ?? "") + String(app.sourceRevision)) {
            search = ""
            if let source = app.selected { await catalog.start(source, app: app) }
        }
        .refreshable { await catalog.load(query: search, reset: true) }
        .onChange(of: catalog.cards.count) { _, count in
            if count > 0 && ProcessInfo.processInfo.arguments.contains("--screen-detail") { screenshotDetail = true }
        }
        .navigationDestination(isPresented: $screenshotDetail) {
            if let card = catalog.cards.first, let source = app.selected { DetailView(card: card, source: source) }
        }
        .sheet(isPresented: $showSources) { NavigationStack { SourcesView().toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { showSources = false } } } } }
    }
}

struct PosterCard: View {
    let card: Card
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(url: card.poster, title: card.title).aspectRatio(0.69, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(card.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let subtitle = card.subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }.accessibilityElement(children: .combine)
    }
}
struct PosterImage: View {
    var url: String?
    var title: String
    private var fallback: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            VStack(spacing: 12) { Image(systemName: "play.rectangle").font(.system(size: 30, weight: .light)); Text(title).font(.headline).multilineTextAlignment(.center).padding(.horizontal, 12) }.foregroundStyle(.secondary)
        }
    }
    var body: some View {
        GeometryReader { proxy in
            if let url, let parsed = URL(string: url), ["https", "http"].contains(parsed.scheme ?? "") {
                AsyncImage(url: parsed) { image in image.resizable().scaledToFill() } placeholder: { fallback }
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            } else { fallback.frame(width: proxy.size.width, height: proxy.size.height) }
        }
    }
}
