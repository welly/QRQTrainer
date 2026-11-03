import Foundation
import Testing
@testable import QRQCore

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

@Suite struct MorseTests {
    @Test func parisIsFiftyUnits() {
        // "PARIS " including the trailing word gap is the standard 50-unit word.
        #expect(Morse.units(of: "PARIS") + 7 == 50)
    }

    @Test func keyingOfA() {
        #expect(Morse.keying(for: "A") == [
            KeyElement(isOn: true, units: 1), KeyElement(isOn: false, units: 1), KeyElement(isOn: true, units: 3),
        ])
    }

    @Test func characterGapAndNoTrailingSilence() {
        let k = Morse.keying(for: "EE ")
        #expect(k == [KeyElement(isOn: true, units: 1), KeyElement(isOn: false, units: 3), KeyElement(isOn: true, units: 1)])
    }

    @Test func ditLength() {
        #expect(close(Morse.ditSeconds(cpm: 60), 0.1))  // 12 WPM
        #expect(Morse.wpm(fromCPM: 250) == 50)
    }

    @Test func renderLengthAndRange() {
        let tone = ToneSettings(frequency: 700, amplitude: 0.5, riseTime: 0.005, sampleRate: 8000)
        let s = MorseSynth.render(text: "DL1ABC", cpm: 300, tone: tone, leadIn: 0.05, tail: 0.05)
        let expected = MorseSynth.duration(of: "DL1ABC", cpm: 300, leadIn: 0.05, tail: 0.05) * 8000
        #expect(close(Double(s.count), expected, 1))
        #expect((s.map { abs($0) }.max() ?? 0) <= 0.5 + 1e-6)
        #expect(s.first == 0)
        #expect(s.last == 0)
    }
}

@Suite struct ScoringTests {
    @Test func editDistance() {
        #expect(Scoring.editDistance("DL1ABC", "DL1ABC") == 0)
        #expect(Scoring.editDistance("DL1ABC", "DL1AB") == 1)
        #expect(Scoring.editDistance("DL1ABC", "DK1ABC") == 1)
        #expect(Scoring.editDistance("", "ABC") == 3)
    }

    @Test func alignment() {
        #expect(Scoring.align(sent: "K1AB", received: "K1XAB") ==
                [.match("K"), .match("1"), .extra("X"), .match("A"), .match("B")])
        #expect(Scoring.align(sent: "K1AB", received: "K1B") ==
                [.match("K"), .match("1"), .missing("A"), .match("B")])
    }

    @Test func points() {
        let full = Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 200, repeated: false)
        let oneOff = Scoring.points(sent: "DL1ABC", received: "DL1ABX", cpm: 200, repeated: false)
        #expect(full > oneOff)
        #expect(oneOff > 0)
        #expect(Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 200, repeated: true) == 0)
        #expect(Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 400, repeated: false) > full)
    }
}

@Suite struct SessionTests {
    @Test func speedAdaptsAndFinishes() {
        var s = TrainingSession(config: TrainingConfig(count: 3, startCPM: 100, stepPercent: 10), callsigns: ["K1AB", "G4XYZ", "JA1ABC"])
        s.submit("K1AB")
        #expect(close(s.currentCPM, 110))
        s.submit("G4XYC")
        #expect(close(s.currentCPM, 99))
        s.markRepeated()
        let r = s.submit("ja1abc")
        #expect(r?.isCorrect == true)
        #expect(r?.points == 0)
        #expect(close(s.currentCPM, 99))  // repeated & correct: unchanged
        #expect(s.isFinished)
        #expect(s.submit("X") == nil)
        #expect(AttemptRecord(session: s, source: "t").peakCPM == 100)
    }
}

@Suite struct CallsignTests {
    @Test func parseSCP() {
        let text = "# comment\nDL1ABC\n k1ab \nfoo\nW1AW, VE3XYZ\nDL1ABC\nEA8/DL1ABC\n"
        #expect(CallsignList.parse(text) == ["DL1ABC", "K1AB", "W1AW", "VE3XYZ", "EA8/DL1ABC"])
    }

    @Test func generatorIsValidAndDeterministic() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        let gen = CallsignGenerator(portableProbability: 0.2, prefixedProbability: 0.1)
        let x = gen.generate(500, using: &a)
        #expect(x == gen.generate(500, using: &b))
        #expect(Set(x).count == 500)
        for call in x { #expect(CallsignList.isValid(call), "\(call)") }
    }

    @Test func pickWithoutRepeats() {
        var rng = SeededRandom(seed: 1)
        let picked = CallsignList.pick(3, from: ["A1A", "B2B", "C3C", "D4D"], using: &rng)
        #expect(Set(picked).count == 3)
        #expect(CallsignList.pick(5, from: ["A1A", "B2B"], using: &rng).count == 5)
    }
}

@Suite struct HistoryTests {
    @Test func roundTripAndCSV() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var s = TrainingSession(config: TrainingConfig(count: 1), callsigns: ["K1AB"])
        s.submit("K1AB")
        let record = AttemptRecord(session: s, source: "Generated", date: Date(timeIntervalSince1970: 1_700_000_000))
        let store = HistoryStore(fileURL: url)
        try store.save([record])
        #expect(try store.load() == [record])
        #expect(HistoryStore.csv([record]).contains("\"Generated\""))
    }
}
