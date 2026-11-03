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
