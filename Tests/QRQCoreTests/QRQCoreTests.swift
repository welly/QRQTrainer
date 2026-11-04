import XCTest
@testable import QRQCore

final class MorseTests: XCTestCase {
    func testParisIsFiftyUnits() {
        // "PARIS " including the trailing word gap is the standard 50-unit word.
        XCTAssertEqual(Morse.units(of: "PARIS") + 7, 50)
    }

    func testKeyingOfA() {
        XCTAssertEqual(Morse.keying(for: "A"), [
            KeyElement(isOn: true, units: 1), KeyElement(isOn: false, units: 1), KeyElement(isOn: true, units: 3),
        ])
    }

    func testCharacterGapAndNoTrailingSilence() {
        let k = Morse.keying(for: "EE ")
        XCTAssertEqual(k, [KeyElement(isOn: true, units: 1), KeyElement(isOn: false, units: 3), KeyElement(isOn: true, units: 1)])
    }

    func testDitLength() {
        XCTAssertEqual(Morse.ditSeconds(cpm: 60), 0.1, accuracy: 1e-9)  // 12 WPM
        XCTAssertEqual(Morse.wpm(fromCPM: 250), 50)
    }

    func testRenderLengthAndRange() {
        let tone = ToneSettings(frequency: 700, amplitude: 0.5, riseTime: 0.005, sampleRate: 8000)
        let s = MorseSynth.render(text: "DL1ABC", cpm: 300, tone: tone, leadIn: 0.05, tail: 0.05)
        let expected = MorseSynth.duration(of: "DL1ABC", cpm: 300, leadIn: 0.05, tail: 0.05) * 8000
        XCTAssertEqual(Double(s.count), expected, accuracy: 1)
        XCTAssertLessThanOrEqual(s.map { abs($0) }.max() ?? 0, 0.5 + 1e-6)
        XCTAssertEqual(s.first, 0)
        XCTAssertEqual(s.last, 0)
    }
}

final class ScoringTests: XCTestCase {
    func testEditDistance() {
        XCTAssertEqual(Scoring.editDistance("DL1ABC", "DL1ABC"), 0)
        XCTAssertEqual(Scoring.editDistance("DL1ABC", "DL1AB"), 1)
        XCTAssertEqual(Scoring.editDistance("DL1ABC", "DK1ABC"), 1)
        XCTAssertEqual(Scoring.editDistance("", "ABC"), 3)
    }

    func testAlignment() {
        XCTAssertEqual(Scoring.align(sent: "K1AB", received: "K1XAB"),
                       [.match("K"), .match("1"), .extra("X"), .match("A"), .match("B")])
        XCTAssertEqual(Scoring.align(sent: "K1AB", received: "K1B"),
                       [.match("K"), .match("1"), .missing("A"), .match("B")])
    }

    func testPoints() {
        let full = Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 200, repeated: false)
        let oneOff = Scoring.points(sent: "DL1ABC", received: "DL1ABX", cpm: 200, repeated: false)
        XCTAssertGreaterThan(full, oneOff)
        XCTAssertGreaterThan(oneOff, 0)
        XCTAssertEqual(Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 200, repeated: true), 0)
        XCTAssertGreaterThan(Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 400, repeated: false), full)
    }

    func testMaxPointsForR() {
        // R = .-. = 7 units; 25 WPM = 125 CPM → 7 × 125 / 100 = 8.75 → 9
        XCTAssertEqual(Scoring.maxPoints(sent: "R", cpm: 125), 9)
    }

    func testResponseTimePenalty() {
        let call = "DL1ABC"  // grace = 1 + 0.25 × 6 = 2.5 s
        XCTAssertEqual(Scoring.timeFactor(responseTime: nil, sent: call), 1)
        XCTAssertEqual(Scoring.timeFactor(responseTime: 2.5, sent: call), 1)
        XCTAssertEqual(Scoring.timeFactor(responseTime: 4.5, sent: call), 0.9, accuracy: 1e-9)
        XCTAssertEqual(Scoring.timeFactor(responseTime: 60, sent: call), 0.5)
        let fast = Scoring.points(sent: call, received: call, cpm: 200, repeated: false, responseTime: 0)
        let slow = Scoring.points(sent: call, received: call, cpm: 200, repeated: false, responseTime: 8)
        XCTAssertEqual(fast, Scoring.maxPoints(sent: call, cpm: 200))
        XCTAssertLessThan(slow, fast)
    }
}

final class SessionTests: XCTestCase {
    func testSpeedAdaptsAndFinishes() {
        var s = TrainingSession(config: TrainingConfig(count: 3, startCPM: 100, stepPercent: 10), callsigns: ["K1AB", "G4XYZ", "JA1ABC"])
        s.submit("K1AB")
        XCTAssertEqual(s.currentCPM, 110, accuracy: 1e-9)
        s.submit("G4XYC")
        XCTAssertEqual(s.currentCPM, 99, accuracy: 1e-9)
        s.markRepeated()
        let r = s.submit("ja1abc")
        XCTAssertEqual(r?.isCorrect, true)
        XCTAssertEqual(r?.points, 0)
        XCTAssertEqual(s.currentCPM, 99, accuracy: 1e-9)  // repeated & correct: unchanged
        XCTAssertTrue(s.isFinished)
        XCTAssertNil(s.submit("X"))
        XCTAssertEqual(AttemptRecord(session: s, source: "t").peakCPM, 100)
    }

    func testPenaltyCanBeDisabled() {
        var on = TrainingSession(config: TrainingConfig(count: 1, responseTimePenalty: true), callsigns: ["DL1ABC"])
        var off = TrainingSession(config: TrainingConfig(count: 1, responseTimePenalty: false), callsigns: ["DL1ABC"])
        let a = on.submit("DL1ABC", responseTime: 10)!
        let b = off.submit("DL1ABC", responseTime: 10)!
        XCTAssertLessThan(a.points, b.points)
        XCTAssertEqual(b.points, b.maxPoints)
        XCTAssertEqual(a.responseTime, 10)
    }

    func testDecodesRecordsWithoutNewFields() throws {
        let json = """
        {"count":1,"startCPM":100,"stepPercent":4,"minCPM":25,"maxCPM":999}
        """
        let c = try JSONDecoder().decode(TrainingConfig.self, from: Data(json.utf8))
        XCTAssertFalse(c.responseTimePenalty)
        let r = try JSONDecoder().decode(CallResult.self, from: Data("""
        {"index":0,"sent":"K1AB","received":"K1AB","cpm":100,"points":5,"repeated":false}
        """.utf8))
        XCTAssertNil(r.responseTime)
    }
}

final class CallsignTests: XCTestCase {
    func testParseSCP() {
        let text = "# comment\nDL1ABC\n k1ab \nfoo\nW1AW, VE3XYZ\nDL1ABC\nEA8/DL1ABC\n"
        XCTAssertEqual(CallsignList.parse(text), ["DL1ABC", "K1AB", "W1AW", "VE3XYZ", "EA8/DL1ABC"])
    }

    func testGeneratorIsValidAndDeterministic() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        let gen = CallsignGenerator(portableProbability: 0.2, prefixedProbability: 0.1)
        let x = gen.generate(500, using: &a)
        XCTAssertEqual(x, gen.generate(500, using: &b))
        XCTAssertEqual(Set(x).count, 500)
        for call in x { XCTAssertTrue(CallsignList.isValid(call), call) }
    }

    func testPickWithoutRepeats() {
        var rng = SeededRandom(seed: 1)
        let picked = CallsignList.pick(3, from: ["A1A", "B2B", "C3C", "D4D"], using: &rng)
        XCTAssertEqual(Set(picked).count, 3)
        XCTAssertEqual(CallsignList.pick(5, from: ["A1A", "B2B"], using: &rng).count, 5)
    }
}

final class HistoryTests: XCTestCase {
    func testRoundTripAndCSV() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var s = TrainingSession(config: TrainingConfig(count: 1), callsigns: ["K1AB"])
        s.submit("K1AB")
        let record = AttemptRecord(session: s, source: "Generated", date: Date(timeIntervalSince1970: 1_700_000_000))
        let store = HistoryStore(fileURL: url)
        try store.save([record])
        XCTAssertEqual(try store.load(), [record])
        XCTAssertTrue(HistoryStore.csv([record]).contains("\"Generated\""))
    }
}

final class CharacterAnalysisTests: XCTestCase {
    private func result(_ sent: String, _ received: String, cpm: Double = 100) -> CallResult {
        CallResult(index: 0, sent: sent, received: received, cpm: cpm, points: 0, repeated: false)
    }

    func testCountsAndConfusions() {
        let a = CharacterAnalysis(results: [
            result("DL5ABC", "DLHABC"),   // 5 → H
            result("K5XY", "KHXY"),       // 5 → H
            result("G4ABC", "G4AC"),      // B missed
            result("W1AW", ""),           // blank: ignored
        ])
        XCTAssertEqual(a.callsignCount, 3)
        XCTAssertEqual(a.stat(for: "5").sent, 2)
        XCTAssertEqual(a.stat(for: "5").correct, 0)
        XCTAssertEqual(a.stat(for: "A").accuracy, 1)
        XCTAssertEqual(a.stat(for: "W").sent, 0)
        XCTAssertEqual(a.confusions.first, Confusion(sent: "5", typed: "H", count: 2))
        XCTAssertTrue(a.confusions.contains(Confusion(sent: "B", typed: nil, count: 1)))
        XCTAssertEqual(a.weakest(1, minSamples: 1).first?.character, "5")
        XCTAssertEqual(a.weakest(10, minSamples: 3).count, 0)
    }

    func testSpeedBands() {
        let bands = CharacterAnalysis.accuracyBySpeed([result("K1A", "K1A", cpm: 110), result("K1A", "X", cpm: 120), result("K1A", "K1A", cpm: 160)])
        XCTAssertEqual(bands.map(\.lowerCPM), [100, 150])
        XCTAssertEqual(bands[0].accuracy, 0.5)
        XCTAssertEqual(bands[1].total, 1)
    }

    func testFocusedGeneration() {
        var rng = SeededRandom(seed: 7)
        let calls = CallsignGenerator().generate(200, focusing: ["5", "H"], using: &rng)
        XCTAssertEqual(calls.count, 200)
        let hits = calls.filter { $0.contains("5") || $0.contains("H") }.count
        XCTAssertGreaterThan(hits, 150)
        for c in calls { XCTAssertTrue(CallsignList.isValid(c), c) }
    }

    func testFocusedPickFromList() {
        var rng = SeededRandom(seed: 3)
        let list = (0..<100).map { "K\($0 % 10)AB" + ($0 < 50 ? "H" : "X") }
        let picked = CallsignList.pick(20, from: Array(Set(list)), focusing: ["H"], using: &rng)
        XCTAssertEqual(picked.count, 20)
        XCTAssertGreaterThanOrEqual(picked.filter { $0.hasSuffix("H") }.count, 15)
    }
}
