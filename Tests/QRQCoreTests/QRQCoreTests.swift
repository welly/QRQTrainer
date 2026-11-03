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

@Suite struct GroupTests {
    @Test func everyTrainableCharacterHasMorse() {
        for ch in CharacterClass.allCharacters { #expect(Morse.code(for: ch) != nil, "\(ch)") }
    }

    @Test func fixedLengthUsesOnlyEnabledCharacters() {
        var rng = SeededRandom(seed: 7)
        let gen = GroupGenerator(mode: .letters, enabled: Set("ABC123"), minLength: 5, maxLength: 5)
        let groups = gen.generate(200, using: &rng)
        #expect(groups.count == 200)
        for g in groups {
            #expect(g.count == 5)
            #expect(Set(g).isSubset(of: Set("ABC")))
        }
    }

    @Test func variableLengthCoversRange() {
        var rng = SeededRandom(seed: 3)
        let gen = GroupGenerator(mode: .all, enabled: Set(CharacterClass.allCharacters), minLength: 2, maxLength: 6)
        let lengths = Set(gen.generate(500, using: &rng).map(\.count))
        #expect(lengths == Set(2...6))
    }

    @Test func swappedBoundsAreNormalised() {
        let gen = GroupGenerator(mode: .figures, enabled: Set("0123456789"), minLength: 8, maxLength: 3)
        #expect(gen.minLength == 3 && gen.maxLength == 8)
    }

    @Test func separatedGroupsUseOneClass() {
        var rng = SeededRandom(seed: 11)
        let gen = GroupGenerator(mode: .lettersFigures, enabled: Set(CharacterClass.allCharacters),
                                 minLength: 4, maxLength: 4, composition: .separated)
        let groups = gen.generate(300, using: &rng)
        let letters = Set(CharacterClass.letters.characters), figures = Set(CharacterClass.figures.characters)
        for g in groups { #expect(Set(g).isSubset(of: letters) || Set(g).isSubset(of: figures), "\(g)") }
        #expect(groups.contains { Set($0).isSubset(of: letters) })
        #expect(groups.contains { Set($0).isSubset(of: figures) })
    }

    @Test func mixedGroupsCombineClasses() {
        var rng = SeededRandom(seed: 5)
        let gen = GroupGenerator(mode: .lettersFigures, enabled: Set(CharacterClass.allCharacters), minLength: 6, maxLength: 6)
        let letters = Set(CharacterClass.letters.characters), figures = Set(CharacterClass.figures.characters)
        #expect(gen.generate(100, using: &rng).contains { !Set($0).isDisjoint(with: letters) && !Set($0).isDisjoint(with: figures) })
    }

    @Test func emptySelectionCannotGenerate() {
        var rng = SeededRandom(seed: 1)
        let gen = GroupGenerator(mode: .symbols, enabled: Set("ABC"), minLength: 1, maxLength: 3)
        #expect(!gen.canGenerate)
        #expect(gen.generate(5, using: &rng).isEmpty)
    }

    @Test func symbolGroupsScore() {
        #expect(Scoring.points(sent: "?/=", received: "?/=", cpm: 200, repeated: false) > 0)
    }

    @Test func hamCodesAreSendable() {
        for code in HamCodes.all { #expect(code.allSatisfy { Morse.code(for: $0) != nil }, "\(code)") }
        #expect(Set(HamCodes.all).count == HamCodes.all.count)
    }
}

@Suite struct FarnsworthTests {
    @Test func noStretchAtFullRatio() {
        #expect(close(MorseSynth.gapUnitSeconds(cpm: 100, farnsworth: 1), Morse.ditSeconds(cpm: 100)))
        #expect(close(MorseSynth.duration(of: "PARIS", cpm: 100, farnsworth: 1), MorseSynth.duration(of: "PARIS", cpm: 100)))
    }

    @Test func effectiveSpeedMatchesRatio() {
        // "PARIS " repeated: one word per 50 units at the character speed; Farnsworth slows the whole word to the ratio.
        let cpm = 100.0, ratio = 0.5
        let word = MorseSynth.duration(of: "PARIS PARIS", cpm: cpm, farnsworth: ratio)
            - MorseSynth.duration(of: "PARIS", cpm: cpm, farnsworth: ratio)
        let effectiveWPM = 60 / word
        #expect(close(effectiveWPM, Morse.wpm(fromCPM: cpm) * ratio, 0.01))
    }

    @Test func charactersKeepTheirSpeed() {
        // A single character has no gaps to stretch.
        #expect(close(MorseSynth.duration(of: "H", cpm: 200, farnsworth: 0.4), MorseSynth.duration(of: "H", cpm: 200)))
        #expect(MorseSynth.duration(of: "HH", cpm: 200, farnsworth: 0.4) > MorseSynth.duration(of: "HH", cpm: 200))
    }

    @Test func renderedLengthMatchesDuration() {
        let tone = ToneSettings(sampleRate: 8000)
        let s = MorseSynth.render(text: "K1AB", cpm: 300, tone: tone, farnsworth: 0.6)
        #expect(close(Double(s.count), MorseSynth.duration(of: "K1AB", cpm: 300, farnsworth: 0.6, leadIn: 0.05, tail: 0.05) * 8000, 1))
    }
}

@Suite struct ResponseTimeTests {
    @Test func factorFallsWithTimeAndBottomsOut() {
        #expect(Scoring.responseFactor(seconds: nil) == 1)
        #expect(Scoring.responseFactor(seconds: 0) == 1)
        #expect(close(Scoring.responseFactor(seconds: 1), 0.97))
        #expect(close(Scoring.responseFactor(seconds: 10), 0.7))
        #expect(Scoring.responseFactor(seconds: 60) == Scoring.minimumResponseFactor)
    }

    @Test func slowerAnswersScoreLess() {
        let fast = Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 300, repeated: false, responseTime: 0.5)
        let slow = Scoring.points(sent: "DL1ABC", received: "DL1ABC", cpm: 300, repeated: false, responseTime: 3)
        #expect(fast > slow)
        #expect(fast <= Scoring.maxPoints(sent: "DL1ABC", cpm: 300))
    }

    @Test func sessionRecordsResponseTime() {
        var s = TrainingSession(config: TrainingConfig(count: 2), callsigns: ["K1AB", "G4XYZ"])
        let a = s.submit("K1AB", responseTime: 0.742)
        #expect(a?.responseMs == 742)
        #expect(a?.maxPoints == Scoring.maxPoints(sent: "K1AB", cpm: 100))
        s.submit("G4XYZ", responseTime: 1.258)
        #expect(AttemptRecord(session: s, source: "t").averageResponseMs == 1000)
    }

    @Test func oldRecordsWithoutResponseTimeStillDecode() throws {
        let json = #"{"index":0,"sent":"K1AB","received":"K1AB","cpm":100,"points":5,"repeated":false}"#
        let r = try JSONDecoder().decode(CallResult.self, from: Data(json.utf8))
        #expect(r.responseMs == nil)
        #expect(r.points == 5)
    }
}

@Suite struct ResponseFromStartTests {
    @Test func penaltyOnlyCountsTimeAfterTheSound() {
        var s = TrainingSession(config: TrainingConfig(count: 2), callsigns: ["K1AB", "K1AB"])
        // 1.5 s response to a 1 s sound: penalised for 0.5 s.
        let r = s.submit("K1AB", responseTime: 1.5, soundDuration: 1.0)
        #expect(r?.responseMs == 1500)
        #expect(r?.soundMs == 1000)
        #expect(r?.points == Scoring.points(sent: "K1AB", received: "K1AB", cpm: 100, repeated: false, responseTime: 0.5))
    }

    @Test func answeringDuringTheSoundIsInstant() {
        var s = TrainingSession(config: TrainingConfig(count: 1), callsigns: ["K1AB"])
        let r = s.submit("K1AB", responseTime: 0.6, soundDuration: 1.0)
        #expect(r?.responseMs == 600)
        #expect(r?.points == Scoring.maxPoints(sent: "K1AB", cpm: 100))
    }

    @Test func soundDurationExcludesLeadInAndTail() {
        let full = MorseSynth.duration(of: "K1AB", cpm: 200, leadIn: 0.05, tail: 0.05)
        let sound = MorseSynth.duration(of: "K1AB", cpm: 200)
        #expect(close(full - sound, 0.1))
    }
}
