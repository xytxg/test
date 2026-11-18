import SwiftUI

/// Source-defined sections, sidebar categories, and ranked cover rows.
struct NovelExploreView: View {
    var onRead: (NovelBook) -> Void
    @Environment(\.dismiss) private var dismiss
    // Keep the user's choice instead of resetting to the first (possibly unavailable) source every visit.
    @AppStorage("novel.rank.source") private var sourceID = ""
    @State private var categories: [LegadoClient.ExploreCategory] = []
    @State private var group = ""
    @State private var categoryID = ""
    @State private var items: [LegadoSearchItem] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var busy = false
    @State private var error: String?
    @State private var managing = false
    @State private var choosingSource = false
    @State private var generation = UUID()
    @State private var controlHeight: CGFloat = 0
    private let accent = STVTheme.accent
    private var sources: [LegadoSource] { LegadoSourceStore.shared.sources.filter { $0.isOn && ($0.bookSourceType ?? 0) == 0 && !($0.exploreUrl ?? "").isEmpty } }
    private var groups: [String] { categories.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } } }

    @State private var searching = false
    @Namespace private var railNS

    /// ui-redesign 06: custom nav with 搜索, `.srcbar` capsule, small underline tabs, 86 pt tinted rail and `.brow` rows.
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DSNavBar(title: "小说榜单") {
                    DSBackButton { dismiss() }
                } trailing: {
                    RoundIconButton(systemName: "magnifyingglass") { searching = true }.accessibilityIdentifier("novel.rank.search")
                }
                if sources.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "books.vertical").font(.system(size: 30)).foregroundStyle(STVTheme.tertiary)
                        Text("先添加书源").font(.system(size: 16, weight: .semibold)).foregroundStyle(STVTheme.text)
                        Text("发现页显示书源实际提供的分类与榜单。").font(.system(size: 13)).foregroundStyle(STVTheme.secondary)
                        Button { managing = true } label: { PillButtonLabel(title: "导入 / 管理书源", small: true) }.buttonStyle(PressScale()).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    sourceBar.padding(.top, 10)
                    if groups.count > 1 { groupBar.padding(.top, 16) } else { Color.clear.frame(height: 12) }
                    if categories.contains(where: { $0.group == group && $0.isControl }) { sourceControls }
                    HStack(spacing: 0) { categoryRail; results.frame(maxWidth: .infinity, maxHeight: .infinity) }
                        .overlay(alignment: .top) { Hairline() }
                        .padding(.top, groups.count > 1 ? 4 : 0)
                }
            }
            .dsAmbient(cool: true)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $managing) { NovelSourcesView() }
            .fullScreenCover(isPresented: $searching) { NovelSearchView(onRead: onRead) }
            .sheet(isPresented: $choosingSource) { sourceSheet }
            .task(id: sources.map(\.id)) { if !sources.contains(where: { $0.id == sourceID }) { sourceID = sources.first?.id ?? "" } }
            .task(id: sourceID) { await refreshCategories() }
            .tint(accent)
        }
    }
    private var sourceBar: some View {
        HStack(spacing: 10) {
            Button { choosingSource = true } label: {
                CapsuleLabel(title: sources.first(where: { $0.id == sourceID })?.bookSourceName ?? "选择书源", icon: "books.vertical", trailingIcon: "chevron.down")
            }
            .buttonStyle(PressScale()).accessibilityIdentifier("novel.rank.source")
            Spacer(minLength: 0)
            Text("实时书源榜单").font(.system(size: 12)).foregroundStyle(STVTheme.tertiary)
        }
        .padding(.horizontal, 16)
    }
    private var groupBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            UnderlineTabs(items: groups, selection: Binding(get: { group }, set: { title in
                guard title != group else { return }
                group = title
                categoryID = categories.first { $0.group == title && !$0.url.isEmpty }?.id ?? ""
                Task { await resetAndLoad() }
            }), label: { $0 }, small: true, idPrefix: "novel.rank.group")
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .mask(FadeMask())
    }
    private var categoryRail: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(categories.filter { $0.group == group && !$0.isControl }) { category in
                    let on = category.id == categoryID
                    Button { withAnimation(DS.select) { select(category) } } label: {
                        Text(category.title).font(.system(size: 14, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? accent : STVTheme.secondary)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 4)
                            .background {
                                if on { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(STVTheme.accentSoft).matchedGeometryEffect(id: "rail", in: railNS) }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale(scale: 0.97))
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("novel.rank.category.\(category.title)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .frame(width: 86).background(STVTheme.rail)
    }
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink { NovelWebDetailView(items: [item], onRead: onRead).toolbar(.visible, for: .navigationBar) } label: { bookRow(item, rank: index + 1) }
                        .buttonStyle(PressScale(scale: 0.98))
                        .overlay(alignment: .top) { if index > 0 { Hairline() } }
                        .accessibilityIdentifier("novel.rank.book.\(index)")
                        .onAppear { if index == items.count - 1, hasMore, !busy, error == nil { Task { await load(generation) } } }
                }
                if busy { ProgressView().tint(STVTheme.secondary).frame(maxWidth: .infinity).padding(26) }
                else if let error {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("这个栏目暂时不可用", systemImage: "wifi.exclamationmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(STVTheme.text)
                        Text(error).font(.system(size: 12)).foregroundStyle(STVTheme.secondary).textSelection(.enabled)
                        HStack(spacing: 8) {
                            Button { Task { await load(generation) } } label: { MiniButtonLabel(title: "重试") }
                            Button { choosingSource = true } label: { MiniButtonLabel(title: "换个书源") }
                        }
                        .buttonStyle(PressScale())
                    }.padding(16)
                } else if items.isEmpty {
                    Text(categoryID.isEmpty ? "选择左侧栏目，或切换其他书源" : "书源没有返回书籍，请尝试其他栏目")
                        .font(.system(size: 13)).foregroundStyle(STVTheme.secondary).padding(20)
                } else if !hasMore {
                    Text("已显示全部").font(.system(size: 12)).foregroundStyle(STVTheme.tertiary).frame(maxWidth: .infinity).padding(20)
                }
            }
            .padding(.bottom, 30)
        }
        .id(categoryID)
        .transition(.opacity)
    }
    private func bookRow(_ item: LegadoSearchItem, rank: Int) -> some View {
        let tags = item.kind.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(2)
        let meta = [item.author, item.latest].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 11) {
            Text("\(rank)").font(.system(size: 20, weight: .heavy).italic()).foregroundStyle(STVTheme.rankColor(rank))
                .minimumScaleFactor(0.6).lineLimit(1).frame(width: 24)
            WebCover(url: item.cover, title: item.name, corner: 6).frame(width: 54, height: 75)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
                if !tags.isEmpty { HStack(spacing: 5) { ForEach(Array(tags), id: \.self) { DSTag(text: $0) } }.padding(.top, 6) }
                if !meta.isEmpty { Text(meta).font(.system(size: 12)).foregroundStyle(STVTheme.tertiary).lineLimit(1).padding(.top, 6) }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
    private var sourceSheet: some View {
        NavigationStack {
            List(sources) { source in
                Button { sourceID = source.id; choosingSource = false } label: {
                    HStack {
                        Text(source.bookSourceName).foregroundStyle(source.id == sourceID ? STVTheme.accent : STVTheme.text)
                        Spacer()
                        if source.id == sourceID { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(STVTheme.accent) }
                    }
                    .frame(minHeight: 44)
                }
                .listRowBackground(STVTheme.card)
            }.novelScreen().presentationCornerRadius(28).navigationTitle("切换榜单来源").toolbar { ToolbarItem(placement: .topBarLeading) { NovelBackButton { choosingSource = false } } }
        }
    }
    private var sourceControls: some View {
        ScrollView(.vertical) {
            ExploreControlsLayout(spacing: 6) {
                ForEach(categories.filter { $0.group == group && $0.isControl }) { c in
                    Group {
                        if c.type == "text" {
                            ExploreTextControl(category: c, enabled: !busy) { performControl(c, value: $0) }
                        } else if c.type == "select" {
                            Menu { ForEach(c.chars, id: \.self) { value in Button(value) { performControl(c, value: value) } } } label: { Text((c.displayTitle.isEmpty ? c.title : c.displayTitle) + "：" + c.value + " ▾") }
                        } else {
                            Button((c.type == "toggle" ? c.value : "") + (c.displayTitle.isEmpty ? c.title : c.displayTitle)) { performControl(c) }
                        }
                    }
                    .font(.system(size: 13)).buttonStyle(.bordered).disabled(busy)
                    .layoutValue(key: ExploreBasisKey.self, value: c.flexBasis)
                    .layoutValue(key: ExploreGrowKey.self, value: c.flexGrow)
                    .layoutValue(key: ExploreWrapKey.self, value: c.wrapBefore)
                    .accessibilityIdentifier("novel.rank.filter." + c.title)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlHeight = $0 }
            .padding(.horizontal, 16)
        }
        .frame(height: min(240, controlHeight))
        .scrollBounceBehavior(.basedOnSize)
    }

    private func select(_ category: LegadoClient.ExploreCategory) {
        guard !busy else { return }
        if category.isControl { performControl(category) }
        else { categoryID = category.id; Task { await resetAndLoad() } }
    }
    private func performControl(_ category: LegadoClient.ExploreCategory, value: String? = nil) {
        guard !busy, let source = sources.first(where: { $0.id == sourceID }) else { return }
        let previous = categories.first { $0.id == categoryID }
        generation = UUID(); let token = generation
        items = []; page = 1; hasMore = false; error = nil; busy = true
        Task {
            do {
                try await LegadoClient.run { try LegadoClient.exploreAction(source, category: category, value: value) }
                guard token == generation, sourceID == source.id, !Task.isCancelled else { return }
                await refreshCategories(previous: previous)
            } catch { if token == generation { self.error = error.localizedDescription; busy = false } }
        }
    }
    private func refreshCategories(previous: LegadoClient.ExploreCategory? = nil) async {
        generation = UUID(); categories = []; categoryID = ""; items = []; error = nil
        guard let source = sources.first(where: { $0.id == sourceID }) else { return }
        let token = generation; busy = true
        do {
            let result = try await LegadoClient.run { try LegadoClient.exploreCategories(source) }
            guard token == generation, !Task.isCancelled else { return }
            categories = result
            if !result.contains(where: { $0.group == group }) { group = result.first?.group ?? "" }
            busy = false
            let chosen = LegadoClient.refreshedCategory(previous, in: result, group: group)
            categoryID = chosen?.id ?? ""
            if let chosen { group = chosen.group }
            if result.isEmpty { error = "书源没有可用的发现配置" }
            await resetAndLoad()
        } catch { if token == generation { self.error = error.localizedDescription; busy = false } }
    }
    private func resetAndLoad() async {
        guard !categoryID.isEmpty else { items = []; hasMore = false; busy = false; return }
        generation = UUID(); items = []; page = 1; hasMore = true; busy = false; error = nil
        await load(generation)
    }
    private func load(_ token: UUID) async {
        guard token == generation, !busy, hasMore, let source = sources.first(where: { $0.id == sourceID }), let category = categories.first(where: { $0.id == categoryID }), !category.url.isEmpty else { return }
        let requestedPage = page; busy = true; error = nil
        do {
            let result = try await LegadoClient.run { try LegadoClient.explore(source, category: category, page: requestedPage) }
            guard token == generation, !Task.isCancelled else { return }
            var seen = Set(items.map(\.id)); let fresh = result.filter { seen.insert($0.id).inserted }
            items += fresh; hasMore = !fresh.isEmpty; page += 1
        } catch { if token == generation { self.error = error.localizedDescription } }
        if token == generation { busy = false }
    }
}

private struct ExploreBasisKey: LayoutValueKey { static let defaultValue: Double = -1 }
private struct ExploreGrowKey: LayoutValueKey { static let defaultValue: Double = 0 }
private struct ExploreWrapKey: LayoutValueKey { static let defaultValue = false }

/// Generic source flex widths/wrapping; not tied to any site's labels or URL formats.
private struct ExploreControlsLayout: Layout {
    var spacing: CGFloat = 6
    private func rows(_ subviews: Subviews, _ width: CGFloat) -> [[(Int, CGFloat)]] {
        var rows: [[(Int, CGFloat)]] = []; var row: [(Int, CGFloat)] = []; var used: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let basis = v[ExploreBasisKey.self]
            let w = min(width, basis > 0 ? width * min(1, basis) : v.sizeThatFits(.unspecified).width)
            if !row.isEmpty && (v[ExploreWrapKey.self] || used + spacing + w > width) { rows.append(row); row = []; used = 0 }
            row.append((i, w)); used += w + (row.count > 1 ? spacing : 0)
        }
        if !row.isEmpty { rows.append(row) }
        return rows.map { row in
            let extra = max(0, width - row.reduce(0) { $0 + $1.1 } - CGFloat(max(0, row.count - 1)) * spacing)
            let grow = row.reduce(0) { $0 + max(0, subviews[$1.0][ExploreGrowKey.self]) }
            return row.map { (i, w) in (i, w + (grow > 0 ? extra * max(0, subviews[i][ExploreGrowKey.self]) / grow : 0)) }
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(subviews, width)
        let height = rows.reduce(CGFloat.zero) { height, row in height + (row.map { subviews[$0.0].sizeThatFits(.init(width: $0.1, height: nil)).height }.max() ?? 0) } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, bounds.width) {
            var x = bounds.minX
            let height = row.map { subviews[$0.0].sizeThatFits(.init(width: $0.1, height: nil)).height }.max() ?? 0
            for (i, width) in row { subviews[i].place(at: CGPoint(x: x, y: y), proposal: .init(width: width, height: height)); x += width + spacing }
            y += height + spacing
        }
    }
}

private struct ExploreTextControl: View {
    let category: LegadoClient.ExploreCategory
    let enabled: Bool
    let onValue: (String) -> Void
    @State private var text: String
    @State private var pending: Task<Void, Never>?
    init(category: LegadoClient.ExploreCategory, enabled: Bool, onValue: @escaping (String) -> Void) {
        self.category = category; self.enabled = enabled; self.onValue = onValue; _text = State(initialValue: category.value)
    }
    var body: some View {
        TextField(category.displayTitle.isEmpty ? category.title : category.displayTitle, text: $text)
            .textFieldStyle(.roundedBorder).frame(minWidth: 140).disabled(!enabled)
            .onChange(of: text) { _, value in
                pending?.cancel()
                guard value != category.value else { return }
                pending = Task { do { try await Task.sleep(for: .milliseconds(450)); onValue(value) } catch {} }
            }
            .onChange(of: enabled) { _, value in
                pending?.cancel()
                if value && text != category.value { pending = Task { do { try await Task.sleep(for: .milliseconds(450)); onValue(text) } catch {} } }
            }
            .onChange(of: category.value) { _, value in text = value }
            .onDisappear { pending?.cancel() }
    }
}
