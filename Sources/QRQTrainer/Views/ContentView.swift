import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case train, progress, history
    var id: Self { self }

    var title: String {
        switch self {
        case .train: "Train"
        case .progress: "Progress"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .train: "waveform"
        case .progress: "chart.xyaxis.line"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @Environment(TrainerModel.self) private var trainer
    @Environment(HistoryModel.self) private var history
    @State private var selection: SidebarItem? = .train
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(item == .history ? history.records.count : 0)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            switch selection ?? .train {
            case .train: TrainView()
            case .progress: ProgressDashboardView()
            case .history: HistoryView()
            }
        }
        // Keep the user focused on copying: collapse the sidebar while an attempt runs.
        .onChange(of: trainer.phase) { _, phase in
            withAnimation {
                if phase == .running {
                    selection = .train
                    columnVisibility = .detailOnly
                } else {
                    columnVisibility = .all
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { history.errorMessage != nil },
            set: { if !$0 { history.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(history.errorMessage ?? "")
        }
    }
}

private struct SidebarFooter: View {
    @Environment(TrainerModel.self) private var trainer
    @AppStorage(Pref.useImported) private var useImported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Callsigns").font(.caption).foregroundStyle(.secondary)
            Label(trainer.sourceName(useImported: useImported), systemImage: "antenna.radiowaves.left.and.right")
                .font(.callout)
                .lineLimit(1)
            SettingsLink {
                Text("Change…").font(.caption)
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
