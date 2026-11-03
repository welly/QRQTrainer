import Foundation

/// A family of characters that can be trained.
public enum CharacterClass: String, CaseIterable, Codable, Sendable {
    case letters, figures, symbols

    public var characters: [Character] {
        switch self {
        case .letters: Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        case .figures: Array("1234567890")
        case .symbols: Array(".,:;+-='\"?()/@")
        }
    }

    public var title: String {
        switch self {
        case .letters: "Letters"
        case .figures: "Figures"
        case .symbols: "Symbols"
        }
    }

    /// Every character any class can produce, in display order.
    public static var allCharacters: [Character] { allCases.flatMap(\.characters) }
}

/// What an attempt is made of.
public enum TrainerMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case callsigns
    case hamCodes
    case letters
    case figures
    case symbols
    case lettersFigures
    case lettersSymbols
    case figuresSymbols
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .callsigns: "Callsigns"
        case .hamCodes: "Ham codes"
        case .letters: "Letters"
        case .figures: "Figures"
        case .symbols: "Symbols"
        case .lettersFigures: "Letters & figures"
        case .lettersSymbols: "Letters & symbols"
        case .figuresSymbols: "Figures & symbols"
        case .all: "All characters"
        }
    }

    /// Character classes used to build random groups. Empty for word-based modes.
    public var classes: [CharacterClass] {
        switch self {
        case .callsigns, .hamCodes: []
        case .letters: [.letters]
        case .figures: [.figures]
        case .symbols: [.symbols]
        case .lettersFigures: [.letters, .figures]
        case .lettersSymbols: [.letters, .symbols]
        case .figuresSymbols: [.figures, .symbols]
        case .all: [.letters, .figures, .symbols]
        }
    }

    /// True for modes made of random character groups (as opposed to callsigns or ham codes).
    public var usesGroups: Bool { !classes.isEmpty }

    /// What one item of an attempt is called in the interface.
    public var itemName: String {
        switch self {
        case .callsigns: "callsign"
        case .hamCodes: "code"
        default: "group"
        }
    }
}

/// How the characters of a group are chosen when a mode combines several classes.
public enum GroupComposition: String, CaseIterable, Codable, Sendable {
    /// Every group may contain characters from all of the mode's classes.
    case mixed
    /// Each group uses a single class (a group of letters, then a group of figures, …).
    case separated
}

/// Generates random character groups such as `KQ7` or `.,?/`.
public struct GroupGenerator: Sendable {
    public var minLength: Int
    public var maxLength: Int
    public var composition: GroupComposition
    /// Characters available per class, already filtered by the user's selection. Classes with no characters are ignored.
    public var pools: [[Character]]

    public init(mode: TrainerMode, enabled: Set<Character>, minLength: Int, maxLength: Int, composition: GroupComposition = .mixed) {
        self.minLength = max(1, min(minLength, maxLength))
        self.maxLength = max(1, minLength, maxLength)
        self.composition = composition
        self.pools = mode.classes
            .map { $0.characters.filter(enabled.contains) }
            .filter { !$0.isEmpty }
    }

    /// False when the selection leaves nothing to send.
    public var canGenerate: Bool { !pools.isEmpty }

    public func next<R: RandomNumberGenerator>(using rng: inout R) -> String {
        guard canGenerate else { return "" }
        let length = Int.random(in: minLength...maxLength, using: &rng)
        let pool = composition == .separated ? pools.randomElement(using: &rng)! : pools.flatMap { $0 }
        return String((0..<length).map { _ in pool.randomElement(using: &rng)! })
    }

    /// `count` groups. Consecutive duplicates are avoided where the pool allows it.
    public func generate<R: RandomNumberGenerator>(_ count: Int, using rng: inout R) -> [String] {
        guard canGenerate else { return [] }
        var out: [String] = []
        let variety = pools.reduce(0) { $0 + $1.count }
        while out.count < count {
            var group = next(using: &rng)
            var tries = 0
            while variety > 1, group == out.last, tries < 10 {
                group = next(using: &rng)
                tries += 1
            }
            out.append(group)
        }
        return out
    }
}

/// Common CW abbreviations, Q codes and signal reports.
public enum HamCodes {
    public static let all: [String] = [
        "CQ", "DE", "K", "KN", "R", "RR", "TU", "TNX", "TKS", "73", "88", "599", "5NN", "579", "559", "RST",
        "QRL", "QRM", "QRN", "QRO", "QRP", "QRQ", "QRS", "QRT", "QRU", "QRV", "QRX", "QRZ", "QSB", "QSK",
        "QSL", "QSO", "QSY", "QTH", "QTR", "QRG", "QRK",
        "ABT", "AGN", "ANT", "B4", "BK", "BURO", "CFM", "CL", "CUL", "CUAGN", "DR", "DX", "ES", "FB", "FER",
        "GA", "GE", "GM", "GN", "GL", "GD", "HI", "HR", "HW", "HPE", "INFO", "MNI", "NAME", "NIL", "NR", "NW",
        "OM", "OP", "PSE", "PWR", "RIG", "RPT", "SIG", "SRI", "TEST", "UR", "VY", "WKD", "WX", "XYL", "YL",
        "TEMP", "BCNU", "OK", "ENUF", "FREQ", "LID", "SKED", "TX", "RX", "WPM", "HVY", "GUD", "OB",
    ]
}
