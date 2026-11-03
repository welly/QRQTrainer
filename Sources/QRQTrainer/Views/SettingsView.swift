import QRQCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            AudioSettings().tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            TrainingSettings().tabItem { Label("Training", systemImage: "figure.run") }
            CallsignSettings().tabItem { Label("Callsigns", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 520)
        .scenePadding()
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
                        Slider(value: $pitch, in: 300...1200, step: 10).labelsHidden()
                        Text("\(Int(pitch)) Hz").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
                Toggle("Vary pitch for each callsign", isOn: $randomPitch)
                if randomPitch {
                    LabeledContent("Variation") {
                        HStack {
                            Slider(value: $pitchSpread, in: 10...300, step: 10).labelsHidden()
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
                        Slider(value: $riseMs, in: 1...10, step: 0.5).labelsHidden()
                        Text("\(riseMs.formatted()) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Softer edges sound cleaner; they are shortened automatically at very high speeds so dits stay crisp.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Play Test Tone", systemImage: "play.circle") { trainer.playTestTone() }
                    .disabled(trainer.phase == .running)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TrainingSettings: View {
    @AppStorage(Pref.stepPercent) private var stepPercent = 4.0
    @AppStorage(Pref.minCPM) private var minCPM = 25.0
    @AppStorage(Pref.maxCPM) private var maxCPM = 999.0
    @AppStorage(Pref.pauseMs) private var pauseMs = 400.0
    @AppStorage(Pref.showWPM) private var showWPM = false

    var body: some View {
        Form {
            Section {
                Picker("Show speed as", selection: $showWPM) {
                    Text("Characters per minute (CPM)").tag(false)
                    Text("Words per minute (WPM, PARIS)").tag(true)
                }
            }
            Section {
                LabeledContent("Speed change per callsign") {
                    Stepper("\(stepPercent.formatted())%", value: $stepPercent, in: 1...10, step: 0.5)
                        .monospacedDigit()
                }
                LabeledContent("Minimum speed") {
                    Stepper("\(Int(minCPM)) CPM", value: $minCPM, in: 25...300, step: 5).monospacedDigit()
                }
                LabeledContent("Maximum speed") {
                    Stepper("\(Int(maxCPM)) CPM", value: $maxCPM, in: 100...999, step: 10).monospacedDigit()
                }
            } footer: {
                Text("A correct copy raises the speed by this percentage, a miss lowers it. Repeated callsigns don't raise it.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Pause before next callsign") {
                    HStack {
                        Slider(value: $pauseMs, in: 0...2000, step: 50).labelsHidden()
                        Text("\(Int(pauseMs)) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
