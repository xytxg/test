import SwiftUI
import AVKit

struct NativePlayerView:UIViewControllerRepresentable{
    let player:AVPlayer
    let fit:Bool
    func makeUIViewController(context:Context)->AVPlayerViewController{
        let controller=AVPlayerViewController();controller.player=player
        controller.showsPlaybackControls=true;controller.allowsPictureInPicturePlayback=true
        controller.canStartPictureInPictureAutomaticallyFromInline=true
        controller.updatesNowPlayingInfoCenter=false
        return controller
    }
    func updateUIViewController(_ controller:AVPlayerViewController,context:Context){
        if controller.player !== player{controller.player=player}
        controller.videoGravity=fit ? .resizeAspect:.resizeAspectFill
    }
    static func dismantleUIViewController(_ controller:AVPlayerViewController,coordinator:()){controller.player=nil}
}
struct RoutePicker:UIViewRepresentable{
    func makeUIView(context:Context)->AVRoutePickerView{let view=AVRoutePickerView();view.tintColor = .white;view.activeTintColor = .systemBlue;view.prioritizesVideoDevices=true;return view}
    func updateUIView(_ view:AVRoutePickerView,context:Context){}
}
struct PlaybackScreen:View{
    @EnvironmentObject private var playback:PlaybackController
    @State private var tracks=false
    @State private var episodes=false
    @State private var findSource=false
    @Environment(\.verticalSizeClass) private var verticalSize
    var body:some View{
        GeometryReader{proxy in
            ZStack{
                Color.black.ignoresSafeArea()
                VStack(spacing:0){
                    header
                    playerArea.frame(maxWidth:.infinity,maxHeight:.infinity)
                    if verticalSize != .compact{controls.padding(.bottom,8)}
                }
            }
            .overlay(alignment:.bottomTrailing){if verticalSize == .compact{compactControls.padding(14)}}
        }.preferredColorScheme(.dark)
        .sheet(isPresented:$tracks){PlaybackTracksView()}
        .sheet(isPresented:$episodes){PlaybackEpisodesView()}
        .sheet(isPresented:$findSource){NavigationStack{SearchView(initialQuery:playback.title,initiallyAll:true)}}
        .onDisappear{playback.saveProgress()}
    }
    private var header:some View{
        HStack(spacing:12){
            Button{playback.showPlayer=false}label:{Image(systemName:"chevron.down").font(.system(size:16,weight:.semibold)).frame(width:42,height:42)}.glassPill().accessibilityLabel("收起播放器，继续播放")
            VStack(alignment:.leading,spacing:3){Text(playback.title).font(.subheadline.weight(.semibold)).lineLimit(1);Text(playback.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)}
            Spacer(minLength:0)
            RoutePicker().frame(width:38,height:38)
            Menu{
                Button("查找其它内容源",systemImage:"magnifyingglass"){findSource=true}
                Button(playback.fit ? "铺满画面":"适应画面",systemImage:"arrow.up.left.and.arrow.down.right"){playback.fit.toggle()}
                Button("重新解析播放地址",systemImage:"arrow.clockwise"){playback.retry()}
                Button("停止播放",systemImage:"stop.fill",role:.destructive){playback.stop()}
            }label:{Image(systemName:"ellipsis").frame(width:40,height:42)}.glassPill()
        }.foregroundStyle(.white).padding(.horizontal,16).padding(.vertical,8)
    }
    @ViewBuilder private var playerArea:some View{
        ZStack{
            if let player=playback.player{NativePlayerView(player:player,fit:playback.fit)}
            if playback.phase == .resolving{status("正在解析播放地址…")}
            else if playback.phase == .buffering{VStack{Spacer();HStack{ProgressView().tint(.white);Text("正在缓冲…").font(.caption);Spacer()}.padding(18)}}
            else if playback.phase == .failed{
                VStack(spacing:18){Image(systemName:"exclamationmark.circle").font(.largeTitle);Text(playback.error ?? "播放失败").font(.subheadline).multilineTextAlignment(.center).textSelection(.enabled)
                    HStack{Button("重试"){playback.retry()};Button("切换线路"){tracks=true}}.buttonStyle(.bordered)
                }.foregroundStyle(.white).padding(28).frame(maxWidth:500).background(.black.opacity(0.8),in:RoundedRectangle(cornerRadius:20))
            }
        }
    }
    private func status(_ text:String)->some View{VStack(spacing:14){ProgressView().tint(.white);Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.8))}.padding(28).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:18))}
    private var controls:some View{
        VStack(spacing:20){
            HStack(spacing:36){
                Button{playback.previous()}label:{Image(systemName:"backward.end.fill").font(.title2)}
                Button{playback.seek(by:-15)}label:{Image(systemName:"gobackward.15").font(.title2)}
                Button{playback.toggle()}label:{Image(systemName:playback.phase == .playing ? "pause.fill":"play.fill").font(.system(size:30)).frame(width:60,height:60)}.glassPill()
                Button{playback.seek(by:15)}label:{Image(systemName:"goforward.15").font(.title2)}
                Button{playback.next()}label:{Image(systemName:"forward.end.fill").font(.title2)}
            }.foregroundStyle(.white)
            HStack(spacing:12){speedMenu;Spacer();Button{tracks=true}label:{Label("线路",systemImage:"point.3.connected.trianglepath.dotted")};Spacer();Button{episodes=true}label:{Label("选集",systemImage:"list.bullet")};Spacer();Button{playback.fit.toggle()}label:{Label("画面",systemImage:"aspectratio")}}.font(.subheadline).foregroundStyle(.white).padding(.horizontal,26)
            HStack{Text(playback.phase == .playing ? "\(playback.elapsed.playbackTime) / \(playback.duration.playbackTime)":"\(playback.context?.group.name ?? "")");Spacer();if playback.nextReady{Label("下集已预热",systemImage:"checkmark.circle")}}.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,26)
        }.padding(.vertical,16)
    }
    private var speedMenu:some View{Menu{ForEach([Float(0.5),0.75,1,1.25,1.5,2,2.5,3],id:\.self){value in Button("\(value.formatted())×"){playback.setRate(value)}}}label:{Text("\(playback.rate.formatted())×").monospacedDigit()}}
    private var compactControls:some View{HStack(spacing:18){speedMenu;Button{tracks=true}label:{Image(systemName:"point.3.connected.trianglepath.dotted")};Button{episodes=true}label:{Image(systemName:"list.bullet")}}.foregroundStyle(.white).padding(.horizontal,18).padding(.vertical,12).glassPill()}
}
struct PlaybackTracksView:View{
    @EnvironmentObject private var playback:PlaybackController
    @Environment(\.dismiss) private var dismiss
    var body:some View{
        NavigationStack{
            List{
                Section("播放线路"){
                    ForEach(playback.context?.detail.groups ?? []){group in
                        Button{playback.selectGroup(group);dismiss()}label:{HStack{VStack(alignment:.leading,spacing:4){Text(group.name);Text("\(group.episodes.count) 集").font(.caption).foregroundStyle(.secondary)};Spacer();if group.id==playback.context?.group.id{Image(systemName:"checkmark")}}}
                    }
                }
                Section("本集资源"){
                    ForEach(playback.variants){media in Button{playback.selectVariant(media.id);dismiss()}label:{HStack{Text(media.name);Spacer();if media.id==playback.selectedVariantID{Image(systemName:"checkmark")}}}}
                }
            }.navigationTitle("切换资源").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
        }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
struct PlaybackEpisodesView:View{
    @EnvironmentObject private var playback:PlaybackController
    @Environment(\.dismiss) private var dismiss
    var body:some View{
        NavigationStack{
            ScrollView{
                LazyVGrid(columns:[GridItem(.adaptive(minimum:80),spacing:10)],spacing:12){ForEach(playback.context?.group.episodes ?? []){episode in
                    Button{playback.selectEpisode(episode);dismiss()}label:{Text(episode.name).font(.subheadline).lineLimit(1).frame(maxWidth:.infinity).padding(.vertical,14).background(episode.id==playback.context?.episode.id ? Color.accentColor:Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12)).foregroundStyle(episode.id==playback.context?.episode.id ? Color.white:Color.primary)}.buttonStyle(.plain)
                }}.padding(20)
            }.navigationTitle("选集").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
        }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
