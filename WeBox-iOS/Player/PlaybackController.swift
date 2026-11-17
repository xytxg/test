import Foundation
import AVFoundation
import MediaPlayer

struct PlaybackContext {
    let source: SourceEntry
    let card: Card
    let detail: ContentDetail
    let group: EpisodeGroup
    let episode: Episode
    var index: Int { group.episodes.firstIndex(where: { $0.id == episode.id }) ?? 0 }
    func replacing(group: EpisodeGroup, episode: Episode) -> PlaybackContext { PlaybackContext(source: source, card: card, detail: detail, group: group, episode: episode) }
}
enum PlaybackPhase: String { case idle, resolving, buffering, playing, paused, failed, ended }
enum EpisodeMatcher {
    static func match(_ episode: Episode, index: Int, in group: EpisodeGroup) -> Episode? {
        if let exact = group.episodes.first(where: { $0.id == episode.id || $0.name == episode.name }) { return exact }
        func number(_ text: String) -> Int? {
            text.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.last.flatMap(Int.init)
        }
        if let value = number(episode.name), let matching = group.episodes.first(where: { number($0.name) == value }) { return matching }
        return group.episodes.indices.contains(index) ? group.episodes[index] : group.episodes.first
    }
}

@MainActor
private final class PlaybackHandle {
    let context: PlaybackContext
    let variants: [MediaSource]
    let selected: Int
    let player: AVPlayer
    let item: AVPlayerItem
    let loader: MediaLoader?
    let created = Date()
    var warmObservation: NSKeyValueObservation?
    init(context: PlaybackContext, variants: [MediaSource], selected: Int, preferences: PlayerPreferences) throws {
        guard variants.indices.contains(selected) else { throw WeBoxError("播放线路已变化") }
        self.context=context;self.variants=variants;self.selected=selected
        let media=variants[selected]
        if media.cenc != nil {
            let loader=try MediaLoader(source:media);self.loader=loader;item=AVPlayerItem(asset:loader.asset())
        } else {
            guard let raw=media.url,let url=URL(string:raw),HTTPClient.valid(url,httpsOnly:context.source.manifest?.allowHttp == false) else { throw WeBoxError("源没有返回有效的播放地址") }
            guard media.manifest == nil else { throw WeBoxError("此版本暂不支持内存 HLS，请选择返回 URL 的线路") }
            loader=nil
            let asset=AVURLAsset(url:url,options:["AVURLAssetHTTPHeaderFieldsKey":media.headers ?? [:]])
            item=AVPlayerItem(asset:asset)
        }
        item.preferredForwardBufferDuration=preferences.forwardBuffer
        player=AVPlayer(playerItem:item);player.automaticallyWaitsToMinimizeStalling=true
        player.allowsExternalPlayback=true;player.preventsDisplaySleepDuringVideoPlayback=true
    }
    func warm(rate: Float, completion: @escaping @MainActor (Bool) -> Void) {
        warmObservation=item.observe(\.status,options:[.initial,.new]) { [weak self] item,_ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed { self.warmObservation=nil;completion(false);return }
                guard item.status == .readyToPlay else { return }
                self.warmObservation=nil;self.player.preroll(atRate:rate) { success in Task { @MainActor in completion(success) } }
            }
        }
    }
    func close() { warmObservation=nil;player.cancelPendingPrerolls();player.pause();player.replaceCurrentItem(with:nil);loader?.stop() }
}

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var context: PlaybackContext?
    @Published private(set) var variants: [MediaSource] = []
    @Published private(set) var selectedVariantID: String?
    @Published private(set) var phase: PlaybackPhase = .idle
    @Published private(set) var error: String?
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var bufferSeconds: Double = 0
    @Published private(set) var nextReady = false
    @Published var showPlayer = false
    @Published var rate: Float = 1
    @Published var fit = true
    var onProgress: ((PlaybackContext, Double, Double) -> Void)?
    private weak var app: AppModel?
    private var handle: PlaybackHandle?
    private var prefetched: PlaybackHandle?
    private var runtime: SourceRuntime?
    private var runtimeKey = ""
    private var resolver: Task<Void, Never>?
    private var preloader: Task<Void, Never>?
    private var stallTimer: Task<Void, Never>?
    private var observations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    private var periodic: Any?
    private var generation = UUID()
    private var preferences = PlayerPreferences()
    private var wantsPlayback = true
    private var resumeAfterInterruption = false
    private var attempted = Set<String>()
    private var refreshed = false
    private var lastSaved: Double = -100
    private var pendingSeek: Double = 0
    private var seeking = false
    private var advanced = false
    private var remoteTokens: [(MPRemoteCommand, Any)] = []

    init() {
        let center=NotificationCenter.default
        notifications.append(center.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor in guard let self,let item=note.object as? AVPlayerItem,item === self.handle?.item else { return };self.ended() }
        })
        notifications.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in Task { @MainActor in self?.interruption(note) } })
        notifications.append(center.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor in
                if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
        installRemoteCommands()
    }
    deinit { for observer in notifications { NotificationCenter.default.removeObserver(observer) };for (command,token) in remoteTokens { command.removeTarget(token) } }
    var isBusy: Bool { phase == .resolving || phase == .buffering }
    var title: String { context?.card.title ?? "尚未播放" }
    var subtitle: String { guard let context else { return "" };return [context.source.name,context.episode.name].joined(separator:" · ") }
    func play(_ value: PlaybackContext, app: AppModel, resume: Double = 0, present: Bool = true) {
        saveProgress(); clearObservers(); self.app=app;preferences=app.preferences;rate=preferences.rate
        if let prepared=prefetched,prepared.context.source.id==value.source.id,prepared.context.card.id==value.card.id,prepared.context.group.id==value.group.id,prepared.context.episode.id==value.episode.id,Date().timeIntervalSince(prepared.created)<120 {
            preloader?.cancel();preloader=nil;prefetched=nil;nextReady=false
            generation=UUID();resolver?.cancel();context=value;attempted=[];refreshed=false;wantsPlayback=true
            adopt(prepared,resume:resume);if present{showPlayer=true};return
        }
        generation=UUID();let currentGeneration=generation
        resolver?.cancel();cancelPrefetch();stallTimer?.cancel()
        context=value;phase = .resolving;error=nil;attempted=[];refreshed=false;wantsPlayback=true;advanced=false
        // Pause the old item immediately, while keeping its last frame until resolution finishes.
        handle?.player.pause();elapsed=max(0,resume.isFinite ? resume : 0);duration=0
        if present { showPlayer=true }
        resolver=Task { [weak self] in
            guard let self else { return }
            do {
                let variants=try await self.resolve(value,refresh:false)
                guard self.generation==currentGeneration,!Task.isCancelled else { return }
                guard !variants.isEmpty else { throw WeBoxError("源没有返回播放线路") }
                let prepared=try self.makeHandle(context:value,variants:variants,preferred:nil)
                self.adopt(prepared,resume:resume)
            } catch { if self.generation==currentGeneration,!Task.isCancelled { self.fail(error.localizedDescription) } }
        }
    }
    private func resolve(_ value: PlaybackContext, refresh: Bool) async throws -> [MediaSource] {
        guard let app else { throw WeBoxError("播放会话已结束") }
        let key=value.source.id+String(app.sourceRevision)+(value.source.fingerprint ?? "")
        if runtime==nil || runtimeKey != key {
            runtime?.close();runtime=nil
            let engine=try await app.makeRuntime(value.source)
            try Task.checkCancellation();runtime=engine;runtimeKey=key
        }
        guard let runtime else { throw WeBoxError("源引擎尚未准备好") }
        var request:[String:Any]=["contentId":value.card.id,"groupId":value.group.id,"episodeId":value.episode.id,"refresh":refresh]
        if let link=value.episode.link { request["episodeLink"]=link }
        let result=try await runtime.invoke("play",request)
        let response=try JSONDecoder().decode(PlayResponse.self,from:JSONSerialization.data(withJSONObject:result))
        return Array(response.sources.prefix(20))
    }
    private func makeHandle(context: PlaybackContext, variants: [MediaSource], preferred: String?) throws -> PlaybackHandle {
        let order=variants.indices.sorted { a,b in
            let left=variants[a].id==preferred,right=variants[b].id==preferred
            return left != right ? left : a<b
        }
        var last:Error=WeBoxError("没有兼容的播放线路")
        for index in order where !attempted.contains(variants[index].id) {
            do { return try PlaybackHandle(context:context,variants:variants,selected:index,preferences:preferences) }
            catch { last=error;attempted.insert(variants[index].id) }
        };throw last
    }
    private func adopt(_ value: PlaybackHandle, resume: Double) {
        clearObservers();handle?.close();handle=value
        value.warmObservation=nil;value.player.cancelPendingPrerolls()
        player=value.player;context=value.context;variants=value.variants;selectedVariantID=value.variants[value.selected].id
        attempted.insert(value.variants[value.selected].id)
        error=nil;phase = .buffering;elapsed=max(0,resume.isFinite ? resume : 0);duration=0;advanced=false
        lastSaved = -100;pendingSeek=max(elapsed,preferences.skipIntro);seeking=false
        let currentGeneration=generation
        observations.append(value.item.observe(\.status,options:[.initial,.new]) { [weak self] item,_ in
            Task { @MainActor in
                guard let self,self.generation==currentGeneration,self.handle?.item === item else { return }
                if item.status == .failed { self.recover(item.error?.localizedDescription ?? "视频无法解码") }
                else if item.status == .readyToPlay { await self.ready(value,generation:currentGeneration) }
            }
        })
        observations.append(value.player.observe(\.timeControlStatus,options:[.new]) { [weak self] player,_ in
            Task { @MainActor in
                guard let self,self.generation==currentGeneration,self.player === player,self.phase != .failed else { return }
                switch player.timeControlStatus {
                case .playing: self.phase = .playing;self.stallTimer?.cancel()
                case .waitingToPlayAtSpecifiedRate: self.phase = .buffering;self.monitorStall()
                default: if !self.seeking && self.handle?.item.status == .readyToPlay {self.phase=self.wantsPlayback ? .buffering : .paused}
                };self.updateNowPlaying()
            }
        })
        periodic=value.player.addPeriodicTimeObserver(forInterval:CMTime(seconds:1,preferredTimescale:600),queue:.main) { [weak self] _ in Task { @MainActor in self?.tick() } }
        try? AVAudioSession.sharedInstance().setActive(true)
        monitorStall()
    }
    private func ready(_ value: PlaybackHandle, generation currentGeneration: UUID) async {
        guard !seeking else { return };seeking=true
        let total=value.item.duration.seconds
        if total.isFinite,total>0,pendingSeek>0 {
            let target=min(max(0,pendingSeek),max(0,total-1))
            _ = await value.player.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:CMTime(seconds:0.2,preferredTimescale:600),toleranceAfter:CMTime(seconds:0.2,preferredTimescale:600))
        }
        guard generation==currentGeneration,handle === value else { return }
        pendingSeek=0;seeking=false
        if wantsPlayback { value.player.play();value.player.rate=rate } else { phase = .paused }
        updateNowPlaying()
    }
    func pause() { wantsPlayback=false;player?.pause();phase = .paused;stallTimer?.cancel();saveProgress();updateNowPlaying() }
    func resume() {
        guard context != nil else { return }
        if phase == .failed || phase == .ended { retry();return }
        wantsPlayback=true;player?.play();player?.rate=rate;monitorStall();updateNowPlaying()
    }
    func toggle() { phase == .playing || phase == .buffering ? pause() : resume() }
    func setRate(_ value: Float) { rate=min(3,max(0.5,value));if wantsPlayback{player?.rate=rate};if let app {app.preferences.rate=rate};updateNowPlaying() }
    func seek(to seconds: Double) {
        guard duration.isFinite,duration>0,let player else { return }
        let target=min(duration,max(0,seconds));player.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
        elapsed=target;saveProgress()
    }
    func seek(by seconds: Double) { seek(to:elapsed+seconds) }
    func selectVariant(_ id: String) {
        guard let context,let index=variants.firstIndex(where:{$0.id==id}),let app else { return }
        saveProgress();let position=elapsed;generation=UUID();resolver?.cancel();cancelPrefetch();attempted=[];refreshed=false;wantsPlayback=true
        do { let value=try PlaybackHandle(context:context,variants:variants,selected:index,preferences:app.preferences);adopt(value,resume:position) }
        catch { fail(error.localizedDescription) }
    }
    func selectGroup(_ group: EpisodeGroup) {
        guard let context,let app,group.id != context.group.id,let episode=EpisodeMatcher.match(context.episode,index:context.index,in:group) else { return }
        play(context.replacing(group:group,episode:episode),app:app,resume:elapsed,present:false)
    }
    func selectEpisode(_ episode: Episode, group: EpisodeGroup? = nil) {
        guard let context,let app else { return };let group=group ?? context.group
        play(context.replacing(group:group,episode:episode),app:app,present:false)
    }
    func next() { step(1) }
    func previous() { step(-1) }
    private func step(_ delta: Int) {
        guard let context,let app else { return };let index=context.index+delta
        guard context.group.episodes.indices.contains(index) else { return }
        play(context.replacing(group:context.group,episode:context.group.episodes[index]),app:app,present:false)
    }
    func retry() { guard let context,let app else {return};runtime?.close();runtime=nil;play(context,app:app,resume:elapsed,present:false) }
    func stop() {
        saveProgress();generation=UUID();resolver?.cancel();resolver=nil;cancelPrefetch();stallTimer?.cancel();clearObservers()
        handle?.close();handle=nil;player=nil;runtime?.close();runtime=nil;context=nil;variants=[];phase = .idle;error=nil;showPlayer=false
        MPNowPlayingInfoCenter.default().nowPlayingInfo=nil;try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func saveProgress() { if let context { onProgress?(context,elapsed,duration) } }
    func applyPreferences(_ value:PlayerPreferences) { preferences=value;rate=value.rate;if wantsPlayback && phase == .playing{player?.rate=rate};handle?.item.preferredForwardBufferDuration=value.forwardBuffer;if !value.prefetchNext{cancelPrefetch()} }
    private func clearObservers() { observations.removeAll();if let periodic,let player {player.removeTimeObserver(periodic)};periodic=nil;stallTimer?.cancel() }
    private func tick() {
        guard let player,let context,let item=handle?.item else { return }
        let position=player.currentTime().seconds,total=item.duration.seconds
        if position.isFinite { elapsed=max(0,position) };if phase == .playing && elapsed>0.5{ScreenshotSupport.mark("player")};duration=total.isFinite ? max(0,total) : 0
        if let range=item.loadedTimeRanges.first?.timeRangeValue {bufferSeconds=max(0,CMTimeGetSeconds(CMTimeRangeGetEnd(range))-elapsed)}
        if abs(elapsed-lastSaved)>=8 {lastSaved=elapsed;saveProgress();updateNowPlaying()}
        if preferences.autoNext,preferences.skipOutro>0,duration>preferences.skipOutro+5,elapsed>=duration-preferences.skipOutro {ended();return}
        if phase == .playing,preferences.prefetchNext,duration>0,duration-elapsed<=45,context.index+1<context.group.episodes.count {prefetch()}
    }
    private func ended() {
        guard !advanced else {return};advanced=true;saveProgress()
        guard preferences.autoNext,let context,context.index+1<context.group.episodes.count else {wantsPlayback=false;phase = .ended;return}
        next()
    }
    private func prefetch() {
        guard preloader==nil,prefetched==nil,let context,let app else { return }
        let next=context.replacing(group:context.group,episode:context.group.episodes[context.index+1]),currentGeneration=generation
        preloader=Task { [weak self] in
            guard let self else {return}
            do {
                let choices=try await self.resolve(next,refresh:false)
                guard !Task.isCancelled,self.generation==currentGeneration,!choices.isEmpty else {return}
                let preferred=self.variants.first(where:{$0.id==self.selectedVariantID})?.name
                let index=choices.firstIndex(where:{$0.name==preferred}) ?? 0
                let value=try PlaybackHandle(context:next,variants:choices,selected:index,preferences:app.preferences)
                self.prefetched=value
                value.warm(rate:self.rate) { [weak self,weak value] success in
                    guard let self,let value,self.generation==currentGeneration,self.prefetched === value else { return };self.nextReady=success
                }
            } catch { /* Foreground playback is unaffected; next() resolves again. */ }
        }
    }
    private func cancelPrefetch() {preloader?.cancel();preloader=nil;prefetched?.close();prefetched=nil;nextReady=false}
    private func monitorStall() {
        stallTimer?.cancel();guard wantsPlayback else {return};let currentGeneration=generation
        stallTimer=Task { [weak self] in
            do {try await Task.sleep(for:.seconds(25))}catch{return}
            guard let self,self.generation==currentGeneration,self.wantsPlayback,self.phase == .buffering else {return}
            self.recover("视频持续缓冲，正在尝试其它线路")
        }
    }
    private func recover(_ message: String) {
        guard let context else {return};let position=elapsed
        if let next=variants.indices.first(where:{!attempted.contains(variants[$0].id)}) {
            cancelPrefetch();generation=UUID();wantsPlayback=true
            do {adopt(try PlaybackHandle(context:context,variants:variants,selected:next,preferences:preferences),resume:position)}catch{attempted.insert(variants[next].id);recover(error.localizedDescription)};return
        }
        guard !refreshed else {fail(message);return};refreshed=true;phase = .resolving;let currentGeneration=generation
        resolver?.cancel();resolver=Task { [weak self] in
            guard let self else{return}
            do {
                let choices=try await self.resolve(context,refresh:true)
                guard !Task.isCancelled,self.generation==currentGeneration else{return}
                self.attempted=[];self.adopt(try self.makeHandle(context:context,variants:choices,preferred:self.selectedVariantID),resume:position)
            }catch{if self.generation==currentGeneration,!Task.isCancelled{self.fail(message+"\n"+error.localizedDescription)}}
        }
    }
    private func fail(_ message: String) {phase = .failed;error=message;wantsPlayback=false;player?.pause();stallTimer?.cancel();saveProgress()}
    private func interruption(_ note: Notification) {
        guard let raw=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,let type=AVAudioSession.InterruptionType(rawValue:raw) else{return}
        if type == .began {resumeAfterInterruption=wantsPlayback;pause()}
        else if resumeAfterInterruption,let options=note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,AVAudioSession.InterruptionOptions(rawValue:options).contains(.shouldResume) {resumeAfterInterruption=false;resume()}
    }
    private func updateNowPlaying() {
        guard let context else{return}
        MPNowPlayingInfoCenter.default().nowPlayingInfo=[MPMediaItemPropertyTitle:context.card.title,MPMediaItemPropertyArtist:context.episode.name,MPMediaItemPropertyAlbumTitle:context.source.name,MPNowPlayingInfoPropertyElapsedPlaybackTime:elapsed,MPMediaItemPropertyPlaybackDuration:duration,MPNowPlayingInfoPropertyPlaybackRate:phase == .playing ? rate : 0]
    }
    private func installRemoteCommands() {
        let remote=MPRemoteCommandCenter.shared()
        func command(_ command: MPRemoteCommand,_ action:@escaping @MainActor (PlaybackController)->Void) {
            let token=command.addTarget { [weak self] _ in Task{@MainActor in if let self{action(self)}};return .success };remoteTokens.append((command,token))
        }
        command(remote.playCommand){$0.resume()};command(remote.pauseCommand){$0.pause()};command(remote.togglePlayPauseCommand){$0.toggle()}
        command(remote.nextTrackCommand){$0.next()};command(remote.previousTrackCommand){$0.previous()}
        remote.skipForwardCommand.preferredIntervals=[15];remote.skipBackwardCommand.preferredIntervals=[15]
        command(remote.skipForwardCommand){$0.seek(by:15)};command(remote.skipBackwardCommand){$0.seek(by:-15)}
        let seek=remote.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let value=event as? MPChangePlaybackPositionCommandEvent else{return .commandFailed}
            Task{@MainActor in self?.seek(to:value.positionTime)};return .success
        };remoteTokens.append((remote.changePlaybackPositionCommand,seek))
    }
}
