import SwiftUI
import AVKit

@MainActor
final class PlaybackModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var resolving = false
    @Published var error: String?
    @Published var episodeID: String?
    private var loader: MediaLoader?
    private var runtime: SourceRuntime?
    private var task: Task<Void, Never>?
    private var observer: NSKeyValueObservation?
    private var finished: NSObjectProtocol?
    private var generation = UUID()
    var onFinished: (() -> Void)?
    var position: Double { player?.currentTime().seconds ?? 0 }
    func play(card: Card, source: SourceEntry, group: EpisodeGroup, episode: Episode, app: AppModel, resume: Double = 0) {
        task?.cancel(); runtime?.close(); runtime = nil
        stopPlayer()
        let gen = UUID(); generation = gen
        resolving = true; error = nil; episodeID = episode.id
        task = Task {
            do {
                let engine = try await app.makeRuntime(source)
                guard generation == gen, !Task.isCancelled else { engine.close(); return }
                runtime = engine
                let value = try await engine.invoke("play", ["contentId": card.id, "groupId": group.id, "episodeId": episode.id, "purpose": "play"])
                let response = try JSONDecoder().decode(PlayResponse.self, from: JSONSerialization.data(withJSONObject: value))
                guard generation == gen, !Task.isCancelled else { return }
                guard let media = response.sources.first, let url = URL(string: media.url), ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { throw WeBoxError("此源没有返回可播放地址") }
                let item: AVPlayerItem
                if media.cenc != nil {
                    let loader = try MediaLoader(source: media); self.loader = loader
                    item = AVPlayerItem(asset: loader.asset())
                } else {
                    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": media.headers ?? [:]])
                    item = AVPlayerItem(asset: asset)
                }
                item.preferredForwardBufferDuration = 8
                let player = AVPlayer(playerItem: item); self.player = player
                observer = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self, self.generation == gen else { return }
                        if item.status == .failed { self.error = item.error?.localizedDescription ?? "播放器无法解码此视频"; self.resolving = false }
                    }
                }
                finished = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in Task { @MainActor in self?.onFinished?() } }
                resolving = false
                if resume.isFinite && resume > 1 { await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
                try AVAudioSession.sharedInstance().setActive(true)
                player.play()
                app.record(card, source: source, episode: episode.id, seconds: resume)
            } catch { if generation == gen, !Task.isCancelled { self.error = error.localizedDescription; resolving = false } }
        }
    }
    private func stopPlayer() {
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        observer = nil
        if let finished { NotificationCenter.default.removeObserver(finished); self.finished = nil }
        loader?.stop(); loader = nil
    }
    func close() {
        generation = UUID(); task?.cancel(); task = nil
        runtime?.close(); runtime = nil; stopPlayer(); resolving = false
    }
}

struct DetailView: View {
    let card: Card
    let source: SourceEntry
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = PlaybackModel()
    @State private var detail: ContentDetail?
    @State private var error: String?
    @State private var groupID = ""
    @State private var ascending = true
    private var group: EpisodeGroup? { detail?.groups.first { $0.id == groupID } ?? detail?.groups.first }
    private var saved: LibraryItem? { app.history.first { $0.sourceID == source.id && $0.card.id == card.id } }
    private var isFavorite: Bool { app.favorites.contains { $0.sourceID == source.id && $0.card.id == card.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                playerView
                introduction
                if let message = playback.error { Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red).textSelection(.enabled) }
                summaryView
                episodesSection
            }.padding(20)
        }
        .navigationTitle("内容详情").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear { playback.onFinished = playNext }
        .onChange(of: scenePhase) { _, phase in if phase != .active { savePosition() } }
        .onDisappear { savePosition(); playback.close() }
    }
    @ViewBuilder private var playerView: some View {
        if let player = playback.player {
            VideoPlayer(player: player).frame(height: 290).background(.black).clipShape(RoundedRectangle(cornerRadius: 16))
        } else if playback.resolving {
            ZStack { Color.black; ProgressView("正在解析播放地址…").tint(.white).foregroundStyle(.white) }
                .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    private var introduction: some View {
        HStack(alignment: .top, spacing: 18) {
            PosterImage(url: detail?.poster ?? card.poster, title: card.title)
                .frame(width: 100, height: 144).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Text(detail?.title ?? card.title).font(.title2.bold())
                Text(source.name).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                Text(card.subtitle ?? "共 \(group?.episodes.count ?? 0) 集").font(.subheadline).foregroundStyle(.secondary)
                Button { app.toggleFavorite(card, source: source) }
                label: { Label(isFavorite ? "已收藏" : "收藏", systemImage: isFavorite ? "heart.fill" : "heart") }.buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var summaryView: some View {
        if let summary = detail?.summary ?? card.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("剧情简介").font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled)
            }
        }
    }
    @ViewBuilder private var episodesSection: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("选集").font(.headline); Spacer()
                    Text("\(group?.episodes.count ?? 0) 集").font(.caption).foregroundStyle(.secondary)
                    Button { ascending.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("切换选集顺序")
                }
                if detail.groups.count > 1 {
                    Picker("播放线路", selection: $groupID) { ForEach(detail.groups) { group in Text(group.name).tag(group.id) } }.pickerStyle(.menu)
                }
                if let group { episodeControls(group) }
            }
        } else if let message = error {
            ContentUnavailableView { Label("分集暂不可用", systemImage: "exclamationmark.circle") }
            description: { Text(message) } actions: { Button("重试") { Task { await load() } } }
        } else { ProgressView("加载分集…").frame(maxWidth: .infinity) }
    }
    private func episodeControls(_ group: EpisodeGroup) -> some View {
        let episodes = ascending ? group.episodes : Array(group.episodes.reversed())
        let current = group.episodes.first { $0.id == saved?.episodeID } ?? group.episodes.first
        return VStack(spacing: 16) {
            if let current {
                Button { play(group, current, resume: saved?.episodeID == current.id ? saved?.seconds ?? 0 : 0) }
                label: { Label(saved == nil ? "立即播放" : "继续观看 · \(current.name)", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                    .buttonStyle(.borderedProminent).disabled(playback.resolving)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 10)], spacing: 10) {
                ForEach(episodes) { episode in episodeButton(group, episode) }
            }
        }
    }
    private func episodeButton(_ group: EpisodeGroup, _ episode: Episode) -> some View {
        let selected = playback.episodeID == episode.id
        return Button { play(group, episode) } label: {
            Text(episode.name).font(.subheadline).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(selected ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }.buttonStyle(.plain)
    }
    private func playNext() {
        guard let group, let index = group.episodes.firstIndex(where: { $0.id == playback.episodeID }), index + 1 < group.episodes.count else { return }
        play(group, group.episodes[index + 1])
    }
    private func savePosition() {
        if let episode = playback.episodeID, playback.player != nil { app.record(card, source: source, episode: episode, seconds: playback.position) }
    }
    private func play(_ group: EpisodeGroup, _ episode: Episode, resume: Double = 0) {
        savePosition(); playback.play(card: card, source: source, group: group, episode: episode, app: app, resume: resume)
    }
    private func load() async {
        error = nil
        var engine: SourceRuntime?
        defer { engine?.close() }
        do {
            let runtime = try await app.makeRuntime(source); engine = runtime
            let value = try await runtime.invoke("detail", ["id": card.id])
            detail = try JSONDecoder().decode(ContentDetail.self, from: JSONSerialization.data(withJSONObject: value))
            groupID = detail?.groups.first?.id ?? ""
        } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}
