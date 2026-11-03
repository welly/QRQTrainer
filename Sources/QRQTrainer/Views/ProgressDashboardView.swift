import Charts
import QRQCore
import SwiftUI

struct ProgressDashboardView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(Pref.showWPM) private var showWPM = false
    @State private var source: String = "Generated"
    @State private var range: TimeRange = .all

    enum TimeRange: String, CaseIterable, Identifiable {
        case last10 = "Last 10", last50 = "Last 50", all = "All"
        var id: Self { self }
        var limit: Int? { self == .last10 ? 10 : self == .last50 ? 50 : nil }
    }

    var body: some View {
        let all = history.records(source: source)
        let records = range.limit.map { Array(all.suffix($0)) } ?? all
        let points = records.enumerated().map { ChartPoint(n: $0.offset + 1, record: $0.element) }

        Group {
            if history.records.isEmpty {
                ContentUnavailableView("No attempts yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Finish an attempt in Train and your progress will appear here."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 16) {
                            StatTile(title: "Best score", value: all.map(\.score).max().map(String.init) ?? "—",
                                     symbol: "trophy.fill", tint: .yellow)
                            StatTile(title: "Peak speed", value: all.map(\.peakCPM).max().map { SpeedFormat.string($0, wpm: showWPM) } ?? "—",
                                     symbol: "speedometer", tint: .orange)
                            StatTile(title: "Accuracy (last 10)", value: accuracy(Array(all.suffix(10))),
                                     symbol: "target", tint: .green)
                            StatTile(title: "Attempts", value: "\(all.count)",
                                     detail: all.last.map { "Last \($0.date.formatted(.relative(presentation: .named)))" },
                                     symbol: "number", tint: .blue)
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Score").font(.headline)
                                if points.isEmpty {
                                    emptyChart
                                } else {
                                    Chart {
                                        ForEach(points) { p in
                                            AreaMark(x: .value("Attempt", p.n), y: .value("Score", p.record.score))
                                                .interpolationMethod(.monotone)
                                                .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                                            LineMark(x: .value("Attempt", p.n), y: .value("Score", p.record.score))
                                                .interpolationMethod(.monotone)
                                                .foregroundStyle(Color.accentColor)
                                            PointMark(x: .value("Attempt", p.n), y: .value("Score", p.record.score))
                                                .foregroundStyle(Color.accentColor)
                                                .symbolSize(24)
                                        }
                                        if let best = records.map(\.score).max() {
                                            RuleMark(y: .value("Best", best))
                                                .foregroundStyle(.yellow)
                                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                                .annotation(position: .top, alignment: .leading) {
                                                    Text("Best \(best)").font(.caption).foregroundStyle(.secondary)
                                                }
                                        }
                                    }
                                    .chartXAxisLabel("Attempt")
                                    .frame(height: 220)
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Speed").font(.headline)
                                if points.isEmpty {
                                    emptyChart
                                } else {
                                    Chart(points) { p in
                                        LineMark(x: .value("Attempt", p.n), y: .value("Speed", speed(p.record.peakCPM)))
                                            .foregroundStyle(by: .value("Series", "Peak"))
                                            .interpolationMethod(.monotone)
                                        LineMark(x: .value("Attempt", p.n), y: .value("Speed", speed(p.record.averageCPM)))
                                            .foregroundStyle(by: .value("Series", "Average"))
                                            .interpolationMethod(.monotone)
                                    }
                                    .chartForegroundStyleScale(["Peak": Color.orange, "Average": Color.blue])
                                    .chartYAxisLabel(SpeedFormat.unit(wpm: showWPM))
                                    .chartXAxisLabel("Attempt")
                                    .chartYScale(domain: .automatic(includesZero: false))
                                    .frame(height: 220)
                                }
                            }
                        }

                        Text("Scores are only comparable between attempts with the same source and length.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .frame(maxWidth: 1080)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Progress")
        .toolbar {
            ToolbarItemGroup {
                Picker("Source", selection: $source) {
                    ForEach(sourceOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Range", selection: $range) {
                    ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear {
            if !sourceOptions.contains(source), let first = history.records.last?.source { source = first }
        }
    }

    private var sourceOptions: [String] {
        let s = history.sources
        return s.isEmpty ? ["Generated"] : s
    }

    private var emptyChart: some View {
        Text("No attempts with this source yet.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func speed(_ cpm: Double) -> Double { showWPM ? Morse.wpm(fromCPM: cpm) : cpm }

    private func accuracy(_ records: [AttemptRecord]) -> String {
        let total = records.reduce(0) { $0 + $1.results.count }
        guard total > 0 else { return "—" }
        let correct = records.reduce(0) { $0 + $1.correctCount }
        return (Double(correct) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct ChartPoint: Identifiable {
    let n: Int
    let record: AttemptRecord
    var id: UUID { record.id }
}
