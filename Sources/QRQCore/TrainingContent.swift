import Foundation

/// What an attempt sends.
public enum TrainingContent: String, Codable, CaseIterable, Identifiable, Sendable {
    case callsigns, letters, numbers, alphanumeric, symbols, mixed

    public var id: Self { self }

    public var title: String {
        switch self {
        case .callsigns: "Callsigns"
        case .letters: "Letters"
        case .numbers: "Numbers"
        case .alphanumeric: "Letters & numbers"
        case .symbols: "Punctuation"
        case .mixed: "Everything"
        }
    }

    public var example: String {
        switch self {
        case .callsigns: "DL1ABC"
        case .letters: "KQZRT"
        case .numbers: "73914"
        case .alphanumeric: "K7Q2X"
        case .symbols: "?/.,="
        case .mixed: "R?7/Q"
        }
    }

    public static let letterSet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    public static let digitSet: [Character] = Array("0123456789")
    public static let symbolSet: [Character] = Array("/?.,=+-()@':")

    /// Characters random groups are drawn from (nil for callsigns, which follow real callsign patterns).
    public var characters: [Character]? {
        switch self {
        case .callsigns: nil
        case .letters: Self.letterSet
        case .numbers: Self.digitSet
        case .alphanumeric: Self.letterSet + Self.digitSet
        case .symbols: Self.symbolSet
        case .mixed: Self.letterSet + Self.digitSet + Self.symbolSet
        }
    }
}

/// Random groups of characters ("KQZRT", "73914"…) for letter, number and punctuation practice.
public struct GroupGenerator: Sendable {
    public let characters: [Character]
    public let length: Int

    public init(content: TrainingContent, length: Int) {
        self.characters = content.characters ?? TrainingContent.letterSet
        self.length = max(1, length)
    }

    /// `count` distinct groups. With `focus`, about half the characters come from the focus set (when it overlaps).
    public func generate<R: RandomNumberGenerator>(_ count: Int, focusing focus: Set<Character> = [], using rng: inout R) -> [String] {
        let focusChars = characters.filter(focus.contains)
        var seen = Set<String>()
        var out: [String] = []
        var tries = 0
        while out.count < count && tries < count * 200 {
            tries += 1
            var group = ""
            for _ in 0..<length {
                if !focusChars.isEmpty, Double.random(in: 0..<1, using: &rng) < 0.5 {
                    group.append(focusChars.randomElement(using: &rng)!)
                } else {
                    group.append(characters.randomElement(using: &rng)!)
                }
            }
            // Very short groups from small sets can't all be unique; allow repeats once uniqueness is exhausted.
            if seen.insert(group).inserted || tries > count * 100 { out.append(group) }
        }
        return out
    }
}
