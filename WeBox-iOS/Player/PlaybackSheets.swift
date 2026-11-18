import SwiftUI
import AVFoundation

struct PlaybackSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct PlaybackChoice: View {
    let title: String
    var subtitle: String? = nil
    let selected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(selected ? .semibold : .regular))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 10)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct PlaybackTracksView: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlaybackSheet("切换资源") {
            List {
                if let context = playback.context {
                    Section {
                        ForEach(context.detail.groups) { group in
                            Button {
                                playback.selectGroup(group)
                                dismiss()
                            } label: {
                                PlaybackChoice(title: group.name, subtitle: "\(group.episodes.count) 集", selected: group.id == context.group.id)
                            }
                            .accessibilityAddTraits(group.id == context.group.id ? .isSelected : [])
                        }
                    } header: { Text("播放线路") }
                }
                if !playback.variants.isEmpty {
                    Section {
                        ForEach(playback.variants) { media in
                            Button {
                                playback.selectVariant(media.id)
                                dismiss()
                            } label: {
                                PlaybackChoice(title: media.name, selected: media.id == playback.selectedVariantID)
                            }
                            .accessibilityAddTraits(media.id == playback.selectedVariantID ? .isSelected : [])
                        }
                    } header: { Text("本集资源") }
                }
            }
        }
    }
}

struct PlaybackEpisodesView: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlaybackSheet("选集") {
            if let context = playback.context {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 10)], spacing: 10) {
                            ForEach(context.group.episodes) { episode in
                                episodeButton(episode, current: context.episode.id)
                                    .id(episode.id)
                            }
                        }
                        .padding(16)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        HStack {
                            Text(context.group.name)
                            Spacer()
                            Text("共 \(context.group.episodes.count) 集")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                    .onAppear { scroll.scrollTo(context.episode.id, anchor: .center) }
                }
            }
        }
    }

    private func episodeButton(_ episode: Episode, current: String) -> some View {
        let selected = episode.id == current
        return Button {
            if !selected { playback.selectEpisode(episode) }
            dismiss()
        } label: {
            Text(episode.name)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .foregroundStyle(selected ? .black : .white)
                .background(.white.opacity(selected ? 1 : 0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PlaybackMediaTracksView: View {
    let item: AVPlayerItem?
    @State private var audio: AVMediaSelectionGroup?
    @State private var subtitles: AVMediaSelectionGroup?
    @State private var selectedAudio: AVMediaSelectionOption?
    @State private var selectedSubtitle: AVMediaSelectionOption?
    @State private var loaded = false

    var body: some View {
        PlaybackSheet("音轨和字幕") {
            if let item {
                List {
                    if let audio {
                        Section("音轨") { options(in: audio, item: item, selected: $selectedAudio) }
                    }
                    if let subtitles {
                        Section("字幕") { options(in: subtitles, item: item, selected: $selectedSubtitle) }
                    }
                }
                .overlay {
                    if !loaded { ProgressView() }
                    else if audio == nil && subtitles == nil {
                        ContentUnavailableView("没有可切换的音轨或字幕", systemImage: "captions.bubble")
                    }
                }
                .task(id: ObjectIdentifier(item)) {
                    async let loadedAudio = try? item.asset.loadMediaSelectionGroup(for: .audible)
                    async let loadedSubtitles = try? item.asset.loadMediaSelectionGroup(for: .legible)
                    let (audio, subtitles) = await (loadedAudio, loadedSubtitles)
                    guard !Task.isCancelled else { return }
                    self.audio = audio
                    self.subtitles = subtitles
                    selectedAudio = audio.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
                    selectedSubtitle = subtitles.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
                    loaded = true
                }
            }
        }
    }

    @ViewBuilder private func options(in group: AVMediaSelectionGroup, item: AVPlayerItem, selected: Binding<AVMediaSelectionOption?>) -> some View {
        if group.allowsEmptySelection {
            track("关闭", option: nil, group: group, item: item, selected: selected)
        }
        ForEach(group.options, id: \.self) { option in
            track(option.displayName, option: option, group: group, item: item, selected: selected)
        }
    }

    private func track(_ title: String, option: AVMediaSelectionOption?, group: AVMediaSelectionGroup, item: AVPlayerItem, selected: Binding<AVMediaSelectionOption?>) -> some View {
        let isSelected = option == selected.wrappedValue
        return Button {
            item.select(option, in: group)
            selected.wrappedValue = option
        } label: {
            PlaybackChoice(title: title, selected: isSelected)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
