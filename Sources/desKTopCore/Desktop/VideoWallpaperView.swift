import AppKit
import AVFoundation
import Foundation

/// Hardware-accelerated seamless looping video wallpaper view using AVPlayerLooper
public final class VideoWallpaperView: NSView {
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    public init(videoURL: URL, isMuted: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        setupPlayer(videoURL: videoURL, isMuted: isMuted)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPlayer(videoURL: URL, isMuted: Bool) {
        let asset = AVURLAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)

        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = isMuted
        player.actionAtItemEnd = .none

        self.playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        self.queuePlayer = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer = layer
        self.playerLayer = layer

        player.play()
    }

    public func pause() {
        queuePlayer?.pause()
    }

    public func resume() {
        queuePlayer?.play()
    }

    public override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    deinit {
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
    }
}
