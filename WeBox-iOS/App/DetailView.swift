import SwiftUI

@MainActor
final class DetailModel:ObservableObject{
    @Published var detail:ContentDetail?
    @Published var error:String?
    @Published var busy=false
    private var engine:SourceRuntime?
    func load(_ card:Card,source:SourceEntry,app:AppModel)async{
        guard !busy else{return};busy=true;error=nil;defer{busy=false;engine?.close();engine=nil}
        do{
            let runtime=try await app.makeRuntime(source);engine=runtime
            let raw=try await runtime.invoke("detail",["id":card.id,"link":card.link ?? "","title":card.title])
            try Task.checkCancellation()
            detail=try JSONDecoder().decode(ContentDetail.self,from:JSONSerialization.data(withJSONObject:raw))
            if detail?.title.isEmpty==true{detail?.title=card.title}
        }catch{if !(error is CancellationError){self.error=error.localizedDescription}}
    }
}
struct DetailView:View{
    let card:Card
    let source:SourceEntry
    @EnvironmentObject private var app:AppModel
    @EnvironmentObject private var playback:PlaybackController
    @StateObject private var model=DetailModel()
    @State private var groupID=""
    @State private var ascending=true
    @State private var page=0
    @State private var expanded=false
    @State private var search=false
    private var saved:LibraryItem?{app.saved(card,source:source)}
    private var group:EpisodeGroup?{model.detail?.groups.first{$0.id==groupID} ?? model.detail?.groups.first}
    private var orderedEpisodes:[Episode]{guard let group else{return []};return ascending ? group.episodes:Array(group.episodes.reversed())}
    private var visibleEpisodes:[Episode]{let values=orderedEpisodes,start=min(page*50,values.count);return Array(values[start..<min(start+50,values.count)])}
    private var currentEpisodeID:String?{playback.context?.source.id==source.id && playback.context?.card.id==card.id ? playback.context?.episode.id:saved?.episodeID}
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:26){
                introduction
                primaryActions
                summary
                if let detail=model.detail{groupPicker(detail);episodesSection}
                else if model.busy{ProgressView("读取详情…").frame(maxWidth:.infinity).padding(30)}
                else if let message=model.error{VStack(spacing:14){Text(message).font(.subheadline).foregroundStyle(.secondary);Button("重试"){Task{await model.load(card,source:source,app:app)}}}.frame(maxWidth:.infinity).padding()}
            }.padding(.horizontal,22).padding(.top,20).padding(.bottom,30)
        }
        .background{ZStack(alignment:.top){Color(uiColor:.systemGroupedBackground);ArtworkView(reference:model.detail?.poster ?? card.poster).frame(height:300).blur(radius:45).opacity(0.18);LinearGradient(colors:[.clear,Color(uiColor:.systemGroupedBackground)],startPoint:.top,endPoint:.bottom).frame(height:350)}.ignoresSafeArea()}
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.topBarTrailing){Menu{Button("搜索其它内容源",systemImage:"magnifyingglass"){search=true};Button("复制名称",systemImage:"doc.on.doc"){UIPasteboard.general.string=card.title};if playback.context?.card.id==card.id{Button("打开播放器",systemImage:"play.rectangle"){playback.showPlayer=true}}}label:{Image(systemName:"ellipsis")}}}
        .sheet(isPresented:$search){NavigationStack{SearchView(initialQuery:card.title,initiallyAll:true)}}
        .task{if model.detail==nil{await model.load(card,source:source,app:app)};if let savedID=saved?.groupID{groupID=savedID};if let index=group?.episodes.firstIndex(where:{$0.id==currentEpisodeID}){page=index/50}}
        .onChange(of:model.detail?.groups.count){_,_ in
            ScreenshotSupport.mark("detail")
            if groupID.isEmpty{groupID=saved?.groupID ?? model.detail?.groups.first?.id ?? ""}
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--screen-player"),let group,let episode=group.episodes.first{start(group,episode,resume:0)}
            #endif
        }
    }
    private var introduction:some View{
        HStack(alignment:.center,spacing:20){
            ArtworkView(reference:model.detail?.poster ?? card.poster).frame(width:112,height:168).clipShape(RoundedRectangle(cornerRadius:16))
            VStack(alignment:.leading,spacing:12){
                Text(model.detail?.title ?? card.title).font(.system(size:25,weight:.semibold)).lineLimit(3)
                if let subtitle=card.subtitle{Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)}
                Text(source.name).font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                if let rating=card.rating,!rating.isEmpty{Label(rating,systemImage:"star.fill").font(.caption).foregroundStyle(.secondary)}
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.accessibilityElement(children:.combine)
    }
    private var primaryActions:some View{
        HStack(spacing:12){
            Button{continuePlayback()}label:{Label(continueTitle,systemImage:"play.fill").font(.headline).frame(maxWidth:.infinity).padding(.vertical,17)}.buttonStyle(.plain).foregroundStyle(.white).background(Color.accentColor,in:RoundedRectangle(cornerRadius:20)).disabled(group?.episodes.isEmpty != false)
            Button{app.toggleFavorite(card,source:source)}label:{Image(systemName:app.favorite(card,source:source) ? "heart.fill":"heart").font(.system(size:22)).frame(width:64,height:58)}.buttonStyle(.plain).glassPill().accessibilityLabel("收藏")
        }
    }
    private var continueTitle:String{
        guard let group,let saved,let episode=group.episodes.first(where:{$0.id==saved.episodeID}) else{return "开始观看"}
        return "继续 · "+episode.name
    }
    @ViewBuilder private var summary:some View{
        if let description=model.detail?.summary ?? card.summary,!description.isEmpty{
            VStack(alignment:.leading,spacing:14){
                Text("剧情简介").font(.title3.bold())
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineSpacing(6).lineLimit(expanded ? nil:4).textSelection(.enabled)
                if description.count>100{Button(expanded ? "收起简介 ⌃":"展开简介 ⌄"){withAnimation(.easeInOut(duration:0.2)){expanded.toggle()}}.font(.subheadline)}
            }
        }
    }
    private func groupPicker(_ detail:ContentDetail)->some View{
        VStack(alignment:.leading,spacing:15){
            HStack{Text("播放线路").font(.title3.bold());Spacer();if detail.groups.count>1{Text("\(detail.groups.count) 条").font(.caption).foregroundStyle(.secondary)}}
            ScrollView(.horizontal,showsIndicators:false){
                HStack(spacing:10){ForEach(detail.groups){value in
                    Button{groupID=value.id;page=0;if playback.context?.source.id==source.id && playback.context?.card.id==card.id{playback.selectGroup(value)}}label:{
                        VStack(spacing:4){Text(value.name).font(.subheadline.weight(.medium)).lineLimit(1);Text("\(value.episodes.count) 集").font(.caption2).opacity(0.75)}.padding(.horizontal,22).padding(.vertical,11)
                            .background(group?.id==value.id ? Color.accentColor:Color(uiColor:.secondarySystemGroupedBackground),in:Capsule()).foregroundStyle(group?.id==value.id ? Color.white:Color.primary)
                    }.buttonStyle(.plain)
                }}
            }
        }
    }
    private var episodesSection:some View{
        VStack(alignment:.leading,spacing:18){
            HStack{Text("选集 · 共 \(orderedEpisodes.count) 集").font(.title3.bold());Spacer();Button{ascending.toggle();page=0}label:{Label(ascending ? "逆序":"正序",systemImage:"arrow.up.arrow.down")}.font(.subheadline)}
            if orderedEpisodes.count>50{
                ScrollView(.horizontal,showsIndicators:false){HStack(spacing:10){ForEach(0..<Int(ceil(Double(orderedEpisodes.count)/50)),id:\.self){index in
                    Button{page=index}label:{Text("\(index*50+1)–\(min((index+1)*50,orderedEpisodes.count))").font(.subheadline).padding(.horizontal,18).padding(.vertical,12).background(page==index ? Color.accentColor:Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:13)).foregroundStyle(page==index ? Color.white:Color.primary)}.buttonStyle(.plain)
                }}}
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:4),spacing:12){ForEach(visibleEpisodes){episode in episodeButton(episode)}}
        }
    }
    private func episodeButton(_ episode:Episode)->some View{
        let selected=episode.id==currentEpisodeID
        return Button{if let group{start(group,episode,resume:0)}}label:{
            Text(episode.name).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth:.infinity).padding(.vertical,16)
                .background(selected ? Color.accentColor:Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:16)).foregroundStyle(selected ? Color.white:Color.primary)
        }.buttonStyle(.plain)
    }
    private func continuePlayback(){
        guard let group,let episode=group.episodes.first(where:{$0.id==saved?.episodeID}) ?? group.episodes.first else{return}
        if playback.context?.source.id==source.id,playback.context?.card.id==card.id,playback.context?.episode.id==episode.id{playback.showPlayer=true;return}
        start(group,episode,resume:saved?.episodeID==episode.id ? saved?.seconds ?? 0:0)
    }
    private func start(_ group:EpisodeGroup,_ episode:Episode,resume:Double){
        guard let detail=model.detail else{return}
        playback.play(PlaybackContext(source:source,card:card,detail:detail,group:group,episode:episode),app:app,resume:resume)
    }
}
