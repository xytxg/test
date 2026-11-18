import SwiftUI

/// 找剧 (ui-redesign 01–03): underline tabs 榜单 / 筛选找片.
/// 榜单 = segmented 剧种 + tone chips + top-3 posters + ranked list rows.
/// 筛选找片 = one card panel (segmented 剧种, named chip rows, 已选 summary + 重置) that collapses into a sticky glass
/// strip once it scrolls away; 「展开」 springs back to the full panel.
struct CategoryView: View {
    enum Mode: String, CaseIterable { case rank = "榜单", filter = "筛选找片" }
    @State private var mode: Mode = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["STV_CATEGORY_MODE"] == "filter" { return .filter }
        #endif
        return .rank
    }()
    @State private var genre: HGRankGenre = .all
    @State private var sub: HGRankSub = .hotSearch
    @State private var panel: HGPanel?
    @State private var panelError: Error?
    @State private var selected: [String: String] = [:]
    /// Display names of the selected option per dimension (the panel reloads per 剧种).
    @State private var selectedNames: [String: String] = [:]
    @State private var pager = Pager()
    @State private var panelGeneration = 0
    @State private var collapsed = false
    @State private var scrolled = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    UnderlineTabs(items: Mode.allCases, selection: $mode, label: \.rawValue, idPrefix: "category.mode")
                        .padding(.horizontal, 20).padding(.top, 8)
                        .id("category.top")
                    Group {
                        if mode == .rank { rankContent } else { filterContent }
                    }
                    .transition(.opacity)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { g in g.contentOffset.y + g.contentInsets.top > 6 } action: { _, v in
                withAnimation(.easeOut(duration: 0.2)) { scrolled = v }
            }
            .overlay(alignment: .top) { topFade }
            .overlay(alignment: .top) {
                if mode == .filter && collapsed {
                    stickyBar { withAnimation(DS.panel) { proxy.scrollTo("category.top", anchor: .top) } }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(DS.panel, value: collapsed)
        }
        .coordinateSpace(name: "category")
        .dsAmbient(visible: !scrolled)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if mode == .filter, panel == nil { await loadPanel() }
            if pager.items.isEmpty { reload() }
        }
        .onChange(of: mode) {
            collapsed = false
            Task { if mode == .filter, panel == nil { await loadPanel() }; reload() }
        }
        .onChange(of: genre) { if !genre.subs.contains(sub) { sub = genre.subs[0] }; reload() }
        .onChange(of: sub) { reload() }
    }

    /// `.topfade`: page colour under the status bar, fading out over the content once it scrolls.
    private var topFade: some View {
        LinearGradient(stops: [.init(color: STVTheme.bg, location: 0), .init(color: STVTheme.bg, location: 0.42), .init(color: STVTheme.bg.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: collapsed && mode == .filter ? 70 : 24)
            .ignoresSafeArea(edges: .top)
            .opacity(scrolled ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: 榜单

    @ViewBuilder private var rankContent: some View {
        SegmentedTabs(items: HGRankGenre.allCases, selection: $genre, label: \.label, idPrefix: "category.genre")
            .padding(.horizontal, 16).padding(.top, 22)
        ChipRow(items: genre.subs, selection: $sub, label: \.label, idPrefix: "category.sub")
            .padding(.top, 12)
        if let e = pager.error, pager.items.isEmpty {
            ErrorStateView(error: e) { reload() }.padding(.top, 24)
        } else {
            let items = pager.items
            LazyVGrid(columns: Self.cols, spacing: 16) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { i, s in
                    PosterCellView(series: s, rank: i + 1)
                }
                if items.isEmpty && pager.isLoading { skeletonCells(3) }
            }
            .padding(.horizontal, 16).padding(.top, 18)
            LazyVStack(spacing: 0) {
                ForEach(Array(items.dropFirst(3).enumerated()), id: \.element.id) { i, s in
                    VStack(spacing: 0) {
                        if i > 0 { Hairline() }
                        RankListRow(series: s, rank: i + 4)
                    }
                    .onAppear { if i + 3 == items.count - 1, pager.hasMore, !pager.isLoading { pager.loadMore() } }
                }
                footer
            }
            .padding(.horizontal, 16).padding(.top, 12)
        }
    }

    // MARK: 筛选找片

    @ViewBuilder private var filterContent: some View {
        Group {
            if let panel { filterPanel(panel) }
            else if let panelError { ErrorStateView(error: panelError) { Task { await loadPanel(); reload() } } }
            else { ShimmerBlock().frame(height: 230).padding(.horizontal, 16) }
        }
        .padding(.top, 22)
        .onGeometryChange(for: Bool.self) { g in g.frame(in: .named("category")).maxY < 40 } action: { v in
            if v != collapsed { collapsed = v }
        }
        if let e = pager.error, pager.items.isEmpty {
            ErrorStateView(error: e) { reload() }.padding(.top, 24)
        } else if panel != nil {
            let items = pager.items
            LazyVGrid(columns: Self.cols, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                    PosterCellView(series: s, subtitle: DS.genres(s) ?? DS.heat(s))
                        .onAppear { if i == items.count - 1, pager.hasMore, !pager.isLoading { pager.loadMore() } }
                }
                if pager.isLoading { skeletonCells(items.isEmpty ? 6 : 3) }
            }
            .padding(.horizontal, 16).padding(.top, 16)
            footer
        }
    }

    private func filterPanel(_ p: HGPanel) -> some View {
        let genreRow = p.rows.first { $0.type == "genre" }
        return VStack(alignment: .leading, spacing: 0) {
            if let genreRow {
                let options = [HGFilterOption(id: "", name: "全部")] + genreRow.items
                SegmentedTabs(items: options, selection: binding(genreRow, options), label: \.name, idPrefix: "filter.genre")
                    .padding(.trailing, 14).padding(.bottom, 8)
            }
            ForEach(p.rows.filter { $0.type != "genre" }) { row in
                let options = [HGFilterOption(id: "", name: "全部")] + row.items
                HStack(spacing: 6) {
                    Text(row.name).font(.system(size: 13)).foregroundStyle(STVTheme.tertiary).lineLimit(1)
                        .frame(minWidth: 36, alignment: .leading).fixedSize()
                    ChipRow(items: options, selection: binding(row, options), label: \.name, neutral: { $0.id.isEmpty }, leading: 0,
                            idPrefix: "filter.\(row.type)")
                }
                .frame(height: 44)
            }
            summary(p)
        }
        .padding(.top, 14).padding(.leading, 14)
        .dsCard(20)
        .padding(.horizontal, 16)
    }

    private struct Pick: Identifiable, Hashable { let type: String; let name: String; var id: String { type } }

    private func picks(_ p: HGPanel) -> [Pick] {
        let order = p.rows.map(\.type)
        return order.compactMap { t in
            guard let id = selected[t], !id.isEmpty else { return nil }
            let name = p.rows.first { $0.type == t }?.items.first { $0.id == id }?.name ?? selectedNames[t] ?? ""
            return name.isEmpty ? nil : Pick(type: t, name: name)
        }
    }

    private func summary(_ p: HGPanel) -> some View {
        let list = picks(p)
        return HStack(spacing: 7) {
            Text("已选").font(.system(size: 13)).foregroundStyle(STVTheme.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if list.isEmpty {
                        Text("全部剧集").font(.system(size: 13)).foregroundStyle(STVTheme.tertiary)
                    }
                    ForEach(list) { pk in
                        Button { remove(pk.type) } label: {
                            HStack(spacing: 3) {
                                Text(pk.name).font(.system(size: 12)).foregroundStyle(STVTheme.text)
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(STVTheme.tertiary)
                            }
                            .padding(.leading, 9).padding(.trailing, 6).frame(height: 24)
                            .background(Capsule().fill(STVTheme.glass))
                        }
                        .buttonStyle(PressScale())
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .accessibilityIdentifier("filter.pick.\(pk.name)")
                    }
                }
                .animation(DS.select, value: list)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            Button { resetAll() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold))
                    Text("重置").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(STVTheme.accent)
                .frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .opacity(list.isEmpty ? 0.4 : 1)
            .disabled(list.isEmpty)
            .accessibilityIdentifier("filter.reset")
        }
        .padding(.trailing, 14)
        .frame(height: 48)
        .overlay(alignment: .top) { Hairline() }
        .padding(.top, 6)
    }

    private func stickyBar(expand: @escaping () -> Void) -> some View {
        let list = panel.map(picks) ?? []
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 15, weight: .semibold)).foregroundStyle(STVTheme.accent)
            Text(list.isEmpty ? "全部剧集" : list.map(\.name).joined(separator: " · "))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
            if !list.isEmpty {
                Text("\(list.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(STVTheme.onAccent)
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(STVTheme.accent))
            }
            Spacer(minLength: 0)
            Button(action: expand) {
                HStack(spacing: 2) {
                    Text("展开").font(.system(size: 13))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(STVTheme.secondary)
                .padding(.leading, 12).padding(.trailing, 8).frame(height: 30)
                .background(Capsule().fill(STVTheme.glass))
            }
            .buttonStyle(PressScale())
            .accessibilityIdentifier("filter.expand")
        }
        .padding(.leading, 14).padding(.trailing, 8)
        .frame(height: 46)
        .dsBar(23)
        .padding(.horizontal, 12).padding(.top, 2)
        .accessibilityIdentifier("filter.sticky")
    }

    @ViewBuilder private var footer: some View {
        if !pager.hasMore && !pager.isLoading && !pager.items.isEmpty {
            Text("没有更多了").font(.system(size: 12)).foregroundStyle(STVTheme.tertiary).frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }

    private func skeletonCells(_ n: Int) -> some View {
        ForEach(0..<n, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 7) {
                ShimmerBlock().aspectRatio(3 / 4, contentMode: .fit)
                ShimmerBlock().frame(height: 12).frame(maxWidth: 80)
            }
        }
    }

    private static let cols = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    // MARK: Data

    private func binding(_ row: HGFilterRow, _ options: [HGFilterOption]) -> Binding<HGFilterOption> {
        Binding(get: { options.first { $0.id == (selected[row.type] ?? "") } ?? options[0] },
                set: { option in select(option, dimension: row.type) })
    }

    private func select(_ option: HGFilterOption, dimension: String) {
        if dimension == "genre" {
            selected = option.id.isEmpty ? [:] : ["genre": option.id]
            selectedNames = option.id.isEmpty ? [:] : ["genre": option.name]
            Task { await loadPanel(); reload() }
        } else {
            selected[dimension] = option.id
            selectedNames[dimension] = option.id.isEmpty ? nil : option.name
            reload()
        }
    }

    private func remove(_ type: String) {
        if type == "genre" { select(HGFilterOption(id: "", name: "全部"), dimension: "genre") }
        else { withAnimation(DS.select) { selected[type] = nil; selectedNames[type] = nil }; reload() }
    }

    private func resetAll() {
        withAnimation(DS.select) { selected = [:]; selectedNames = [:] }
        Task { await loadPanel(); reload() }
    }

    private func loadPanel() async {
        panelGeneration += 1
        let generation = panelGeneration, selectedGenre = selected["genre"] ?? ""
        panelError = nil
        do {
            let fresh = try await HongguoClient.shared.panel(genre: selectedGenre)
            guard generation == panelGeneration, selectedGenre == (selected["genre"] ?? "") else { return }
            withAnimation(DS.panel) { panel = fresh }
        } catch { if generation == panelGeneration { panelError = error } }
    }

    private func reload() {
        if mode == .rank {
            let b = BoardSpec(kind: .hongguo(genre, sub))
            pager.reset { try await b.fetch($0, $1) }
        } else {
            guard panel != nil else { return }
            let ids = selected.values.filter { !$0.isEmpty }.sorted()
            pager.reset { prev, seen in try await HongguoClient.shared.category(filterIds: ids, offset: prev.nextOffset ?? 0, sessionId: prev.sessionId, seenIds: seen.map(\.seriesId)) }
        }
    }
}
