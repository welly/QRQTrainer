import Foundation

public struct TrainingConfig: Codable, Equatable, Sendable {
    /// Number of callsigns in one attempt.
    public var count: Int
    public var startCPM: Double
    /// Speed change after each callsign, in percent of the current speed.
    public var stepPercent: Double
    public var minCPM: Double
    public var maxCPM: Double

    public init(count: Int = 50, startCPM: Double = 100, stepPercent: Double = 4, minCPM: Double = 25, maxCPM: Double = 999) {
        self.count = count
        self.startCPM = startCPM
        self.stepPercent = stepPercent
        self.minCPM = minCPM
        self.maxCPM = maxCPM
    }
}

public struct CallResult: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let sent: String
    public let received: String
    public let cpm: Double
    public let points: Int
    public let repeated: Bool
    /// Milliseconds from the start of the first tone to pressing Return. Nil in attempts recorded before it was measured.
    public var responseMs: Int?
    /// Milliseconds from the start of the first tone to the end of the last one.
    public var soundMs: Int?
    /// Milliseconds from the start of the first tone to the first key typed. Nil in older attempts.
    public var firstKeyMs: Int?

    public init(index: Int, sent: String, received: String, cpm: Double, points: Int, repeated: Bool,
                responseMs: Int? = nil, soundMs: Int? = nil, firstKeyMs: Int? = nil) {
        self.index = index
        self.sent = sent
        self.received = received
        self.cpm = cpm
        self.points = points
        self.repeated = repeated
        self.responseMs = responseMs
        self.soundMs = soundMs
        self.firstKeyMs = firstKeyMs
    }

    /// What a perfect, instant copy would have earned.
    public var maxPoints: Int { repeated ? 0 : Scoring.maxPoints(sent: sent, cpm: cpm) }
    public var isCorrect: Bool { sent == received }
    public var errors: Int { Scoring.editDistance(sent, received) }
}

/// The rules of one attempt: callsigns are sent one at a time at the current speed; a correct copy
/// raises the speed, a wrong copy lowers it. Pure state, no audio or timing — the UI drives it.
public struct TrainingSession: Sendable {
    public let config: TrainingConfig
    public private(set) var callsigns: [String]
    /// When true, a missed item is sent again a few items later (at most twice), in place of a new one.
    public let bringBackMisses: Bool
    /// Indices that hold a brought-back item, so they aren't replaced again.
    private var broughtBack: Set<Int> = []
    private var returns: [String: Int] = [:]
    public private(set) var index = 0
    public private(set) var currentCPM: Double
    public private(set) var results: [CallResult] = []
    public private(set) var currentWasRepeated = false

    /// How many items later a missed item comes back.
    public static let bringBackGap = 3

    public init(config: TrainingConfig, callsigns: [String], bringBackMisses: Bool = false) {
        self.config = config
        self.callsigns = callsigns
        self.bringBackMisses = bringBackMisses
        self.currentCPM = min(max(config.startCPM, config.minCPM), config.maxCPM)
    }

    public var currentCallsign: String? { index < callsigns.count ? callsigns[index] : nil }
    public var isFinished: Bool { index >= callsigns.count }
    public var score: Int { results.reduce(0) { $0 + $1.points } }
    public var correctCount: Int { results.filter(\.isCorrect).count }
    public var progress: Double { callsigns.isEmpty ? 1 : Double(index) / Double(callsigns.count) }

    /// The current callsign will be (or was) played again; it no longer earns points.
    public mutating func markRepeated() {
        guard !isFinished else { return }
        currentWasRepeated = true
    }

    /// Scores the answer to the current item. `responseTime` is the seconds from the start of the first tone to Return,
    /// and `soundDuration` how long the item sounded. Only the time after the sound counts against the score, so long
    /// or slow items aren't penalised for their length. A nil `responseTime` leaves time out of the score.
    @discardableResult
    /// `firstKeyTime` is the seconds from the start of the first tone to the first key typed, for instant recognition.
    public mutating func submit(_ answer: String, responseTime: Double? = nil, soundDuration: Double = 0,
                                firstKeyTime: Double? = nil) -> CallResult? {
        let responseTime = responseTime.map { max(0, $0) }
        guard let sent = currentCallsign else { return nil }
        let received = answer.trimmingCharacters(in: .whitespaces).uppercased()
        let result = CallResult(
            index: index,
            sent: sent,
            received: received,
            cpm: currentCPM,
            points: Scoring.points(sent: sent, received: received, cpm: currentCPM, repeated: currentWasRepeated,
                                   responseTime: responseTime.map { max(0, $0 - soundDuration) }),
            repeated: currentWasRepeated,
            responseMs: responseTime.map { Int(($0 * 1000).rounded()) },
            soundMs: responseTime == nil ? nil : Int((soundDuration * 1000).rounded()),
            firstKeyMs: firstKeyTime.map { Int((max(0, $0) * 1000).rounded()) }
        )
        results.append(result)

        if bringBackMisses, !result.isCorrect, returns[sent, default: 0] < 2 {
            var target = index + Self.bringBackGap
            while broughtBack.contains(target) { target += 1 }
            if target < callsigns.count {
                callsigns[target] = sent
                broughtBack.insert(target)
                returns[sent, default: 0] += 1
            }
        }

        let step = config.stepPercent / 100
        if !result.isCorrect {
            currentCPM = max(config.minCPM, currentCPM * (1 - step))
        } else if !currentWasRepeated {
            currentCPM = min(config.maxCPM, currentCPM * (1 + step))
        }
        index += 1
        currentWasRepeated = false
        return result
    }
}

/// A finished attempt, as stored in the history.
public struct AttemptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    /// Where the callsigns came from ("Generated" or the imported file name). Scores are only comparable within a source.
    public let source: String
    public let config: TrainingConfig
    public let results: [CallResult]

    public init(id: UUID = UUID(), date: Date = Date(), source: String, config: TrainingConfig, results: [CallResult]) {
        self.id = id
        self.date = date
        self.source = source
        self.config = config
        self.results = results
    }

    public init(session: TrainingSession, source: String, date: Date = Date()) {
        self.init(date: date, source: source, config: session.config, results: session.results)
    }

    public var score: Int { results.reduce(0) { $0 + $1.points } }
    public var correctCount: Int { results.filter(\.isCorrect).count }
    /// Highest speed at which a callsign was copied correctly.
    public var peakCPM: Double { results.filter(\.isCorrect).map(\.cpm).max() ?? 0 }
    public var averageCPM: Double { results.isEmpty ? 0 : results.map(\.cpm).reduce(0, +) / Double(results.count) }
    public var accuracy: Double { results.isEmpty ? 0 : Double(correctCount) / Double(results.count) }
    /// Mean response time in milliseconds, or nil if it wasn't measured.
    public var averageResponseMs: Int? {
        let times = results.compactMap(\.responseMs)
        return times.isEmpty ? nil : times.reduce(0, +) / times.count
    }
}
