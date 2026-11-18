import SwiftUI
import AVKit

private struct PlayerVideoSurface: UIViewRepresentable {
    let player: AVPlayer?
    let fit: Bool
    let surface: PlayerSurface

    func makeUIView(context: Context) -> PlayerSurfaceView {
        PlayerSurfaceView(videoLayer: surface.layer)
    }

    func updateUIView(_ view: PlayerSurfaceView, context: Context) {
        if surface.layer.player !== player { surface.layer.player = player }
        surface.layer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
    }

}

private final class PlayerSurfaceView: UIView {
    private let videoLayer: AVPlayerLayer

    init(videoLayer: AVPlayerLayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
        layer.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}

@MainActor
private final class PlayerSurface: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let layer = AVPlayerLayer()
    @Published private(set) var pipAvailable = false
    @Published private(set) var pipActive = false
    private var pip: AVPictureInPictureController?
    private var pipObservation: NSKeyValueObservation?

    override init() {
        super.init()
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layer) else { return }
        pip = controller
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.pipAvailable = possible }
        }
    }

    func togglePiP() {
        guard let pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipActive = false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(layer.superlayer != nil)
    }
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

struct PlaybackScreen: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.verticalSizeClass) private var verticalSize
    @StateObject private var surface = PlayerSurface()
    @State private var panel: Panel?
    @State private var controlsVisible = true
    @State private var interaction = 0
    @State private var scrubbing = false
    @State private var skip: Skip?

    private enum Panel: String, Identifiable {
        case resources, episodes, rate, more, mediaTracks, findSource
        var id: Self { self }
    }

    private struct Skip: Equatable {
        let id = UUID()
        let seconds: Int
    }

    private var compact: Bool { verticalSize == .compact }
    private var isPlaying: Bool { playback.phase == .playing }
    private var canAutoHide: Bool {
        isPlaying && controlsVisible && !scrubbing && panel == nil && !voiceOver
            && !ProcessInfo.processInfo.arguments.contains("--screenshots")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerVideoSurface(player: playback.player, fit: playback.fit, surface: surface)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            pictureGestures
            if controlsVisible {
                chrome
                    .transition(.opacity)
            }
            playbackStatus
            if let skip { skipOverlay(skip) }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .preferredColorScheme(.dark)
        .statusBarHidden(!controlsVisible)
        .sheet(item: $panel, onDismiss: { showControls() }) { selection in
            switch selection {
            case .resources: PlaybackTracksView()
            case .episodes: PlaybackEpisodesView()
            case .rate: ratePanel
            case .more: morePanel
            case .mediaTracks: PlaybackMediaTracksView(item: playback.player?.currentItem)
            case .findSource: NavigationStack { SearchView(initialQuery: playback.title, initiallyAll: true) }
            }
        }
        .task(id: canAutoHide ? interaction : nil) {
            guard canAutoHide else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            setControlsVisible(false)
        }
        .task(id: skip) {
            guard skip != nil else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            skip = nil
        }
        .onChange(of: playback.phase) { _, phase in
            if phase == .paused || phase == .failed || phase == .ended { showControls() }
        }
        .onChange(of: voiceOver) { _, enabled in
            if enabled { showControls() }
        }
        .onDisappear { playback.saveProgress() }
    }

    private var pictureGestures: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture()).onEnded { value in
                    switch value {
                    case .first(let tap):
                        let fraction = tap.location.x / max(1, proxy.size.width)
                        if fraction < 0.35 { jump(-15) }
                        else if fraction > 0.65 { jump(15) }
                        else if playback.phase != .resolving { playback.toggle() }
                    case .second:
                        if controlsVisible && !voiceOver { setControlsVisible(false) }
                        else { showControls() }
                    }
                })
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private var chrome: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.84), .black.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: compact ? 94 : 140)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.6), .black.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                    .frame(height: compact ? 126 : 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                if !compact { transport.padding(.bottom, 6) }
                footer
            }
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.top, compact ? 6 : 4)
            .padding(.bottom, 4)

            if compact { transport }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            circleButton("收起播放器", icon: "chevron.down", id: "player-minimize") { playback.showPlayer = false }
            VStack(alignment: .leading, spacing: 3) {
                Text(playback.title).font(.headline).lineLimit(1)
                Text(playback.subtitle).font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoutePicker().frame(width: 44, height: 44)
                .background(.black.opacity(0.24), in: Circle())
            circleButton("更多播放选项", icon: "ellipsis", id: "player-more") { panel = .more }
        }
    }

    private func circleButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassPill()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private var transport: some View {
        HStack(spacing: compact ? 14 : 6) {
            transportButton("上一集", icon: "backward.end.fill", enabled: (playback.context?.index ?? 0) > 0) {
                showControls()
                playback.previous()
            }
            transportButton("后退 15 秒", icon: "gobackward.15", enabled: playback.canSeek) { jump(-15) }
            Button {
                showControls()
                playback.toggle()
            } label: {
                Image(systemName: isPlaying || playback.phase == .buffering ? "pause.fill" : playback.phase == .ended ? "arrow.counterclockwise" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .glassPill()
            }
            .buttonStyle(.plain)
            .disabled(playback.context == nil || playback.phase == .resolving)
            .accessibilityLabel(isPlaying || playback.phase == .buffering ? "暂停" : playback.phase == .ended ? "重播" : "播放")
            .accessibilityIdentifier("player-play-pause")
            transportButton("前进 15 秒", icon: "goforward.15", enabled: playback.canSeek) { jump(15) }
            transportButton("下一集", icon: "forward.end.fill", enabled: playback.hasNextEpisode) {
                showControls()
                playback.next()
            }
        }
        .frame(maxWidth: 390)
    }

    private func transportButton(_ label: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.34)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            PlaybackTimeline(scrubbing: $scrubbing, onInteraction: showControls)
            HStack(spacing: 4) {
                shortcut("倍速", iconText: "\(playback.rate.formatted())×", id: "player-rate") { panel = .rate }
                shortcut("线路", icon: "point.3.connected.trianglepath.dotted", id: "player-resources") { panel = .resources }
                shortcut("选集", icon: "list.bullet", id: "player-episodes") { panel = .episodes }
                shortcut(playback.fit ? "适应" : "填满", icon: "aspectratio", id: "player-fit") {
                    playback.fit.toggle()
                    showControls()
                }
                .accessibilityLabel(playback.fit ? "画面适应，轻点切换填满" : "画面填满，轻点切换适应")
            }
            .frame(maxWidth: 560)
        }
    }

    private func shortcut(_ label: String, icon: String? = nil, iconText: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                if let iconText { Text(iconText).font(.subheadline.monospacedDigit().weight(.semibold)) }
                Text(label).font(.caption.weight(.medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var playbackStatus: some View {
        switch playback.phase {
        case .resolving, .buffering:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text(playback.phase == .resolving ? "正在解析播放地址…" : "正在缓冲…")
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.72), in: Capsule())
            .offset(y: compact ? -56 : 0)
            .allowsHitTesting(false)
        case .failed:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle").font(.title2)
                Text("播放失败").font(.headline)
                if let error = playback.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                        .multilineTextAlignment(.center).textSelection(.enabled)
                }
                HStack {
                    Button("重试") { playback.retry() }
                    Button("切换线路") { panel = .resources }
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .frame(maxWidth: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 28)
        default:
            if surface.pipActive {
                Label("正在画中画播放", systemImage: "pip").font(.subheadline)
                    .allowsHitTesting(false)
            }
        }
    }

    private func skipOverlay(_ skip: Skip) -> some View {
        Label(skip.seconds > 0 ? "+15 秒" : "−15 秒", systemImage: skip.seconds > 0 ? "goforward.15" : "gobackward.15")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .padding(12)
            .background(.black.opacity(0.72), in: Capsule())
            .frame(maxWidth: .infinity, alignment: skip.seconds > 0 ? .trailing : .leading)
            .padding(.horizontal, compact ? 46 : 22)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func jump(_ seconds: Int) {
        guard playback.canSeek else { return }
        playback.seek(by: Double(seconds))
        skip = Skip(seconds: seconds)
        interaction += 1
    }

    private func showControls() { setControlsVisible(true) }

    private func setControlsVisible(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { controlsVisible = visible }
        if visible { interaction += 1 }
    }

    private var ratePanel: some View {
        PlaybackSheet("播放倍速") {
            List {
                ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2, 2.5, 3], id: \.self) { rate in
                    Button {
                        playback.setRate(rate)
                        panel = nil
                    } label: {
                        PlaybackChoice(title: "\(rate.formatted())×", selected: playback.rate == rate)
                    }
                    .accessibilityAddTraits(playback.rate == rate ? .isSelected : [])
                }
            }
        }
    }

    private var morePanel: some View {
        PlaybackSheet("播放选项") {
            List {
                if surface.pipAvailable || surface.pipActive {
                    Button(surface.pipActive ? "关闭画中画" : "进入画中画", systemImage: "pip") {
                        surface.togglePiP()
                        panel = nil
                    }
                }
                if playback.player?.currentItem != nil {
                    Button("音轨和字幕", systemImage: "captions.bubble") { panel = .mediaTracks }
                }
                Button("查找其它内容源", systemImage: "magnifyingglass") {
                    panel = .findSource
                }
                Button("重新解析播放地址", systemImage: "arrow.clockwise") {
                    panel = nil
                    playback.retry()
                }
                Button("停止播放", systemImage: "stop.fill", role: .destructive) {
                    panel = nil
                    playback.stop()
                }
            }
        }
    }
}

private struct PlaybackTimeline: View {
    @EnvironmentObject private var playback: PlaybackController
    @Binding var scrubbing: Bool
    let onInteraction: () -> Void
    @State private var target = 0.0

    private var position: Double { scrubbing ? target : playback.elapsed }
    private var upperBound: Double { playback.canSeek ? playback.duration : 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(position.playbackTime).accessibilityLabel("已播放 \(position.playbackTime)")
                Spacer()
                Text(playback.canSeek ? playback.duration.playbackTime : "–:––")
                    .accessibilityLabel(playback.canSeek ? "总时长 \(playback.duration.playbackTime)" : "时长未知")
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.8))
            Slider(value: Binding(get: { min(max(0, position), upperBound) }, set: { value in
                if scrubbing { target = value }
                else { playback.seek(to: value) }
                onInteraction()
            }), in: 0...upperBound, onEditingChanged: { editing in
                if editing {
                    target = playback.elapsed
                    scrubbing = true
                } else if scrubbing {
                    playback.seek(to: target)
                    scrubbing = false
                }
                onInteraction()
            })
            .disabled(!playback.canSeek)
            .accessibilityLabel("播放进度")
            .accessibilityValue(playback.canSeek ? "\(position.playbackTime) / \(playback.duration.playbackTime)" : "时长未知")
            .accessibilityIdentifier("player-timeline")
        }
        .onChange(of: playback.context?.episode.id) { _, _ in scrubbing = false }
        .onChange(of: playback.canSeek) { _, seekable in if !seekable { scrubbing = false } }
    }
}
