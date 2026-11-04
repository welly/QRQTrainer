import Foundation
import QRQCore

/// UserDefaults keys shared by `@AppStorage` in the views and by `TrainerSettings.current()`.
enum Pref {
    static let count = "count"
    static let startCPM = "startCPM"
    static let stepPercent = "stepPercent"
    static let minCPM = "minCPM"
    static let maxCPM = "maxCPM"
    static let pauseMs = "pauseMs"
    static let pitch = "pitch"
    static let randomPitch = "randomPitch"
    static let pitchSpread = "pitchSpread"
    static let volume = "volume"
    static let riseMs = "riseMs"
    static let useImported = "useImported"
    static let portablePercent = "portablePercent"
    static let prefixedPercent = "prefixedPercent"
    static let showWPM = "showWPM"
    static let timePenalty = "timePenalty"

    static let defaults: [String: Any] = [
        count: 50, startCPM: 100.0, stepPercent: 4.0, minCPM: 25.0, maxCPM: 999.0, pauseMs: 400.0,
        pitch: 600.0, randomPitch: false, pitchSpread: 100.0, volume: 0.6, riseMs: 5.0,
        useImported: false, portablePercent: 0.0, prefixedPercent: 0.0, showWPM: false, timePenalty: true,
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }
}

/// A snapshot of the preferences, taken when an attempt starts so changes mid-attempt don't affect it.
struct TrainerSettings {
    var count: Int
    var startCPM: Double
    var stepPercent: Double
    var minCPM: Double
    var maxCPM: Double
    var pauseMs: Double
    var pitch: Double
    var randomPitch: Bool
    var pitchSpread: Double
    var volume: Double
    var riseMs: Double
    var useImported: Bool
    var portablePercent: Double
    var prefixedPercent: Double
    var timePenalty: Bool

    static func current(_ d: UserDefaults = .standard) -> TrainerSettings {
        TrainerSettings(
            count: max(1, d.integer(forKey: Pref.count)),
            startCPM: d.double(forKey: Pref.startCPM),
            stepPercent: d.double(forKey: Pref.stepPercent),
            minCPM: d.double(forKey: Pref.minCPM),
            maxCPM: d.double(forKey: Pref.maxCPM),
            pauseMs: d.double(forKey: Pref.pauseMs),
            pitch: d.double(forKey: Pref.pitch),
            randomPitch: d.bool(forKey: Pref.randomPitch),
            pitchSpread: max(0, d.double(forKey: Pref.pitchSpread)),
            volume: d.double(forKey: Pref.volume),
            riseMs: d.double(forKey: Pref.riseMs),
            useImported: d.bool(forKey: Pref.useImported),
            portablePercent: d.double(forKey: Pref.portablePercent),
            prefixedPercent: d.double(forKey: Pref.prefixedPercent),
            timePenalty: d.bool(forKey: Pref.timePenalty)
        )
    }

    var config: TrainingConfig {
        TrainingConfig(count: count, startCPM: startCPM, stepPercent: stepPercent,
                       minCPM: min(minCPM, maxCPM), maxCPM: max(minCPM, maxCPM),
                       responseTimePenalty: timePenalty)
    }

    func tone(sampleRate: Double) -> ToneSettings {
        var frequency = pitch
        if randomPitch && pitchSpread > 0 { frequency += Double.random(in: -pitchSpread...pitchSpread) }
        return ToneSettings(frequency: max(200, frequency), amplitude: volume, riseTime: riseMs / 1000, sampleRate: sampleRate)
    }
}

/// Formats a speed the way the user prefers (CPM is the RufzXP-style unit; WPM is PARIS).
enum SpeedFormat {
    static func value(_ cpm: Double, wpm: Bool) -> Int { Int((wpm ? Morse.wpm(fromCPM: cpm) : cpm).rounded()) }
    static func unit(wpm: Bool) -> String { wpm ? "WPM" : "CPM" }
    static func string(_ cpm: Double, wpm: Bool) -> String { "\(value(cpm, wpm: wpm)) \(unit(wpm: wpm))" }
    static func secondary(_ cpm: Double, wpm: Bool) -> String { string(cpm, wpm: !wpm) }
}
