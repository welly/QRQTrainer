import Foundation
import Observation
import QRQCore

// MARK: - History

@Observable @MainActor
final class HistoryModel {
    private(set) var records: [AttemptRecord] = []
    var errorMessage: String?
    private let store = HistoryStore(fileURL: HistoryStore.defaultURL)

    init() {
        do { records = try store.load() } catch { errorMessage = "Couldn't read history: \(error.localizedDescription)" }
    }

    var sources: [String] { Array(Set(records.map(\.source))).sorted() }

    func records(source: String?) -> [AttemptRecord] {
        records.filter { source == nil || $0.source == source }.sorted { $0.date < $1.date }
    }

    func best(source: String) -> AttemptRecord? {
        records.filter { $0.source == source }.max { $0.score < $1.score }
    }

    func add(_ record: AttemptRecord) {
        records.append(record)
        persist()
    }

    func delete(ids: Set<UUID>) {
        records.removeAll { ids.contains($0.id) }
        persist()
    }

    private func persist() {
        do { try store.save(records) } catch { errorMessage = "Couldn't save history: \(error.localizedDescription)" }
    }
}

// MARK: - Callsign library

/// The imported callsign list (e.g. Super Check Partial MASTER.SCP), copied into Application Support.
@Observable @MainActor
final class CallsignLibrary {
    private(set) var calls: [String] = []
    private(set) var name: String?
    private let fileURL = HistoryStore.supportFile("callsigns.txt")
    private let nameKey = "importedListName"

    init() {
        name = UserDefaults.standard.string(forKey: nameKey)
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) { calls = CallsignList.parse(text) }
    }

    /// Imports a file and returns the number of valid callsigns found.
    @discardableResult
    func importFile(_ url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let parsed = CallsignList.parse(text)
        guard !parsed.isEmpty else { throw ImportError.noCallsigns }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try parsed.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        calls = parsed
        name = url.lastPathComponent
        UserDefaults.standard.set(name, forKey: nameKey)
        return parsed.count
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        calls = []
        name = nil
        UserDefaults.standard.removeObject(forKey: nameKey)
        UserDefaults.standard.set(false, forKey: Pref.useImported)
    }

    enum ImportError: LocalizedError {
        case noCallsigns
        var errorDescription: String? { "The file doesn't contain any recognisable callsigns." }
    }
}

// MARK: - Trainer

@Observable @MainActor
final class TrainerModel {
    enum Phase { case idle, running, finished }

    private(set) var phase: Phase = .idle
    private(set) var session: TrainingSession?
    private(set) var lastResult: CallResult?
    private(set) var isPlaying = false
    /// True from the moment a callsign starts playing until it is answered.
    private(set) var awaitingAnswer = false
    private(set) var finishedRecord: AttemptRecord?
    private(set) var previousBest: Int?
    var entry = ""

    let history: HistoryModel
    let library: CallsignLibrary
    private let player = MorsePlayer.shared
    private var settings = TrainerSettings.current()
    private var nextCall: Task<Void, Never>?
    private var source = ""
    /// When the first tone of the current item reaches the listener (playback start plus output latency and lead-in).
    private var soundStarts: ContinuousClock.Instant?
    /// Seconds from the first tone's start to the last tone's end.
    private var soundDuration: Double = 0

    init(history: HistoryModel, library: CallsignLibrary) {
        self.history = history
        self.library = library
    }

    /// Name of what the next attempt will send, from the current preferences. Scores are compared within a source.
    func sourceName() -> String { TrainerSettings.current().sourceName(library: library) }

    /// What one item of the running (or next) attempt is called: "callsign", "group" or "code".
    var itemName: String { (phase == .idle ? TrainerSettings.current() : settings).mode.itemName }

    /// False when the character selection leaves nothing to send in the chosen mode.
    func canStart() -> Bool {
        let s = TrainerSettings.current()
        return !s.mode.usesGroups || s.groupGenerator.canGenerate
    }

    var isNewBest: Bool {
        guard let record = finishedRecord, record.score > 0 else { return false }
        return record.score > (previousBest ?? 0)
    }

    func start() {
        guard phase != .running else { return }
        settings = .current()
        var rng = SystemRandomNumberGenerator()
        let calls: [String]
        switch settings.mode {
        case .callsigns:
            if settings.useImported, !library.calls.isEmpty {
                calls = CallsignList.pick(settings.count, from: library.calls, using: &rng)
            } else {
                let generator = CallsignGenerator(portableProbability: settings.portablePercent / 100,
                                                  prefixedProbability: settings.prefixedPercent / 100)
                calls = generator.generate(settings.count, using: &rng)
            }
        case .hamCodes:
            calls = CallsignList.pick(settings.count, from: HamCodes.all, using: &rng)
        default:
            calls = settings.groupGenerator.generate(settings.count, using: &rng)
        }
        source = settings.sourceName(library: library)
        guard !calls.isEmpty else { return }

        session = TrainingSession(config: settings.config, callsigns: calls)
        previousBest = history.best(source: source)?.score
        lastResult = nil
        finishedRecord = nil
        entry = ""
        phase = .running
        scheduleNextCall(after: 0.8)
    }

    func submit() {
        guard phase == .running, awaitingAnswer, var s = session else { return }
        let elapsed = soundStarts.map { ContinuousClock.now - $0 } ?? .zero
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let result = s.submit(entry, responseTime: seconds, soundDuration: soundDuration)
        session = s
        lastResult = result
        entry = ""
        awaitingAnswer = false
        player.stop()
        isPlaying = false
        if s.isFinished {
            finish()
        } else {
            scheduleNextCall(after: settings.pauseMs / 1000)
        }
    }

    /// Plays the current callsign again. That callsign then scores no points.
    func repeatCurrent() {
        guard phase == .running, awaitingAnswer, var s = session else { return }
        s.markRepeated()
        session = s
        playCurrent()
    }

    func abort() {
        nextCall?.cancel()
        player.stop()
        isPlaying = false
        awaitingAnswer = false
        session = nil
        phase = .idle
    }

    func dismissResults() {
        phase = .idle
    }

    private func scheduleNextCall(after seconds: Double) {
        nextCall?.cancel()
        nextCall = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            guard !Task.isCancelled else { return }
            self?.playCurrent()
        }
    }

    private func playCurrent() {
        guard phase == .running, let s = session, let call = s.currentCallsign else { return }
        let leadIn = 0.05
        let samples = MorseSynth.render(text: call, cpm: s.currentCPM, tone: settings.tone(sampleRate: player.sampleRate),
                                       farnsworth: settings.farnsworth, leadIn: leadIn, tail: 0.05)
        awaitingAnswer = true
        isPlaying = true
        let start = player.play(samples) { [weak self] in self?.isPlaying = false }
        soundStarts = start + .seconds(leadIn)
        soundDuration = MorseSynth.duration(of: call, cpm: s.currentCPM, farnsworth: settings.farnsworth)
    }

    private func finish() {
        guard let s = session else { return }
        let record = AttemptRecord(session: s, source: source)
        history.add(record)
        finishedRecord = record
        phase = .finished
    }

    /// Short sample so the user can hear their audio settings.
    func playTestTone() {
        guard phase != .running else { return }
        let s = TrainerSettings.current()
        player.play(MorseSynth.render(text: "VVV DL1ABC", cpm: s.startCPM, tone: s.tone(sampleRate: player.sampleRate),
                                      farnsworth: s.farnsworth))
    }
}
