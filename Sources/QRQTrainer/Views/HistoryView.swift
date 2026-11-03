import AppKit
import QRQCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @AppStorage(Pref.showWPM) private var showWPM = false
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\AttemptRecord.date, order: .reverse)]
    @State private var showDetails = true
    @State private var confirmDelete = false

    var body: some View {
        let rows = history.records.sorted(using: sortOrder)
        let selected = selection.count == 1 ? history.records.first { $0.id == selection.first } : nil

        Group {
            if history.records.isEmpty {
                ContentUnavailableView("No history", systemImage: "clock.arrow.circlepath",
                                       description: Text("Every finished attempt is saved here automatically."))
            } else {
                VSplitView {
                    Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Date", value: \.date) { Text($0.date.shortDateTime) }
                        .width(min: 130, ideal: 170)
                    TableColumn("Source", value: \.source)
                        .width(min: 140, ideal: 260)
                    TableColumn("Score", value: \.score) { Text("\($0.score)").monospacedDigit().fontWeight(.semibold) }
                        .width(min: 50, ideal: 70)
                    TableColumn("Correct", value: \.correctCount) { Text("\($0.correctCount)/\($0.results.count)").monospacedDigit() }
                        .width(min: 50, ideal: 70)
                    TableColumn("Peak", value: \.peakCPM) { Text(SpeedFormat.string($0.peakCPM, wpm: showWPM)).monospacedDigit() }
                        .width(min: 60, ideal: 90)
                    TableColumn("Start", value: \.config.startCPM) { Text(SpeedFormat.string($0.config.startCPM, wpm: showWPM)).monospacedDigit() }
                        .width(min: 60, ideal: 90)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Delete", role: .destructive) {
                        selection = ids
                        confirmDelete = true
                    }
                }
                .onDeleteCommand { if !selection.isEmpty { confirmDelete = true } }
                    .frame(maxWidth: .infinity, minHeight: 140, idealHeight: 220)

                    if showDetails {
                        Group {
                            if let selected {
                                AttemptDetail(record: selected, showWPM: showWPM)
                            } else if selection.isEmpty {
                                ContentUnavailableView("No attempt selected", systemImage: "rectangle.bottomhalf.inset.filled",
                                                       description: Text("Select an attempt above to see everything that was sent and what you copied."))
                            } else {
                                ContentUnavailableView("\(selection.count) attempts selected", systemImage: "rectangle.bottomhalf.inset.filled",
                                                       description: Text("Select a single attempt to see its details."))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 260, idealHeight: 420, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup {
                Button("Export CSV", systemImage: "square.and.arrow.up") { exportCSV() }
                    .disabled(history.records.isEmpty)
                Button("Delete", systemImage: "trash") { confirmDelete = true }
                    .disabled(selection.isEmpty)
                Button(showDetails ? "Hide Details" : "Show Details", systemImage: "rectangle.bottomhalf.inset.filled") { showDetails.toggle() }
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

/// Details of one attempt, shown under the history list: summary and speed chart on the left,
/// every item on the right.
private struct AttemptDetail: View {
    let record: AttemptRecord
    let showWPM: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.score) points").font(.title2.weight(.bold))
                    Text(record.source).font(.callout)
                    Text(record.date.shortDateTime).font(.callout).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("Correct", "\(record.correctCount) of \(record.results.count)")
                    row("Peak speed", SpeedFormat.string(record.peakCPM, wpm: showWPM))
                    row("Average speed", SpeedFormat.string(record.averageCPM, wpm: showWPM))
                    row("Start speed", SpeedFormat.string(record.config.startCPM, wpm: showWPM))
                    row("Avg response (ms)", ResponseFormat.string(record.averageResponseMs))
                    row("Speed step", "\(record.config.stepPercent.formatted())% per copy")
                }
                .font(.callout)
                AttemptSpeedChart(record: record, showWPM: showWPM)
                    .frame(minHeight: 120, maxHeight: 180)
                Spacer(minLength: 0)
            }
            .frame(width: 300)

            AttemptResultsTable(record: record, showWPM: showWPM)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
