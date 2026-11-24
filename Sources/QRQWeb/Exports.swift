// The web version's entry points: QRQCore compiled to WebAssembly (a WASI reactor), called from web/engine.js.
//
// One export does the work: JavaScript writes a JSON command into the input buffer and calls `qrq_call`,
// which answers with JSON (and, for commands that make sound, samples JavaScript reads straight from linear
// memory). The attempt in progress (`TrainingSession`) lives here, so the speed rules, brought-back words and
// scoring are QRQCore's own; the page keeps the history and the settings.
//
// Built by scripts/build-web.sh. No Foundation, to keep the download small. It also compiles on the Mac, so
// `swift build` of the whole package works.
import QRQCore

/// Buffers handed to JavaScript. Each stays put until the next call replaces it.
nonisolated(unsafe) private var input = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 0)
nonisolated(unsafe) private var samples = UnsafeMutableBufferPointer<Float>.allocate(capacity: 0)
nonisolated(unsafe) private var result = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 0)

/// The imported callsign list (set with `setList`).
nonisolated(unsafe) private var importedCalls: [String] = []
/// The attempt in progress, and the settings it started with (changes mid-attempt don't affect it).
nonisolated(unsafe) private var session: TrainingSession?
nonisolated(unsafe) private var attemptSettings = WebSettings(.null)
/// How long the current item sounded when it was last played, from the first tone's start to the last one's end.
nonisolated(unsafe) private var soundSeconds = 0.0

/// Silence before the first tone and after the last, as in the Mac app.
private let leadIn = 0.05

private func replace<T>(_ buffer: inout UnsafeMutableBufferPointer<T>, with values: [T]) {
    buffer.deallocate()
    buffer = .allocate(capacity: values.count)
    _ = buffer.initialize(from: values)
}

/// Makes room for `size` bytes of input (a JSON command) and returns where to write it.
@_cdecl("qrq_input")
func qrqInput(_ size: Int32) -> UnsafeMutablePointer<UInt8>? {
    input.deallocate()
    input = .allocate(capacity: Int(max(size, 1)))
    return input.baseAddress
}

/// Runs the JSON command in the input buffer. Audio is rendered at `sampleRate`.
/// Returns 0, or -1 if the command can't be read or can't be done (no attempt running, for example).
@_cdecl("qrq_call")
func qrqCall(_ length: Int32, _ sampleRate: Double) -> Int32 {
    guard let command = JSON.parse(Array(input.prefix(Int(length)))), let name = command["cmd"]?.string else { return -1 }
    var audio: [Float] = []
    guard let answer = run(name, command, sampleRate: sampleRate, audio: &audio) else { return -1 }
    replace(&samples, with: audio)
    replace(&result, with: Array(answer.text.utf8))
    return 0
}

@_cdecl("qrq_samples")
func qrqSamples() -> UnsafeMutablePointer<Float>? { samples.baseAddress }

@_cdecl("qrq_sample_count")
func qrqSampleCount() -> Int32 { Int32(samples.count) }

@_cdecl("qrq_result")
func qrqResult() -> UnsafeMutablePointer<UInt8>? { result.baseAddress }

@_cdecl("qrq_result_length")
func qrqResultLength() -> Int32 { Int32(result.count) }

// MARK: Commands

private func run(_ name: String, _ command: JSON, sampleRate: Double, audio: inout [Float]) -> JSON? {
    switch name {
    case "codes":
        // The Morse for every character, for showing it beside characters in Insights.
        return .object(Morse.table.keys.sorted().map { (String($0), .string(Morse.table[$0]!)) })

    case "setList":
        // The imported callsign list: parsed and kept for `start`. The page stores the cleaned-up text.
        importedCalls = CallsignList.parse(command["text"]?.string ?? "")
        return .object([("count", .number(Double(importedCalls.count))),
                         ("text", .string(importedCalls.joined(separator: "\n")))])

    case "describe":
        return describe(WebSettings(command["settings"] ?? .null), seed: UInt64(command["seed"]?.double ?? 1))

    case "start":
        let settings = WebSettings(command["settings"] ?? .null)
        let earlier = (command["earlier"]?.array ?? []).compactMap(callResult)
        let calls = items(for: settings, earlierWords: earlier)
        guard !calls.isEmpty else { return nil }
        attemptSettings = settings
        session = TrainingSession(config: settings.config, callsigns: calls,
                                  bringBackMisses: settings.mode == .words && settings.bringBackMisses)
        return state(extra: [("source", .string(settings.sourceName(importedCount: importedCalls.count)))])

    case "play":
        // The current item, rendered at the current speed. `repeat`: it was asked for again, so it scores nothing.
        guard var s = session, let call = s.currentCallsign else { return nil }
        if command["repeat"]?.bool == true {
            s.markRepeated()
            session = s
        }
        let settings = attemptSettings
        audio = MorseSynth.render(text: call, cpm: s.currentCPM, tone: settings.tone(sampleRate: sampleRate),
                                  farnsworth: settings.farnsworth, leadIn: leadIn, tail: 0.05)
        soundSeconds = MorseSynth.duration(of: call, cpm: s.currentCPM, farnsworth: settings.farnsworth)
        return state(extra: [("text", .string(call)), ("soundSeconds", .number(soundSeconds)), ("leadIn", .number(leadIn))])

    case "submit":
        // `responseTime` and `firstKeyTime`: seconds from the start of the first tone to Return and to the first key.
        guard var s = session else { return nil }
        guard let r = s.submit(command["answer"]?.string ?? "", responseTime: command["responseTime"]?.double,
                               soundDuration: soundSeconds, firstKeyTime: command["firstKeyTime"]?.double) else { return nil }
        session = s
        return state(extra: [("result", encode(r)), ("detail", detail(r))])

    case "end":
        session = nil
        return .object([])

    case "testTone":
        // "VVV" at the start speed with the audio settings.
        let settings = WebSettings(command["settings"] ?? .null)
        audio = MorseSynth.render(text: "VVV", cpm: settings.startCPM, tone: settings.tone(sampleRate: sampleRate),
                                  farnsworth: settings.farnsworth)
        return .object([])

    case "details":
        // What a list of results needs for display: maximum points and how each answer lines up with what was sent.
        return .array((command["results"]?.array ?? []).compactMap(callResult).map(detail))

    case "analyse":
        return analyse((command["results"]?.array ?? []).compactMap(callResult),
                       minSamples: Int(command["minSamples"]?.double ?? 5))

    default:
        return nil
    }
}

/// Where the attempt has got to.
private func state(extra: [(String, JSON)] = []) -> JSON {
    guard let s = session else { return .object(extra) }
    return .object([
        ("index", .number(Double(s.index))), ("total", .number(Double(s.callsigns.count))),
        ("cpm", .number(s.currentCPM)), ("score", .number(Double(s.score))),
        ("finished", .bool(s.isFinished)), ("progress", .number(s.progress)),
        ("config", .object([
            ("count", .number(Double(s.config.count))), ("startCPM", .number(s.config.startCPM)),
            ("stepPercent", .number(s.config.stepPercent)), ("minCPM", .number(s.config.minCPM)),
            ("maxCPM", .number(s.config.maxCPM)),
        ])),
    ] + extra)
}

/// The items for an attempt, as the Mac app's `TrainerModel.start` chooses them.
private func items(for s: WebSettings, earlierWords: [CallResult]) -> [String] {
    var rng = SystemRandomNumberGenerator()
    if s.usesGroups { return s.groupGenerator.generate(s.count, using: &rng) }
    switch s.mode {
    case .callsigns:
        if s.useImported, !importedCalls.isEmpty { return CallsignList.pick(s.count, from: importedCalls, using: &rng) }
        return s.callsignGenerator.generate(s.count, using: &rng)
    case .words:
        let list = s.wordList
        guard s.bringBackMisses else { return CallsignList.pick(s.count, from: list, using: &rng) }
        // Up to a quarter are words missed in earlier Words attempts.
        let inList = Set(list)
        let missed = Words.missed(in: earlierWords).filter(inList.contains).prefix(s.count / 4)
        let rest = list.filter { !missed.contains($0) }
        let fresh = CallsignList.pick(s.count - missed.count, from: rest.isEmpty ? list : rest, using: &rng)
        return (Array(missed) + fresh).shuffled(using: &rng)
    default:
        return CallsignList.pick(s.count, from: HamCodes.all, using: &rng)
    }
}

/// What the Train screen shows about the settings: the source name, whether an attempt can start, and examples.
private func describe(_ s: WebSettings, seed: UInt64) -> JSON {
    var rng = SeededRandom(seed: seed)
    let examples: [String]
    if s.usesGroups {
        examples = s.groupGenerator.generate(8, using: &rng)
    } else {
        switch s.mode {
        case .callsigns:
            examples = s.useImported && !importedCalls.isEmpty
                ? CallsignList.pick(6, from: importedCalls, using: &rng)
                : s.callsignGenerator.generate(6, using: &rng)
        case .words: examples = CallsignList.pick(8, from: s.wordList, using: &rng)
        default: examples = CallsignList.pick(8, from: HamCodes.all, using: &rng)
        }
    }
    let canStart = s.usesGroups ? s.groupGenerator.canGenerate : (s.mode == .words ? !s.wordList.isEmpty : true)
    let classChars = s.mode.classes.flatMap(\.characters)
    var generated = SeededRandom(seed: seed &+ 1)
    return .object([
        ("source", .string(s.sourceName(importedCount: importedCalls.count))),
        ("caption", .string(s.caption(importedCount: importedCalls.count))),
        ("itemName", .string(s.mode.itemName)),
        ("canStart", .bool(canStart)),
        ("examples", .array(examples.map(JSON.string))),
        ("wordCount", .number(Double(s.wordList.count))),
        ("wordTotal", .number(Double(s.wordSet.words.count))),
        ("selected", .number(Double(classChars.filter(s.enabledCharacters.contains).count))),
        ("classTotal", .number(Double(classChars.count))),
        ("classes", .array(s.mode.classes.map { .string($0.rawValue) })),
        ("needsWork", .string(String(CharacterClass.allCharacters.filter(s.practice.contains)))),
        ("generatedExamples", .array(s.callsignGenerator.generate(5, using: &generated).map(JSON.string))),
    ])
}

/// Per-character accuracy and instant recognition, mix-ups and accuracy by speed, as the Mac app's Insights shows them.
private func analyse(_ results: [CallResult], minSamples: Int) -> JSON {
    let analysis = CharacterAnalysis(results: results)
    let ranked = analysis.stats.values.filter { $0.sent >= minSamples }
    func optional(_ value: Double?) -> JSON { value.map(JSON.number) ?? .null }
    func stat(_ st: CharacterStat) -> JSON {
        let mixUp = analysis.confusions.first { $0.sent == st.character }
        return .object([
            ("c", .string(String(st.character))), ("sent", .number(Double(st.sent))), ("correct", .number(Double(st.correct))),
            ("timed", .number(Double(st.timed))), ("instant", .number(Double(st.instant))),
            ("accuracy", optional(st.accuracy)), ("instantRate", optional(st.instantRate)),
            ("averageThinkMs", optional(st.averageThinkMs.map(Double.init))), ("isInstant", .bool(st.isInstant)),
            ("mixUp", mixUp.map { m in .object([("typed", m.typed.map { .string(String($0)) } ?? .null)]) } ?? .null),
        ])
    }
    // Every letter, number and "/", then any other symbol that has been sent.
    let grid = CharacterAnalysis.alphabet + CharacterClass.symbols.characters.filter { $0 != "/" && analysis.stat(for: $0).sent > 0 }
    let weakest = analysis.weakest(5, minSamples: minSamples)
    let bands = CharacterAnalysis.accuracyBySpeed(results, width: 25).filter { $0.total >= 3 }
    return .object([
        ("grid", .array(grid.map { stat(analysis.stat(for: $0)) })),
        ("weakest", .array(weakest.map(stat))),
        ("strongest", .array(analysis.strongest(5, minSamples: minSamples).map(stat))),
        ("needsWork", .string(String(CharacterClass.allCharacters.filter(Set(weakest.map(\.character)).contains)))),
        ("confusions", .array(analysis.confusions.prefix(8).map { c in
            .object([("sent", .string(String(c.sent))), ("typed", c.typed.map { .string(String($0)) } ?? .null),
                     ("count", .number(Double(c.count)))])
        })),
        ("bands", .array(bands.map { b in
            .object([("lowerCPM", .number(b.lowerCPM)), ("upperCPM", .number(b.upperCPM)),
                     ("total", .number(Double(b.total))), ("correct", .number(Double(b.correct)))])
        })),
        ("answered", .number(Double(analysis.callsignCount))),
        ("ranked", .number(Double(ranked.count))),
        ("instantCount", .number(Double(ranked.filter(\.isInstant).count))),
        ("charsSent", .number(Double(analysis.stats.values.reduce(0) { $0 + $1.sent }))),
        ("charsCorrect", .number(Double(analysis.stats.values.reduce(0) { $0 + $1.correct }))),
    ])
}

/// Maximum points, errors, and the answer lined up against what was sent: [kind, sent, typed] with kind
/// "match", "wrong", "missing" or "extra".
private func detail(_ r: CallResult) -> JSON {
    let align: [JSON] = Scoring.align(sent: r.sent, received: r.received).map { item in
        switch item {
        case .match(let c): .array([.string("match"), .string(String(c)), .string(String(c))])
        case .substitution(let s, let t): .array([.string("wrong"), .string(String(s)), .string(String(t))])
        case .missing(let s): .array([.string("missing"), .string(String(s)), .null])
        case .extra(let t): .array([.string("extra"), .null, .string(String(t))])
        }
    }
    return .object([("maxPoints", .number(Double(r.maxPoints))), ("errors", .number(Double(r.errors))), ("align", .array(align))])
}

// MARK: Results as JSON (the Mac app's history.json keys)

private func encode(_ r: CallResult) -> JSON {
    var members: [(String, JSON)] = [
        ("index", .number(Double(r.index))), ("sent", .string(r.sent)), ("received", .string(r.received)),
        ("cpm", .number(r.cpm)), ("points", .number(Double(r.points))), ("repeated", .bool(r.repeated)),
    ]
    if let ms = r.responseMs { members.append(("responseMs", .number(Double(ms)))) }
    if let ms = r.soundMs { members.append(("soundMs", .number(Double(ms)))) }
    if let ms = r.firstKeyMs { members.append(("firstKeyMs", .number(Double(ms)))) }
    return .object(members)
}

private func callResult(_ json: JSON) -> CallResult? {
    guard let sent = json["sent"]?.string, let received = json["received"]?.string, let cpm = json["cpm"]?.double else { return nil }
    return CallResult(index: Int(json["index"]?.double ?? 0), sent: sent, received: received, cpm: cpm,
                      points: Int(json["points"]?.double ?? 0), repeated: json["repeated"]?.bool ?? false,
                      responseMs: json["responseMs"]?.double.map { Int($0) }, soundMs: json["soundMs"]?.double.map { Int($0) },
                      firstKeyMs: json["firstKeyMs"]?.double.map { Int($0) })
}
