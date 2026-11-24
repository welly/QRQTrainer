import CWKit

// QRQ Trainer's view of the shared Morse engine, CWKit (github.com/welly/cw-kit): the characters it trains, speeds in
// characters per minute, and an item rendered with a little silence either side. The Morse itself (alphabet, PARIS
// and Farnsworth timing, click-free tone) is CWKit's; don't add Morse logic here.

/// International Morse code with standard (PARIS) timing, as QRQ Trainer uses it.
public enum Morse {
    /// Every character QRQ Trainer sends or accepts as an answer, with its code written with `.` and `-`.
    public static let table: [Character: String] = Dictionary(uniqueKeysWithValues:
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/?.,=:;+-'\"()@").map { ($0, MorseAlphabet.patterns[$0]!) })

    public static func code(for character: Character) -> String? {
        table[Character(character.uppercased())]
    }

    /// Length of `text` in dit units, with no gap after the last character. Points are worked out from it.
    public static func units(of text: String) -> Int {
        MorseKeyer.units(of: text)
    }

    /// Fastest speed: CWKit's 100 WPM. Nobody needs training beyond it.
    public static let maxCPM = cpm(fromWPM: MorseTiming.wpmRange.upperBound)

    /// Dit length in seconds for a speed in characters per minute (PARIS: 1 WPM = 5 CPM, dit = 1.2 s / WPM).
    public static func ditSeconds(cpm: Double) -> Double {
        MorseTiming(characterCPM: cpm).dit
    }

    public static func wpm(fromCPM cpm: Double) -> Double { MorseTiming.wpm(fromCPM: cpm) }
    public static func cpm(fromWPM wpm: Double) -> Double { MorseTiming.cpm(fromWPM: wpm) }
}

/// Renders an item to mono Float32 samples with CWKit.
public enum MorseSynth {
    /// CWKit timing for a speed in CPM. With Farnsworth spacing, characters keep their full speed and the gaps between
    /// them are stretched so the overall speed is `farnsworth` × the character speed (0.1...1; 1 means none).
    public static func timing(cpm: Double, farnsworth: Double = 1) -> MorseTiming {
        let ratio = min(1, max(0.1, farnsworth))
        let characterWPM = min(max(Morse.wpm(fromCPM: cpm), MorseTiming.wpmRange.lowerBound), MorseTiming.wpmRange.upperBound)
        return MorseTiming(characterWPM: characterWPM, spacing: ratio < 1 ? .farnsworth(overallWPM: characterWPM * ratio) : .standard)
    }

    /// Length of one unit of the gaps between characters and words, in seconds (a dit unless Farnsworth stretches it).
    public static func gapUnitSeconds(cpm: Double, farnsworth: Double = 1) -> Double {
        timing(cpm: cpm, farnsworth: farnsworth).characterGap / 3
    }

    /// How long `text` sounds, from the start of the first tone to the end of the last, plus any lead-in and tail.
    public static func duration(of text: String, cpm: Double, farnsworth: Double = 1, leadIn: Double = 0, tail: Double = 0) -> Double {
        leadIn + MorseKeyer.duration(of: MorseKeyer.segments(for: text, timing: timing(cpm: cpm, farnsworth: farnsworth))) + tail
    }

    /// The item's samples at `tone.sampleRate`, with `leadIn` seconds of silence before and `tail` after.
    public static func render(
        text: String,
        cpm: Double,
        tone: ToneSettings,
        farnsworth: Double = 1,
        leadIn: Double = 0.05,
        tail: Double = 0.05
    ) -> [Float] {
        let body = ToneRenderer(tone: tone, timing: timing(cpm: cpm, farnsworth: farnsworth)).render(text)
        let before = [Float](repeating: 0, count: Int((leadIn * tone.sampleRate).rounded()))
        let after = [Float](repeating: 0, count: Int((tail * tone.sampleRate).rounded()))
        return before + body + after
    }
}
