import AVFoundation

/// Plays pre-rendered Morse PCM through AVAudioEngine.
///
/// Each callsign is rendered in full before playback (see `MorseSynth`), so timing is sample-accurate
/// even at ultra-high speeds and there is no scheduling jitter between elements.
@MainActor
final class MorsePlayer {
    static let shared = MorsePlayer()

    let sampleRate: Double = 48_000
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    /// Incremented on every play/stop so completions from superseded buffers are ignored.
    private var generation = 0

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    func play(_ samples: [Float], completion: (@MainActor () -> Void)? = nil) {
        stop()
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else {
            completion?()
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: samples.count)
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                NSLog("QRQTrainer: audio engine failed to start: \(error)")
                completion?()
                return
            }
        }

        let token = generation
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                completion?()
            }
        }
        node.play()
    }

    func stop() {
        generation += 1
        if engine.isRunning { node.stop() }
    }
}
