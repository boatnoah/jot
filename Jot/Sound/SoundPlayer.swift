import AVFoundation

/// Plays bundled sound files as fire-and-forget one-shots. Players are cached
/// per sound and rewound on replay.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// Master switch (preferences will drive this later).
    var isEnabled = true

    private var cache: [Sound: AVAudioPlayer] = [:]

    private init() {}

    /// Fire-and-forget one-shot.
    func play(_ sound: Sound, volume: Float = 0.85) {
        guard isEnabled, let player = oneShot(for: sound) else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func oneShot(for sound: Sound) -> AVAudioPlayer? {
        if let cached = cache[sound] { return cached }
        guard let url = sound.url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        cache[sound] = player
        return player
    }
}
