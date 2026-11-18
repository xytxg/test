import SwiftUI

struct SourceSearchResult:Identifiable{
    let source:SourceEntry
    let cards:[Card]
    let error:String?
    let more:Bool
    var id:String{source.id}
}
@MainActor
final class SearchModel:ObservableObject{
    @Published var results:[SourceSearchResult]=[]
    @Published var busy=false
    private var generation=UUID()
    func search(_ word: String, all: Bool, app: AppModel) async {
        generation = UUID()
        let token = generation
        results = []
        let query = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { busy = false; return }
        busy = true
        defer { if token == generation { busy = false } }
        let sources = (all ? app.enabledSources : app.selected.map { [$0] } ?? [])
            .filter { $0.manifest?.supportsSearch != false }
        var pending = sources.enumerated().makeIterator()
        var completed: [(Int, SourceSearchResult)] = []
        await withTaskGroup(of: (Int, SourceSearchResult).self) { group in
            for _ in 0..<min(2, sources.count) {
                if let (index, source) = pending.next() {
                    group.addTask { (index, await self.perform(source, word: query, app: app)) }
                }
            }
            for await received in group {
                guard token == generation, !Task.isCancelled else { group.cancelAll(); return }
                completed.append(received)
                results = completed.sorted { $0.0 < $1.0 }.map { $0.1 }
                if let (index, source) = pending.next() {
                    group.addTask { (index, await self.perform(source, word: query, app: app)) }
                }
            }
        }
    }
    private func perform(_ source:SourceEntry,word:String,app:AppModel)async->SourceSearchResult{
        var engine:SourceRuntime?;defer{engine?.close()}
        do{
            guard !app.needsConfiguration(source) else{throw WeBoxError("这个源尚未完成配置")}
            let runtime=try await app.makeRuntime(source);engine=runtime;try Task.checkCancellation()
            _ = try await runtime.invoke("filters")
            let value=try await runtime.invoke("search",["query":word,"filters":[:],"page":1])
            let page=try JSONDecoder().decode(CatalogPage.self,from:JSONSerialization.data(withJSONObject:value))
            var seen = Set<String>()
            let cards = page.items.filter { seen.insert($0.id).inserted }
            return SourceSearchResult(source: source, cards: cards, error: nil, more: page.nextCursor != nil)
        }catch{return SourceSearchResult(source:source,cards:[],error:error.localizedDescription,more:false)}
    }
}
struct SearchView:View{
    var initialQuery=""
    var initiallyAll=false
    @EnvironmentObject private var app:AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model=SearchModel()
    @State private var query=""
    @State private var all=false
    @State private var started = false
    @State private var retry = 0
    private struct SearchKey: Equatable {
        let text: String
        let all: Bool
        let sourceID: String
        let revision: Int
        let retry: Int
    }
    private var key: SearchKey {
        SearchKey(text: query, all: all, sourceID: all ? "" : app.selectedID, revision: app.sourceRevision, retry: retry)
    }
    private let columns=[GridItem(.adaptive(minimum:100,maximum:170),spacing:12,alignment:.top)]
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:22){
                if app.enabledSources.count > 1 {
                    Picker("搜索范围", selection: $all) { Text("当前源").tag(false); Text("全部源").tag(true) }
                        .pickerStyle(.segmented)
                }
                if query.isEmpty {
                    ContentUnavailableView("搜索内容", systemImage: "magnifyingglass", description: Text("输入片名或关键词。"))
                }
                ForEach(model.results){result in resultSection(result)}
                if model.busy{ProgressView("正在搜索…").frame(maxWidth:.infinity).padding()}
                else if !query.isEmpty && model.results.allSatisfy({$0.cards.isEmpty && $0.error==nil}){ContentUnavailableView.search(text:query)}
            }.padding(20)
        }
        .navigationTitle("搜索").navigationBarTitleDisplayMode(.inline)
        .searchable(text:$query,prompt:"片名、关键词")
        .toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
        .onAppear {
            if !started { started = true; query = initialQuery; all = initiallyAll }
        }
        .task(id: key) {
            let requested = key
            do {
                if !requested.text.isEmpty { try await Task.sleep(for: .milliseconds(350)) }
                try Task.checkCancellation()
                await model.search(requested.text, all: requested.all, app: app)
            } catch { }
        }
    }
    private func resultSection(_ result:SourceSearchResult)->some View{
        VStack(alignment:.leading,spacing:14){
            HStack{Text(result.source.name).font(.headline);Spacer();Text("\(result.cards.count) 部").font(.caption).foregroundStyle(.secondary)}
            if let error = result.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    if !model.busy { Button("重新搜索") { retry += 1 }.font(.footnote) }
                }
            }
            LazyVGrid(columns:columns,alignment:.leading,spacing:18){ForEach(result.cards){card in NavigationLink{DetailView(card:card,source:result.source)}label:{PosterCard(card:card)}.buttonStyle(.plain)}}
            if result.more{NavigationLink("更多结果"){BrowseView(source:result.source,title:query,query:query)}.font(.subheadline)}
        }
    }
}
