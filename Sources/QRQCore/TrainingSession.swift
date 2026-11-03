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
    public mutating func submit(_ answer: String) -> CallResult? {
        guard let sent = currentCallsign else { return nil }
        let received = answer.trimmingCharacters(in: .whitespaces).uppercased()
        let result = CallResult(
            index: index,
            sent: sent,
            received: received,
            cpm: currentCPM,
            points: Scoring.points(sent: sent, received: received, cpm: currentCPM, repeated: currentWasRepeated),
            repeated: currentWasRepeated
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
    public var correctCount: Int { results.filter(\.isCorrect).count }
    /// Highest speed at which a callsign was copied correctly.
    public var peakCPM: Double { results.filter(\.isCorrect).map(\.cpm).max() ?? 0 }
    public var averageCPM: Double { results.isEmpty ? 0 : results.map(\.cpm).reduce(0, +) / Double(results.count) }
    public var accuracy: Double { results.isEmpty ? 0 : Double(correctCount) / Double(results.count) }
}
