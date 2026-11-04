import AppKit
import SwiftUI

@main
struct QRQTrainerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var history: HistoryModel
    @State private var library: CallsignLibrary
    @State private var trainer: TrainerModel

    init() {
        Pref.register()
        let history = HistoryModel()
        let library = CallsignLibrary()
        _history = State(initialValue: history)
        _library = State(initialValue: library)
        _trainer = State(initialValue: TrainerModel(history: history, library: library))
    }

    var body: some Scene {
        Window("QRQ Trainer", id: "main") {
            ContentView()
                .environment(trainer)
                .environment(history)
                .environment(library)
                .frame(minWidth: 880, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Training") {
                Button("Start Attempt") { trainer.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trainer.phase == .running)
                Button("Repeat") { trainer.repeatCurrent() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!trainer.awaitingAnswer)
                Divider()
                Button("End Attempt") { trainer.abort() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(trainer.phase != .running)
                Divider()
                Button(trainer.isTestTonePlaying ? "Stop Test Tone" : "Play Test Tone") { trainer.toggleTestTone() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(trainer.phase == .running)
            }
        }

        Settings {
            SettingsView()
                .environment(trainer)
                .environment(library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no .app bundle) so the window comes to the front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
