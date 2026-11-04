import AppKit
import QRQCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(Pref.showWPM) private var showWPM = false
    /// Share of the height given to the attempts list; the detail gets the rest. Draggable, remembered.
    @AppStorage("historySplit") private var split = 0.42
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\AttemptRecord.date, order: .reverse)]
    @State private var confirmDelete = false

    var body: some View {
        let rows = history.records.sorted(using: sortOrder)
        let selected = selection.count == 1 ? history.records.first { $0.id == selection.first } : nil

        Group {
            if history.records.isEmpty {
                ContentUnavailableView("No history", systemImage: "clock.arrow.circlepath",
                                       description: Text("Every finished attempt is saved here automatically."))
            } else {
                GeometryReader { geo in
                    let available = geo.size.height - SplitHandle.height
                    let topHeight = max(140, min(available - 260, available * split))
                    VStack(spacing: 0) {
                        attemptsTable(rows)
                            .frame(height: topHeight)
                        SplitHandle { dy in
                            split = max(0.15, min(0.85, (topHeight + dy) / max(available, 1)))
                        }
                        Group {
                            if let selected {
                                AttemptDetail(record: selected, showWPM: showWPM)
                            } else {
                                ContentUnavailableView(selection.isEmpty ? "Select an attempt" : "\(selection.count) attempts selected",
                                                       systemImage: "list.bullet.rectangle",
                                                       description: Text("Select one attempt to see every callsign and what you copied."))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup {
                Button("Export CSV", systemImage: "square.and.arrow.up") { exportCSV() }
                    .disabled(history.records.isEmpty)
                    .help("Export all attempts as a CSV file")
                Button("Delete", systemImage: "trash") { confirmDelete = true }
                    .disabled(selection.isEmpty)
                    .help("Delete the selected attempts")
            }
        }
        .confirmationDialog("Delete \(selection.count) attempt\(selection.count == 1 ? "" : "s")?",
                            isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                history.delete(ids: selection)
                selection = []
            }
        } message: {
            Text("This can't be undone.")
        }
        .onAppear(perform: selectNewestIfNeeded)
        .onChange(of: history.records.count) { selectNewestIfNeeded() }
    }

    private func attemptsTable(_ rows: [AttemptRecord]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { Text($0.date.shortDateTime) }
            TableColumn("Source", value: \.source)
            TableColumn("Score", value: \.score) { r in
                Text("\(r.score)").monospacedDigit().fontWeight(.semibold)
                    + Text(" / \(r.maxScore)").monospacedDigit().foregroundColor(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Correct", value: \.correctCount) { Text("\($0.correctCount)/\($0.results.count)").monospacedDigit() }
                .width(70)
            TableColumn("Peak", value: \.peakCPM) { Text(SpeedFormat.string($0.peakCPM, wpm: showWPM)).monospacedDigit() }
                .width(90)
            TableColumn("Start", value: \.config.startCPM) { Text(SpeedFormat.string($0.config.startCPM, wpm: showWPM)).monospacedDigit() }
                .width(90)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Delete", role: .destructive) {
                selection = ids
                confirmDelete = true
            }
        }
        .onDeleteCommand { if !selection.isEmpty { confirmDelete = true } }
    }

    @MainActor
    private func selectNewestIfNeeded() {
        let ids = Set(history.records.map(\.id))
        selection = selection.intersection(ids)
        if selection.isEmpty, let newest = history.records.max(by: { $0.date < $1.date }) {
            selection = [newest.id]
        }
    }

    @MainActor
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "QRQTrainer-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try HistoryStore.csv(history.records).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            history.errorMessage = "Couldn't export: \(error.localizedDescription)"
        }
    }
}

/// Horizontal divider that can be dragged to resize the split.
private struct SplitHandle: View {
    static let height: CGFloat = 9
    let onDrag: (CGFloat) -> Void
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            Capsule().fill(.tertiary).frame(width: 36, height: 4)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.background)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    onDrag(value.translation.height - lastTranslation)
                    lastTranslation = value.translation.height
                }
                .onEnded { _ in lastTranslation = 0 }
        )
        .accessibilityLabel("Resize")
    }
}

/// Full detail for one attempt: summary and speed chart on the left, every callsign on the right.
private struct AttemptDetail: View {
    let record: AttemptRecord
    let showWPM: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(record.score)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("of \(record.maxScore) points").foregroundStyle(.secondary)
                        }
                        Text("\(record.source) · \(record.date.shortDateTime)").font(.callout).foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        row("Correct", "\(record.correctCount) of \(record.results.count) (\(record.accuracy.formatted(.percent.precision(.fractionLength(0)))))")
                        row("Peak speed", SpeedFormat.string(record.peakCPM, wpm: showWPM))
                        row("Average speed", SpeedFormat.string(record.averageCPM, wpm: showWPM))
                        row("Started at", SpeedFormat.string(record.config.startCPM, wpm: showWPM))
                        if let t = record.averageResponseTime { row("Average answer", ResponseFormat.string(t)) }
                        row("Speed step", "\(record.config.stepPercent.formatted())% per callsign")
                        row("Time penalty", record.config.responseTimePenalty ? "On" : "Off")
                    }
                    .font(.callout)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speed through the attempt").font(.subheadline.weight(.semibold))
                        AttemptSpeedChart(record: record, showWPM: showWPM)
                            .frame(height: 170)
                    }
                }
                .padding(20)
            }
            .frame(width: 340)
            .background(.background.secondary)

            Divider()

            AttemptResultsTable(record: record, showWPM: showWPM)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ title: String, _ value: String) -> GridRow<TupleView<(Text, Text)>> {
        GridRow {
            Text(title).foregroundColor(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
