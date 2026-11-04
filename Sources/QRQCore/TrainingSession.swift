import Foundation

public struct TrainingConfig: Codable, Equatable, Sendable {
    /// Number of callsigns in one attempt.
    public var count: Int
    public var startCPM: Double
    /// Speed change after each callsign, in percent of the current speed.
    public var stepPercent: Double
    public var minCPM: Double
    public var maxCPM: Double
    /// Slow answers lose points (see `Scoring.timeFactor`).
    public var responseTimePenalty: Bool
    public var content: TrainingContent
    /// Length of random groups (not used for callsigns).
    public var groupLength: Int
    /// Farnsworth spacing: overall speed as a percentage of character speed. 100 = standard spacing.
    public var farnsworthPercent: Double

    public init(count: Int = 50, startCPM: Double = 100, stepPercent: Double = 4, minCPM: Double = 25, maxCPM: Double = 999,
                responseTimePenalty: Bool = true, content: TrainingContent = .callsigns, groupLength: Int = 5,
                farnsworthPercent: Double = 100) {
        self.content = content
        self.groupLength = groupLength
        self.farnsworthPercent = farnsworthPercent
        self.count = count
        self.startCPM = startCPM
        self.stepPercent = stepPercent
        self.minCPM = minCPM
        self.maxCPM = maxCPM
        self.responseTimePenalty = responseTimePenalty
    }

    // Custom decoding so history saved before a field existed still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decode(Int.self, forKey: .count)
        startCPM = try c.decode(Double.self, forKey: .startCPM)
        stepPercent = try c.decode(Double.self, forKey: .stepPercent)
        minCPM = try c.decode(Double.self, forKey: .minCPM)
        maxCPM = try c.decode(Double.self, forKey: .maxCPM)
        responseTimePenalty = try c.decodeIfPresent(Bool.self, forKey: .responseTimePenalty) ?? false
        content = try c.decodeIfPresent(TrainingContent.self, forKey: .content) ?? .callsigns
        groupLength = try c.decodeIfPresent(Int.self, forKey: .groupLength) ?? 5
        farnsworthPercent = try c.decodeIfPresent(Double.self, forKey: .farnsworthPercent) ?? 100
    }

    /// Effective (overall) speed for Farnsworth spacing at character speed `cpm`, or nil for standard spacing.
    public func effectiveCPM(at cpm: Double) -> Double? {
        farnsworthPercent < 100 ? cpm * max(farnsworthPercent, 10) / 100 : nil
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
    /// Seconds from the end of the callsign to Return (0 if answered while it was still playing). Nil in old records.
    public let responseTime: Double?

    public init(index: Int, sent: String, received: String, cpm: Double, points: Int, repeated: Bool, responseTime: Double? = nil) {
        self.index = index
        self.sent = sent
        self.received = received
        self.cpm = cpm
        self.points = points
        self.repeated = repeated
        self.responseTime = responseTime
    }

    /// What this callsign was worth at the speed it was sent.
    public var maxPoints: Int { Scoring.maxPoints(sent: sent, cpm: cpm) }
    public var isCorrect: Bool { sent == received }
    public var errors: Int { Scoring.editDistance(sent, received) }
}

/// The rules of one attempt: callsigns are sent one at a time at the current speed; a correct copy
/// raises the speed, a wrong copy lowers it. Pure state, no audio or timing — the UI drives it.
public struct TrainingSession: Sendable {
    public let config: TrainingConfig
    public let callsigns: [String]
    public private(set) var index = 0
    public private(set) var currentCPM: Double
    public private(set) var results: [CallResult] = []
    public private(set) var currentWasRepeated = false

    public init(config: TrainingConfig, callsigns: [String]) {
        self.config = config
        self.callsigns = callsigns
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

    @discardableResult
    public mutating func submit(_ answer: String, responseTime: Double? = nil) -> CallResult? {
        guard let sent = currentCallsign else { return nil }
        let received = answer.trimmingCharacters(in: .whitespaces).uppercased()
        let result = CallResult(
            index: index,
            sent: sent,
            received: received,
            cpm: currentCPM,
            points: Scoring.points(sent: sent, received: received, cpm: currentCPM, repeated: currentWasRepeated,
                                   responseTime: config.responseTimePenalty ? responseTime : nil),
            repeated: currentWasRepeated,
            responseTime: responseTime
        )
        results.append(result)

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
    public var maxScore: Int { results.reduce(0) { $0 + $1.maxPoints } }
    public var correctCount: Int { results.filter(\.isCorrect).count }
    public var averageResponseTime: Double? {
        let times = results.compactMap(\.responseTime)
        return times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
    }
    /// Highest speed at which a callsign was copied correctly.
    public var peakCPM: Double { results.filter(\.isCorrect).map(\.cpm).max() ?? 0 }
    public var averageCPM: Double { results.isEmpty ? 0 : results.map(\.cpm).reduce(0, +) / Double(results.count) }
    public var accuracy: Double { results.isEmpty ? 0 : Double(correctCount) / Double(results.count) }
}
