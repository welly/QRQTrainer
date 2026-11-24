import CWKit
import Foundation
import Testing
@testable import QRQCore

// QRQ Trainer moved from its own Morse engine (LegacyMorse.swift) to the shared CWKit on 2026-11-24. These check the
// change didn't alter what scores depend on: each item's length in Morse units (its points) and how long it sounds
// (the response time only counts after the sound), and that the sound is keyed at the same moments.

private let calls: [String] = {
    var rng = SeededRandom(seed: 2026)
    return CallsignGenerator(portableProbability: 0.2, prefixedProbability: 0.2).generate(300, using: &rng)
        + HamCodes.all + Words.ranked
        + GroupGenerator(mode: .all, enabled: Set(CharacterClass.allCharacters), minLength: 1, maxLength: 12).generate(150, using: &rng)
}()
private let speeds: [Double] = [25, 100, 300, 500]
private let ratios: [Double] = [1, 0.6]

@Suite struct EngineEquivalenceTests {
    @Test func unitsAndPointsAreUnchanged() {
        for call in calls {
            #expect(Morse.units(of: call) == LegacyMorse.units(of: call), "\(call)")
            for cpm in speeds {
                #expect(Scoring.maxPoints(sent: call, cpm: cpm)
                        == Int((Double(LegacyMorse.units(of: call)) * cpm / 100).rounded()), "\(call) \(cpm)")
            }
        }
    }

    @Test func durationsAreUnchanged() {
        for call in calls { for cpm in speeds { for ratio in ratios {
            let new = MorseSynth.duration(of: call, cpm: cpm, farnsworth: ratio)
            let old = LegacyMorseSynth.duration(of: call, cpm: cpm, farnsworth: ratio)
            #expect(abs(new - old) < 1e-9, "\(call) \(cpm) CPM ×\(ratio): \(new) vs \(old)")
        } } }
    }

    @Test func soundIsKeyedAtTheSameMoments() {
        // Compare where the tone is on: allowing for the edges' shaping, at most a couple of samples per edge differ.
        let rate = 8000.0
        for call in calls.prefix(30) { for cpm in [100.0, 500] {
            let new = MorseSynth.render(text: call, cpm: cpm, tone: ToneSettings(frequency: 600, riseTime: 0.002, sampleRate: rate))
            let old = LegacyMorseSynth.render(text: call, cpm: cpm, tone: LegacyToneSettings(frequency: 600, riseTime: 0.002, sampleRate: rate))
            #expect(abs(new.count - old.count) <= 1, "\(call) \(cpm): \(new.count) vs \(old.count) samples")
            let n = min(new.count, old.count)
            // Envelope on/off from a short window, so zero crossings inside a tone don't count.
            func on(_ s: [Float], _ i: Int) -> Bool { (max(0, i - 7)...min(n - 1, i + 7)).contains { abs(s[$0]) > 0.05 } }
            let differing = (0..<n).filter { on(new, $0) != on(old, $0) }.count
            let edges = 2 * Morse.units(of: call)  // generous: at most one rise and one fall per unit
            #expect(differing <= 2 * edges, "\(call) \(cpm): \(differing) samples differ")
        } }
    }
}
