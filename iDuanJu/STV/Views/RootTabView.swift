import SwiftUI

/// 四个根页面 + PlutoFish 式底部悬浮玻璃胶囊导航（系统 TabBar 隐藏）。
/// 胶囊只在根页面显示；进入详情 / 播放器等二级页面时隐藏。
struct RootTabView: View {
    @State private var tab = min(3, max(0, Int(ProcessInfo.processInfo.environment["STV_TAB"] ?? "") ?? 0))
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paths = [NavigationPath(), NavigationPath(), NavigationPath(), NavigationPath()]
    static let items: [(String, String)] = [("首页", "house.fill"), ("搜索", "magnifyingglass"),
                                            ("找剧", "square.grid.2x2.fill"), ("我的", "person.crop.circle.fill")]
    var body: some View {
        TabView(selection: $tab) {
            Stack(path: $paths[0]) { HomeView() }.tag(0)
            Stack(path: $paths[1]) { SearchView() }.tag(1)
            Stack(path: $paths[2]) { CategoryView() }.tag(2)
            Stack(path: $paths[3]) { ProfileView() }.tag(3)
        }
        .tint(STVTheme.accent)
        .overlay(alignment: .bottom) {
            if paths[tab].isEmpty {
                GlassTabBar(selection: $tab, items: Self.items) { i in
                    if i == tab { paths[i] = NavigationPath() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DS.select, value: paths[tab].isEmpty)
        .onAppear {
            Router.handler = { r in paths[tab].append(r) }
            #if DEBUG
            if ProcessInfo.processInfo.environment["STV_TD_OPEN"] == "1" { Router.push(.tdlib) }
            #endif
        }
        // Cold start: restore a saved TDLib login (no network login, nothing is sent).
        .task { await TDLibService.shared.bootstrap() }
    }
}

private struct Stack<V: View>: View {
    @Binding var path: NavigationPath
    @ViewBuilder var content: V
    @Namespace private var ns
    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: GlassTabBar.clearance) }
                .routes()
        }.environment(\.zoomNS, ns)
    }
}

struct GlassTabBar: View {
    static let clearance: CGFloat = 72
    @Binding var selection: Int
    let items: [(String, String)]
    var onReselect: (Int) -> Void = { _ in }
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let on = i == selection
                Button {
                    if on { onReselect(i) } else { withAnimation(reduceMotion ? nil : DS.select) { selection = i } }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: items[i].1).font(.system(size: 19, weight: on ? .semibold : .regular)).frame(height: 21)
                        Text(items[i].0).font(.caption2.weight(on ? .semibold : .medium)).lineLimit(1)
                    }
                    .foregroundStyle(on ? STVTheme.accent : STVTheme.secondary)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background {
                        if on { Capsule().fill(STVTheme.accentSoft).matchedGeometryEffect(id: "pill", in: ns) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[i].0)
                .accessibilityIdentifier("tab.\(i)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(maxWidth: 400)
        // ui-redesign `.tabbar`: 60 pt glass capsule, 16 pt from the sides, 26 pt above the screen edge.
        .dsBar(30)
        .padding(.horizontal, 16)
        .padding(.bottom, -8)
    }
}
