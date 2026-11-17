import SwiftUI
import AVFoundation

@main
struct WeBoxApp: App {
    @StateObject private var model = AppModel()
    init() { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback) }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .task { await model.bootstrap() }
                .onOpenURL { url in Task { await model.importFile(url) } }
                .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("知道了", role: .cancel) { model.error = nil }
                } message: { Text(model.error ?? "") }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { CatalogView() }.tabItem { Label("发现", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { LibraryView() }.tabItem { Label("资料库", systemImage: "books.vertical") }.tag(1)
            NavigationStack { SourcesView() }.tabItem { Label("源管理", systemImage: "externaldrive") }.tag(2)
        }
        .tint(Color(red: 0.15, green: 0.33, blue: 0.90))
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--screen-sources") { tab = 2 }
            if ProcessInfo.processInfo.arguments.contains("--screen-library") { tab = 1 }
        }
    }
}
