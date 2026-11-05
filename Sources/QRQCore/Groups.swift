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

/// Common English words, plus a few radio ones, for plain-language practice.
public enum Words {
    /// Every word, most common first: the 100 most common English words, then the next 100, then the rest.
    public static let ranked: [String] = [
        "THE", "OF", "AND", "A", "TO", "IN", "IS", "YOU", "THAT", "IT", "HE", "WAS", "FOR", "ON", "ARE", "AS", "WITH",
        "HIS", "THEY", "I", "AT", "BE", "THIS", "HAVE", "FROM", "OR", "ONE", "HAD", "BY", "WORD", "BUT", "NOT",
        "WHAT", "ALL", "WERE", "WE", "WHEN", "YOUR", "CAN", "SAID", "THERE", "USE", "AN", "EACH", "WHICH", "SHE",
        "DO", "HOW", "THEIR", "IF", "WILL", "UP", "OTHER", "ABOUT", "OUT", "MANY", "THEN", "THEM", "THESE", "SO",
        "SOME", "HER", "WOULD", "MAKE", "LIKE", "HIM", "INTO", "TIME", "HAS", "LOOK", "TWO", "MORE", "WRITE", "GO",
        "SEE", "NUMBER", "NO", "WAY", "COULD", "PEOPLE", "MY", "THAN", "FIRST", "WATER", "BEEN", "CALL", "WHO", "OIL",
        "ITS", "NOW", "FIND", "LONG", "DOWN", "DAY", "DID", "GET", "COME", "MADE", "MAY", "PART", "OVER", "NEW",
        "SOUND", "TAKE", "ONLY", "LITTLE", "WORK", "KNOW", "PLACE", "YEAR", "LIVE", "ME", "BACK", "GIVE", "MOST",
        "VERY", "AFTER", "THING", "OUR", "JUST", "NAME", "GOOD", "SENTENCE", "MAN", "THINK", "SAY", "GREAT", "WHERE",
        "HELP", "THROUGH", "MUCH", "BEFORE", "LINE", "RIGHT", "TOO", "MEAN", "OLD", "ANY", "SAME", "TELL", "BOY",
        "FOLLOW", "CAME", "WANT", "SHOW", "ALSO", "AROUND", "FORM", "THREE", "SMALL", "SET", "PUT", "END", "DOES",
        "ANOTHER", "WELL", "LARGE", "MUST", "BIG", "EVEN", "SUCH", "BECAUSE", "TURN", "HERE", "WHY", "ASK", "WENT",
        "MEN", "READ", "NEED", "LAND", "DIFFERENT", "HOME", "US", "MOVE", "TRY", "KIND", "HAND", "PICTURE", "AGAIN",
        "CHANGE", "OFF", "PLAY", "SPELL", "AIR", "AWAY", "ANIMAL", "HOUSE", "POINT", "PAGE", "LETTER", "MOTHER",
        "ANSWER", "FOUND", "STUDY", "STILL", "LEARN", "SHOULD", "WORLD", "HIGH", "BOX", "DOG", "FOX", "LET", "WAX",
        "BAND", "BEST", "BOOK", "BOTH", "CASE", "CITY", "CODE", "COPY", "DOOR", "FACE", "FACT", "FEEL", "FOUR",
        "FREE", "FULL", "HALF", "HEAD", "HOPE", "IDEA", "JAZZ", "KEEP", "LAST", "LATE", "LAZY", "LEFT", "LIFE",
        "LOVE", "MIND", "NEAR", "NEXT", "ONCE", "OPEN", "PLAN", "QUIZ", "REAL", "REST", "ROAD", "ROOM", "SEEM",
        "SIDE", "SURE", "TALK", "TOLD", "TREE", "TRUE", "UPON", "USED", "WAIT", "WALK", "WARM", "WEEK", "WIND",
        "WISH", "ZERO", "ZONE", "BEING", "BELOW", "BROWN", "CHECK", "CLEAR", "EARLY", "EVERY", "EXTRA", "GROUP",
        "JUDGE", "JUMPS", "KNIFE", "LATER", "LIGHT", "MIGHT", "MONEY", "MORSE", "NEVER", "NIGHT", "NOISE", "OFTEN",
        "ORDER", "PAPER", "POWER", "QUICK", "QUITE", "RADIO", "SHALL", "SINCE", "SPEAK", "SPEED", "STAND", "START",
        "STATE", "STORY", "THOSE", "TODAY", "UNDER", "UNTIL", "VOICE", "WHILE", "WHITE", "WHOLE", "YOUNG", "ALWAYS",
        "BETTER", "FAMILY", "FRIEND", "GROUND", "LISTEN", "MOMENT", "OXYGEN", "PERSON", "SCHOOL", "SIGNAL", "SIMPLE",
        "SUMMER", "SYSTEM", "THOUGH", "TOWARD", "TRAVEL", "VALLEY", "WINTER", "YELLOW", "ALREADY", "AMATEUR",
        "ANTENNA", "BELIEVE", "BETWEEN", "BROUGHT", "CERTAIN", "COMPANY", "CONTEST", "COUNTRY", "EVENING", "EXAMPLE",
        "FREEDOM", "GENERAL", "HISTORY", "HOWEVER", "HUNDRED", "JOURNEY", "KITCHEN", "MACHINE", "MESSAGE", "MINUTES",
        "MORNING", "NOTHING", "OUTSIDE", "PERHAPS", "PRESENT", "PROBLEM", "PROGRAM", "RECEIVE", "SEVERAL", "SPECIAL",
        "STATION", "STRANGE", "THOUGHT", "TONIGHT", "VILLAGE", "WEATHER", "WEEKEND", "WITHOUT", "WRITING", "BIRTHDAY",
        "BUILDING", "CHILDREN", "EVERYONE", "EXERCISE", "HOSPITAL", "LANGUAGE", "MOUNTAIN", "OPERATOR", "PRACTICE",
        "QUESTION", "REMEMBER", "STRENGTH", "TOGETHER", "TRAINING", "UMBRELLA", "YOURSELF", "BEAUTIFUL", "BEGINNING",
        "EQUIPMENT", "FREQUENCY", "IMPORTANT", "KNOWLEDGE", "SOMETHING", "TELEPHONE", "WONDERFUL", "YESTERDAY",
        "ACCEPTABLE", "BACKGROUND", "CONDITIONS", "CONNECTION", "DIFFERENCE", "DIRECTIONS", "EVERYTHING",
        "EXPERIENCE", "GOVERNMENT", "IMPORTANCE", "POPULATION", "REMARKABLE", "THEMSELVES", "UNDERSTAND",
        "COMPETITION", "DEFINITIONS", "ELECTRICITY", "ENVIRONMENT", "EXPERIMENTS", "IMMEDIATELY", "INDEPENDENT",
        "INFORMATION", "INSTRUMENTS", "OPPORTUNITY", "TEMPERATURE", "TRANSMITTER", "ACKNOWLEDGED", "APPRECIATION",
        "ARCHITECTURE", "ASSOCIATIONS", "CONVERSATION", "DISTRIBUTION", "ENTERTAINING", "INSTRUCTIONS",
        "INTRODUCTION", "OBSERVATIONS", "PARTICULARLY", "PROFESSIONAL", "RELATIONSHIP",
    ]

    /// Every word, shortest first.
    public static let common: [String] = ranked.sorted { ($0.count, $0) < ($1.count, $1) }

    /// Word lengths that can be chosen: A and I up to 12-letter words.
    public static let lengths: ClosedRange<Int> = 1...12

    /// The words in `set` whose length is within `minLength...maxLength`, most common first.
    public static func list(_ set: WordSet = .all, minLength: Int, maxLength: Int) -> [String] {
        let range = max(1, min(minLength, maxLength))...max(minLength, maxLength)
        return set.words.filter { range.contains($0.count) }
    }

    /// Words whose most recent copy in `results` (oldest first) was wrong, most recently missed first.
    public static func missed<S: Sequence>(in results: S) -> [String] where S.Element == CallResult {
        var last: [String: (index: Int, correct: Bool)] = [:]
        for (i, r) in results.enumerated() where !r.repeated || !r.isCorrect {
            last[r.sent] = (i, r.isCorrect)
        }
        return last.filter { !$0.value.correct }.sorted { $0.value.index > $1.value.index }.map(\.key)
    }
}

/// How many of the most common words Words mode draws from. A smaller set means hearing each word more often.
public enum WordSet: String, CaseIterable, Codable, Sendable, Identifiable {
    case top100, top200, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .top100: "Top 100"
        case .top200: "Top 200"
        case .all: "All"
        }
    }

    public var words: [String] {
        switch self {
        case .top100: Array(Words.ranked.prefix(100))
        case .top200: Array(Words.ranked.prefix(200))
        case .all: Words.ranked
        }
    }
}
