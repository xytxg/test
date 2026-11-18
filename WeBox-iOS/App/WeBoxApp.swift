import SwiftUI
import AVFoundation

@main
struct WeBoxApp: App {
    @StateObject private var app = ScreenshotSupport.makeAppModel()
    @Environment(\.scenePhase) private var scenePhase
    init(){try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback);ScreenshotSupport.prepareImportTestFiles()}
    var body:some Scene{
        WindowGroup{
            RootView().environmentObject(app).environmentObject(app.playback)
                .task{if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil{await app.bootstrap()}}
                .onOpenURL{url in
                    Task{
                        if url.isFileURL{await app.importFile(url)}
                        else if url.scheme=="webox",let address=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="url"})?.value{await app.importURL(address)}
                    }
                }
                .onChange(of:scenePhase){_,phase in if phase != .active{app.playback.saveProgress()}}
                .onChange(of:app.preferences){_,value in app.playback.applyPreferences(value)}
                .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in Task{await ArtworkCache.shared.clear()}}
                .alert("操作未完成",isPresented:Binding(get:{app.error != nil},set:{if !$0{app.error=nil}})){Button("知道了",role:.cancel){app.error=nil}}message:{Text(app.error ?? "")}
                .sheet(isPresented:Binding(get:{!app.importResults.isEmpty && app.importOwner == nil},set:{if !$0{app.importResults=[]}})){ImportResultsView()}
        }
    }
}
struct RootView:View{
    @EnvironmentObject private var app:AppModel
    @EnvironmentObject private var playback:PlaybackController
    @State private var tab=0
    var body:some View{
        Group{
            if #available(iOS 26.1,*){
                tabs.tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory(isEnabled:playback.context != nil){MiniPlayerView()}
            }else{
                tabs.safeAreaInset(edge:.bottom,spacing:0){if playback.context != nil{MiniPlayerView().padding(10).background(.bar)}}
            }
        }
        .tint(Color(red:0.12,green:0.37,blue:0.78))
        .fullScreenCover(isPresented:$playback.showPlayer){PlaybackScreen()}
        .onAppear{
            if ProcessInfo.processInfo.arguments.contains("--screen-library"){tab=1}
            if ProcessInfo.processInfo.arguments.contains("--screen-settings"){tab=2}
        }
    }
    private var tabs:some View{
        TabView(selection:$tab){
            NavigationStack{CatalogView()}.tabItem{Label("首页",systemImage:"house")}.tag(0)
            NavigationStack{LibraryView()}.tabItem{Label("资料库",systemImage:"heart")}.tag(1)
            NavigationStack{SettingsView()}.tabItem{Label("设置",systemImage:"gearshape")}.tag(2)
        }
    }
}
struct MiniPlayerView:View{
    @EnvironmentObject private var playback:PlaybackController
    var body:some View{
        HStack(spacing:10){
            ArtworkView(reference:playback.context?.card.poster).frame(width:34,height:40).clipShape(RoundedRectangle(cornerRadius:6))
            Button{playback.showPlayer=true}label:{VStack(alignment:.leading,spacing:3){Text(playback.title).font(.subheadline.weight(.medium)).lineLimit(1);Text(playback.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
            if playback.isBusy{ProgressView().controlSize(.small)}
            Button{playback.toggle()}label:{Image(systemName:playback.phase == .playing ? "pause.fill":"play.fill").frame(width:32,height:40)}.buttonStyle(.plain).accessibilityLabel("播放或暂停")
            Button{playback.next()}label:{Image(systemName:"forward.end.fill").frame(width:32,height:40)}.buttonStyle(.plain).accessibilityLabel("下一集")
        }.padding(.horizontal,12).padding(.vertical,6)
    }
}
