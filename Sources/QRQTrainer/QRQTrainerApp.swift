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
            // No Edit or Help menus: nothing to edit, and no help book yet. Emptied here, removed in AppDelegate.
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .help) {}
            CommandMenu("Training") {
                Button("Start Attempt") { trainer.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trainer.phase == .running)
                Button("Repeat Callsign") { trainer.repeatCurrent() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!trainer.awaitingAnswer)
                Divider()
                Button("End Attempt") { trainer.abort() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(trainer.phase != .running)
                Divider()
                Button("Play Test Tone") { trainer.playTestTone() }
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
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Stop AppKit adding "Start Dictation…" and "Emoji & Symbols" (which would recreate an Edit menu).
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no .app bundle) so the window comes to the front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { MainActor.assumeIsolated { Self.removeUnusedMenus() } }
        // SwiftUI can rebuild the main menu (e.g. when windows change), so prune again when items are added.
        NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let menu = note.object as? NSMenu, menu === NSApp.mainMenu else { return }
                Self.removeUnusedMenus()
            }
        }
    }

    @MainActor
    static func removeUnusedMenus() {
        guard let menu = NSApp.mainMenu else { return }
        let help = NSApp.helpMenu
        for item in menu.items {
            let isHelp = help != nil && item.submenu === help
            if isHelp || item.title == "Edit" || item.title == "Help" { menu.removeItem(item) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
