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
    func search(_ word:String,all:Bool,app:AppModel)async{
        generation=UUID();let token=generation;results=[]
        let query=word.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else{busy=false;return};busy=true
        let sources=(all ? app.enabledSources : app.selected.map{[$0]} ?? []).filter{$0.manifest?.supportsSearch != false}
        for start in stride(from:0,to:sources.count,by:2){
            guard token==generation,!Task.isCancelled else{return}
            let batch=Array(sources[start..<min(start+2,sources.count)])
            if batch.count==2{
                async let first=perform(batch[0],word:query,app:app)
                async let second=perform(batch[1],word:query,app:app)
                let pair=await[first,second];if token==generation{results+=pair}
            }else{let value=await perform(batch[0],word:query,app:app);if token==generation{results.append(value)}}
        }
        if token==generation{busy=false}
    }
    private func perform(_ source:SourceEntry,word:String,app:AppModel)async->SourceSearchResult{
        var engine:SourceRuntime?;defer{engine?.close()}
        do{
            guard !app.needsConfiguration(source) else{throw WeBoxError("这个源尚未完成配置")}
            let runtime=try await app.makeRuntime(source);engine=runtime;try Task.checkCancellation()
            _ = try await runtime.invoke("filters")
            let value=try await runtime.invoke("search",["query":word,"filters":[:],"page":1])
            let page=try JSONDecoder().decode(CatalogPage.self,from:JSONSerialization.data(withJSONObject:value))
            return SourceSearchResult(source:source,cards:page.items,error:nil,more:page.nextCursor != nil)
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
    private let columns=[GridItem(.adaptive(minimum:100,maximum:170),spacing:12,alignment:.top)]
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:22){
                Picker("搜索范围",selection:$all){Text("当前源").tag(false);Text("全部源").tag(true)}.pickerStyle(.segmented)
                if query.isEmpty{ContentUnavailableView("找一部想看的",systemImage:"magnifyingglass",description:Text("可搜索当前内容源，也可以同时检索已启用的内容源。"))}
                ForEach(model.results){result in resultSection(result)}
                if model.busy{ProgressView("正在搜索…").frame(maxWidth:.infinity).padding()}
                else if !query.isEmpty && model.results.allSatisfy({$0.cards.isEmpty && $0.error==nil}){ContentUnavailableView.search(text:query)}
            }.padding(20)
        }
        .navigationTitle("搜索").navigationBarTitleDisplayMode(.inline)
        .searchable(text:$query,prompt:"片名、关键词")
        .toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
        .onAppear{query=initialQuery;all=initiallyAll}
        .task(id:query+String(all)+String(app.sourceRevision)){
            do{try await Task.sleep(for:.milliseconds(400));try Task.checkCancellation();await model.search(query,all:all,app:app)}catch{}
        }
    }
    private func resultSection(_ result:SourceSearchResult)->some View{
        VStack(alignment:.leading,spacing:14){
            HStack{Text(result.source.name).font(.headline);Spacer();Text("\(result.cards.count) 部").font(.caption).foregroundStyle(.secondary)}
            if let error=result.error{Text(error).font(.caption).foregroundStyle(.secondary)}
            LazyVGrid(columns:columns,alignment:.leading,spacing:18){ForEach(result.cards){card in NavigationLink{DetailView(card:card,source:result.source)}label:{PosterCard(card:card)}.buttonStyle(.plain)}}
            if result.more{NavigationLink("更多结果"){BrowseView(source:result.source,title:query,query:query)}.font(.subheadline)}
        }
    }
}
