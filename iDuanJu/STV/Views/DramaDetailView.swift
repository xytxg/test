import SwiftUI
import UIKit

struct EpisodeRange: Hashable {
    let start: Int
    let end: Int
    init(_ start: Int, _ end: Int) { self.start = start; self.end = end }
}

enum EpisodeGroups {
    /// Group size: 30 (≤300 eps), 50 (≤600), 60 (more). Small totals stay in one group.
    static func size(for total: Int) -> Int {
        if total <= 30 { return max(total, 1) }
        if total <= 300 { return 30 }
        if total <= 600 { return 50 }
        return 60
    }
    static func ranges(total: Int) -> [EpisodeRange] {
        guard total > 0 else { return [] }
        let g = size(for: total)
        if total <= g { return [EpisodeRange(0, total - 1)] }
        var out: [EpisodeRange] = []
        var i = 0
        while i < total {
            out.append(EpisodeRange(i, min(i + g - 1, total - 1)))
            i += g
        }
        return out
    }
    static func label(_ r: EpisodeRange, episodes: [HGEpisode]) -> String {
        let a = episodes.indices.contains(r.start) ? episodes[r.start].ep : r.start + 1
        let b = episodes.indices.contains(r.end) ? episodes[r.end].ep : r.end + 1
        return a == b ? "\(a)" : "\(a)-\(b)"
    }
}

struct DramaDetailView: View {
    let series: HGSeries
    var seededDetail: HGSeriesDetail? = nil
    @State private var detail: HGSeriesDetail?
    @State private var error: Error?
    @State private var group = 0
    @State private var seasons: [HGSeries] = []
    /// Long-video sites: resolved 播放源 list (preloaded so the player starts instantly).
    @State private var sources: [HGStream] = []
    @State private var sourcesError: String?
    @State private var sourcesVerify: VerifyTarget?
    @State private var verifySheet: VerifyTarget?
    @Environment(\.zoomNS) private var ns
    private let library = LibraryStore.shared


    @State private var scrollY: CGFloat = 0
    @State private var actionsOut = false
    @State private var introOpen = false
    @State private var introClamped = false
    @Environment(\.dismiss) private var dismiss

    private var pinned: Bool { scrollY > 236 }
    private var title: String { detail?.title ?? series.title }

    /// ui-redesign 12 / 13: blurred poster-colour hero with a poster card, stats card, actions, tags, folding intro,
    /// 选集 before 系列 / 演员; a pinned nav once the hero scrolls away and a floating play bar once the main button does.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                if let d = detail { detailBody(d) }
                else if let error { ErrorStateView(error: error) { Task { await load() } }.padding(.top, 24) }
                else {
                    VStack(spacing: 10) {
                        ShimmerBlock().frame(height: 66).clipShape(RoundedRectangle(cornerRadius: 16))
                        ForEach(0..<3, id: \.self) { _ in ShimmerBlock().frame(height: 16) }
                    }.padding(.horizontal, 20).padding(.top, 18)
                }
            }
            .padding(.bottom, 110)
        }
        .coordinateSpace(.named("detail"))
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in scrollY = y }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(DebugScroll.anchor)
        .accessibilityIdentifier("screen.detail")
        .ignoresSafeArea(edges: .top)
        .background(STVTheme.bg.ignoresSafeArea())
        .overlay(alignment: .top) { navBar }
        .overlay(alignment: .bottom) { playBar }
        .toolbar(.hidden, for: .navigationBar)
        .zoomDestination(series.id, ns)
        .task {
            if let seededDetail { detail = seededDetail; selectResumeGroup() }
            else if detail == nil { await load() }
        }
        .onChange(of: detail?.episodes.count) { _, _ in selectResumeGroup() }
        .task(id: detail?.seriesId) {
            guard let d = detail else { return }
            if series.source.isLongVideo {
                await loadSources(d)
            } else {
                seasons = await SeasonStore.seasons(for: d, series: series)
            }
        }
    }

    // MARK: nav + play bar

    private var navBar: some View {
        HStack(spacing: 0) {
            DSBackButton(tone: pinned ? .glass : .overlay) { dismiss() }.frame(width: 96, alignment: .leading)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
                .frame(maxWidth: .infinity)
                .opacity(pinned ? 1 : 0).offset(y: pinned ? 0 : 6)
            Color.clear.frame(width: 96, height: 1)
        }
        .frame(height: 44)
        .padding(.horizontal, 16).padding(.bottom, 6)
        .dsPinned(pinned)
        .animation(.easeOut(duration: 0.2), value: pinned)
    }

    @ViewBuilder private var playBar: some View {
        if let d = detail, !d.episodes.isEmpty, actionsOut {
            HStack(spacing: 10) {
                NavigationLink(value: Route.play(series, library.progress(for: series)?.episodeIndex)) {
                    PillButtonLabel(title: playTitle, icon: "play.fill", tone: .ink, expand: true)
                }
                .buttonStyle(PressScale(scale: 0.98))
                .accessibilityIdentifier("detail.playbar")
                heart(48)
            }
            .padding(8)
            .dsBar(32)
            .padding(.horizontal, 16).padding(.bottom, -8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var playTitle: String {
        guard let r = library.progress(for: series) else { return "开始播放" }
        return series.source.isLongVideo ? "继续 " + Fmt.clock(Int(r.seconds)) : "继续第 \(r.episodeNumber) 集"
    }

    private func heart(_ size: CGFloat) -> some View {
        let on = library.isFavorite(series)
        return Button { withAnimation(DS.press) { library.toggleFavorite(series) } } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(on ? STVTheme.accent : STVTheme.text)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .stvGlass(in: Circle(), tint: on ? STVTheme.accent.opacity(0.24) : STVTheme.glass, interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(on ? "取消收藏" : "收藏")
        .accessibilityIdentifier("detail.favorite")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: hero

    private var cover: String { DetailCover.pick(detail: detail?.cover ?? "", list: series.cover) }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // `.bd`: the poster itself, blurred 30 pt and saturated, bleeding past the hero edges.
            CoverView(url: cover, corner: 0, fallback: series.cover)
                .frame(maxWidth: .infinity).frame(height: 400)
                .blur(radius: 30, opaque: true).saturation(1.15)
                .frame(height: 300).clipped()
                .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0), .init(color: .black.opacity(0.08), location: 0.34),
                                               .init(color: STVTheme.bg.opacity(0.74), location: 0.76), .init(color: STVTheme.bg, location: 1)],
                                        startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 16) {
                CoverView(url: cover, corner: 12, fallback: series.cover, a11yID: "detail.poster")
                    .frame(width: 116, height: 155)
                    .overlay(alignment: .bottom) {
                        if let e = DS.episodes(series) ?? detail.map({ "全 \(max($0.totalEps, $0.episodes.count)) 集" }) {
                            Text(e).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 8)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }
                    }
                    .shadow(color: .black.opacity(0.4), radius: 15, y: 14)
                VStack(alignment: .leading, spacing: 0) {
                    DSStatus(text: series.source.label, tone: .accent)
                    Text(title).font(.system(size: 23, weight: .heavy)).foregroundStyle(STVTheme.text).lineLimit(2)
                        .padding(.top, 8)
                        .contextMenu { Button("复制剧名", systemImage: "doc.on.doc") { UIPasteboard.general.string = title } }
                    Text(heroMeta).font(.system(size: 13)).foregroundStyle(STVTheme.secondary).lineLimit(1).padding(.top, 6)
                }
                .padding(.bottom, 2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.bottom, 2)
        }
        .frame(height: 300)
    }

    private var heroMeta: String {
        let eps = detail.map { $0.episodeLabel.isEmpty ? "全 \(max($0.totalEps, $0.episodes.count)) 集" : DS.spaced($0.episodeLabel) }
        return [eps, detail?.author].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: body

    @ViewBuilder private func detailBody(_ d: HGSeriesDetail) -> some View {
        stats(d).padding(.top, 18)

        HStack(spacing: 12) {
            NavigationLink(value: Route.play(series, library.progress(for: series)?.episodeIndex)) {
                PillButtonLabel(title: playTitle, icon: "play.fill", tone: .ink, height: 50, expand: true)
            }
            .buttonStyle(PressScale(scale: 0.98))
            .disabled(d.episodes.isEmpty)
            .accessibilityIdentifier("detail.play")
            heart(50)
        }
        .padding(.horizontal, 20).padding(.top, 16)
        .onGeometryChange(for: Bool.self) { $0.frame(in: .named("detail")).maxY < 60 } action: { out in
            withAnimation(DS.panel) { actionsOut = out }
        }

        if !d.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(d.tags, id: \.self) { t in
                        Text(t).font(.system(size: 12)).foregroundStyle(STVTheme.secondary)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(STVTheme.glass))
                    }
                }.padding(.horizontal, 20)
            }
            .padding(.top, 16)
        }
        if d.cast.isEmpty && !d.actors.isEmpty {
            Text("主演：" + d.actors.joined(separator: " / "))
                .font(.system(size: 12)).foregroundStyle(STVTheme.secondary).padding(.horizontal, 20).padding(.top, 12)
        }
        if !d.desc.isEmpty { intro(d.desc).padding(.top, 14) }

        if series.source.isLongVideo {
            VStack(alignment: .leading, spacing: 0) { sourcesSection }.padding(.top, 22)
        } else {
            VStack(alignment: .leading, spacing: 0) { episodes(d) }.padding(.top, 22)
        }

        let shelf = d.relatedSeries.count > 1 ? d.relatedSeries : seasons
        if shelf.count > 1 { relatedShelf(shelf, currentId: d.seriesId).padding(.top, 26) }
        if !d.cast.isEmpty { castRow(d.cast).padding(.top, 24) }
    }

    private func stats(_ d: HGSeriesDetail) -> some View {
        var cells: [(icon: String?, value: String, label: String)] = []
        if d.rating > 0 { cells.append(("star.fill", String(format: "%.1f", d.rating), "观众评分" + (d.ratingCount.isEmpty ? "" : " · " + DS.spaced(d.ratingCount) + "人"))) }
        if d.favoriteCount > 0 { cells.append((nil, DS.count(d.favoriteCount), "收藏")) }
        if !d.hotText.isEmpty { cells.append(("flame.fill", DS.spaced(d.hotText), "全网热度")) }
        // Preserve the spec's three-column density when upstream only supplies one/two metrics.
        // Missing metrics are absent, never fabricated; the card hugs its occupied columns.
        return GeometryReader { geo in
          HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        if let icon = c.icon { Image(systemName: icon).font(.system(size: 13)).foregroundStyle(STVTheme.accentWarm) }
                        Text(c.value).font(.system(size: 17, weight: .bold)).foregroundStyle(STVTheme.text).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(height: 22)
                    Text(c.label).font(.system(size: 11)).foregroundStyle(STVTheme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) { if i > 0 { STVTheme.hairline.frame(width: 1) } }
            }
        }
          .frame(width: geo.size.width * CGFloat(min(3, cells.count)) / 3, height: 63)
          .dsCard(16)
        }
        .frame(height: cells.isEmpty ? 0 : 63)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.stats")
    }

    private func intro(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(STVTheme.secondary).lineSpacing(5)
            .lineLimit(introOpen ? nil : 3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Measure the full height once to know whether 展开 is needed.
                Text(text).font(.system(size: 14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true).hidden()
                    .onGeometryChange(for: Bool.self) { $0.size.height > 70 } action: { introClamped = $0 }
            }
            .overlay(alignment: .bottomTrailing) {
                if introClamped && !introOpen {
                    Text("展开").font(.system(size: 14, weight: .semibold)).foregroundStyle(STVTheme.accent)
                        .padding(.leading, 36)
                        .background(LinearGradient(stops: [.init(color: STVTheme.bg.opacity(0), location: 0), .init(color: STVTheme.bg, location: 0.42)],
                                                   startPoint: .leading, endPoint: .trailing))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if introClamped { withAnimation(DS.panel) { introOpen.toggle() } } }
            .padding(.horizontal, 20)
            .accessibilityIdentifier("detail.intro")
    }

    @ViewBuilder private func episodes(_ d: HGSeriesDetail) -> some View {
        let resume = library.progress(for: series)
        let ranges = EpisodeGroups.ranges(total: d.episodes.count)
        let g = ranges.indices.contains(group) ? group : 0
        let range = ranges.isEmpty ? EpisodeRange(0, -1) : ranges[g]
        DSSectionHeader(title: "选集", note: "共 \(max(d.totalEps, d.episodes.count)) 集", inset: 20)
        if ranges.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ranges.indices, id: \.self) { i in
                        Button { withAnimation(DS.select) { group = i } } label: { Text(EpisodeGroups.label(ranges[i], episodes: d.episodes)) }
                            .buttonStyle(ToneChipStyle(on: i == g, neutral: true, small: true))
                            .accessibilityIdentifier("detail.range.\(i)")
                    }
                }.padding(.horizontal, 20)
            }
            .padding(.top, 12)
        }
        if range.end >= range.start {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(range.start...range.end, id: \.self) { i in
                    let on = resume?.episodeIndex == i
                    NavigationLink(value: Route.play(series, i)) {
                        Text("\(d.episodes[i].ep)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? STVTheme.accent : STVTheme.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? STVTheme.accentSoft : STVTheme.glass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay { if on { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(STVTheme.accentLine, lineWidth: 1) } }
                            .overlay(alignment: .topTrailing) { if on { Circle().fill(STVTheme.accent).frame(width: 5, height: 5).padding(6) } }
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressScale(scale: 0.94))
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            .id(g)
            .transition(.opacity)
        }
    }

    private func castRow(_ cast: [HGCelebrity]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader(title: "演员", inset: 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(cast) { c in
                        let cell = VStack(spacing: 0) {
                            Group {
                                if c.avatar.isEmpty {
                                    Text(String(c.name.prefix(1)))
                                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                                        .frame(width: 56, height: 56)
                                        .background(LinearGradient(colors: [STVTheme.accent, STVTheme.accentWarm], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                                } else { ActorAvatar(url: c.avatar, size: 56) }
                            }
                            Text(c.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1).padding(.top, 6)
                            if !c.role.isEmpty { Text(c.role).font(.system(size: 11)).foregroundStyle(STVTheme.secondary).lineLimit(1) }
                        }.frame(width: 64)
                        if c.id.isEmpty { cell } else { NavigationLink(value: Route.actor(c)) { cell }.buttonStyle(PressScale()) }
                    }
                }.padding(.horizontal, 20)
            }
        }
    }

    /// 播放源 — same look as the 选集 buttons, 3 columns, small status line under the name.
    @ViewBuilder private var sourcesSection: some View {
        DSSectionHeader(title: series.source.streamSectionTitle, inset: 20).padding(.bottom, 12)
        if sources.isEmpty {
            if let sourcesError {
                Text(sourcesError).font(.caption).foregroundStyle(STVTheme.secondary).padding(.horizontal, 20)
                if let t = sourcesVerify {
                    Button("去验证") { verifySheet = t }.buttonStyle(.borderedProminent).tint(STVTheme.accent)
                        .padding(.horizontal, 20)
                        .sheet(item: $verifySheet) { t in SiteVerifySheet(target: t, onDone: retrySources) }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in ShimmerBlock().frame(height: 52) }
                }.padding(.horizontal, 20)
            }
        } else {
            let current = SitePrefs.preferredStream[series.id] ?? sources.first?.id
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(sources) { s in
                    let on = s.id == current
                    NavigationLink(value: Route.play(series, 0)) {
                        VStack(spacing: 3) {
                            Text(s.quality ?? "默认").font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(s.kind == .hls || s.kind == .hlsAES ? "HLS" : "MP4").font(.caption2)
                                .foregroundStyle(on ? STVTheme.accent.opacity(0.8) : STVTheme.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(on ? STVTheme.accentSoft : STVTheme.glass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { if on { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(STVTheme.accentLine, lineWidth: 1) } }
                        .foregroundStyle(on ? STVTheme.accent : STVTheme.text)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { SitePrefs.preferredStream[series.id] = s.id })
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func retrySources() {
        guard let d = detail else { return }
        sourcesError = nil
        sourcesVerify = nil
        Task { await loadSources(d) }
    }

    private func loadSources(_ d: HGSeriesDetail) async {
        guard let ep = d.episodes.first else { return }
        do {
            let r = try await Catalog.resolve(series, ep)
            sources = r.streams
            sourcesError = r.streams.isEmpty ? (r.err ?? "暂无可用播放源") : nil
            sourcesVerify = nil
        } catch { sourcesError = error.localizedDescription; sourcesVerify = error.verifyTarget }
    }

    /// `系列` shelf: 104 pt posters, the current season ringed in accent with a 当前 badge.
    @ViewBuilder private func relatedShelf(_ items: [HGSeries], currentId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader(title: "系列", note: "共 \(items.count) 季", inset: 20) {
                NavigationLink(value: Route.searchFor(SeasonParser.parse(detail?.title ?? series.title).base)) {
                    MoreLabel(title: "搜全系列", icon: "magnifyingglass")
                }
                .accessibilityIdentifier("detail.series.search")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { s in
                        let on = s.seriesId == currentId
                        if on { relatedPoster(s, current: true, label: SeasonStore.label(s, in: items)) }
                        else {
                            NavigationLink(value: Route.series(s)) { relatedPoster(s, current: false, label: SeasonStore.label(s, in: items)) }
                                .buttonStyle(PressScale(scale: 0.97))
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 4)
            }
        }
    }

    private func relatedPoster(_ s: HGSeries, current: Bool, label: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverView(url: s.cover, corner: 12)
                .frame(width: 104, height: 139)
                .zoomSource(s.id, ns)
                .overlay(alignment: .topLeading) {
                    if current {
                        Text("当前").font(.system(size: 10.5, weight: .bold)).foregroundStyle(STVTheme.onAccent)
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(STVTheme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .padding(6)
                    }
                }
                .background {
                    if current {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(STVTheme.accent, lineWidth: 2).padding(-4)
                    }
                }
            Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1).padding(.top, 8)
            Text([label, s.episodeCount > 0 ? "\(s.episodeCount) 集" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(STVTheme.secondary).lineLimit(1).padding(.top, 2)
        }
        .frame(width: 104, alignment: .leading)
    }

    private func selectResumeGroup() {
        guard let d = detail, let r = library.progress(for: series) else { return }
        let ranges = EpisodeGroups.ranges(total: d.episodes.count)
        if let i = ranges.firstIndex(where: { r.episodeIndex >= $0.start && r.episodeIndex <= $0.end }) {
            group = i
        }
    }

    private func load() async {
        do {
            let d = try await Catalog.detail(series)
            detail = d
            error = nil
            selectResumeGroup()
            if series.source == .hongguo {
                // Warm the play URL of the episode a tap would open (resume point, else episode 1).
                let i = library.progress(for: series)?.episodeIndex ?? 0
                if d.episodes.indices.contains(i) { HongguoClient.shared.prefetch(vids: [d.episodes[i].vid]) }
                // Second pass: cast / tags / rating from the official site.
                if let e = await Catalog.enriched(series, d), detail?.seriesId == e.seriesId { detail = e }
            }
        } catch { self.error = error }
    }
}


/// Simulator screenshot host for the related-seasons shelf (`STV_DETAIL_SHOT=1`).
/// Set `STV_LIVE_SERIES=<seriesId>` to load a real franchise instead of mock data.
struct DetailRelatedShotHost: View {
    @State private var series = HGSeries(
        seriesId: "7000001", title: "霸总的秘密助理",
        cover: "https://picsum.photos/seed/stv1/600/900", episodeCount: 12)
    @State private var seed: HGSeriesDetail?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            Group {
                if let seed {
                    DramaDetailView(series: series, seededDetail: seed)
                        .id(seed.seriesId + "-\(seed.relatedSeries.count)")
                } else if loading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DramaDetailView(series: series, seededDetail: .previewDetail)
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(STVTheme.bg)
        .task {
            let live = ProcessInfo.processInfo.environment["STV_LIVE_SERIES"] ?? ""
            if HongguoClient.looksSID(live), let d = try? await HongguoClient.shared.detail(seriesId: live) {
                series = HGSeries(seriesId: d.seriesId, title: d.title, cover: d.cover, episodeCount: max(d.totalEps, d.episodes.count))
                seed = d
            } else {
                seed = .previewDetail
            }
            loading = false
        }
    }
}


/// One-shot live probe: franchise landing for a known multi-season stick_id.
struct ResolveProbeHost: View {
    @State private var lines: [String] = ["probing…"]
    private var vid: String {
        let e = ProcessInfo.processInfo.environment["STV_PROBE_VID"] ?? ""
        return e.isEmpty ? "7683440834066271256" : e
    }
    var body: some View {
        ScrollView { Text(lines.joined(separator: "\n")).font(.system(.footnote, design: .monospaced)).padding() }
            .task { await run() }
    }
    private func run() async {
        var out: [String] = []
        let d = HGPlayerDevice.current()
        out.append("player device src=\(d.source ?? "?") did=\(d.deviceId) (len=\(d.deviceId.count))")
        do {
            let r = try await HongguoClient.shared.resolve(vid: vid)
            out.append("OK streams=\(r.streams.count) err=\(r.err ?? "nil") duration=\(r.duration.map(String.init(describing:)) ?? "nil")")
            NSLog("[HG] probe resolve OK streams=%d", r.streams.count)
        } catch {
            out.append("FAIL \(error.localizedDescription)")
            NSLog("[HG] probe resolve FAIL %@", error.localizedDescription)
        }
        lines = out
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("resolve-probe.txt")
        try? out.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        NSLog("[HG] probe wrote %@", url.path)
    }
}

struct RelatedProbeHost: View {
    @State private var text = "probing…"
    var body: some View {
        ScrollView {
            Text(text).font(.system(.caption, design: .monospaced)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .background(Color.black)
        .task { await run() }
    }
    private func run() async {
        let sid = "7661844828728085528" // 被贬北凉… S1 from gateway tests
        var lines: [String] = ["stick_ids=" + sid]
        do {
            let items = try await HongguoClient.shared.seriesLanding(stickIds: sid)
            lines.append("landing count=\(items.count)")
            for s in items.prefix(20) {
                lines.append("\(s.seriesId) | \(s.title) | eps=\(s.episodeCount)")
            }
            let d = try await HongguoClient.shared.detail(seriesId: sid)
            lines.append("detail related=\(d.relatedSeries.count) title=\(d.title)")
            for s in d.relatedSeries.prefix(20) {
                lines.append("rel \(s.seriesId) | \(s.title)")
            }
            // Dump raw relate keys from a fresh detail post is inside client; summarize here.
        } catch {
            lines.append("ERR \(error)")
        }
        text = lines.joined(separator: "\n")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("related-probe.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        lines.append("wrote \(url.path)")
        text = lines.joined(separator: "\n")
    }
}

/// 观众评分 + 全网热度 pills (官网 seriesSocialInfo, hongguo-open-player 详情弹窗).
struct SocialStats: View {
    let detail: HGSeriesDetail
    var body: some View {
        HStack(spacing: 8) {
            if detail.rating > 0 {
                pill(Image(systemName: "star.fill"), String(format: "%.1f", detail.rating) + " 观众评分" +
                     (detail.ratingCount.isEmpty ? "" : " · \(detail.ratingCount)人"), STVTheme.accentWarm)
            }
            if !detail.hotText.isEmpty { pill(Image(systemName: "flame.fill"), "全网热度 " + detail.hotText, STVTheme.accent) }
        }
    }
    private func pill(_ icon: Image, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 4) { icon.foregroundStyle(tint); Text(text).foregroundStyle(.white) }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.12)) }
    }
}
