import AppKit
import QRQCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(TrainerModel.self) private var trainer

    var body: some View {
        TabView {
            AudioSettings().tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            TrainingSettings().tabItem { Label("Training", systemImage: "figure.run") }
            CharacterSettings().tabItem { Label("Characters", systemImage: "character.textbox") }
            CallsignSettings().tabItem { Label("Callsigns", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 520)
        .scenePadding()
        // Don't leave the test tone playing once Settings is closed. SwiftUI may keep this view alive when the
        // window closes, so watch for the window closing as well as the view disappearing.
        .onDisappear { trainer.stopTestTone() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if let window = note.object as? NSWindow, window.identifier?.rawValue.contains("Settings") == true {
                trainer.stopTestTone()
            }
        }
    }
}

private struct AudioSettings: View {
    @Environment(TrainerModel.self) private var trainer
    @AppStorage(Pref.pitch) private var pitch = 600.0
    @AppStorage(Pref.randomPitch) private var randomPitch = false
    @AppStorage(Pref.pitchSpread) private var pitchSpread = 100.0
    @AppStorage(Pref.volume) private var volume = 0.6
    @AppStorage(Pref.riseMs) private var riseMs = 5.0

    var body: some View {
        Form {
            Section {
                LabeledContent("Pitch") {
                    HStack {
                        Slider(value: snapped($pitch, to: 10), in: 300...1200).labelsHidden()
                        Text("\(Int(pitch)) Hz").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
                Toggle("Vary pitch for each callsign", isOn: $randomPitch)
                if randomPitch {
                    LabeledContent("Variation") {
                        HStack {
                            Slider(value: snapped($pitchSpread, to: 10), in: 10...300).labelsHidden()
                            Text("± \(Int(pitchSpread)) Hz").monospacedDigit().frame(width: 64, alignment: .trailing)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $volume, in: 0.05...1).labelsHidden()
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Edge shaping") {
                    HStack {
                        Slider(value: snapped($riseMs, to: 0.5), in: 1...10).labelsHidden()
                        Text("\(riseMs.formatted()) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Softer edges sound cleaner; they are shortened automatically at very high speeds so dits stay crisp.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(trainer.isTestTonePlaying ? "Stop Test Tone" : "Play Test Tone",
                       systemImage: trainer.isTestTonePlaying ? "stop.circle" : "play.circle") { trainer.toggleTestTone() }
                    .disabled(trainer.phase == .running)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TrainingSettings: View {
    @AppStorage(Pref.stepPercent) private var stepPercent = 4.0
    @AppStorage(Pref.pauseMs) private var pauseMs = 400.0
    @AppStorage(Pref.showWPM) private var showWPM = false
    @AppStorage(Pref.farnsworth) private var farnsworth = false
    @AppStorage(Pref.farnsworthPercent) private var farnsworthPercent = 60.0
    @AppStorage(Pref.startCPM) private var startCPM = 100.0

    var body: some View {
        Form {
            Section {
                Picker("Show speed as", selection: $showWPM) {
                    Text("Characters per minute (CPM)").tag(false)
                    Text("Words per minute (WPM, PARIS)").tag(true)
                }
            }
            Section {
                LabeledContent("Speed change per copy") {
                    Stepper("\(stepPercent.formatted())%", value: $stepPercent, in: 1...10, step: 0.5)
                        .monospacedDigit()
                }
            } footer: {
                Text("A correct copy raises the speed by this percentage, a miss lowers it. Repeats don't raise it.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Farnsworth spacing", isOn: $farnsworth)
                if farnsworth {
                    LabeledContent("Overall speed") {
                        HStack {
                            Slider(value: snapped($farnsworthPercent, to: 5), in: 20...95).labelsHidden()
                            Text("\(Int(farnsworthPercent))%").monospacedDigit().frame(width: 64, alignment: .trailing)
                        }
                    }
                }
            } footer: {
                Text(farnsworthFooter).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Pause before next item") {
                    HStack {
                        Slider(value: snapped($pauseMs, to: 50), in: 0...2000).labelsHidden()
                        Text("\(Int(pauseMs)) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var farnsworthFooter: String {
        let charSpeed = SpeedFormat.string(startCPM, wpm: showWPM)
        let overall = SpeedFormat.string(startCPM * farnsworthPercent / 100, wpm: showWPM)
        let example = farnsworth ? " At your start speed, characters are sent at \(charSpeed) with an overall speed of \(overall)." : ""
        return "Sends each character at full speed but stretches the gaps between characters and words, "
            + "so you learn the sound of fast characters with more time to think.\(example) "
            + "Attempts with Farnsworth spacing are scored separately."
    }
}

private struct CharacterSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose which characters character-group modes may send. A mode only uses the classes in its name, so Letters ignores the figures and symbols chosen here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CharacterPicker(classes: CharacterClass.allCases)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CallsignSettings: View {
    @Environment(CallsignLibrary.self) private var library
    @AppStorage(Pref.useImported) private var useImported = false
    @AppStorage(Pref.portablePercent) private var portablePercent = 0.0
    @AppStorage(Pref.prefixedPercent) private var prefixedPercent = 0.0
    @State private var importing = false
    @State private var message: String?
    @State private var preview: [String] = []

    var body: some View {
        Form {
            Section {
                Picker("Source", selection: $useImported) {
                    Text("Generated callsigns").tag(false)
                    Text("Imported list").tag(true)
                }
                .pickerStyle(.radioGroup)
                .disabled(library.calls.isEmpty && !useImported)
            } footer: {
                Text("Real callsigns from a file such as Super Check Partial's MASTER.SCP feel most like on-air copying.")
                    .foregroundStyle(.secondary)
            }

            Section("Imported list") {
                if let name = library.name, !library.calls.isEmpty {
                    LabeledContent(name, value: "\(library.calls.count.formatted()) callsigns")
                }
                HStack {
                    Button(library.calls.isEmpty ? "Import File…" : "Replace…", systemImage: "square.and.arrow.down") { importing = true }
                    if !library.calls.isEmpty {
                        Button("Remove", role: .destructive) { library.remove() }
                    }
                }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            }

            Section {
                LabeledContent("Portable / mobile (/P, /M)") {
                    Stepper("\(Int(portablePercent))%", value: $portablePercent, in: 0...50, step: 5).monospacedDigit()
                }
                LabeledContent("Foreign prefix (EA8/…)") {
                    Stepper("\(Int(prefixedPercent))%", value: $prefixedPercent, in: 0...50, step: 5).monospacedDigit()
                }
                LabeledContent("Examples") {
                    Text(preview.joined(separator: "  ")).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            } header: {
                Text("Generated callsigns")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .data]) { result in
            switch result {
            case .success(let url):
                do {
                    let count = try library.importFile(url)
                    useImported = true
                    message = "Imported \(count.formatted()) callsigns."
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .onAppear(perform: refreshPreview)
        .onChange(of: portablePercent) { refreshPreview() }
        .onChange(of: prefixedPercent) { refreshPreview() }
    }

    private func refreshPreview() {
        var rng = SystemRandomNumberGenerator()
        preview = CallsignGenerator(portableProbability: portablePercent / 100, prefixedProbability: prefixedPercent / 100)
            .generate(5, using: &rng)
    }
}
