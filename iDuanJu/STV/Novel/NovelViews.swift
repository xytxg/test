import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Non-scrolling text view: renders a page exactly as TextKit paginated it (and sizes itself in scroll mode).
struct NovelTextView: UIViewRepresentable {
    var text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = false
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        if v.attributedText != text { v.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 320
        if proposal.height != nil, proposal.height != .infinity { return CGSize(width: w, height: proposal.height!) }
        return CGSize(width: w, height: ceil(uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height))
    }
}

// MARK: - Shelf

/// 小说 tab: local bookshelf (TXT / EPUB import). 书源 come in the next phase.
struct NovelHomeView: View {
    var embedded = false
    private let store = NovelStore.shared
    @State private var importing = false
    @State private var busy = false
    @State private var errors: [String] = []
    @State private var reading: NovelBook?
    @State private var deleting: NovelBook?
    @State private var searching = false
    @State private var managing = false
    @State private var exploring = false

    @State private var importSheet = false
    @State private var sourceImport = false
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    /// ui-redesign 04: 继续阅读 card, four shortcut tiles, then the 3-column shelf.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let b = store.shelf.first(where: { store.fraction($0) != nil }) ?? store.shelf.first {
                    continueCard(b).padding(.top, 24).transition(.opacity)
                }
                tiles.padding(.top, store.books.isEmpty ? 24 : 14)
                DSSectionHeader(title: "我的书架", note: store.books.isEmpty ? nil : "\(store.books.count) 本")
                    .overlay(alignment: .trailing) { if busy { ProgressView().controlSize(.small).padding(.trailing, 16) } }
                    .padding(.top, 24)
                if store.books.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical").font(.system(size: 30)).foregroundStyle(STVTheme.tertiary)
                        Text("书架是空的").font(.system(size: 16, weight: .semibold)).foregroundStyle(STVTheme.text)
                        Text("「导入」本地 TXT / EPUB，或导入「阅读」书源后「搜书」。")
                            .font(.system(size: 13)).foregroundStyle(STVTheme.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 24)
                } else {
                    LazyVGrid(columns: cols, spacing: 16) {
                        ForEach(store.shelf) { b in
                            Button { reading = b } label: { bookCell(b) }
                                .buttonStyle(PressScale(scale: 0.97))
                                .contextMenu { Button("删除", systemImage: "trash", role: .destructive) { deleting = b } }
                                .accessibilityIdentifier("novel.book.\(b.title)")
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12)
                }
            }
            .padding(.bottom, 100)
            .animation(DS.panel, value: store.books.count)
        }
        .scrollIndicators(.hidden)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .epub], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r, !urls.isEmpty else { return }
            busy = true
            Task { errors = await store.importFiles(urls); busy = false }
        }
        .alert("部分文件导入失败", isPresented: Binding(get: { !errors.isEmpty }, set: { if !$0 { errors = [] } })) {
            Button("好") { errors = [] }
        } message: { Text(errors.joined(separator: "\n")) }
        .confirmationDialog("从书架删除「\(deleting?.title ?? "")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let b = deleting { store.remove(b) }; deleting = nil }
        } message: { Text("会同时删除阅读进度和本机保存的文件。") }
        .fullScreenCover(item: $reading) { b in NovelReaderView(book: store.book(b.id) ?? b) }
        .fullScreenCover(isPresented: $searching) {
            NovelSearchView { b in
                searching = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { reading = b }
            }
        }
        .fullScreenCover(isPresented: $managing) { NovelSourcesView() }
        .fullScreenCover(isPresented: $exploring) {
            NovelExploreView { b in
                exploring = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { reading = b }
            }
        }
        .sheet(isPresented: $importSheet) {
            NovelImportSheet(onLocalFiles: {
                importSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { importing = true }
            })
        }
        .task {
            seedFixtureIfNeeded()
            #if DEBUG
            // Screenshot hook: `STV_NOVEL_PAGE=search|rank|sources|import` opens that sub-page on launch.
            switch ProcessInfo.processInfo.environment["STV_NOVEL_PAGE"] {
            case "search": searching = true
            case "rank": exploring = true
            case "sources": managing = true
            case "import": importSheet = true
            default: break
            }
            #endif
        }
    }

    private func continueCard(_ b: NovelBook) -> some View {
        let f = store.fraction(b)
        return HStack(spacing: 14) {
            NovelCover(book: b).frame(width: 88, height: 88 / 0.72)
            VStack(alignment: .leading, spacing: 0) {
                Text(f == nil ? "开始阅读" : "继续阅读").font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(STVTheme.accentWarm)
                Text(b.title).font(.system(size: 19, weight: .bold)).foregroundStyle(STVTheme.text).lineLimit(1).padding(.top, 4)
                Text([b.author, b.isWeb ? "书源" : b.format.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(STVTheme.secondary).lineLimit(1).padding(.top, 2)
                HStack(spacing: 8) {
                    DSProgressBar(value: f ?? 0)
                    Text(f.map { "读到 \(Int(($0 * 100).rounded()))%" } ?? "未读").font(.system(size: 12)).foregroundStyle(STVTheme.secondary)
                }
                .padding(.top, 9)
                Button { reading = b } label: { PillButtonLabel(title: f == nil ? "开始阅读" : "继续阅读", icon: "play.fill", tone: .ink, small: true) }
                    .buttonStyle(PressScale()).padding(.top, 11).accessibilityIdentifier("novel.continue")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .dsCard(20)
        .padding(.horizontal, 16)
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile("搜书", "magnifyingglass", id: "novel.search") { searching = true }
            tile("排行榜", "chart.bar.fill", id: "novel.rank") { exploring = true }
            tile("书源", "books.vertical", id: "novel.sources") { managing = true }
            tile("导入", "square.and.arrow.down", id: "novel.import") { importSheet = true }
        }
        .padding(.horizontal, 16)
    }

    private func tile(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                IconWell(systemName: icon, size: 34)
                Text(title).font(.system(size: 13)).foregroundStyle(STVTheme.text)
            }
            .frame(maxWidth: .infinity).frame(height: 78)
            .dsCard(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.97))
        .accessibilityIdentifier(id)
    }

    private func bookCell(_ b: NovelBook) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NovelCover(book: b).aspectRatio(0.72, contentMode: .fit)
            Text(b.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1).padding(.top, 7)
            if let f = store.fraction(b) {
                HStack(spacing: 8) {
                    DSProgressBar(value: f)
                    Text("\(Int((f * 100).rounded()))%").font(.system(size: 12)).foregroundStyle(STVTheme.secondary)
                }
                .padding(.top, 5)
            } else {
                Text("未读").font(.system(size: 12)).foregroundStyle(STVTheme.secondary).padding(.top, 2)
            }
        }
    }

    /// UI tests: `STV_NOVEL_SEED=/abs/file.txt` imports that file once into an empty shelf;
    /// `STV_LEGADO_FIXTURE=/abs/dir` serves a fake book site from `routes.json` and imports its `sources.json`.
    private func seedFixtureIfNeeded() {
        #if DEBUG
        // `STV_LEGADO_IMPORT=/abs/sources.json`: import a (real) source collection, like the user does.
        if let f = ProcessInfo.processInfo.environment["STV_LEGADO_IMPORT"], let d = FileManager.default.contents(atPath: f),
        let list = try? LegadoSourceStore.parse(d) {
            LegadoSourceStore.shared.remove(Set(LegadoSourceStore.shared.sources.map(\.id)))
            LegadoSourceStore.shared.add(list)
        }
        let preview = ProcessInfo.processInfo.environment["STV_UI_PREVIEW"] == "1"
        let requested = preview ? Bundle.main.resourceURL?.appendingPathComponent("ui_novel_preview").path : ProcessInfo.processInfo.environment["STV_LEGADO_FIXTURE"]
        let fixtureDir = requested.map { FileManager.default.fileExists(atPath: $0) ? $0 : (Bundle.main.resourceURL?.appendingPathComponent("ui_legado").path ?? $0) }
        if let dir = fixtureDir, !dir.isEmpty,
        let rd = FileManager.default.contents(atPath: dir + "/routes.json"),
        let routes = (try? JSONSerialization.jsonObject(with: rd)) as? [String: String] {
            LegadoHTTP.transport = { req in
                let u = req.url!.absoluteString
                guard let f = routes[u], let d = FileManager.default.contents(atPath: dir + "/" + f) else {
                    return (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
                }
                Thread.sleep(forTimeInterval: 0.2)
                return (d, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!)
            }
            if let sd = FileManager.default.contents(atPath: dir + "/sources.json"), let list = try? LegadoSourceStore.parse(sd) {
                // Only the fixture sources (a previous run may have imported a big collection).
                LegadoSourceStore.shared.remove(Set(LegadoSourceStore.shared.sources.map(\.id)))
                LegadoSourceStore.shared.add(list)
            }
        }
        if preview {
            // Synthetic .invalid source state only; no real account, login or credential.
            LegadoSourceState.setLoginInfo("https://a.source.invalid", ["离线合成状态": "界面验收"])
        }
        let requestedBook = ProcessInfo.processInfo.environment["STV_NOVEL_SEED"]
        let seedPath = requestedBook.map { FileManager.default.fileExists(atPath: $0) ? $0 : (Bundle.main.url(forResource: "novel_sample_gbk", withExtension: "txt")?.path ?? $0) }
        guard let p = seedPath, !p.isEmpty,
        let data = FileManager.default.contents(atPath: p),
        let parsed = try? NovelImport.parse(data, fileName: (p as NSString).lastPathComponent),
        !store.books.contains(where: { $0.title == parsed.title }) else { return }
        try? store.add(parsed, format: (p as NSString).pathExtension)
        #endif
    }
}

struct NovelCover: View {
    let book: NovelBook
    var body: some View {
        ZStack {
            if book.hasCover, let img = UIImage(contentsOfFile: NovelStore.coverURL(book.id).path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let u = book.coverURL {
                WebCover(url: u, title: book.title)
            } else {
                let h = abs(book.title.hashValue % 360)
                LinearGradient(colors: [Color(hue: Double(h) / 360, saturation: 0.35, brightness: 0.72),
                        Color(hue: Double(h) / 360, saturation: 0.45, brightness: 0.48)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 6) {
                    Text(book.title).font(.custom("STSongti-SC-Bold", size: 15)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).lineLimit(4)
                    if let a = book.author { Text(a).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).lineLimit(1) }
                }.padding(10)
            }
        }
        .overlay {
            LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0), location: 0.07)],
                           startPoint: .leading, endPoint: .trailing).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 5, y: 4)
    }
}
