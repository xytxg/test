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
    func start(_ source:SourceEntry,app:AppModel,force:Bool=false) async {
        engine?.close();engine=nil;generation=UUID();let token=generation;sourceID=source.id
        error=nil;networkError=nil;sections=[];filters=[];busy=true
        let key=source.id+String(app.sourceRevision)+(source.fingerprint ?? "")+String(app.encryptedDNS)
        if !force,let cached=cache[key],Date().timeIntervalSince(cached.0)<90 {sections=cached.1;filters=cached.2;busy=false;return}
        guard !app.needsConfiguration(source) else {busy=false;error="请先完成这个源的配置";return}
        do {
            let runtime=try await app.makeRuntime(source)
            guard token==generation,!Task.isCancelled else{runtime.close();return};engine=runtime
            defer {runtime.close();if token==generation{engine=nil}}
            let value=try await runtime.invoke("filters")
            guard token==generation,!Task.isCancelled else{return}
            filters=try JSONDecoder().decode([SourceFilter].self,from:JSONSerialization.data(withJSONObject:value))
            var defaults:[String:String]=[:];for filter in filters{defaults[filter.key]=filter.default ?? filter.options.first?.value ?? ""}
            let primary=filters.first
            let homeOptions=primary?.options.filter{$0.home==true} ?? []
            let choices=Array((homeOptions.isEmpty ? primary?.options ?? [] : homeOptions).prefix(4))
            if let primary,!choices.isEmpty {
                for option in choices {
                    try Task.checkCancellation();guard token==generation else{return}
                    var selected=defaults;selected[primary.key]=option.value
                    let raw=try await runtime.invoke("list",["filters":selected,"surface":"home","page":1,"refresh":force])
                    let page=try JSONDecoder().decode(CatalogPage.self,from:JSONSerialization.data(withJSONObject:raw))
                    guard token==generation else{return}
                    if !page.items.isEmpty{sections.append(CatalogSection(id:option.value,title:option.label,filters:selected,cards:Array(page.items.prefix(12))))}
                    if !sections.isEmpty{busy=false}
                }
            } else {
                let raw=try await runtime.invoke("list",["filters":defaults,"surface":"home","page":1,"refresh":force])
                let page=try JSONDecoder().decode(CatalogPage.self,from:JSONSerialization.data(withJSONObject:raw))
                guard token==generation,!Task.isCancelled else{return}
                sections=[CatalogSection(id:"main",title:source.name,filters:defaults,cards:Array(page.items.prefix(12)))]
            }
            guard token==generation else{return};cache[key]=(Date(),sections,filters)
            if cache.count>3,let oldest=cache.min(by:{$0.value.0<$1.value.0})?.key{cache.removeValue(forKey:oldest)}
        } catch {
            if token == generation, !(error is CancellationError) {
                networkError = error as? HTTPNetworkError
                self.error = error.localizedDescription
            }
        }
        if token==generation{busy=false}
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
    private var key:String{app.selectedID+String(app.sourceRevision)+String(app.encryptedDNS)}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:26){
                if let source=app.selected {sourceContent(source)}else{emptyState}
            }.padding(.bottom,24)
        }
        .background(Color(uiColor:.systemGroupedBackground))
        .ignoresSafeArea(edges:home.hero.isEmpty || home.sourceID != app.selectedID ? [] : .top)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar{toolbar}
        .toolbarBackground(.hidden,for:.navigationBar)
        .task(id:key){if let source=app.selected{await home.start(source,app:app)}}
        .refreshable{if let source=app.selected{await home.start(source,app:app,force:true)}}
        .sheet(isPresented:$sourcePicker){SourcePickerView()}
        .sheet(isPresented:$search){NavigationStack{SearchView()}}
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
            ForEach(home.sections){section in sectionView(section,source:source)}
            status(source)
        }else{ProgressView("正在切换内容源…").frame(maxWidth:.infinity).padding(60)}
    }
    @ToolbarContentBuilder private var toolbar:some ToolbarContent {
        ToolbarItem(placement:.topBarLeading){
            Button{sourcePicker=true}label:{HStack(spacing:8){Image(systemName:"square.stack.3d.up");Text(app.selected?.name ?? "选择内容源").font(.subheadline.weight(.semibold)).lineLimit(1);Image(systemName:"chevron.down").font(.caption2.weight(.semibold))}.frame(maxWidth:220)}
                .accessibilityIdentifier("source-picker")
        }
        ToolbarItem(placement:.topBarTrailing){Button{search=true}label:{Image(systemName:"magnifyingglass")}.accessibilityLabel("搜索所有内容源")}
    }
    private func hero(_ source:SourceEntry)->some View {
        TabView {
            ForEach(home.hero){card in
                NavigationLink{DetailView(card:card,source:source)}label:{
                    ZStack(alignment:.bottom){
                        ArtworkView(reference:card.poster)
                        LinearGradient(colors:[.black.opacity(0.1),.clear,.black.opacity(0.55),Color(uiColor:.systemGroupedBackground)],startPoint:.top,endPoint:.bottom)
                        VStack(spacing:10){Text(card.title).font(.system(size:27,weight:.semibold)).lineLimit(2).multilineTextAlignment(.center);Text(card.subtitle ?? source.name).font(.subheadline).lineLimit(1).foregroundStyle(.white.opacity(0.85))}.foregroundStyle(.white).padding(.horizontal,30).padding(.bottom,54)
                    }
                }.buttonStyle(.plain)
            }
        }.tabViewStyle(.page(indexDisplayMode:home.hero.count>1 ? .always:.never)).frame(height:440)
    }
    @ViewBuilder private func categories(_ source:SourceEntry)->some View {
        if let primary=home.filters.first {
            ScrollView(.horizontal,showsIndicators:false){
                HStack(spacing:10){ForEach(primary.options){option in
                    NavigationLink{BrowseView(source:source,title:option.label,initialFilters:[primary.key:option.value])}label:{Text(option.label).font(.subheadline.weight(.medium)).padding(.horizontal,18).padding(.vertical,11).background(Color(uiColor:.secondarySystemGroupedBackground),in:Capsule()).overlay(Capsule().stroke(.quaternary,lineWidth:0.5))}.buttonStyle(.plain)
                }}.padding(.horizontal,20)
            }
        }
    }
    private func sectionView(_ section:CatalogSection,source:SourceEntry)->some View {
        VStack(alignment:.leading,spacing:15){
            HStack{
                Text(section.title).font(.title3.bold());Spacer()
                NavigationLink{BrowseView(source:source,title:section.title,initialFilters:section.filters)}label:{HStack(spacing:4){Text("更多");Image(systemName:"chevron.right").font(.caption2.weight(.semibold))}.font(.subheadline).foregroundStyle(.secondary)}
            }.padding(.horizontal,20)
            ScrollView(.horizontal,showsIndicators:false){
                HStack(alignment:.top,spacing:12){ForEach(section.cards){card in NavigationLink{DetailView(card:card,source:source)}label:{PosterCard(card:card,width:130)}.buttonStyle(.plain)}}.padding(.horizontal,20)
            }
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
                        } else if failure.isResolutionFailure && !app.encryptedDNS {
                            Button("用 Google 加密 DNS 重试") { app.setEncryptedDNS(true) }
                            Text("仅用于 WeBox。可以在设置中关闭。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(maxWidth: .infinity).padding(24)
        } else if !home.busy && home.sections.isEmpty {ContentUnavailableView("暂无内容",systemImage:"rectangle.stack",description:Text("试试搜索，或选择其它内容源。"))}
    }
    private var emptyState:some View {
        VStack(alignment:.leading,spacing:22){
            Image(systemName:"play.rectangle.on.rectangle").font(.system(size:52,weight:.ultraLight)).foregroundStyle(.tint).padding(.top,70)
            Text("一个播放器，\n连接你的内容。 ").font(.largeTitle.bold())
            Text("添加你自己的 JavaScript 内容源。首页、分类和影片会随源变化，观看体验始终一致。").font(.body).foregroundStyle(.secondary).lineSpacing(5)
            Button{sourcePicker=true}label:{Label("添加内容源",systemImage:"plus").frame(maxWidth:.infinity).padding(.vertical,10)}.buttonStyle(.borderedProminent).controlSize(.large)
            Text("支持文件与链接导入 · 不预装内容源").font(.caption).foregroundStyle(.tertiary)
        }.padding(28)
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
            let raw=try await runtime.invoke("filters");filters=try JSONDecoder().decode([SourceFilter].self,from:JSONSerialization.data(withJSONObject:raw))
            selection=Dictionary(uniqueKeysWithValues:filters.map{($0.key,$0.default ?? $0.options.first?.value ?? "")});selection.merge(initial){_,new in new}
            busy=false;await load(reset:true)
        }catch{if token==generation{self.error=error.localizedDescription;busy=false}}
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
    func close(){generation=UUID();engine?.close();engine=nil}
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
                if let error=model.error{VStack(spacing:12){Text(error).font(.subheadline).foregroundStyle(.secondary);Button("重试"){Task{await model.load(reset:model.cards.isEmpty)}}}.frame(maxWidth:.infinity).padding()}
                else if model.cursor != nil{Button("加载更多"){Task{await model.load(reset:false)}}.buttonStyle(.bordered).frame(maxWidth:.infinity).padding()}
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
