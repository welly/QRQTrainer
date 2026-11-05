import Charts
import QRQCore
import SwiftUI

/// What to practise: per-character accuracy and instant recognition (ICR), common mix-ups, and where speed starts to hurt.
struct InsightsView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(TrainerModel.self) private var trainer
    @AppStorage(Pref.showWPM) private var showWPM = false
    @AppStorage("insightsRange") private var range: TimeRange = .last50
    /// Called after "Practise these" starts an attempt, so the window can switch to Train.
    var onPractise: () -> Void = {}

    /// Characters need this many copies before they're ranked, so one unlucky miss doesn't top the list.
    private let minSamples = 5

    enum TimeRange: String, CaseIterable, Identifiable {
        case last10 = "Last 10", last50 = "Last 50", all = "All"
        var id: Self { self }
        var limit: Int? { self == .last10 ? 10 : self == .last50 ? 50 : nil }
    }

    var body: some View {
        let all = history.records.sorted { $0.date < $1.date }
        let records = range.limit.map { Array(all.suffix($0)) } ?? all
        let results = records.flatMap(\.results)
        let analysis = CharacterAnalysis(results: results)
        let weakest = analysis.weakest(5, minSamples: minSamples)
        let strongest = analysis.strongest(5, minSamples: minSamples)
        let rankedCount = analysis.stats.values.filter { $0.sent >= minSamples }.count

        Group {
            if history.records.isEmpty {
                ContentUnavailableView("No attempts yet", systemImage: "lightbulb",
                                       description: Text("Finish an attempt and you'll see which characters you copy best and which need work."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summaryTiles(records: records, analysis: analysis)

                        HStack(alignment: .top, spacing: 16) {
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Label("Needs work", systemImage: "exclamationmark.triangle.fill")
                                            .font(.headline).foregroundStyle(.orange)
                                        Spacer()
                                        if !weakest.isEmpty {
                                            Button("Practise these", systemImage: "play.fill") {
                                                trainer.practise(Set(weakest.map(\.character)))
                                                onPractise()
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(trainer.phase == .running)
                                            .help("Set up Train with groups of only these characters. Go back to your usual mode from the Train screen.")
                                        }
                                    }
                                    if weakest.isEmpty {
                                        notEnoughData
                                    } else {
                                        ForEach(weakest) { stat in
                                            CharacterRow(stat: stat, mixUp: topMixUp(for: stat.character, in: analysis))
                                        }
                                    }
                                }
                            }
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    Label("Instant recognition", systemImage: "bolt.fill")
                                        .font(.headline).foregroundStyle(.green)
                                        .frame(minHeight: 28)
                                        .help("Characters you copy correctly and answer quickly, without having to work them out")
                                    if rankedCount == 0 {
                                        notEnoughData
                                    } else if strongest.isEmpty {
                                        Text("No characters with ⚡ yet. A character earns it when you copy it correctly at least 90% of the time and press Return within 800 ms of the sound ending at least 80% of the time.")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                                    } else {
                                        ForEach(strongest) { stat in CharacterRow(stat: stat, mixUp: nil) }
                                    }
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Every character").font(.headline)
                                    Spacer()
                                    Label("instant", systemImage: "bolt.fill").font(.caption2).foregroundStyle(.secondary)
                                    AccuracyLegend()
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 80), spacing: 8)], spacing: 8) {
                                    ForEach(CharacterAnalysis.alphabet + CharacterClass.symbols.characters.filter { c in c != "/" && analysis.stat(for: c).sent > 0 }, id: \.self) { c in
                                        CharacterCell(stat: analysis.stat(for: c), minSamples: minSamples,
                                                      mixUp: topMixUp(for: c, in: analysis))
                                    }
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Common mix-ups").font(.headline)
                                    let mixUps = Array(analysis.confusions.prefix(8))
                                    if mixUps.isEmpty {
                                        Text("No mistakes recorded. Try a faster start speed.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(mixUps) { MixUpRow(confusion: $0) }
                                    }
                                }
                            }
                            Card {
                                SpeedAccuracyChart(results: results, showWPM: showWPM)
                            }
                        }

                        Text("Based on \(analysis.callsignCount.formatted()) answered items from \(records.count) attempt\(records.count == 1 ? "" : "s"). Characters need \(minSamples) copies before they're ranked. A copy is instant when it's correct and you press Return within 800 ms of the sound ending, plus 200 ms for each further character to type. Characters copied correctly 90% of the time and instantly 80% get ⚡.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .frame(maxWidth: 1080)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItem {
                Picker("Range", selection: $range) {
                    ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Which attempts to analyse")
            }
        }
    }

    private func summaryTiles(records: [AttemptRecord], analysis: CharacterAnalysis) -> some View {
        let sent = analysis.stats.values.reduce(0) { $0 + $1.sent }
        let correct = analysis.stats.values.reduce(0) { $0 + $1.correct }
        let charAccuracy = sent == 0 ? "—" : (Double(correct) / Double(sent)).formatted(.percent.precision(.fractionLength(0)))
        let items = records.flatMap(\.results)
        let itemAccuracy = items.isEmpty ? "—"
            : (Double(items.filter(\.isCorrect).count) / Double(items.count)).formatted(.percent.precision(.fractionLength(0)))
        let instantChars = analysis.stats.values.filter { $0.sent >= minSamples && $0.isInstant }.count
        let ranked = analysis.stats.values.filter { $0.sent >= minSamples }.count
        return HStack(spacing: 16) {
            StatTile(title: "Character accuracy", value: charAccuracy, detail: "\(sent.formatted()) characters", symbol: "character", tint: .blue)
            StatTile(title: "Instant recognition", value: ranked == 0 ? "—" : "\(instantChars) of \(ranked)",
                     detail: "characters with ⚡", symbol: "bolt.fill", tint: .green)
            StatTile(title: "Copy accuracy", value: itemAccuracy, detail: "\(items.count.formatted()) items copied", symbol: "checkmark.circle.fill", tint: .teal)
            StatTile(title: "Peak speed", value: records.map(\.peakCPM).max().map { SpeedFormat.string($0, wpm: showWPM) } ?? "—",
                     symbol: "speedometer", tint: .orange)
            StatTile(title: "Attempts", value: "\(records.count)",
                     detail: records.last.map { "Last \($0.date.formatted(.relative(presentation: .named)))" }, symbol: "number", tint: .purple)
        }
    }

    private var notEnoughData: some View {
        Text("Not enough data yet. Each character needs \(minSamples) copies.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func topMixUp(for c: Character, in analysis: CharacterAnalysis) -> Confusion? {
        analysis.confusions.first { $0.sent == c }
    }
}

// MARK: - Pieces

enum AccuracyColor {
    /// Red below 50%, through orange and yellow, to green at 100%.
    static func color(_ accuracy: Double?) -> Color {
        guard let a = accuracy else { return .secondary.opacity(0.25) }
        let t = max(0, min(1, (a - 0.5) / 0.5))
        return Color(hue: 0.33 * t, saturation: 0.72, brightness: 0.86)
    }
}

private struct AccuracyLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("≤50%").font(.caption2).foregroundStyle(.secondary)
            LinearGradient(colors: [0.5, 0.625, 0.75, 0.875, 1].map { AccuracyColor.color($0) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 90, height: 8)
                .clipShape(Capsule())
            Text("100%").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct MorseGlyph: View {
    let character: Character
    var body: some View {
        Text(Morse.code(for: character).map { $0.replacingOccurrences(of: ".", with: "·").replacingOccurrences(of: "-", with: "–") } ?? "")
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
    }
}

private struct CharacterRow: View {
    let stat: CharacterStat
    let mixUp: Confusion?

    /// The headline figure: how often it was copied instantly, or plain accuracy for untimed (older) attempts.
    private var value: Double { stat.instantRate ?? stat.accuracy ?? 0 }
    private var valueLabel: String {
        value.formatted(.percent.precision(.fractionLength(0))) + (stat.instantRate != nil ? " instant" : " correct")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(stat.character))
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .frame(width: 40, height: 40)
                .background(AccuracyColor.color(value).opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .topTrailing) {
                    if stat.isInstant {
                        Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green).offset(x: 4, y: -4)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    MorseGlyph(character: stat.character)
                    Spacer()
                    Text(valueLabel)
                        .font(.callout.weight(.semibold)).monospacedDigit()
                }
                ProgressView(value: value)
                    .tint(AccuracyColor.color(value))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        let accuracy = (stat.accuracy ?? 0).formatted(.percent.precision(.fractionLength(0)))
        var text = "\(stat.instant) of \(stat.timed) instant · \(accuracy) correct"
        if stat.timed == 0 { text = "\(stat.correct) of \(stat.sent) correct" }
        if let ms = stat.averageThinkMs { text += " · \(ms) ms after the sound" }
        if let m = mixUp {
            text += m.typed.map { " · often typed as \($0)" } ?? " · often left out"
        }
        return text
    }
}

private struct CharacterCell: View {
    let stat: CharacterStat
    let minSamples: Int
    let mixUp: Confusion?

    var body: some View {
        let enough = stat.sent >= minSamples
        VStack(spacing: 2) {
            Text(String(stat.character))
                .font(.system(.title3, design: .monospaced, weight: .bold))
            HStack(spacing: 2) {
                if enough && stat.isInstant { Image(systemName: "bolt.fill").foregroundStyle(.green) }
                Text(enough ? (stat.accuracy ?? 0).formatted(.percent.precision(.fractionLength(0))) : "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption2.weight(.medium))
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(
            enough ? AccuracyColor.color(stat.accuracy).opacity(0.28) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(enough ? AccuracyColor.color(stat.accuracy).opacity(0.5) : Color.clear)
        )
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
    }

    private var help: String {
        guard stat.sent > 0 else { return "\(stat.character): not sent yet" }
        var text = "\(stat.character): \(stat.correct) of \(stat.sent) correct"
        if stat.sent < minSamples { text += " (not enough copies to rank)" }
        if stat.timed > 0 { text += ", \(stat.instant) instant" }
        if let ms = stat.averageThinkMs { text += ", \(ms) ms after the sound on average" }
        if let m = mixUp { text += m.typed.map { ", often typed as \($0)" } ?? ", often left out" }
        return text
    }
}

private struct MixUpRow: View {
    let confusion: Confusion

    var body: some View {
        HStack(spacing: 10) {
            charBadge(confusion.sent)
            VStack(alignment: .leading, spacing: 0) {
                MorseGlyph(character: confusion.sent)
            }
            .frame(width: 70, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
            if let typed = confusion.typed {
                charBadge(typed, tint: .red)
                MorseGlyph(character: typed).frame(width: 70, alignment: .leading)
            } else {
                Text("left out").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("×\(confusion.count)").font(.callout.weight(.semibold)).monospacedDigit()
        }
        .help(confusion.typed.map { "\(confusion.sent) was sent, you typed \($0)" } ?? "\(confusion.sent) was sent, you left it out")
    }

    private func charBadge(_ c: Character, tint: Color = .primary) -> some View {
        Text(String(c))
            .font(.system(.body, design: .monospaced, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SpeedAccuracyChart: View {
    let results: [CallResult]
    let showWPM: Bool

    var body: some View {
        let bands = CharacterAnalysis.accuracyBySpeed(results, width: 25).filter { $0.total >= 3 }
        let breakpoint = bands.first { $0.total >= 5 && $0.accuracy < 0.5 }

        VStack(alignment: .leading, spacing: 10) {
            Text("Accuracy by speed").font(.headline)
            if bands.isEmpty {
                Text("Not enough data yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(bands) { band in
                    BarMark(x: .value("Speed", label(band)), y: .value("Accuracy", band.accuracy))
                        .foregroundStyle(AccuracyColor.color(band.accuracy))
                        .cornerRadius(4)
                    RuleMark(y: .value("Half", 0.5))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { v in
                        AxisGridLine()
                        AxisValueLabel { Text((v.as(Double.self) ?? 0).formatted(.percent.precision(.fractionLength(0)))) }
                    }
                }
                .chartXAxisLabel(SpeedFormat.unit(wpm: showWPM))
                .frame(height: 180)
                Text(breakpoint.map { "Accuracy drops below half from about \(SpeedFormat.string($0.lowerCPM, wpm: showWPM)). Start a little below that to build a solid base." }
                     ?? "You're above 50% at every speed you've reached. Try starting faster.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ band: SpeedBand) -> String {
        "\(SpeedFormat.value(band.lowerCPM, wpm: showWPM))"
    }
}
