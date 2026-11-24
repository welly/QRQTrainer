// The page's settings, read from the JSON it sends. The same keys and defaults as the Mac app's preferences
// (`Pref` in Sources/QRQTrainer/Model/Preferences.swift), and the same rules as its `TrainerSettings`.
// Keep the two in step.
import CWKit
import QRQCore

struct WebSettings {
    var count = 50
    var startCPM = 100.0
    /// Speed change per copy; 0 when the speed is fixed.
    var stepPercent = 4.0
    var pitch = 600.0
    var randomPitch = false
    var pitchSpread = 100.0
    var volume = 0.6
    var riseMs = 5.0
    var useImported = false
    /// The imported list's file name, for the source name.
    var listName = ""
    var portablePercent = 0.0
    var prefixedPercent = 0.0
    var mode = TrainerMode.callsigns
    /// The Needs work characters, in Needs work mode (empty otherwise).
    var practice: Set<Character> = []
    var minLength = 5
    var maxLength = 5
    var composition = GroupComposition.mixed
    var wordSet = WordSet.top100
    var bringBackMisses = true
    var enabledCharacters = Set(CharacterClass.allCharacters)
    /// Effective speed as a fraction of the character speed (1 = no Farnsworth spacing).
    var farnsworth = 1.0

    init(_ json: JSON) {
        func double(_ key: String, _ fallback: Double) -> Double { json[key]?.double ?? fallback }
        func bool(_ key: String, _ fallback: Bool) -> Bool { json[key]?.bool ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { json[key]?.double.map { Int($0) } ?? fallback }

        mode = json["trainerMode"]?.string.flatMap(TrainerMode.init) ?? .callsigns
        count = max(1, int("count", 50))
        startCPM = min(double("startCPM", 100), Morse.maxCPM)
        stepPercent = bool("fixedSpeed", false) ? 0 : double("stepPercent", 4)
        pitch = double("pitch", 600)
        randomPitch = bool("randomPitch", false)
        pitchSpread = max(0, double("pitchSpread", 100))
        volume = double("volume", 0.6)
        riseMs = double("riseMs", 5)
        useImported = bool("useImported", false)
        listName = json["listName"]?.string ?? ""
        portablePercent = double("portablePercent", 0)
        prefixedPercent = double("prefixedPercent", 0)
        if mode == .needsWork {
            practice = Set((json["needsWorkCharacters"]?.string ?? "").filter { Morse.code(for: $0) != nil })
        }
        // Words keep their own length setting, separate from character groups.
        let words = mode == .words
        let variable = bool(words ? "variableWordLength" : "variableGroupLength", words)
        let fixed = int(words ? "wordLength" : "groupLength", 5)
        minLength = variable ? int(words ? "wordMinLength" : "groupMinLength", 1) : fixed
        maxLength = variable ? int(words ? "wordMaxLength" : "groupMaxLength", 12) : fixed
        composition = json["groupComposition"]?.string.flatMap(GroupComposition.init) ?? .mixed
        wordSet = json["wordSet"]?.string.flatMap(WordSet.init) ?? .top100
        bringBackMisses = bool("bringBackMissedWords", true)
        if let chars = json["enabledCharacters"]?.string { enabledCharacters = Set(chars) }
        farnsworth = bool("farnsworth", false) ? min(1, max(0.2, double("farnsworthPercent", 60) / 100)) : 1
    }

    var usesGroups: Bool { mode == .needsWork || mode.usesGroups }

    var wordList: [String] { Words.list(wordSet, minLength: minLength, maxLength: maxLength) }

    var lengthLabel: String { minLength == maxLength ? "\(minLength)" : "\(minLength)–\(maxLength)" }

    var groupGenerator: GroupGenerator {
        if mode == .needsWork {
            return GroupGenerator(mode: .all, enabled: practice, minLength: minLength, maxLength: maxLength)
        }
        return GroupGenerator(mode: mode, enabled: enabledCharacters, minLength: minLength, maxLength: maxLength, composition: composition)
    }

    var callsignGenerator: CallsignGenerator {
        CallsignGenerator(portableProbability: portablePercent / 100, prefixedProbability: prefixedPercent / 100)
    }

    var config: TrainingConfig { TrainingConfig(count: count, startCPM: startCPM, stepPercent: stepPercent) }

    func tone(sampleRate: Double) -> ToneSettings {
        var frequency = pitch
        if randomPitch && pitchSpread > 0 { frequency += Double.random(in: -pitchSpread...pitchSpread) }
        return ToneSettings(frequency: max(200, frequency), riseTime: riseMs / 1000, amplitude: volume, sampleRate: sampleRate)
    }

    /// Name of what an attempt sends. Attempts are only compared (best score, progress) within one source.
    func sourceName(importedCount: Int) -> String {
        var name = baseSourceName(importedCount: importedCount)
        if farnsworth < 1 { name += " · Farnsworth \(Int((farnsworth * 100).rounded()))%" }
        if stepPercent == 0 { name += " · fixed speed" }
        return name
    }

    private func baseSourceName(importedCount: Int) -> String {
        if mode == .needsWork { return "\(mode.title) · \(lengthLabel)" }
        switch mode {
        case .callsigns:
            if useImported, importedCount > 0 { return listName.isEmpty ? "Imported list" : listName }
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
}
