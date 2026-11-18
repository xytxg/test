import SwiftUI

enum HomeTab: Hashable {
    case hongguo(HGRankGenre)
    case actorRank
    case huangguo(HuangguoSub)
    /// Opt-in long-video site (片源管理), listed after the built-in tabs.
    case site(DramaSource)
    var label: String {
        switch self {
        case .actorRank: "剧星榜"
        case .hongguo(let g): g == .all ? "红果榜单" : g.label
        case .huangguo(let s): "黄果" + s.label
        case .site(let s): s.label
        }
    }
    /// Label inside a source page's secondary chips.
    var subLabel: String {
        switch self {
        case .hongguo(.all): "全部榜单"
        case .hongguo(.ai): "红果 AI剧"
        case .huangguo(.ai): "黄果 AI 站"
        case .huangguo(let s): s.label
        default: label
        }
    }
}

/// Top-level home pages (横滑翻页 + 顶部分类条): one page per source; each source's own boards
/// (红果榜单 / 真人剧 / …) are secondary chips inside its page. Adult sites only appear once enabled in
/// 片源管理 (and unlocked with Face ID when the lock is on) — `SourceGate.visibleSites`.
enum HomeSource: Hashable, Identifiable {
    case hongguo, huangguo, ai
    case site(DramaSource)
    /// Telegram 频道 feed (not a drama source; its page is `ChannelFeedView`).
    case channels
    /// 漫画 (MangaHomeView).
    case manga
    /// 小说 (NovelHomeView: local TXT / EPUB bookshelf).
    case novel
    var id: String { label }
    var label: String {
        switch self {
        case .hongguo: "红果"
        case .huangguo: "黄果"
        case .ai: "AI剧"
        case .site(let s): s.label
        case .channels: "频道"
        case .manga: "漫画"
        case .novel: "小说"
        }
    }
    @MainActor var subs: [HomeTab] {
        switch self {
        case .hongguo: [.hongguo(.all), .hongguo(.human), .hongguo(.comic), .actorRank]
        case .huangguo: [.huangguo(.video), .huangguo(.legacy)]
        case .ai: SourceGate.shared.showHuangguo ? [.hongguo(.ai), .huangguo(.ai)] : [.hongguo(.ai)]
        case .site(let s): [.site(s)]
        case .channels, .manga, .novel: []
        }
    }
    @MainActor static var all: [HomeSource] {
        let g = SourceGate.shared
        return [.hongguo] + (g.showHuangguo ? [.huangguo] : []) + [.ai] + g.visibleSites.map { .site($0) } + [.channels, .manga, .novel]
    }
}

/// Caches the first page of each rank board for the home cards.
@MainActor @Observable
final class BoardCache {
    static let shared = BoardCache()
    var items: [String: [HGSeries]] = [:]
    var loading: Set<String> = []
    var failed: Set<String> = []
    var errors: [String: Error] = [:]
    func load(_ b: BoardSpec, force: Bool = false) {
        guard !loading.contains(b.id), force || items[b.id] == nil else { return }
        loading.insert(b.id); failed.remove(b.id); errors[b.id] = nil
        Task {
            do { items[b.id] = try await b.fetch(HGPage(items: [], hasMore: true, nextOffset: nil), []).items; errors[b.id] = nil }
            catch { failed.insert(b.id); errors[b.id] = error }
            loading.remove(b.id)
        }
    }
}

/// 发现页：玻璃搜索栏/筛选 → 来源分类条（红果 / 黄果 / AI剧 / 已开启的长视频站）→ 下方按来源横滑翻页，
/// 分类条联动（选中项自动滚到居中、指示条跟随）。每页：二级榜单选择 → 竖海报 hero → 真实榜单分段。
/// 横滑冲突：hero 轮播区域内的横滑归轮播；其它区域横滑翻来源页；首页是根页面，没有系统侧滑返回。
struct HomeView: View {
    @State private var source: HomeSource
    @State private var subs: [HomeSource: HomeTab]
    /// ui-redesign 10/11: the header always sits on the page colour (ambient glow on top); once the current page
    /// scrolls it pins with a blurred 80 % page-colour ground and a hairline.
    private var headerInk: Color { STVTheme.text }
    @State private var scrolled: [HomeSource: Bool] = [:]
    private var pinned: Bool { scrolled[source] ?? false }
    @State private var showChannels = false

    init() {
        let e = ProcessInfo.processInfo.environment["STV_HOME_TAB"] ?? ""
        var src = HomeSource.hongguo, sub: [HomeSource: HomeTab] = [:]
        if e == "actorRank" { sub[.hongguo] = .actorRank }
        #if DEBUG
        if let s = DramaSource(rawValue: e), s.isLongVideo { src = .site(s) }
        if e == "huangguo" { src = .huangguo }
        if e == "ai" { src = .ai }
        if e == "channels" { src = .channels }
        if e == "manga" { src = .manga }
        if e == "novel" { src = .novel }
        #endif
        _source = State(initialValue: src)
        _subs = State(initialValue: sub)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $source) {
                ForEach(HomeSource.all) { s in
                    if s == .channels {
                        ChannelFeedView(embedded: true).tag(s)
                    } else if s == .manga {
                        MangaHomeView(embedded: true).tag(s)
                    } else if s == .novel {
                        NovelHomeView(embedded: true).tag(s)
                    } else {
                        HomeFeedPage(source: s,
                                     tab: Binding(get: { subs[s] ?? s.subs[0] }, set: { subs[s] = $0 }),
                                     onScrolled: { v in if scrolled[s] != v { scrolled[s] = v } })
                            .tag(s)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .dsAmbient(visible: !pinned)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showChannels) { channelPanel }
        .onChange(of: SourceGate.shared.visibleSites) { _, _ in if !HomeSource.all.contains(source) { source = .hongguo } }
    }

    // MARK: Header (search + filter, source bar)

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NavigationLink(value: Route.search) {
                    DSSearchBarLabel()
                        .padding(.leading, 16).frame(height: 46).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("home.search")
                Button { showChannels = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 14, weight: .semibold))
                        Text("筛选").font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(STVTheme.text)
                    .padding(.horizontal, 16).frame(height: 46).contentShape(Rectangle())
                }.buttonStyle(PressScale()).accessibilityLabel("筛选与全部频道").accessibilityIdentifier("home.filter")
            }
            .stvGlass(in: Capsule(), tint: STVTheme.glass, interactive: true)
            .padding(.horizontal, 16)
            HomeChannelBar(items: HomeSource.all, selection: $source, label: \.label, ink: headerInk) { showChannels = true }
                .padding(.leading, 20)
                .padding(.top, pinned ? 14 : 18)
        }
        .padding(.top, 8)
        .padding(.bottom, pinned ? 10 : 0)
        .dsPinned(pinned)
        .animation(.easeOut(duration: 0.22), value: pinned)
        .zIndex(1)
    }

    private var channelPanel: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(HomeSource.all.filter { !$0.subs.isEmpty }) { s in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(s.label).font(.subheadline.weight(.semibold)).foregroundStyle(STVTheme.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                                ForEach(s.subs, id: \.self) { t in
                                    let on = s == source && (subs[s] ?? s.subs[0]) == t
                                    Button { subs[s] = t; source = s; showChannels = false } label: {
                                        Text(t.subLabel).font(.subheadline.weight(on ? .semibold : .regular))
                                            .foregroundStyle(on ? STVTheme.accent : STVTheme.text)
                                            .frame(maxWidth: .infinity).frame(height: 40)
                                            .stvGlass(in: RoundedRectangle(cornerRadius: 13),
                                                      tint: on ? STVTheme.accent.opacity(0.22) : STVTheme.glass,
                                                      interactive: true)
                                    }.buttonStyle(.plain).accessibilityIdentifier("panel.\(s.label).\(t.subLabel)")
                                        .accessibilityAddTraits(on ? .isSelected : [])
                                }
                            }
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("频道").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("home.channelPanel")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showChannels = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One source page: secondary board chips → hero → real board sections. Vertical scroll inside a horizontal pager.
private struct HomeFeedPage: View {
    let source: HomeSource
    @Binding var tab: HomeTab
    var onScrolled: (Bool) -> Void = { _ in }
    @State private var legacyChannels: [HuangguoChannel] = []
    @State private var legacyError: Error?
    @State private var heroIndex = 0
    private let cache = BoardCache.shared
    private let library = LibraryStore.shared
    private let gutter: CGFloat = 16
    /// DEBUG `STV_HOME_SCROLL=bottom` opens the feed scrolled to the end (simulator screenshots).
    private static var debugAnchor: UnitPoint? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["STV_HOME_SCROLL"] == "bottom" { return .bottom }
        #endif
        return nil
    }

    var body: some View {
        if case .site(let source) = tab, source.cmsKey != nil || source.pluginID != nil {
            DynamicSiteFeed(source: source)
        } else {
            rankFeed
        }
    }

    private var rankFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if source.subs.count > 1 { subChips } else if case .site = source { boardChips }
                if tab == .actorRank {
                    ActorRankList().padding(.vertical, 8)
                } else {
                    if !heroPicks.isEmpty {
                        PosterHero(board: boards.first?.title ?? "", picks: heroPicks, index: $heroIndex).id(tab).padding(.horizontal, gutter)
                            .padding(.top, 16)
                            .transition(.opacity)
                    }
                    if source == .hongguo, !library.continueWatching.isEmpty {
                        HomeContinueRow(items: library.continueWatching).padding(.top, 24)
                    }
                    sections
                }
            }
            .padding(.bottom, 24)
            .animation(.easeOut(duration: 0.25), value: heroPicks.isEmpty)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(Self.debugAnchor)
        .onScrollGeometryChange(for: Bool.self) { g in g.contentOffset.y + g.contentInsets.top > 4 } action: { _, v in onScrolled(v) }
        .accessibilityIdentifier("home.page.\(source.label)")
        .refreshable { if tab == .actorRank { await ActorRankStore.shared.reload() } else { boards.forEach { cache.load($0, force: true) } } }
        .task(id: tab) {
            heroIndex = 0
            if case .huangguo(.legacy) = tab, legacyChannels.isEmpty { await loadLegacy() }
        }
        .onAppear { boards.prefix(1).forEach { cache.load($0) } }
        .onChange(of: tab) { _, _ in boards.prefix(1).forEach { cache.load($0) } }
    }


    /// ui-redesign 10: secondary boards are the same glass segmented control as 找剧.
    private var subChips: some View {
        SegmentedTabs(items: source.subs, selection: $tab, label: \.subLabel, idPrefix: "home.sub")
            .padding(.horizontal, gutter)
            .padding(.top, 18)
    }

    /// Long-video site pages: same chip row height as 红果/黄果 (top never jumps); each chip opens that board.
    private var boardChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(boards.enumerated()), id: \.element.id) { i, b in
                    NavigationLink(value: Route.board(b)) { Text(b.title) }
                    .buttonStyle(ToneChipStyle(on: i == 0, neutral: true))
                    .accessibilityIdentifier("home.sub.\(b.title)")
                }
            }.padding(.horizontal, gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .mask(FadeMask())
        .padding(.top, 18)
    }

    // MARK: Data

    private var boards: [BoardSpec] {
        switch tab {
        case .hongguo(let g): g.subs.map { BoardSpec(kind: .hongguo(g, $0)) }
        case .huangguo(.ai): HuangguoClient.aiChannels.map { BoardSpec(kind: .huangguo($0)) }
        case .huangguo(.video): HuangguoClient.videoChannels.map { BoardSpec(kind: .huangguo($0)) }
        case .huangguo(.legacy): legacyChannels.map { BoardSpec(kind: .huangguo($0)) }
        case .site(let s): (Sites.provider(s)?.categories ?? []).map { BoardSpec(kind: .site(s, $0)) }
        case .actorRank: []
        }
    }

    private var heroPicks: [HGSeries] {
        guard let first = boards.first, let items = cache.items[first.id] else { return [] }
        return Array(items.prefix(5))
    }

    @ViewBuilder private var sections: some View {
        if case .huangguo(.legacy) = tab, legacyChannels.isEmpty {
            if let legacyError { ErrorStateView(error: legacyError) { Task { await loadLegacy() } } }
            else { cardsSkeleton }
        } else {
            if let e = boards.lazy.compactMap({ cache.errors[$0.id] }).first(where: { $0.verifyTarget != nil }) {
                ErrorStateView(error: e) { boards.forEach { cache.load($0, force: true) } }
            }
            ForEach(Array(boards.enumerated()), id: \.element.id) { n, b in
                Group {
                    if let items = cache.items[b.id], !items.isEmpty {
                        // 第一个榜单一律跳过 hero 里已展示的剧（数据不够时也跳过，只剩标题和「全部」）。
                        let heroIds = Set(heroPicks.map(\.id))
                        let rest = n == 0 ? items.filter { !heroIds.contains($0.id) } : items
                        HomeShelf(title: b.title, note: nil, items: Array(rest.prefix(12)), more: b)
                    } else if cache.failed.contains(b.id) {
                        HomeShelf(title: b.title, note: cache.errors[b.id]?.verifyTarget != nil ? "需要验证，点上方「去验证」" : "加载失败，下拉重试", items: [], more: b)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            DSSectionHeader(title: b.title)
                            cardsSkeleton.padding(.horizontal, gutter)
                        }
                    }
                }
                .padding(.top, n == 0 && heroPicks.isEmpty && library.continueWatching.isEmpty ? 18 : 24)
                .onAppear { cache.load(b) }
            }
        }
    }

    private var cardsSkeleton: some View {
        let landscape: Bool = { if case .site(let s) = tab { return s.isLongVideo } else { return false } }()
        return LazyVGrid(columns: HomeSection.columns(landscape: landscape), spacing: 16) {
            ForEach(0..<(landscape ? 2 : 3), id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerBlock().aspectRatio(landscape ? 16/9 : 3/4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                    ShimmerBlock().frame(height: 12).frame(maxWidth: 90)
                }
            }
        }
    }

    private func loadLegacy() async {
        do { legacyChannels = try await HuangguoClient.shared.legacyChannels(); legacyError = nil } catch { legacyError = error }
    }
}

/// CMS / JS plugin home: every returned category is a selectable module, and the selected one pages its own list.
private struct DynamicSiteFeed: View {
    let source: DramaSource
    @State private var categories: [SiteCategory] = []
    @State private var selected = ""
    @State private var pager = Pager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if categories.count > 1 { chips }
                if let e = pager.error, pager.items.isEmpty {
                    ErrorStateView(error: e) { reload(selected) }
                } else if pager.items.isEmpty && pager.isLoading {
                    cardsSkeleton.padding(.horizontal, 16)
                } else if pager.items.isEmpty {
                    ContentUnavailableView("该分类暂无内容", systemImage: "rectangle.stack", description: Text("部分采集站的父分类不直接提供资源，请选择动作片、国产剧等具体分类。"))
                } else {
                    NumberedGrid(items: pager.items, numbered: false, hasMore: pager.hasMore, loading: pager.isLoading) { pager.loadMore() }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("home.page.\(source.label)")
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { c in
                    let on = c.id == selected
                    Button { selected = c.id; reload(c.id) } label: {
                        Text(c.title).font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? STVTheme.bg : STVTheme.text.opacity(0.8))
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(on ? STVTheme.text : STVTheme.text.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.module.\(c.title)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }.padding(.horizontal, 16)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .padding(.bottom, 4)
    }

    private var cardsSkeleton: some View {
        LazyVGrid(columns: HomeSection.columns(landscape: source.isLongVideo), spacing: 16) {
            ForEach(0..<(source.isLongVideo ? 2 : 3), id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerBlock().aspectRatio(source.isLongVideo ? 16/9 : 3/4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    ShimmerBlock().frame(height: 12).frame(maxWidth: 90)
                }
            }
        }
    }

    private func refresh() async {
        let loaded = await Self.loadCategories(source)
        categories = loaded
        let id = loaded.contains { $0.id == selected } ? selected : (loaded.first?.id ?? "")
        selected = id
        reload(id)
    }

    private func reload(_ id: String) {
        let source = source
        pager.reset { prev, _ in
            guard let provider = Sites.provider(source) else { throw ProviderError.unsupported(source.label) }
            let category = SiteCategory(id: id, title: "", path: id)
            return try await provider.list(category, page: max(1, prev.nextOffset ?? 1))
        }
    }

    private static func loadCategories(_ source: DramaSource) async -> [SiteCategory] {
        if let key = source.cmsKey {
            var stored = CMSStore.site(key)?.categories ?? []
            if let site = CMSStore.site(key), let fresh = try? await MacCMSProvider.fetchCategories(api: site.api), !fresh.isEmpty {
                stored = fresh
                await MainActor.run { CMSStore.shared.cacheCategories(key, fresh) }
            }
            let latest = SiteCategory(id: "", title: "最新", path: "")
            return [latest] + stored.map { SiteCategory(id: $0.id, title: $0.name, path: $0.id) }
        }
        let fallback = SiteCategory(id: "", title: "推荐", path: "")
        guard let provider = Sites.provider(source) else { return [fallback] }
        let categories = provider.categories.filter { !$0.id.isEmpty }
        return [fallback] + categories
    }
}

enum HomeFmt {
    /// 次要信息：类型（最多两个标签）· 集数 / 热度；长视频是时长 · 观看。
    static func meta(_ s: HGSeries) -> String {
        if s.source.isLongVideo { return Fmt.meta(s) }
        let genres = s.tags.prefix(2).joined(separator: " · ")
        let parts = [genres.isEmpty ? nil : genres, s.episodeCount > 0 ? "\(s.episodeCount)集" : nil].compactMap { $0 }
        return parts.isEmpty ? Fmt.meta(s) : parts.joined(separator: " · ")
    }
    /// 右下角小角标：「更新至 N 集」/「全 N 集」/ 长视频时长。
    static func progress(_ s: HGSeries) -> String? {
        if let sub = s.subtitle, sub.contains("更新至") || sub.hasPrefix("全") { return sub }
        if s.source.isLongVideo { return s.duration > 0 ? Fmt.clock(s.duration) : nil }
        return s.episodeCount > 0 ? "全\(s.episodeCount)集" : nil
    }
}

/// 分类条：未选中 17pt 次要色，选中 20pt 粗体 + 品牌色短条（随选中项滑动）；点击或翻页时选中项自动滚到居中。
struct HomeChannelBar<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var ink: Color = .white
    var onExpand: () -> Void
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .lastTextBaseline, spacing: 22) {
                        ForEach(items, id: \.self) { it in
                            let on = it == selection
                            Button { withAnimation(DS.select) { selection = it } } label: {
                                UnderlineTabLabel(title: label(it), on: on, ink: ink, inkOff: STVTheme.secondary, ns: ns)
                                    .frame(minHeight: 40, alignment: .bottom)
                            }.buttonStyle(.plain).id(it).accessibilityIdentifier("home.channel.\(label(it))")
                                .accessibilityAddTraits(on ? .isSelected : [])
                        }
                        Color.clear.frame(width: 12, height: 1)
                    }
                }
                .accessibilityIdentifier("home.channels")
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                             .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                .onChange(of: selection) { _, it in withAnimation(.snappy) { proxy.scrollTo(it, anchor: .center) } }
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
            }
            Button(action: onExpand) {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(STVTheme.secondary).frame(width: 44, height: 40)
            }.buttonStyle(.plain).accessibilityLabel("展开全部频道").accessibilityIdentifier("home.expand")
        }
        .frame(height: 40)
    }
}

/// 竖海报 hero：整块用当前海报模糊做底，左侧完整 3:4 竖海报（不裁成横图），
/// 右侧榜单名、片名、标签/集数/热度、简介或主演，以及「查看详情」。横滑切换，右上指示点。
/// 长视频站点（横版封面）同一布局里海报区按 16:9 显示在上方。
private struct PosterHero: View {
    @Environment(\.zoomNS) private var ns
    let board: String
    let picks: [HGSeries]
    @Binding var index: Int

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(picks.enumerated()), id: \.element.id) { i, s in
                NavigationLink(value: Route.series(s)) { page(s, rank: i + 1) }.buttonStyle(.plain).tag(i)
                    .accessibilityIdentifier("home.hero.page.\(i)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Same card height for every source so switching pages never makes the top jump.
        .frame(height: height)
        .background { backdrop }
        .overlay(alignment: .bottomTrailing) { dots }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 15, y: 14)
        // Auto-advance; the timer restarts on every page change, so a manual swipe gets a full 6 s.
        .task(id: "\(picks.count)-\(index)") {
            guard picks.count > 1, Self.autoAdvance else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { index = (index + 1) % picks.count }
        }
    }

    /// `.hero`: 14 pt padding around a 112 pt 3:4 poster (landscape sites: 16:9 at 176 pt).
    private static let pad: CGFloat = 14
    private static let posterHeight: CGFloat = 112 * 4 / 3
    private static let landscapeHeight: CGFloat = pad + 99 + pad + 62
    private static let portraitHeight: CGFloat = pad + posterHeight + pad
    private var height: CGFloat { landscape ? Self.landscapeHeight : Self.portraitHeight }
    /// DEBUG `STV_HERO_STILL=1` (UI tests) disables auto-advance so taps never race a page change.
    static var autoAdvance: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["STV_HERO_STILL"] == "1" { return false }
        #endif
        return true
    }
    private var landscape: Bool { picks.first?.isLandscapeCover ?? false }

    /// Poster colours: the current cover blurred, darkened toward the bottom-right like the spec's gradient card.
    private var backdrop: some View {
        let url = picks.indices.contains(index) ? picks[index].cover : ""
        return ZStack {
            Color(red: 0.14, green: 0.10, blue: 0.10)
            CoverView(url: url, corner: 0).blur(radius: 40).scaleEffect(1.5).opacity(0.85).id(url).transition(.opacity)
            LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: url)
        .allowsHitTesting(false)
    }

    private func kicker(_ rank: Int) -> String { board.isEmpty ? "TOP \(rank)" : "\(board) · TOP \(rank)" }

    @ViewBuilder private func page(_ s: HGSeries, rank: Int) -> some View {
        if landscape {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    CoverView(url: s.cover, corner: 12)
                        .frame(width: 176, height: 99)
                        .zoomSource(s.id, ns)
                        .overlay(alignment: .bottomTrailing) { if let p = HomeFmt.progress(s) { HomeBadge(text: p).padding(5) } }
                        .accessibilityIdentifier("home.hero.cover")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(kicker(rank)).font(.system(size: 11, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(Color(red: 0.949, green: 0.710, blue: 0.361)).lineLimit(1)
                        Text(s.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                let line = Fmt.meta(s)
                if !line.isEmpty { Text(line).font(.system(size: 12)).foregroundStyle(.white.opacity(0.74)).lineLimit(1).padding(.top, 9) }
                Spacer(minLength: 0)
                detailButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        } else {
            HStack(alignment: .top, spacing: 14) {
                CoverView(url: s.cover, corner: 12)
                    .frame(width: 112, height: 112 * 4 / 3)
                    .overlay {
                        LinearGradient(stops: [.init(color: .clear, location: 0.46), .init(color: .black.opacity(0.62), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let e = DS.episodes(s) {
                            Text(e).font(.system(size: 11)).foregroundStyle(.white.opacity(0.9)).padding(.trailing, 8).padding(.bottom, 7)
                        }
                    }
                    .zoomSource(s.id, ns)
                info(s, rank: rank)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func info(_ s: HGSeries, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker(rank)).font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Color(red: 0.949, green: 0.710, blue: 0.361)).lineLimit(1)
            Text(s.title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            let line1 = [DS.genres(s), s.episodeCount > 0 ? "\(s.episodeCount) 集" : nil].compactMap { $0 }.joined(separator: " · ")
            let line2 = s.playCount > 0 ? DS.count(s.playCount) + "热度" : (s.actors.isEmpty ? "" : "主演 " + s.actors.prefix(3).joined(separator: " / "))
            VStack(alignment: .leading, spacing: 0) {
                if !line1.isEmpty { Text(line1).lineLimit(1) }
                if !line2.isEmpty { Text(line2).lineLimit(1) }
            }
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.74))
            .lineSpacing(3)
            .padding(.top, 7)
            Spacer(minLength: 0)
            detailButton
        }
        .padding(.top, 3).padding(.bottom, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var detailButton: some View {
        PillButtonLabel(title: "查看详情", icon: "play.fill", tone: .white, small: true)
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(picks.indices, id: \.self) { i in
                Capsule().fill(i == index ? Color.white : Color.white.opacity(0.4)).frame(width: i == index ? 14 : 5, height: 5)
            }
        }
        .animation(DS.select, value: index)
        .padding(.trailing, 14).padding(.bottom, 14 + 1 + 13.5)
        .opacity(picks.count > 1 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(index + 1) 部，共 \(picks.count) 部")
        .accessibilityIdentifier("home.hero.dots")
    }
}

/// ui-redesign 10 `.cw`: horizontal 继续观看 cards with progress and a round play button.
struct HomeContinueRow: View {
    @Environment(\.zoomNS) private var ns
    let items: [WatchProgress]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader(title: "继续观看") {
                NavigationLink(value: Route.history) { MoreLabel() }.buttonStyle(.plain).accessibilityIdentifier("home.more.继续观看")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items.prefix(10)) { p in
                        ZStack(alignment: .trailing) {
                            NavigationLink(value: Route.series(p.series)) { card(p) }
                                .buttonStyle(PressScale(scale: 0.98))
                                .contextMenu { Button("删除观看记录", systemImage: "trash", role: .destructive) { LibraryStore.shared.removeProgress(p.series) } }
                            NavigationLink(value: Route.play(p.series, p.episodeIndex)) { playButton }
                                .buttonStyle(PressScale()).padding(.trailing, 12)
                                .accessibilityLabel("继续播放 \(p.series.title)")
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private func card(_ p: WatchProgress) -> some View {
        HStack(spacing: 12) {
            CoverView(url: p.series.cover, corner: 8).frame(width: 52, height: 52 * 4 / 3).zoomSource(p.series.id, ns)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.series.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
                Text(line(p)).font(.system(size: 12)).foregroundStyle(STVTheme.secondary).lineLimit(1).padding(.top, 2)
                DSProgressBar(value: p.fraction).padding(.top, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 10)
        .frame(width: 296)
        .dsCard(18)
    }

    private var playButton: some View {
        Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(STVTheme.bg)
            .offset(x: 1)
            .frame(width: 38, height: 38)
            .background(Circle().fill(STVTheme.text))
            .contentShape(Circle())
    }

    private func line(_ p: WatchProgress) -> String {
        if p.series.source.isLongVideo { return p.resumeLabel }
        let total = p.series.episodeCount
        return total > 0 ? "看到第 \(p.episodeNumber) 集 · 共 \(total) 集" : "看到第 \(p.episodeNumber) 集"
    }
}

/// ui-redesign 10/11: one horizontally scrolling row per board (`.hs` of 112 pt cells).
struct HomeShelf: View {
    let title: String
    let note: String?
    let items: [HGSeries]
    var more: BoardSpec? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader(title: title, note: note) {
                if let more {
                    NavigationLink(value: Route.board(more)) { MoreLabel() }.buttonStyle(.plain).accessibilityIdentifier("home.more.\(title)")
                }
            }
            if !items.isEmpty {
                let landscape = items.first?.isLandscapeCover ?? false
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(items) { s in
                            PosterCellView(series: s, subtitle: DS.shelfMeta(s))
                                .frame(width: landscape ? 200 : 112)
                                .accessibilityIdentifier("home.card")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }
}

struct HomeBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).monospacedDigit()
            .lineLimit(1).padding(.horizontal, 5).frame(height: 17)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// 分段：左写接口真实榜单名，右侧「全部」进完整榜单；下面按封面比例的网格。
struct HomeSection: View {
    static func columns(landscape: Bool) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: landscape ? 12 : 10, alignment: .top), count: landscape ? 2 : 3)
    }
    /// 竖海报 2 行 × 3，横版 2 行 × 2。
    static func count(for items: [HGSeries]) -> Int { (items.first?.isLandscapeCover ?? false) ? 4 : 6 }
    let title: String
    let note: String?
    let items: [HGSeries]
    var more: BoardSpec? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(STVTheme.text)
                Spacer(minLength: 0)
                if let note { Text(note).font(.system(size: 12, weight: .medium)).foregroundStyle(STVTheme.secondary) }
                if let more {
                    NavigationLink(value: Route.board(more)) {
                        HStack(spacing: 2) { Text("全部"); Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
                            .font(.system(size: 13)).foregroundStyle(STVTheme.secondary)
                    }.buttonStyle(.plain).accessibilityIdentifier("home.more.\(title)")
                }
            }
            if !items.isEmpty {
                let landscape = items.first?.isLandscapeCover ?? false
                LazyVGrid(columns: Self.columns(landscape: landscape), alignment: .leading, spacing: 16) {
                    ForEach(items) { s in
                        NavigationLink(value: Route.series(s)) { HomePosterCard(series: s) }.buttonStyle(.plain)
                            .accessibilityIdentifier("home.card")
                    }
                }
            }
        }
    }
}

/// 卡片按来源封面比例：短剧 3:4 竖海报（三列），长视频站 16:9（两列）。
/// 封面下方片名（两行内）+ 一行类型/集数；右下角只保留「全 N 集 / 更新至 N 集」小角标。
struct HomePosterCard: View {
    @Environment(\.zoomNS) private var ns
    let series: HGSeries
    var body: some View {
        let landscape = series.isLandscapeCover
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(landscape ? 16/9 : 3/4, contentMode: .fit)
                .overlay { CoverView(url: series.cover, corner: 0) }
                .clipShape(RoundedRectangle(cornerRadius: landscape ? 12 : 10, style: .continuous))
                .zoomSource(series.id, ns)
                .overlay(alignment: .bottomTrailing) {
                    if let p = HomeFmt.progress(series) { HomeBadge(text: p).padding(5) }
                }
                .overlay { RoundedRectangle(cornerRadius: landscape ? 12 : 10, style: .continuous).strokeBorder(STVTheme.glassBorder, lineWidth: 0.6) }
            Text(series.title)
                .font(.system(size: landscape ? 14 : 13, weight: .semibold)).foregroundStyle(STVTheme.text)
                .lineLimit(landscape ? 1 : 2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 7)
            let meta = HomeFmt.meta(series)
            if !meta.isEmpty {
                Text(meta).font(.system(size: 11)).foregroundStyle(STVTheme.secondary).lineLimit(1).padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Full list of one board, 3-column numbered grid with infinite paging.
struct BoardListView: View {
    let board: BoardSpec
    @State private var pager = Pager()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let e = pager.error, pager.items.isEmpty { ErrorStateView(error: e) { reload() } }
                else { NumberedGrid(items: pager.items, hasMore: pager.hasMore, loading: pager.isLoading) { pager.loadMore() } }
            }.padding(.vertical, 8)
        }
        .background(STVTheme.bg.ignoresSafeArea())
        .accessibilityIdentifier("screen.board")
        .navigationTitle(board.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if pager.items.isEmpty { reload() } }
    }
    private func reload() { let b = board; pager.reset { try await b.fetch($0, $1) } }
}
