import SwiftUI

struct LibraryView:View{
    @EnvironmentObject private var app:AppModel
    @State private var section=0
    @State private var sourceID=""
    private var items:[LibraryItem]{(section==0 ? app.history:app.favorites).filter{sourceID.isEmpty || $0.sourceID==sourceID}}
    var body:some View{
        List{
            Section{Picker("资料库",selection:$section){Text("继续观看").tag(0);Text("我的收藏").tag(1)}.pickerStyle(.segmented)}.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:4,leading:0,bottom:8,trailing:0))
            if items.isEmpty{ContentUnavailableView(section==0 ? "从一段故事开始":"把喜欢的留在这里",systemImage:section==0 ? "clock":"heart",description:Text(section==0 ? "播放进度会按内容源分别保存，随时继续。":"在内容详情页点击收藏，即可快速找到。 ")).listRowBackground(Color.clear)}
            ForEach(items){item in
                if let source=app.sources.first(where:{$0.id==item.sourceID}){
                    NavigationLink{DetailView(card:item.card,source:source)}label:{row(item,source:source)}
                }else{HStack{Image(systemName:"externaldrive.badge.xmark").foregroundStyle(.secondary);VStack(alignment:.leading,spacing:5){Text(item.card.title);Text("原内容源已移除，重新导入同一源后会关联记录").font(.caption).foregroundStyle(.secondary)}}}
            }.onDelete{indices in let ids=Set(indices.map{items[$0].id});if section==0{app.history.removeAll{ids.contains($0.id)}}else{app.favorites.removeAll{ids.contains($0.id)}};app.persist()}
        }.navigationTitle("资料库")
            .toolbar{ToolbarItem(placement:.topBarTrailing){Menu{Button("全部内容源"){sourceID=""};ForEach(app.sources){source in Button(source.name){sourceID=source.id}}}label:{Image(systemName:"line.3.horizontal.decrease")}}}
    }
    private func row(_ item:LibraryItem,source:SourceEntry)->some View{
        HStack(spacing:14){
            ArtworkView(reference:item.card.poster).frame(width:68,height:96).clipShape(RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading,spacing:7){Text(item.card.title).font(.subheadline.weight(.semibold)).lineLimit(2);Text(source.name).font(.caption).foregroundStyle(.secondary)
                if section==0{Text((item.episodeName ?? "")+(item.seconds.map{" · "+$0.playbackTime} ?? "")).font(.caption).foregroundStyle(.secondary);if item.progress>0{ProgressView(value:item.progress).tint(.accentColor)}}
            }
        }.padding(.vertical,4)
    }
}
