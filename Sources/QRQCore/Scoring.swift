import Foundation

/// One position in the alignment between what was sent and what was typed.
public enum AlignedChar: Equatable, Sendable {
    case match(Character)
    case substitution(sent: Character, received: Character)
    /// Sent but not typed.
    case missing(Character)
    /// Typed but not sent.
    case extra(Character)
}

public enum Scoring {
    /// Levenshtein distance between two strings.
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Character alignment of `received` against `sent` (minimal edits), for highlighting mistakes.
    public static func align(sent: String, received: String) -> [AlignedChar] {
        let a = Array(sent), b = Array(received)
        let n = a.count, m = b.count
        var d = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let cost = a[i - 1] == b[j - 1] ? 0 : 1
                    d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                }
            }
        }
        var out: [AlignedChar] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1) {
                out.append(a[i - 1] == b[j - 1] ? .match(a[i - 1]) : .substitution(sent: a[i - 1], received: b[j - 1]))
                i -= 1; j -= 1
            } else if i > 0, d[i][j] == d[i - 1][j] + 1 {
                out.append(.missing(a[i - 1]))
                i -= 1
            } else {
                out.append(.extra(b[j - 1]))
                j -= 1
            }
        }
        return out.reversed()
    }

    /// The most a callsign can score at a given speed: its Morse length in dit units × CPM ÷ 100.
    /// Long, dense callsigns copied fast are worth the most.
    public static func maxPoints(sent: String, cpm: Double) -> Int {
        Int((Double(Morse.units(of: sent)) * cpm / 100).rounded())
    }

    /// Seconds after the callsign ends before slow answers start losing points: 1 s plus 0.25 s per character.
    public static func graceSeconds(for sent: String) -> Double {
        1.0 + 0.25 * Double(sent.count)
    }

    /// Multiplier for answer speed: 1 within the grace period, then 5% less per extra second, never below 50%.
    public static func timeFactor(responseTime: Double?, sent: String) -> Double {
        guard let t = responseTime else { return 1 }
        let late = max(0, t - graceSeconds(for: sent))
        return max(0.5, 1 - 0.05 * late)
    }

    /// Points for one callsign.
    ///
    /// `maxPoints` × accuracy × answer speed. Each wrong character costs 2/length of the points; a repeated
    /// callsign scores nothing. `responseTime` (seconds from the end of the callsign to Return) is optional;
    /// when nil there is no time penalty.
    public static func points(sent: String, received: String, cpm: Double, repeated: Bool, responseTime: Double? = nil) -> Int {
        guard !repeated else { return 0 }
        let errors = editDistance(sent, received)
        let accuracy = max(0, 1 - 2 * Double(errors) / Double(max(sent.count, 1)))
        let base = Double(Morse.units(of: sent)) * cpm / 100
        return Int((base * accuracy * timeFactor(responseTime: responseTime, sent: sent)).rounded())
    }
}
