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

    @Test func fixedSpeedNeverChanges() {
        var session = TrainingSession(config: TrainingConfig(count: 3, startCPM: 125, stepPercent: 0), callsigns: ["AB", "CD", "EF"])
        _ = session.submit("AB")
        _ = session.submit("XX")
        #expect(session.currentCPM == 125)
        #expect(session.results.allSatisfy { $0.cpm == 125 })
    }

    @Test func wordSetsAreMostCommonFirst() {
        #expect(WordSet.top100.words.count == 100 && WordSet.top200.words.count == 200)
        #expect(WordSet.top100.words.prefix(3) == ["THE", "OF", "AND"])
        #expect(Set(WordSet.top100.words).isSubset(of: Set(WordSet.top200.words)))
        #expect(Set(Words.ranked).count == Words.ranked.count)
        #expect(Words.list(.top100, minLength: 3, maxLength: 3).allSatisfy { $0.count == 3 && WordSet.top100.words.contains($0) })
    }

    @Test func missedWordsComeBackInTheAttempt() {
        let words = ["ONE", "TWO", "SIX", "TEN", "BIG", "CAT", "DOG"]
        var session = TrainingSession(config: TrainingConfig(count: 7), callsigns: words, bringBackMisses: true)
        _ = session.submit("ONX")                     // miss ONE
        #expect(session.callsigns[3] == "ONE")         // back 3 items later
        _ = session.submit("TWX")                     // miss TWO: slot 4
        #expect(session.callsigns[4] == "TWO")
        _ = session.submit("SIX")
        _ = session.submit("ONX")                     // miss ONE again: comes back a second time
        #expect(session.callsigns[6] == "ONE")
        #expect(session.callsigns.count == 7)
        var plain = TrainingSession(config: TrainingConfig(count: 7), callsigns: words)
        _ = plain.submit("X")
        #expect(plain.callsigns == words)
    }

    @Test func missedWordsAcrossAttempts() {
        let pairs = [("CAT", "CAT"), ("DOG", "DOX"), ("SUN", "SUX"), ("DOG", "DOG"), ("SKY", "SK")]
        let results = pairs.enumerated().map { CallResult(index: $0.offset, sent: $0.element.0, received: $0.element.1, cpm: 100, points: 0, repeated: false) }
        #expect(Words.missed(in: results) == ["SKY", "SUN"])
    }

    @Test func wordsAreSendable() {
        for word in Words.common { #expect(word.allSatisfy { Morse.code(for: $0) != nil }, "\(word)") }
        #expect(Set(Words.common).count == Words.common.count)
        #expect(Words.common.count >= 200)
        #expect(TrainerMode.words.itemName == "word" && !TrainerMode.words.usesGroups)
    }

    @Test func wordsFilterByLength() {
        #expect(Words.list(minLength: 4, maxLength: 4).allSatisfy { $0.count == 4 })
        #expect(Words.list(minLength: 6, maxLength: 3).allSatisfy { (3...6).contains($0.count) })  // order doesn't matter
        #expect(Words.list(minLength: Words.lengths.lowerBound, maxLength: Words.lengths.upperBound).count == Words.common.count)
        #expect(Words.lengths == 1...12)
        for n in Words.lengths { #expect(Words.list(minLength: n, maxLength: n).count >= 2, "length \(n)") }
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

@Suite struct CharacterAnalysisTests {
    private func result(_ sent: String, _ received: String, responseMs: Int? = nil, soundMs: Int? = nil) -> CallResult {
        CallResult(index: 0, sent: sent, received: received, cpm: 100, points: 0, repeated: false,
                   responseMs: responseMs, soundMs: soundMs)
    }

    @Test func countsAccuracyAndMixUps() {
        let a = CharacterAnalysis(results: [result("AB", "AB"), result("AB", "AX"), result("AB", "A")])
        #expect(a.stat(for: "A").sent == 3 && a.stat(for: "A").correct == 3)
        #expect(a.stat(for: "B").sent == 3 && a.stat(for: "B").correct == 1)
        #expect(a.confusions.contains { $0.sent == "B" && $0.typed == "X" })
        #expect(a.confusions.contains { $0.sent == "B" && $0.typed == nil })
    }

    @Test func instantNeedsCorrectAndQuick() {
        // Older attempts (Return only): allowance 1500 ms after the sound for one character.
        var results: [CallResult] = []
        for _ in 0..<9 { results.append(result("E", "E", responseMs: 1500, soundMs: 300)) }  // 1200 ms after: instant
        results.append(result("E", "E", responseMs: 2300, soundMs: 300))                       // 2000 ms after: slow
        for _ in 0..<5 { results.append(result("T", "T", responseMs: 2300, soundMs: 300)) }   // always slow
        let a = CharacterAnalysis(results: results)
        #expect(a.stat(for: "E").instant == 9 && a.stat(for: "E").timed == 10)
        #expect(a.stat(for: "E").isInstant)
        #expect(!a.stat(for: "T").isInstant)
        #expect(a.stat(for: "T").averageThinkMs == 2000)
        #expect(a.weakest(5).map(\.character) == ["T"])
        #expect(a.strongest(5).map(\.character) == ["E"])  // only ⚡ characters, never the slow T
    }

    @Test func allowanceGrowsWithLength() {
        #expect(CharacterAnalysis.instantAllowanceMs(length: 1) == 1500)
        #expect(CharacterAnalysis.instantAllowanceMs(length: 6) == 2500)
    }

    @Test func firstKeyDecidesInstant() {
        // Slow to press Return, but the first key came 700 ms after the sound: instant.
        let quick = CallResult(index: 0, sent: "QRQ", received: "QRQ", cpm: 100, points: 0, repeated: false,
                               responseMs: 4000, soundMs: 1000, firstKeyMs: 1700)
        #expect(CharacterAnalysis.recognition(of: quick)! == (700, true))
        // First key 1200 ms after the sound: not instant, however fast Return was.
        let slow = CallResult(index: 0, sent: "E", received: "E", cpm: 100, points: 0, repeated: false,
                              responseMs: 1300, soundMs: 100, firstKeyMs: 1300)
        #expect(CharacterAnalysis.recognition(of: slow)!.quick == false)
        // Typing before the sound ended counts as 0 ms.
        let early = CallResult(index: 0, sent: "E", received: "E", cpm: 100, points: 0, repeated: false,
                               responseMs: 500, soundMs: 400, firstKeyMs: 300)
        #expect(CharacterAnalysis.recognition(of: early)!.thinkMs == 0)
    }

    @Test func untimedResultsFallBackToAccuracy() {
        let a = CharacterAnalysis(results: Array(repeating: result("K", "K"), count: 5))
        #expect(a.stat(for: "K").instantRate == nil)
        #expect(a.stat(for: "K").recognition == 1)
        #expect(!a.stat(for: "K").isInstant)
    }
}
