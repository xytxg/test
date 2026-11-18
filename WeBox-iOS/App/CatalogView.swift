import SwiftUI

struct DetailRoute:Hashable { let source:SourceEntry;let card:Card }

struct CatalogSection: Identifiable {
    let id: String
    let title: String
    let filters: [String:String]
    let cards: [Card]
}
@MainActor
final class HomeCatalogModel: ObservableObject {
    @Published var sections:[CatalogSection]=[]
    @Published private(set) var sourceID=""
    @Published var filters:[SourceFilter]=[]
    @Published var busy=false
    @Published var error:String?
    @Published private(set) var networkError: HTTPNetworkError?
    private var engine:SourceRuntime?
    private var generation=UUID()
    private var cache:[String:(Date,[CatalogSection],[SourceFilter])]=[:]
    var hero:[Card]{Array(sections.first?.cards.prefix(6) ?? [])}
    func start(_ source: SourceEntry, app: AppModel, force: Bool = false) async {
        engine?.close()
        engine = nil
        generation = UUID()
        let token = generation
        let sameSource = sourceID == source.id
        sourceID = source.id
        error = nil
        networkError = nil
        if !sameSource { sections = []; filters = [] }
        let key = [source.id, String(app.sourceRevision), source.fingerprint ?? "", String(app.encryptedDNS)].joined(separator: ":")
        if !force, let cached = cache[key], Date().timeIntervalSince(cached.0) < 90 {
            sections = cached.1
            filters = cached.2
            busy = false
            return
        }
        busy = true
        defer { if token == generation { busy = false } }
        guard !app.needsConfiguration(source) else {
            sections = []
            filters = []
            error = "请先完成这个源的配置"
            return
        }
        do {
            let runtime = try await app.makeRuntime(source)
            defer {
                runtime.close()
                if token == generation { engine = nil }
            }
            guard token == generation, !Task.isCancelled else { return }
            engine = runtime
            let value = try await runtime.invoke("filters")
            guard token == generation, !Task.isCancelled else { return }
            let decoded = try JSONDecoder().decode([SourceFilter].self, from: JSONSerialization.data(withJSONObject: value))
            filters = decoded
            var defaults: [String: String] = [:]
            for filter in decoded { defaults[filter.key] = filter.default ?? filter.options.first?.value ?? "" }

            let primary = decoded.first
            let homeOptions = primary?.options.filter { $0.home == true } ?? []
            let choices = (homeOptions.isEmpty ? primary?.options ?? [] : homeOptions).prefix(4)
            var requests = choices.map { option in
                var selected = defaults
                if let primary { selected[primary.key] = option.value }
                return (id: option.value, title: option.label, filters: selected)
            }
            if requests.isEmpty { requests = [(id: "main", title: source.name, filters: defaults)] }
            var loaded: [CatalogSection] = []
            var firstFailure: Error?
            var receivedPage = false
            for request in requests {
                do {
                    try Task.checkCancellation()
                    guard token == generation else { return }
                    let raw = try await runtime.invoke("list", ["filters": request.filters, "surface": "home", "page": 1, "refresh": force])
                    guard token == generation, !Task.isCancelled else { return }
                    let page = try JSONDecoder().decode(CatalogPage.self, from: JSONSerialization.data(withJSONObject: raw))
                    receivedPage = true
                    var seen = Set<String>()
                    let cards = page.items.filter { seen.insert($0.id).inserted }.prefix(12)
                    if !cards.isEmpty {
                        loaded.append(CatalogSection(id: request.id, title: request.title, filters: request.filters, cards: Array(cards)))
                        sections = loaded
                    }
                } catch {
                    guard !(error is CancellationError), token == generation else { return }
                    if loaded.isEmpty, let failure = error as? HTTPNetworkError,
                       failure.isResolutionFailure || failure.cellularDenied {
                        throw failure
                    }
                    firstFailure = firstFailure ?? error
                }
            }
            if loaded.isEmpty, let firstFailure { throw firstFailure }
            if receivedPage { sections = loaded }
            if firstFailure == nil { cache[key] = (Date(), loaded, decoded) }
            if cache.count > 3, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache.removeValue(forKey: oldest) }
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            networkError = error as? HTTPNetworkError
            self.error = error.localizedDescription
        }
    }
}

struct CatalogView: View {
    @EnvironmentObject private var app:AppModel
    @Environment(\.openURL) private var openURL
    @StateObject private var home=HomeCatalogModel()
    @State private var sourcePicker=false
    @State private var search=false
    @State private var configure:SourceEntry?
    @State private var fixtureDetail:DetailRoute?
    @State private var fixtureOpened=false
    @Environment(\.horizontalSizeClass) private var horizontalSize
    private var key:String{app.selectedID+String(app.sourceRevision)+String(app.encryptedDNS)}
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:24){
                if let source=app.selected {sourceContent(source)}else{emptyState}
            }.padding(.bottom,24)
        }
        .background(Color(uiColor:.systemGroupedBackground))
        .ignoresSafeArea(edges:home.hero.isEmpty || home.sourceID != app.selectedID ? [] : .top)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar{toolbar}
        .task(id:key){if let source=app.selected{await home.start(source,app:app)}}
        .refreshable{if let source=app.selected{await home.start(source,app:app,force:true)}}
        .sheet(isPresented:$sourcePicker){SourcePickerView()}
        .sheet(isPresented:$search){NavigationStack{SearchView(initiallyAll: app.enabledSources.count > 1)}}
        .sheet(item:$configure){source in NavigationStack{SourceConfigurationView(source:source)}}
        .onChange(of:home.sections.count){_,count in
            if count>0 {ScreenshotSupport.mark("discover")}
            #if DEBUG
            if count>0,!fixtureOpened,(ProcessInfo.processInfo.arguments.contains("--screen-detail") || ProcessInfo.processInfo.arguments.contains("--screen-player")),let source=app.selected,let card=home.hero.first { fixtureOpened=true;fixtureDetail=DetailRoute(source:source,card:card) }
            #endif
            if count>0 && ProcessInfo.processInfo.arguments.contains("--screen-sources"){sourcePicker=true}
        }
        .onAppear{if app.sources.isEmpty && ProcessInfo.processInfo.arguments.contains("--screen-empty"){ScreenshotSupport.mark("empty")}}
        .navigationDestination(item:$fixtureDetail){route in DetailView(card:route.card,source:route.source)}
    }
    @ViewBuilder private func sourceContent(_ source:SourceEntry)->some View {
        if home.sourceID==source.id {
            if !home.hero.isEmpty{hero(source)}
            categories(source)
            resumeShelf(source)
            ForEach(home.sections){section in sectionView(section,source:source)}
            status(source)
        }else{ProgressView("正在切换内容源…").frame(maxWidth:.infinity).padding(60)}
    }
    @ToolbarContentBuilder private var toolbar:some ToolbarContent {
        ToolbarItem(placement:.topBarLeading){
            Button{sourcePicker=true}label:{HStack(spacing:8){Image(systemName:"square.stack.3d.up");Text(app.selected?.name ?? "选择内容源").font(.subheadline.weight(.semibold)).lineLimit(1);Image(systemName:"chevron.down").font(.caption2.weight(.semibold))}.frame(maxWidth:220)}
                .accessibilityIdentifier("source-picker")
        }
        ToolbarItem(placement:.topBarTrailing){Button{search=true}label:{Image(systemName:"magnifyingglass")}.accessibilityLabel("搜索内容")}
    }
    private func hero(_ source: SourceEntry) -> some View {
        TabView {
            ForEach(home.hero) { card in
                NavigationLink { DetailView(card: card, source: source) } label: {
                    ZStack(alignment: .bottomLeading) {
                        ArtworkView(reference: card.poster)
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.19), location: 0),
                            .init(color: .clear, location: 0.40),
                            .init(color: .black.opacity(0.85), location: 0.90)
                        ], startPoint: .top, endPoint: .bottom)
                        HStack(alignment: .bottom, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(card.title).font(.largeTitle.weight(.semibold)).lineLimit(2)
                                Text(card.subtitle ?? source.name).font(.subheadline).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .glassPill()
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 52)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: home.hero.count > 1 ? .always : .never))
        .frame(height: horizontalSize == .regular ? 500 : 380)
    }

    @ViewBuilder private func categories(_ source: SourceEntry) -> some View {
        if let primary = home.filters.first, !primary.options.isEmpty {
            ScrollView(.horizontal) {
                GlassControls(spacing: 8) {
                    LazyHStack(spacing: 8) {
                        ForEach(primary.options) { option in
                            NavigationLink {
                                BrowseView(source: source, title: option.label, initialFilters: [primary.key: option.value])
                            } label: {
                                Text(option.label).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .glassPill()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func resumeShelf(_ source: SourceEntry) -> some View {
        let recent = Array(app.history.lazy.filter { $0.sourceID == source.id && ($0.seconds ?? 0) > 0 }.prefix(6))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("继续观看", systemImage: "clock").font(.title3.weight(.semibold))
                    .padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(recent) { item in
                            NavigationLink {
                                DetailView(card: item.card, source: source, resumeOnOpen: true)
                            } label: {
                                HStack(spacing: 10) {
                                    ArtworkView(reference: item.card.poster)
                                        .frame(width: 46, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.card.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text([item.episodeName, item.seconds?.playbackTime].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        if item.progress > 0 { ProgressView(value: item.progress).tint(.accentColor) }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(.tint)
                                }
                                .padding(9)
                                .frame(width: 225)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func sectionView(_ section: CatalogSection, source: SourceEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(section.title).font(.title3.weight(.semibold))
                Spacer()
                NavigationLink {
                    BrowseView(source: source, title: section.title, initialFilters: section.filters)
                } label: {
                    Label("全部", systemImage: "chevron.right")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).frame(minHeight: 40).glassPill()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(section.title)全部内容")
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(section.cards) { card in
                        NavigationLink { DetailView(card: card, source: source) } label: {
                            PosterCard(card: card, width: horizontalSize == .regular ? 152 : 122)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
    @ViewBuilder private func status(_ source:SourceEntry)->some View {
        if home.busy{ProgressView("正在读取内容…").frame(maxWidth:.infinity).padding(30)}
        if let message=home.error {
            VStack(spacing: 14) {
                Image(systemName: app.needsConfiguration(source) ? "slider.horizontal.3" : "wifi.exclamationmark")
                    .font(.title2)
                Text(message).font(.subheadline).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary).textSelection(.enabled)
                if app.needsConfiguration(source) {
                    Button("配置这个源") { configure = source }.buttonStyle(.borderedProminent)
                } else {
                    Button("重新加载") { Task { await home.start(source, app: app, force: true) } }
                        .buttonStyle(.bordered)
                    if let failure = home.networkError {
                        if failure.cellularDenied {
                            Button("打开 iOS 设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        } else {
                            if failure.isResolutionFailure && !app.encryptedDNS && app.sourceHTTPSProxy == nil && !app.useSurgeVIF {
                                Button("用备用 DNS 重试") { app.setEncryptedDNS(true) }
                            }
                            NavigationLink("设置源网络线路") { SourceNetworkSettingsView() }
                            NavigationLink("查看请求日志") { SourceRequestLogView() }
                        }
                    }
                }
            }.frame(maxWidth: .infinity).padding(24)
        } else if !home.busy && home.sections.isEmpty {ContentUnavailableView("暂无内容",systemImage:"rectangle.stack",description:Text("试试搜索，或选择其它内容源。"))}
    }
    private var emptyState: some View {
        ContentUnavailableView {
            Label(app.sources.isEmpty ? "添加内容源" : "选择内容源", systemImage: "play.rectangle.on.rectangle")
        } description: {
            Text(app.sources.isEmpty ? "从文件或链接导入 JS，首页会显示该源的分类和内容。" : "在内容源管理中启用要使用的源。")
        } actions: {
            Button(app.sources.isEmpty ? "添加内容源" : "管理内容源", systemImage: "plus") { sourcePicker = true }
                .primaryGlassButton()
                .controlSize(.large)
        }
        .padding(.top, 38)
    }
}

@MainActor
final class BrowseModel:ObservableObject {
    @Published var cards:[Card]=[]
    @Published var filters:[SourceFilter]=[]
    @Published var selection:[String:String]=[:]
    @Published var busy=false
    @Published var error:String?
    @Published var cursor:String?
    private var engine:SourceRuntime?
    private var generation=UUID()
    private var query=""
    func start(_ source:SourceEntry,app:AppModel,initial:[String:String],query:String="")async{
        engine?.close();engine=nil;generation=UUID();let token=generation;self.query=query
        busy=true;error=nil;cards=[]
        do{
            let runtime=try await app.makeRuntime(source);guard token==generation,!Task.isCancelled else{runtime.close();return};engine=runtime
            let raw = try await runtime.invoke("filters")
            guard token == generation, !Task.isCancelled else { return }
            filters = try JSONDecoder().decode([SourceFilter].self, from: JSONSerialization.data(withJSONObject: raw))
            selection = Dictionary(filters.map { ($0.key, $0.default ?? $0.options.first?.value ?? "") }, uniquingKeysWith: { first, _ in first })
            selection.merge(initial) { _, new in new }
            busy=false;await load(reset:true)
        } catch {
            if token == generation {
                engine?.close()
                engine = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
                busy = false
            }
        }
    }
    func load(reset:Bool)async{
        guard !busy,let engine else{return};if !reset && cursor==nil{return}
        busy=true;error=nil;let token=generation;defer{if token==generation{busy=false}}
        if reset{cards=[];cursor=nil}
        var request:[String:Any]=["filters":selection,"surface":"browse","query":query];if !reset,let cursor{request["cursor"]=cursor}
        do{
            let value=try await engine.invoke(query.isEmpty ? "list":"search",request)
            let page=try JSONDecoder().decode(CatalogPage.self,from:JSONSerialization.data(withJSONObject:value))
            guard token==generation,!Task.isCancelled else{return}
            if !reset,page.nextCursor==cursor, page.nextCursor != nil{throw WeBoxError("源返回了重复的分页游标，请刷新")}
            var seen=Set(cards.map(\.id));cards+=page.items.filter{seen.insert($0.id).inserted};cursor=page.nextCursor
            if let updates=page.filters{for filter in updates{if !filters.contains(where:{$0.key==filter.key}){filters.append(filter);selection[filter.key]=filter.default ?? filter.options.first?.value}}}
        }catch{if token==generation,!(error is CancellationError){self.error=error.localizedDescription}}
    }
    var hasRuntime: Bool { engine != nil }
    func close(){generation=UUID();engine?.close();engine=nil;busy=false}
}
struct BrowseView:View {
    let source:SourceEntry
    let title:String
    var initialFilters:[String:String]=[:]
    var query:String=""
    @EnvironmentObject private var app:AppModel
    @StateObject private var model=BrowseModel()
    private let columns=[GridItem(.adaptive(minimum:105,maximum:180),spacing:12,alignment:.top)]
    var body:some View {
        ScrollView{
            VStack(alignment:.leading,spacing:18){
                ForEach(model.filters){filter in filterMenu(filter)}
                LazyVGrid(columns:columns,alignment:.leading,spacing:22){ForEach(model.cards){card in NavigationLink{DetailView(card:card,source:source)}label:{PosterCard(card:card)}.buttonStyle(.plain)}}
                if model.busy{ProgressView().frame(maxWidth:.infinity).padding()}
                if let error=model.error{VStack(spacing:12){Text(error).font(.subheadline).foregroundStyle(.secondary);Button("重试"){Task{
                    if model.hasRuntime { await model.load(reset:model.cards.isEmpty) }
                    else { await model.start(source,app:app,initial:initialFilters,query:query) }
                }}}.frame(maxWidth:.infinity).padding()}
                else if model.cursor != nil {
                    Button("加载更多") { Task { await model.load(reset: false) } }
                        .primaryGlassButton().frame(maxWidth: .infinity).padding()
                } else if !model.busy && model.cards.isEmpty {
                    ContentUnavailableView("此分类暂无内容", systemImage: "rectangle.stack")
                }
            }.padding(20)
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor:.systemGroupedBackground))
            .task{if model.cards.isEmpty{await model.start(source,app:app,initial:initialFilters,query:query)}}
            .refreshable{await model.load(reset:true)}
    }
    private func filterMenu(_ filter:SourceFilter)->some View{
        HStack{Text(filter.label).font(.subheadline).foregroundStyle(.secondary);Spacer();Picker(filter.label,selection:Binding(get:{model.selection[filter.key] ?? ""},set:{model.selection[filter.key]=$0;Task{await model.load(reset:true)}})){ForEach(filter.options){option in Text(option.label).tag(option.value)}}.disabled(model.busy)}
    }
}
