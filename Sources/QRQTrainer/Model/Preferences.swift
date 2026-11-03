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
    static let mode = "trainerMode"
    static let variableLength = "variableGroupLength"
    static let groupLength = "groupLength"
    static let groupMin = "groupMinLength"
    static let groupMax = "groupMaxLength"
    static let composition = "groupComposition"
    static let enabledCharacters = "enabledCharacters"
    static let farnsworth = "farnsworth"
    static let farnsworthPercent = "farnsworthPercent"

    static let allCharacters = String(CharacterClass.allCharacters)

    static let defaults: [String: Any] = [
        count: 50, startCPM: 100.0, stepPercent: 4.0, minCPM: 25.0, maxCPM: 999.0, pauseMs: 400.0,
        pitch: 600.0, randomPitch: false, pitchSpread: 100.0, volume: 0.6, riseMs: 5.0,
        useImported: false, portablePercent: 0.0, prefixedPercent: 0.0, showWPM: false,
        mode: TrainerMode.callsigns.rawValue, variableLength: false, groupLength: 5, groupMin: 1, groupMax: 12,
        composition: GroupComposition.mixed.rawValue, enabledCharacters: allCharacters,
        farnsworth: false, farnsworthPercent: 60.0,
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
    var mode: TrainerMode
    var minLength: Int
    var maxLength: Int
    var composition: GroupComposition
    var enabledCharacters: Set<Character>
    /// Effective speed as a fraction of the character speed (1 = no Farnsworth spacing).
    var farnsworth: Double

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
            mode: TrainerMode(rawValue: d.string(forKey: Pref.mode) ?? "") ?? .callsigns,
            minLength: d.bool(forKey: Pref.variableLength) ? d.integer(forKey: Pref.groupMin) : d.integer(forKey: Pref.groupLength),
            maxLength: d.bool(forKey: Pref.variableLength) ? d.integer(forKey: Pref.groupMax) : d.integer(forKey: Pref.groupLength),
            composition: GroupComposition(rawValue: d.string(forKey: Pref.composition) ?? "") ?? .mixed,
            enabledCharacters: Set(d.string(forKey: Pref.enabledCharacters) ?? Pref.allCharacters),
            farnsworth: d.bool(forKey: Pref.farnsworth) ? min(1, max(0.2, d.double(forKey: Pref.farnsworthPercent) / 100)) : 1
        )
    }

    var groupGenerator: GroupGenerator {
        GroupGenerator(mode: mode, enabled: enabledCharacters, minLength: minLength, maxLength: maxLength, composition: composition)
    }

    /// Name of what the next attempt will send. Attempts are only compared (best score, progress) within one source,
    /// so it includes everything that changes difficulty: mode, group length, composition and a custom character set.
    @MainActor func sourceName(library: CallsignLibrary) -> String {
        let base = baseSourceName(library: library)
        return farnsworth < 1 ? "\(base) · Farnsworth \(Int((farnsworth * 100).rounded()))%" : base
    }

    @MainActor private func baseSourceName(library: CallsignLibrary) -> String {
        switch mode {
        case .callsigns:
            if useImported, !library.calls.isEmpty { return library.name ?? "Imported list" }
            return "Generated"
        case .hamCodes:
            return TrainerMode.hamCodes.title
        default:
            let g = groupGenerator
            var parts = [mode.title, g.minLength == g.maxLength ? "\(g.minLength)" : "\(g.minLength)–\(g.maxLength)"]
            if mode.classes.count > 1, composition == .separated { parts.append("separated") }
            let full = Set(mode.classes.flatMap(\.characters))
            if !full.isSubset(of: enabledCharacters) { parts.append("custom set") }
            return parts.joined(separator: " · ")
        }
    }

    var config: TrainingConfig {
        TrainingConfig(count: count, startCPM: startCPM, stepPercent: stepPercent,
                       minCPM: min(minCPM, maxCPM), maxCPM: max(minCPM, maxCPM))
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
