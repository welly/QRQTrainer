import Foundation

/// How often one character was copied correctly.
public struct CharacterStat: Identifiable, Equatable, Sendable {
    public var id: Character { character }
    public let character: Character
    public internal(set) var sent: Int = 0
    public internal(set) var correct: Int = 0

    public init(character: Character, sent: Int = 0, correct: Int = 0) {
        self.character = character
        self.sent = sent
        self.correct = correct
    }

    public var errors: Int { sent - correct }
    public var accuracy: Double? { sent == 0 ? nil : Double(correct) / Double(sent) }
}

/// A recurring mistake: `sent` was played, `typed` was entered instead (nil = left out).
public struct Confusion: Identifiable, Equatable, Sendable {
    public var id: String { String(sent) + "→" + (typed.map(String.init) ?? "∅") }
    public let sent: Character
    public let typed: Character?
    public let count: Int
}

/// Per-character accuracy across many copied callsigns, from aligning what was sent with what was typed.
public struct CharacterAnalysis: Sendable {
    public static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/")

    public private(set) var stats: [Character: CharacterStat] = [:]
    public private(set) var confusions: [Confusion] = []
    /// Callsigns that were analysed (blank answers are skipped: they say nothing about individual characters).
    public private(set) var callsignCount = 0

    public init<S: Sequence>(results: S) where S.Element == CallResult {
        var confusionCounts: [String: (Character, Character?, Int)] = [:]
        for result in results where !result.received.isEmpty {
            callsignCount += 1
            for item in Scoring.align(sent: result.sent, received: result.received) {
                switch item {
                case .match(let c):
                    stats[c, default: CharacterStat(character: c)].sent += 1
                    stats[c, default: CharacterStat(character: c)].correct += 1
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

    /// Characters with at least `minSamples` copies, least accurate first (ties: more errors first).
    public func weakest(_ n: Int, minSamples: Int = 5) -> [CharacterStat] {
        Array(rated(minSamples).sorted {
            ($0.accuracy!, -$0.errors, String($0.character)) < ($1.accuracy!, -$1.errors, String($1.character))
        }.prefix(n))
    }

    /// Characters with at least `minSamples` copies, most accurate first (ties: more copies first).
    public func strongest(_ n: Int, minSamples: Int = 5) -> [CharacterStat] {
        Array(rated(minSamples).sorted {
            ($0.accuracy!, $0.sent, String($1.character)) > ($1.accuracy!, $1.sent, String($0.character))
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
