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
        refreshNeedsWork()
    }

    /// Which attempts Insights (and so Needs work) looks at.
    enum InsightsRange: String, CaseIterable, Identifiable {
        case last10 = "Last 10", last50 = "Last 50", all = "All"
        var id: Self { self }
        var limit: Int? { self == .last10 ? 10 : self == .last50 ? 50 : nil }
        static var current: InsightsRange {
            InsightsRange(rawValue: UserDefaults.standard.string(forKey: Pref.insightsRange) ?? "") ?? .last50
        }
    }

    /// Characters need this many copies before they're ranked, so one unlucky miss doesn't top the list.
    static let minSamples = 5

    /// The attempts in `range`, oldest first.
    func records(in range: InsightsRange) -> [AttemptRecord] {
        let all = records.sorted { $0.date < $1.date }
        return range.limit.map { Array(all.suffix($0)) } ?? all
    }

    /// The five characters that most need work, as Insights shows them.
    func needsWork(in range: InsightsRange = .current) -> [CharacterStat] {
        CharacterAnalysis(results: records(in: range).flatMap(\.results)).weakest(5, minSamples: Self.minSamples)
    }

    /// Saves the Needs work characters where the Needs work mode reads them. Call when history or the range changes.
    func refreshNeedsWork() {
        let chars = Set(needsWork().map(\.character))
        let value = String(CharacterClass.allCharacters.filter(chars.contains))
        if UserDefaults.standard.string(forKey: Pref.needsWork) != value {
            UserDefaults.standard.set(value, forKey: Pref.needsWork)
        }
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
        refreshNeedsWork()
    }

    func delete(ids: Set<UUID>) {
        records.removeAll { ids.contains($0.id) }
        persist()
        refreshNeedsWork()
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

    /// What one item of the running (or next) attempt is called: "callsign", "group", "word" or "code".
    var itemName: String { (phase == .idle ? TrainerSettings.current() : settings).itemName }

    /// False when the character selection leaves nothing to send in the chosen mode.
    func canStart() -> Bool {
        let s = TrainerSettings.current()
        if s.usesGroups { return s.groupGenerator.canGenerate }
        if s.mode == .words { return !s.wordList.isEmpty }
        return true
    }

    var isNewBest: Bool {
        guard let record = finishedRecord, record.score > 0 else { return false }
        return record.score > (previousBest ?? 0)
    }

    /// Switches to the Needs work mode: groups of the characters Insights says need work.
    func practiseNeedsWork() {
        history.refreshNeedsWork()
        UserDefaults.standard.set(TrainerMode.needsWork.rawValue, forKey: Pref.mode)
    }

    /// Starts an attempt in the current mode.
    func start() {
        guard phase != .running else { return }
        stopTestTone()
        settings = .current()
        var rng = SystemRandomNumberGenerator()
        let calls: [String]
        if settings.usesGroups {
            calls = settings.groupGenerator.generate(settings.count, using: &rng)
        } else {
            switch settings.mode {
            case .callsigns:
                if settings.useImported, !library.calls.isEmpty {
                    calls = CallsignList.pick(settings.count, from: library.calls, using: &rng)
                } else {
                    calls = CallsignGenerator(portableProbability: settings.portablePercent / 100,
                                              prefixedProbability: settings.prefixedPercent / 100)
                        .generate(settings.count, using: &rng)
                }
            case .words:
                calls = CallsignList.pick(settings.count, from: settings.wordList, using: &rng)
            default:
                calls = CallsignList.pick(settings.count, from: HamCodes.all, using: &rng)
            }
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

    /// True while the test tone is playing.
    private(set) var isTestTonePlaying = false

    /// Plays a short "VVV" so the user can hear their audio settings, or stops it if it's already playing.
    func toggleTestTone() {
        if isTestTonePlaying { stopTestTone(); return }
        guard phase != .running else { return }
        let s = TrainerSettings.current()
        isTestTonePlaying = true
        player.play(MorseSynth.render(text: "VVV", cpm: s.startCPM, tone: s.tone(sampleRate: player.sampleRate),
                                      farnsworth: s.farnsworth)) { [weak self] in
            self?.isTestTonePlaying = false
        }
    }

    func stopTestTone() {
        guard isTestTonePlaying else { return }
        player.stop()
        isTestTonePlaying = false
    }
}
