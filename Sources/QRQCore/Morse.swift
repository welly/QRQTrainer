import Foundation

/// One keying segment: the key is either down (tone) or up (silence) for a number of dit units.
public struct KeyElement: Equatable, Sendable {
    public let isOn: Bool
    public let units: Int

    public init(isOn: Bool, units: Int) {
        self.isOn = isOn
        self.units = units
    }
}

/// International Morse code with standard (PARIS) timing.
///
/// dit = 1 unit, dah = 3 units, gap inside a character = 1 unit,
/// gap between characters = 3 units, gap between words = 7 units.
public enum Morse {
    public static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.",
        "G": "--.", "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..",
        "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
        "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        "/": "-..-.", "?": "..--..", ".": ".-.-.-", ",": "--..--", "=": "-...-",
        ":": "---...", ";": "-.-.-.", "+": ".-.-.", "-": "-....-", "'": ".----.",
        "\"": ".-..-.", "(": "-.--.", ")": "-.--.-", "@": ".--.-.",
    ]

    public static func code(for character: Character) -> String? {
        table[Character(character.uppercased())]
    }

    /// Converts text into a sequence of key-down / key-up segments.
    /// Unknown characters are skipped. The result never starts or ends with silence.
    public static func keying(for text: String) -> [KeyElement] {
        var out: [KeyElement] = []

        func addGap(_ units: Int) {
            guard let last = out.last else { return }  // no leading silence
            if last.isOn {
                out.append(KeyElement(isOn: false, units: units))
            } else {
                out[out.count - 1] = KeyElement(isOn: false, units: max(last.units, units))
            }
        }

        for ch in text.uppercased() {
            if ch == " " {
                addGap(7)
                continue
            }
            guard let code = table[ch] else { continue }
            addGap(3)
            for (i, symbol) in code.enumerated() {
                if i > 0 { addGap(1) }
                out.append(KeyElement(isOn: true, units: symbol == "." ? 1 : 3))
            }
        }
        if let last = out.last, !last.isOn { out.removeLast() }
        return out
    }

    /// Length of `text` in dit units (no trailing gap).
    public static func units(of text: String) -> Int {
        keying(for: text).reduce(0) { $0 + $1.units }
    }

    /// Dit length in seconds for a speed in characters per minute (PARIS: 1 WPM = 5 CPM, dit = 1.2 s / WPM).
    public static func ditSeconds(cpm: Double) -> Double {
        6.0 / max(cpm, 1)
    }

    public static func wpm(fromCPM cpm: Double) -> Double { cpm / 5.0 }
    public static func cpm(fromWPM wpm: Double) -> Double { wpm * 5.0 }
}

/// Tone shape used when rendering Morse to audio samples.
public struct ToneSettings: Equatable, Sendable {
    public var frequency: Double
    public var amplitude: Double
    /// Rise/fall time of each element edge (raised cosine). Clamped at high speeds.
    public var riseTime: Double
    public var sampleRate: Double

    public init(frequency: Double = 600, amplitude: Double = 0.6, riseTime: Double = 0.005, sampleRate: Double = 48_000) {
        self.frequency = frequency
        self.amplitude = amplitude
        self.riseTime = riseTime
        self.sampleRate = sampleRate
    }
}

/// Renders Morse code into mono Float32 PCM with click-free envelopes.
public enum MorseSynth {
    /// Length of one unit of the gaps between characters and words, in seconds.
    ///
    /// With Farnsworth spacing, characters keep their full speed and only these gaps are stretched, so the
    /// overall (effective) speed is `farnsworth` × the character speed. Uses the ARRL formula: the extra delay
    /// per PARIS word, `(60c − 37.2s) / (c·s)` seconds, spread over its 19 gap units.
    public static func gapUnitSeconds(cpm: Double, farnsworth: Double = 1) -> Double {
        let dit = Morse.ditSeconds(cpm: cpm)
        let ratio = min(1, max(0.1, farnsworth))
        guard ratio < 1 else { return dit }
        let c = Morse.wpm(fromCPM: max(cpm, 1)), s = c * ratio
        return max(dit, (60 * c - 37.2 * s) / (c * s) / 19)
    }

    private static func seconds(of element: KeyElement, dit: Double, gapUnit: Double) -> Double {
        // Gaps of 3 or more units separate characters or words; the 1-unit gaps inside a character are never stretched.
        Double(element.units) * (!element.isOn && element.units >= 3 ? gapUnit : dit)
    }

    public static func duration(of text: String, cpm: Double, farnsworth: Double = 1, leadIn: Double = 0, tail: Double = 0) -> Double {
        let dit = Morse.ditSeconds(cpm: cpm), gap = gapUnitSeconds(cpm: cpm, farnsworth: farnsworth)
        return leadIn + Morse.keying(for: text).reduce(0) { $0 + seconds(of: $1, dit: dit, gapUnit: gap) } + tail
    }

    public static func render(
        text: String,
        cpm: Double,
        tone: ToneSettings,
        farnsworth: Double = 1,
        leadIn: Double = 0.05,
        tail: Double = 0.05
    ) -> [Float] {
        let sr = tone.sampleRate
        let dit = Morse.ditSeconds(cpm: cpm)
        let elements = Morse.keying(for: text)
        let gapUnit = gapUnitSeconds(cpm: cpm, farnsworth: farnsworth)
        let total = Int((duration(of: text, cpm: cpm, farnsworth: farnsworth, leadIn: leadIn, tail: tail) * sr).rounded(.up))
        var samples = [Float](repeating: 0, count: max(total, 0))
        guard !elements.isEmpty, total > 0 else { return samples }

        // At ultra-high speed keep edges well inside the element so dits stay distinct.
        let rise = max(0.0005, min(tone.riseTime, dit * 0.3))
        let omega = 2.0 * Double.pi * tone.frequency / sr
        let amp = max(0, min(1, tone.amplitude))

        var t = leadIn
        for element in elements {
            let length = seconds(of: element, dit: dit, gapUnit: gapUnit)
            if element.isOn {
                let start = Int((t * sr).rounded())
                let end = min(Int(((t + length) * sr).rounded()), samples.count)
                if start < end {
                    for i in start..<end {
                        let fromStart = Double(i - start) / sr
                        let toEnd = Double(end - i) / sr
                        var env = 1.0
                        if fromStart < rise { env = 0.5 - 0.5 * cos(Double.pi * fromStart / rise) }
                        if toEnd < rise { env = min(env, 0.5 - 0.5 * cos(Double.pi * toEnd / rise)) }
                        // Absolute sample index keeps phase continuous across elements.
                        samples[i] = Float(amp * env * sin(omega * Double(i)))
                    }
                }
            }
            t += length
        }
        return samples
    }
}
