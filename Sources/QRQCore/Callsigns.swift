import Foundation

/// Deterministic RNG (SplitMix64) so tests and "replay this attempt" are reproducible.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Parses and validates callsign lists such as Super Check Partial `MASTER.SCP`
/// (one call per line, `#` comments) or any whitespace/comma separated text.
public enum CallsignList {
    public static func isValid(_ call: String) -> Bool {
        guard (3...15).contains(call.count) else { return false }
        var hasLetter = false, hasDigit = false
        for ch in call {
            if ch.isASCII && ch.isLetter && ch.isUppercase { hasLetter = true }
            else if ch.isASCII && ch.isNumber { hasDigit = true }
            else if ch != "/" { return false }
        }
        return hasLetter && hasDigit && call.first != "/" && call.last != "/"
    }

    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") || line.hasPrefix(";") { continue }
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," || $0 == ";" }) {
                let call = token.uppercased()
                if isValid(call), seen.insert(call).inserted { out.append(call) }
            }
        }
        return out
    }

    /// Picks `count` calls in random order without repeats (cycles only if the list is too short).
    public static func pick<R: RandomNumberGenerator>(_ count: Int, from list: [String], using rng: inout R) -> [String] {
        guard !list.isEmpty, count > 0 else { return [] }
        var out: [String] = []
        while out.count < count {
            out.append(contentsOf: list.shuffled(using: &rng).prefix(count - out.count))
        }
        return out
    }
}

/// Generates realistic-looking amateur radio callsigns from common ITU prefixes,
/// weighted roughly by CW activity. Used when no callsign file has been imported.
public struct CallsignGenerator: Sendable {
    struct Rule: Sendable {
        let prefixes: [String]
        /// Digits that may follow the prefix. Empty when the prefix already ends in its digit (e.g. HB9).
        let digits: String
        let suffixLengths: [Int]
        let weight: Int
    }

    /// Probability (0...1) of producing a portable/mobile call such as `DL1ABC/P`.
    public var portableProbability: Double
    /// Probability (0...1) of producing a call with a foreign prefix such as `EA8/DL1ABC`.
    public var prefixedProbability: Double

    public init(portableProbability: Double = 0, prefixedProbability: Double = 0) {
        self.portableProbability = portableProbability
        self.prefixedProbability = prefixedProbability
    }

    static let rules: [Rule] = [
        // North America
        Rule(prefixes: ["K", "W", "N"], digits: "0123456789", suffixLengths: [2, 3, 3], weight: 14),
        Rule(prefixes: ["KA", "KB", "KC", "KD", "KE", "KF", "KG", "KI", "KJ", "KK", "KM", "KN", "KO", "KS",
                        "KU", "KV", "KW", "KX", "KY", "KZ", "WA", "WB", "WD", "WX", "NA", "NB", "ND", "NX",
                        "AA", "AB", "AC", "AD", "AE", "AF", "AG", "AI", "AJ", "AK"],
             digits: "0123456789", suffixLengths: [1, 2, 3], weight: 12),
        Rule(prefixes: ["VE", "VA"], digits: "1234567", suffixLengths: [2, 3], weight: 4),
        Rule(prefixes: ["KH6", "KL7", "KP4", "NH6", "NL7", "WP4"], digits: "", suffixLengths: [2, 3], weight: 1),
        // Europe
        Rule(prefixes: ["DL", "DJ", "DK", "DF", "DG", "DH", "DM", "DO", "DB", "DC", "DD"],
             digits: "0123456789", suffixLengths: [2, 3, 3], weight: 10),
        Rule(prefixes: ["G", "M"], digits: "0013456", suffixLengths: [3], weight: 5),
        Rule(prefixes: ["2E"], digits: "01", suffixLengths: [3], weight: 1),
        Rule(prefixes: ["GM", "GW", "GI", "MM", "MW", "GD", "GJ"], digits: "034", suffixLengths: [3], weight: 2),
        Rule(prefixes: ["F"], digits: "1245689", suffixLengths: [2, 3], weight: 4),
        Rule(prefixes: ["I", "IK", "IZ", "IW", "IU"], digits: "0123456789", suffixLengths: [2, 3], weight: 5),
        Rule(prefixes: ["EA", "EB", "EC"], digits: "123456789", suffixLengths: [2, 3], weight: 4),
        Rule(prefixes: ["OH", "OG"], digits: "0123456789", suffixLengths: [2, 3], weight: 3),
        Rule(prefixes: ["SM", "SA", "SK"], digits: "01234567", suffixLengths: [2, 3], weight: 3),
        Rule(prefixes: ["LA", "LB"], digits: "123456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["OZ", "OU"], digits: "0123456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["PA", "PD", "PE", "PH"], digits: "0123456789", suffixLengths: [2, 3], weight: 3),
        Rule(prefixes: ["ON", "OO", "OT"], digits: "123456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["OK", "OL"], digits: "12", suffixLengths: [2, 3], weight: 3),
        Rule(prefixes: ["OM"], digits: "0123578", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["SP", "SQ", "SO", "SN"], digits: "123456789", suffixLengths: [2, 3], weight: 4),
        Rule(prefixes: ["HA", "HG"], digits: "12345678", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["YO"], digits: "23456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["LZ"], digits: "123", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["S5"], digits: "0123456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["9A"], digits: "1234567", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["YU", "YT"], digits: "1234567", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["E7"], digits: "1234567", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["OE"], digits: "123456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["HB9"], digits: "", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["ES"], digits: "12345678", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["YL"], digits: "23", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["LY"], digits: "12345", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["EI"], digits: "23456789", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["CT"], digits: "1234567", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["SV"], digits: "123456789", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["UA", "RA", "RN", "RW", "RU", "RK", "RZ", "R"], digits: "0123456789", suffixLengths: [2, 3], weight: 8),
        Rule(prefixes: ["UR", "UT", "UX", "US"], digits: "012345678", suffixLengths: [2, 3], weight: 3),
        Rule(prefixes: ["EU", "EW"], digits: "1234678", suffixLengths: [2, 3], weight: 1),
        // Asia / Pacific
        Rule(prefixes: ["JA", "JH", "JR", "JE", "JF", "JG", "JI", "JJ", "JK", "JL", "JM", "JN", "JO", "JP", "JQ"],
             digits: "0123456789", suffixLengths: [3], weight: 7),
        Rule(prefixes: ["7K", "7L", "7M", "7N"], digits: "1234", suffixLengths: [3], weight: 1),
        Rule(prefixes: ["HL", "DS"], digits: "123456789", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["BY", "BA", "BG", "BH", "BD"], digits: "123456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["VU"], digits: "23", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["4X", "4Z"], digits: "123456", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["A6", "A7", "A9", "9K", "HZ"], digits: "0123456789", suffixLengths: [1, 2, 3], weight: 1),
        Rule(prefixes: ["HS", "E2"], digits: "0", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["9M2", "9M6", "9V1"], digits: "", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["YB", "YC", "YD"], digits: "0123456789", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["VK"], digits: "12345678", suffixLengths: [2, 3], weight: 3),
        Rule(prefixes: ["ZL"], digits: "1234", suffixLengths: [2, 3], weight: 1),
        // South America / Africa
        Rule(prefixes: ["PY", "PU", "PP", "PR"], digits: "12345678", suffixLengths: [2, 3], weight: 3),
        Rule(prefixes: ["LU", "LW"], digits: "123456789", suffixLengths: [2, 3], weight: 2),
        Rule(prefixes: ["CE", "CA", "XQ"], digits: "1234567", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["CX", "OA", "HK", "YV", "XE", "TI", "HC", "HP"], digits: "123456789", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["ZS", "ZR"], digits: "123456", suffixLengths: [2, 3], weight: 1),
        Rule(prefixes: ["EA8", "EA9", "CT3", "CN8", "5B4", "SU1", "5Z4", "9J2", "V51"], digits: "", suffixLengths: [2, 3], weight: 1),
    ]

    static let foreignPrefixes = ["EA8", "EA6", "OH0", "CT3", "IS0", "TK", "SV9", "OJ0", "VP9", "KH6", "VE8", "HB0", "F"]
    static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let totalWeight = rules.reduce(0) { $0 + $1.weight }

    public func next<R: RandomNumberGenerator>(using rng: inout R) -> String {
        var pick = Int.random(in: 0..<Self.totalWeight, using: &rng)
        var rule = Self.rules[0]
        for r in Self.rules {
            if pick < r.weight { rule = r; break }
            pick -= r.weight
        }

        var call = rule.prefixes.randomElement(using: &rng)!
        if let digit = rule.digits.randomElement(using: &rng) { call.append(digit) }
        let length = rule.suffixLengths.randomElement(using: &rng)!
        for i in 0..<length {
            var letter = Self.letters.randomElement(using: &rng)!
            // Suffixes starting with Q are rare (Q codes); avoid them like real allocations do.
            while i == 0 && letter == "Q" { letter = Self.letters.randomElement(using: &rng)! }
            call.append(letter)
        }

        if prefixedProbability > 0, Double.random(in: 0..<1, using: &rng) < prefixedProbability {
            call = Self.foreignPrefixes.randomElement(using: &rng)! + "/" + call
        } else if portableProbability > 0, Double.random(in: 0..<1, using: &rng) < portableProbability {
            call += ["/P", "/M", "/P", "/1", "/2", "/3", "/5", "/7", "/9"].randomElement(using: &rng)!
        }
        return call
    }

    /// `count` distinct generated callsigns.
    public func generate<R: RandomNumberGenerator>(_ count: Int, using rng: inout R) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        var attempts = 0
        while out.count < count && attempts < count * 100 {
            attempts += 1
            let call = next(using: &rng)
            if seen.insert(call).inserted { out.append(call) }
        }
        return out
    }
}
