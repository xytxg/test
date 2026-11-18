import AetherEngine
import AVFoundation
import AVKit

/// Keep Aether's thread-safe time/range answers, route user transport commands through the
/// coordinator so the inline icon and the next episode share the same play intent.
final class SoftwarePiPTransportDelegate: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, @unchecked Sendable {
    private let source: SoftwarePiPSource
    private let wrapped: AVPictureInPictureSampleBufferPlaybackDelegate
    private let request: @MainActor (Bool) -> Void

    @MainActor init(source: SoftwarePiPSource, request: @escaping @MainActor (Bool) -> Void) {
        self.source = source
        self.wrapped = source.playbackDelegate
        self.request = request
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        if Thread.isMainThread { MainActor.assumeIsolated { request(playing) } }
        else { Task { @MainActor [self] in request(playing) } }
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        wrapped.pictureInPictureControllerTimeRangeForPlayback(controller)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        wrapped.pictureInPictureControllerIsPlaybackPaused(controller)
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize size: CMVideoDimensions) {
        wrapped.pictureInPictureController(controller, didTransitionToRenderSize: size)
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval interval: CMTime, completion: @escaping () -> Void) {
        wrapped.pictureInPictureController(controller, skipByInterval: interval, completion: completion)
    }
}
