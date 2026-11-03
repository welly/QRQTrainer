import Foundation

/// JSON file persistence for attempt history.
public struct HistoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// `~/Library/Application Support/QRQTrainer/<name>`
    public static func supportFile(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("QRQTrainer", isDirectory: true).appendingPathComponent(name)
    }

    public static var defaultURL: URL { supportFile("history.json") }

    public func load() throws -> [AttemptRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AttemptRecord].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ records: [AttemptRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
    }

    public static func csv(_ records: [AttemptRecord]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["date,source,callsigns,score,correct,peak_cpm,peak_wpm,average_cpm,start_cpm"]
        for r in records.sorted(by: { $0.date < $1.date }) {
            let source = "\"" + r.source.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            lines.append([
                iso.string(from: r.date), source, String(r.results.count), String(r.score), String(r.correctCount),
                String(Int(r.peakCPM.rounded())), String(Int(Morse.wpm(fromCPM: r.peakCPM).rounded())),
                String(Int(r.averageCPM.rounded())), String(Int(r.config.startCPM.rounded())),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
