import Foundation
import QRQCore

/// UserDefaults keys shared by `@AppStorage` in the views and by `TrainerSettings.current()`.
enum Pref {
    static let count = "count"
    static let startCPM = "startCPM"
    static let stepPercent = "stepPercent"
    static let pauseMs = "pauseMs"
    static let fixedSpeed = "fixedSpeed"
    /// The characters Insights lists under Needs work, kept up to date by HistoryModel for the Needs work mode.
    static let needsWork = "needsWorkCharacters"
    static let insightsRange = "insightsRange"
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
    static let wordVariable = "variableWordLength"
    static let wordLength = "wordLength"
    static let wordMin = "wordMinLength"
    static let wordMax = "wordMaxLength"
    static let wordSet = "wordSet"
    static let bringBackMisses = "bringBackMissedWords"
    static let composition = "groupComposition"
    static let enabledCharacters = "enabledCharacters"
    static let farnsworth = "farnsworth"
    static let farnsworthPercent = "farnsworthPercent"

    static let allCharacters = String(CharacterClass.allCharacters)

    static let defaults: [String: Any] = [
        count: 50, startCPM: 100.0, stepPercent: 4.0, fixedSpeed: false, needsWork: "", pauseMs: 400.0,
        pitch: 600.0, randomPitch: false, pitchSpread: 100.0, volume: 0.6, riseMs: 5.0,
        useImported: false, portablePercent: 0.0, prefixedPercent: 0.0, showWPM: false,
        mode: TrainerMode.callsigns.rawValue, variableLength: false, groupLength: 5, groupMin: 1, groupMax: 12,
        wordVariable: true, wordLength: 5, wordMin: 1, wordMax: 12,
        wordSet: WordSet.top100.rawValue, bringBackMisses: true,
        composition: GroupComposition.mixed.rawValue, enabledCharacters: allCharacters,
        farnsworth: false, farnsworthPercent: 60.0,
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }
}

/// A snapshot of the preferences, taken when an attempt starts so changes mid-attempt don't affect it.
struct TrainerSettings {
    var count: Int
    var startCPM: Double
    /// Speed change per copy; 0 when the speed is fixed.
    var stepPercent: Double
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
    /// The Needs work characters, in Needs work mode (empty otherwise, or when there isn't enough history yet).
    var practice: Set<Character>
    var minLength: Int
    var maxLength: Int
    var composition: GroupComposition
    var wordSet: WordSet
    /// Words mode: missed words come back later in the attempt and in the next one.
    var bringBackMisses: Bool
    var enabledCharacters: Set<Character>
    /// Effective speed as a fraction of the character speed (1 = no Farnsworth spacing).
    var farnsworth: Double

    static func current(_ d: UserDefaults = .standard) -> TrainerSettings {
        let mode = TrainerMode(rawValue: d.string(forKey: Pref.mode) ?? "") ?? .callsigns
        // Words keep their own length setting, separate from character groups.
        let practice: Set<Character> = mode == .needsWork ? Set((d.string(forKey: Pref.needsWork) ?? "").filter { Morse.code(for: $0) != nil }) : []
        let words = mode == .words
        let variable = d.bool(forKey: words ? Pref.wordVariable : Pref.variableLength)
        let fixed = d.integer(forKey: words ? Pref.wordLength : Pref.groupLength)
        return TrainerSettings(
            count: max(1, d.integer(forKey: Pref.count)),
            startCPM: d.double(forKey: Pref.startCPM),
            stepPercent: d.bool(forKey: Pref.fixedSpeed) ? 0 : d.double(forKey: Pref.stepPercent),
            pauseMs: d.double(forKey: Pref.pauseMs),
            pitch: d.double(forKey: Pref.pitch),
            randomPitch: d.bool(forKey: Pref.randomPitch),
            pitchSpread: max(0, d.double(forKey: Pref.pitchSpread)),
            volume: d.double(forKey: Pref.volume),
            riseMs: d.double(forKey: Pref.riseMs),
            useImported: d.bool(forKey: Pref.useImported),
            portablePercent: d.double(forKey: Pref.portablePercent),
            prefixedPercent: d.double(forKey: Pref.prefixedPercent),
            mode: mode,
            practice: practice,
            minLength: variable ? d.integer(forKey: words ? Pref.wordMin : Pref.groupMin) : fixed,
            maxLength: variable ? d.integer(forKey: words ? Pref.wordMax : Pref.groupMax) : fixed,
            composition: GroupComposition(rawValue: d.string(forKey: Pref.composition) ?? "") ?? .mixed,
            wordSet: WordSet(rawValue: d.string(forKey: Pref.wordSet) ?? "") ?? .top100,
            bringBackMisses: d.bool(forKey: Pref.bringBackMisses),
            enabledCharacters: Set(d.string(forKey: Pref.enabledCharacters) ?? Pref.allCharacters),
            farnsworth: d.bool(forKey: Pref.farnsworth) ? min(1, max(0.2, d.double(forKey: Pref.farnsworthPercent) / 100)) : 1
        )
    }

    /// The words Words mode can send with the chosen length.
    var wordList: [String] { Words.list(wordSet, minLength: minLength, maxLength: maxLength) }

    /// "5" or "3–7".
    var lengthLabel: String { minLength == maxLength ? "\(minLength)" : "\(minLength)–\(maxLength)" }

    var groupGenerator: GroupGenerator {
        if mode == .needsWork {
            return GroupGenerator(mode: .all, enabled: practice, minLength: minLength, maxLength: maxLength)
        }
        return GroupGenerator(mode: mode, enabled: enabledCharacters, minLength: minLength, maxLength: maxLength, composition: composition)
    }

    /// True for attempts made of random character groups, including Needs work.
    var usesGroups: Bool { mode == .needsWork || mode.usesGroups }

    var itemName: String { mode.itemName }

    /// The Needs work characters in display order, e.g. "W 8 N".
    var practiceLabel: String {
        CharacterClass.allCharacters.filter(practice.contains).map(String.init).joined(separator: " ")
    }

    /// Name of what the next attempt will send. Attempts are only compared (best score, progress) within one source,
    /// so it includes everything that changes difficulty: mode, group length, composition and a custom character set.
    @MainActor func sourceName(library: CallsignLibrary) -> String {
        var name = baseSourceName(library: library)
        if farnsworth < 1 { name += " · Farnsworth \(Int((farnsworth * 100).rounded()))%" }
        if stepPercent == 0 { name += " · fixed speed" }
        return name
    }

    @MainActor private func baseSourceName(library: CallsignLibrary) -> String {
        // Scored as one source however the characters change, so progress on Needs work stays comparable.
        if mode == .needsWork { return "\(mode.title) · \(lengthLabel)" }
        switch mode {
        case .callsigns:
            if useImported, !library.calls.isEmpty { return library.name ?? "Imported list" }
            return "Generated"
        case .hamCodes:
            return mode.title
        case .words:
            let all = minLength <= Words.lengths.lowerBound && maxLength >= Words.lengths.upperBound
            var parts = [mode.title]
            if wordSet != .all { parts.append(wordSet.title) }
            if !all { parts.append(lengthLabel) }
            return parts.joined(separator: " · ")
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
        // Speed adapts within TrainingConfig's default limits (25–999 CPM).
        TrainingConfig(count: count, startCPM: startCPM, stepPercent: stepPercent)
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
