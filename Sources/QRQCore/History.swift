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
        var lines = ["date,source,callsigns,score,correct,peak_cpm,peak_wpm,average_cpm,start_cpm,average_response_ms"]
        for r in records.sorted(by: { $0.date < $1.date }) {
            // Built field by field: one big array literal is too slow for some compilers to type-check.
            let source = "\"" + r.source.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            var fields: [String] = [iso.string(from: r.date), source]
            fields.append(String(r.results.count))
            fields.append(String(r.score))
            fields.append(String(r.correctCount))
            fields.append(String(Int(r.peakCPM.rounded())))
            fields.append(String(Int(Morse.wpm(fromCPM: r.peakCPM).rounded())))
            fields.append(String(Int(r.averageCPM.rounded())))
            fields.append(String(Int(r.config.startCPM.rounded())))
            fields.append(r.averageResponseMs.map { String($0) } ?? "")
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
