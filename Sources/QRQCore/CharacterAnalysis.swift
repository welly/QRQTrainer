import Foundation

/// How often one character was copied correctly, and how often instantly.
public struct CharacterStat: Identifiable, Equatable, Sendable {
    public var id: Character { character }
    public let character: Character
    public internal(set) var sent: Int = 0
    public internal(set) var correct: Int = 0
    /// Times it was sent in an item whose response was timed (older attempts weren't).
    public internal(set) var timed: Int = 0
    /// Correct copies answered within the instant-recognition allowance.
    public internal(set) var instant: Int = 0
    /// Sum of the time from the end of the sound to Return, over timed correct copies.
    public internal(set) var thinkMsTotal: Int = 0
    public internal(set) var thinkCount: Int = 0

    public init(character: Character, sent: Int = 0, correct: Int = 0) {
        self.character = character
        self.sent = sent
        self.correct = correct
    }

    public var errors: Int { sent - correct }
    public var accuracy: Double? { sent == 0 ? nil : Double(correct) / Double(sent) }
    /// Share of timed copies that were correct and instant. Nil when none were timed.
    public var instantRate: Double? { timed == 0 ? nil : Double(instant) / Double(timed) }
    /// Average time from the end of the sound to Return when copied correctly.
    public var averageThinkMs: Int? { thinkCount == 0 ? nil : thinkMsTotal / thinkCount }
    /// Instant character recognition: copied correctly at least 90% of the time and instantly at least 80%.
    public var isInstant: Bool { (accuracy ?? 0) >= 0.9 && (instantRate ?? 0) >= 0.8 }
    /// Ranking key: the instant rate where timing exists, otherwise plain accuracy.
    public var recognition: Double { instantRate ?? accuracy ?? 0 }
}

/// A recurring mistake: `sent` was played, `typed` was entered instead (nil = left out).
public struct Confusion: Identifiable, Equatable, Sendable {
    public var id: String { String(sent) + "→" + (typed.map(String.init) ?? "∅") }
    public let sent: Character
    public let typed: Character?
    public let count: Int
}

/// Per-character accuracy and recognition speed across many copied items, from aligning what was sent with
/// what was typed.
public struct CharacterAnalysis: Sendable {
    public static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/")

    /// How long after the sound ends an answer still counts as instant: 800 ms, plus 200 ms of typing time for
    /// each further character in the item.
    public static func instantAllowanceMs(length: Int) -> Int { 800 + 200 * max(0, length - 1) }

    public private(set) var stats: [Character: CharacterStat] = [:]
    public private(set) var confusions: [Confusion] = []
    /// Callsigns that were analysed (blank answers are skipped: they say nothing about individual characters).
    public private(set) var callsignCount = 0

    public init<S: Sequence>(results: S) where S.Element == CallResult {
        var confusionCounts: [String: (Character, Character?, Int)] = [:]
        for result in results where !result.received.isEmpty {
            callsignCount += 1
            // Time after the sound, for items whose response and sound length were both recorded.
            let thinkMs = result.responseMs.flatMap { r in result.soundMs.map { max(0, r - $0) } }
            let quick = thinkMs.map { $0 <= Self.instantAllowanceMs(length: result.sent.count) } ?? false
            for item in Scoring.align(sent: result.sent, received: result.received) {
                if case .extra = item { continue }  // an inserted character isn't a miss of any sent character
                let sentChar: Character
                switch item {
                case .match(let c), .missing(let c): sentChar = c
                case .substitution(let c, _): sentChar = c
                case .extra: continue
                }
                if thinkMs != nil { stats[sentChar, default: CharacterStat(character: sentChar)].timed += 1 }
                switch item {
                case .match(let c):
                    stats[c, default: CharacterStat(character: c)].sent += 1
                    stats[c, default: CharacterStat(character: c)].correct += 1
                    if let thinkMs {
                        stats[c]!.thinkMsTotal += thinkMs
                        stats[c]!.thinkCount += 1
                        if quick && !result.repeated { stats[c]!.instant += 1 }
                    }
                case .substitution(let s, let t):
                    stats[s, default: CharacterStat(character: s)].sent += 1
                    let key = "\(s)\(t)"
                    confusionCounts[key] = (s, t, (confusionCounts[key]?.2 ?? 0) + 1)
                case .missing(let s):
                    stats[s, default: CharacterStat(character: s)].sent += 1
                    let key = "\(s)∅"
                    confusionCounts[key] = (s, nil, (confusionCounts[key]?.2 ?? 0) + 1)
                case .extra:
                    break  // an inserted character isn't a miss of any sent character
                }
            }
        }
        confusions = confusionCounts.values
            .map { Confusion(sent: $0.0, typed: $0.1, count: $0.2) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
    }

    public func stat(for c: Character) -> CharacterStat { stats[c] ?? CharacterStat(character: c) }

    /// Characters with at least `minSamples` copies that need work: least often recognised instantly first
    /// (plain accuracy where there's no timing), then least accurate. Instantly recognised characters are left out.
    public func weakest(_ n: Int, minSamples: Int = 5) -> [CharacterStat] {
        Array(rated(minSamples).filter { !$0.isInstant }.sorted {
            ($0.recognition, $0.accuracy!, -$0.errors, String($0.character))
                < ($1.recognition, $1.accuracy!, -$1.errors, String($1.character))
        }.prefix(n))
    }

    /// Instantly recognised characters (⚡) with at least `minSamples` copies, most often instant first (ties: more
    /// accurate, then more copies). Empty until a character earns ⚡.
    public func strongest(_ n: Int, minSamples: Int = 5) -> [CharacterStat] {
        Array(rated(minSamples).filter(\.isInstant).sorted {
            ($0.recognition, $0.accuracy!, $0.sent, String($1.character))
                > ($1.recognition, $1.accuracy!, $1.sent, String($0.character))
        }.prefix(n))
    }

    private func rated(_ minSamples: Int) -> [CharacterStat] {
        stats.values.filter { $0.sent >= max(1, minSamples) }
    }

    /// Callsign accuracy grouped into speed bands of `width` CPM, slowest first.
    public static func accuracyBySpeed<S: Sequence>(_ results: S, width: Double = 25) -> [SpeedBand] where S.Element == CallResult {
        var bands: [Int: (Int, Int)] = [:]
        for r in results {
            let key = Int((r.cpm / width).rounded(.down))
            let cur = bands[key] ?? (0, 0)
            bands[key] = (cur.0 + 1, cur.1 + (r.isCorrect ? 1 : 0))
        }
        return bands.keys.sorted().map { k in
            SpeedBand(lowerCPM: Double(k) * width, upperCPM: Double(k + 1) * width, total: bands[k]!.0, correct: bands[k]!.1)
        }
    }
}

public struct SpeedBand: Identifiable, Equatable, Sendable {
    public var id: Double { lowerCPM }
    public let lowerCPM: Double
    public let upperCPM: Double
    public let total: Int
    public let correct: Int
    public var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    public var midCPM: Double { (lowerCPM + upperCPM) / 2 }
}

extension CallsignGenerator {
    /// Generated callsigns that mostly contain at least one of `focus`, for drilling weak characters.
    /// Roughly 85% of calls contain a focus character; the rest are ordinary so it still feels like real traffic.
    public func generate<R: RandomNumberGenerator>(_ count: Int, focusing focus: Set<Character>, using rng: inout R) -> [String] {
        guard !focus.isEmpty else { return generate(count, using: &rng) }
        var seen = Set<String>()
        var out: [String] = []
        var tries = 0
        while out.count < count && tries < count * 2000 {
            tries += 1
            var call = next(using: &rng)
            if !call.contains(where: focus.contains) {
                // Splice a focus character into the suffix so letters/digits that are rare in prefixes still appear.
                // Digits replace the call area digit, letters replace the last suffix letter.
                if Double.random(in: 0..<1, using: &rng) < 0.85,
                   let f = focus.filter({ $0 != "/" }).randomElement(using: &rng),
                   let slot = f.isNumber ? call.lastIndex(where: \.isNumber) : call.lastIndex(where: \.isLetter) {
                    call.replaceSubrange(slot...slot, with: String(f))
                } else if Double.random(in: 0..<1, using: &rng) >= 0.15 {
                    continue
                }
            }
            if CallsignList.isValid(call), seen.insert(call).inserted { out.append(call) }
        }
        return out
    }
}

extension CallsignList {
    /// Calls from `list` that contain any of `focus`, topped up with other calls if there aren't enough.
    public static func pick<R: RandomNumberGenerator>(_ count: Int, from list: [String], focusing focus: Set<Character>, using rng: inout R) -> [String] {
        let matching = list.filter { $0.contains(where: focus.contains) }
        guard matching.count >= count / 2 else { return pick(count, from: list, using: &rng) }
        let focused = pick(min(count, Int(Double(count) * 0.85)), from: matching, using: &rng)
        let rest = list.filter { !$0.contains(where: focus.contains) }
        let others = pick(count - focused.count, from: rest.isEmpty ? matching : rest, using: &rng)
        return (focused + others).shuffled(using: &rng)
    }
}
