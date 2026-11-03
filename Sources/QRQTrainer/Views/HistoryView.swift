import AppKit
import QRQCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(Pref.showWPM) private var showWPM = false
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\AttemptRecord.date, order: .reverse)]
    @State private var showInspector = true
    @State private var confirmDelete = false

    var body: some View {
        let rows = history.records.sorted(using: sortOrder)
        let selected = selection.count == 1 ? history.records.first { $0.id == selection.first } : nil

        Group {
            if history.records.isEmpty {
                ContentUnavailableView("No history", systemImage: "clock.arrow.circlepath",
                                       description: Text("Every finished attempt is saved here automatically."))
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Date", value: \.date) { Text($0.date.shortDateTime) }
                    TableColumn("Source", value: \.source)
                    TableColumn("Score", value: \.score) { Text("\($0.score)").monospacedDigit().fontWeight(.semibold) }
                        .width(70)
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
        }
        .navigationTitle("History")
        .inspector(isPresented: $showInspector) {
            Group {
                if let selected {
                    AttemptInspector(record: selected, showWPM: showWPM)
                } else {
                    ContentUnavailableView("Select an attempt", systemImage: "sidebar.right",
                                           description: Text("See everything that was sent and what you copied."))
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 380, max: 520)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Export CSV", systemImage: "square.and.arrow.up") { exportCSV() }
                    .disabled(history.records.isEmpty)
                Button("Delete", systemImage: "trash") { confirmDelete = true }
                    .disabled(selection.isEmpty)
                Button("Details", systemImage: "sidebar.right") { showInspector.toggle() }
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
    }

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

private struct AttemptInspector: View {
    let record: AttemptRecord
    let showWPM: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(record.score) points").font(.title2.weight(.bold))
                Text("\(record.source) · \(record.date.shortDateTime)").font(.callout).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("Correct").foregroundStyle(.secondary); Text("\(record.correctCount) of \(record.results.count)") }
                GridRow { Text("Peak").foregroundStyle(.secondary); Text(SpeedFormat.string(record.peakCPM, wpm: showWPM)) }
                GridRow { Text("Average").foregroundStyle(.secondary); Text(SpeedFormat.string(record.averageCPM, wpm: showWPM)) }
                GridRow { Text("Response").foregroundStyle(.secondary); Text(ResponseFormat.string(record.averageResponseMs) + " average") }
                GridRow { Text("Step").foregroundStyle(.secondary); Text("\(record.config.stepPercent.formatted())% per copy") }
            }
            .font(.callout)
            AttemptSpeedChart(record: record, showWPM: showWPM)
                .frame(height: 140)
            AttemptResultsTable(record: record, showWPM: showWPM)
        }
        .padding()
    }
}
