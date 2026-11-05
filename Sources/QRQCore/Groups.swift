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
        case .figures: "Numbers"
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
    case words
    /// Groups of the characters Insights lists under Needs work.
    case needsWork
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
        case .words: "Words"
        case .needsWork: "Needs work"
        case .letters: "Letters"
        case .figures: "Numbers"
        case .symbols: "Symbols"
        case .lettersFigures: "Letters & numbers"
        case .lettersSymbols: "Letters & symbols"
        case .figuresSymbols: "Numbers & symbols"
        case .all: "All characters"
        }
    }

    /// Character classes used to build random groups. Empty for word-based modes.
    public var classes: [CharacterClass] {
        switch self {
        case .callsigns, .hamCodes, .words, .needsWork: []
        case .letters: [.letters]
        case .figures: [.figures]
        case .symbols: [.symbols]
        case .lettersFigures: [.letters, .figures]
        case .lettersSymbols: [.letters, .symbols]
        case .figuresSymbols: [.figures, .symbols]
        case .all: [.letters, .figures, .symbols]
        }
    }

    /// True for modes made of random character groups (as opposed to callsigns, ham codes or words).
    public var usesGroups: Bool { !classes.isEmpty }

    /// What one item of an attempt is called in the interface.
    public var itemName: String {
        switch self {
        case .callsigns: "callsign"
        case .hamCodes: "code"
        case .words: "word"
        default: "group"
        }
    }
}

/// How the characters of a group are chosen when a mode combines several classes.
public enum GroupComposition: String, CaseIterable, Codable, Sendable {
    /// Every group may contain characters from all of the mode's classes.
    case mixed
    /// Each group uses a single class (a group of letters, then a group of numbers, …).
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

/// Common English words, plus a few radio ones, for plain-language practice. Sorted by length.
public enum Words {
    public static let common: [String] = [
        "A", "I", "AN", "AS", "AT", "BE", "BY", "DO", "GO", "HE", "IF", "IN", "IS", "IT", "ME", "MY", "NO", "OF",
        "ON", "OR", "SO", "TO", "UP", "US", "WE", "ALL", "AND", "ANY", "ARE", "BOX", "BOY", "BUT", "CAN", "DAY",
        "DID", "DOG", "FOR", "FOX", "GET", "HAD", "HAS", "HER", "HIM", "HIS", "HOW", "ITS", "LET", "MAN", "NEW",
        "NOT", "NOW", "OLD", "ONE", "OUR", "OUT", "PUT", "SAY", "SEE", "SHE", "THE", "TOO", "TWO", "USE", "WAS",
        "WAX", "WAY", "WHO", "YOU", "ALSO", "AWAY", "BACK", "BAND", "BEEN", "BEST", "BOOK", "BOTH", "CALL", "CAME",
        "CASE", "CITY", "CODE", "COME", "COPY", "DOOR", "DOWN", "EACH", "EVEN", "FACE", "FACT", "FEEL", "FIND",
        "FOUR", "FREE", "FROM", "FULL", "GIVE", "GOOD", "HALF", "HAND", "HAVE", "HEAD", "HELP", "HERE", "HIGH",
        "HOME", "HOPE", "IDEA", "JAZZ", "JUST", "KEEP", "KIND", "KNOW", "LAST", "LATE", "LAZY", "LEFT", "LIFE",
        "LIKE", "LINE", "LIVE", "LONG", "LOOK", "LOVE", "MADE", "MAKE", "MANY", "MIND", "MORE", "MOST", "MOVE",
        "MUCH", "MUST", "NAME", "NEAR", "NEED", "NEXT", "ONCE", "ONLY", "OPEN", "OVER", "PART", "PLAN", "PLAY",
        "QUIZ", "READ", "REAL", "REST", "ROAD", "ROOM", "SAID", "SAME", "SEEM", "SHOW", "SIDE", "SOME", "SUCH",
        "SURE", "TAKE", "TALK", "TELL", "THAN", "THAT", "THEM", "THEY", "THIS", "TIME", "TOLD", "TREE", "TRUE",
        "TURN", "UPON", "USED", "VERY", "WAIT", "WALK", "WANT", "WARM", "WEEK", "WELL", "WENT", "WERE", "WHAT",
        "WHEN", "WILL", "WIND", "WISH", "WITH", "WORD", "WORK", "YEAR", "YOUR", "ZERO", "ZONE", "ABOUT", "AFTER",
        "AGAIN", "BEING", "BELOW", "BROWN", "CHECK", "CLEAR", "COULD", "EARLY", "EVERY", "EXTRA", "FIRST", "FOUND",
        "GREAT", "GROUP", "HOUSE", "JUDGE", "JUMPS", "KNIFE", "LARGE", "LATER", "LEARN", "LIGHT", "MIGHT", "MONEY",
        "MORSE", "NEVER", "NIGHT", "NOISE", "OFTEN", "ORDER", "OTHER", "PAPER", "PLACE", "POINT", "POWER", "QUICK",
        "QUITE", "RADIO", "RIGHT", "SHALL", "SINCE", "SMALL", "SOUND", "SPEAK", "SPEED", "STAND", "START", "STATE",
        "STILL", "STORY", "STUDY", "THEIR", "THERE", "THESE", "THING", "THINK", "THOSE", "THREE", "TODAY", "UNDER",
        "UNTIL", "VOICE", "WATER", "WHERE", "WHICH", "WHILE", "WHITE", "WHOLE", "WORLD", "WOULD", "WRITE", "YOUNG",
        "ALWAYS", "ANSWER", "AROUND", "BEFORE", "BETTER", "CHANGE", "FAMILY", "FRIEND", "GROUND", "LETTER", "LISTEN",
        "LITTLE", "MOMENT", "MOTHER", "NUMBER", "OXYGEN", "PEOPLE", "PERSON", "SCHOOL", "SHOULD", "SIGNAL", "SIMPLE",
        "SUMMER", "SYSTEM", "THOUGH", "TOWARD", "TRAVEL", "VALLEY", "WINTER", "YELLOW", "ALREADY", "AMATEUR",
        "ANOTHER", "ANTENNA", "BECAUSE", "BELIEVE", "BETWEEN", "BROUGHT", "CERTAIN", "COMPANY", "CONTEST", "COUNTRY",
        "EVENING", "EXAMPLE", "FREEDOM", "GENERAL", "HISTORY", "HOWEVER", "HUNDRED", "JOURNEY", "KITCHEN", "MACHINE",
        "MESSAGE", "MINUTES", "MORNING", "NOTHING", "OUTSIDE", "PERHAPS", "PICTURE", "PRESENT", "PROBLEM", "PROGRAM",
        "RECEIVE", "SEVERAL", "SPECIAL", "STATION", "STRANGE", "THOUGHT", "THROUGH", "TONIGHT", "VILLAGE", "WEATHER",
        "WEEKEND", "WITHOUT", "WRITING", "BIRTHDAY", "BUILDING", "CHILDREN", "EVERYONE", "EXERCISE", "HOSPITAL",
        "LANGUAGE", "MOUNTAIN", "OPERATOR", "PRACTICE", "QUESTION", "REMEMBER", "STRENGTH", "TOGETHER", "TRAINING",
        "UMBRELLA", "YOURSELF", "BEAUTIFUL", "BEGINNING", "DIFFERENT", "EQUIPMENT", "FREQUENCY", "IMPORTANT",
        "KNOWLEDGE", "SOMETHING", "TELEPHONE", "WONDERFUL", "YESTERDAY", "ACCEPTABLE", "BACKGROUND", "CONDITIONS",
        "CONNECTION", "DIFFERENCE", "DIRECTIONS", "EVERYTHING", "EXPERIENCE", "GOVERNMENT", "IMPORTANCE",
        "POPULATION", "REMARKABLE", "THEMSELVES", "UNDERSTAND", "COMPETITION", "DEFINITIONS", "ELECTRICITY",
        "ENVIRONMENT", "EXPERIMENTS", "IMMEDIATELY", "INDEPENDENT", "INFORMATION", "INSTRUMENTS", "OPPORTUNITY",
        "TEMPERATURE", "TRANSMITTER", "ACKNOWLEDGED", "APPRECIATION", "ARCHITECTURE", "ASSOCIATIONS", "CONVERSATION",
        "DISTRIBUTION", "ENTERTAINING", "INSTRUCTIONS", "INTRODUCTION", "OBSERVATIONS", "PARTICULARLY",
        "PROFESSIONAL", "RELATIONSHIP",
    ]

    /// Word lengths that can be chosen: A and I up to 12-letter words.
    public static let lengths: ClosedRange<Int> = 1...12

    /// The words whose length is within `minLength...maxLength`.
    public static func list(minLength: Int, maxLength: Int) -> [String] {
        let range = max(1, min(minLength, maxLength))...max(minLength, maxLength)
        return common.filter { range.contains($0.count) }
    }
}
