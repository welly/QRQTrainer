import Charts
import QRQCore
import SwiftUI

struct TrainView: View {
    @Environment(TrainerModel.self) private var trainer

    var body: some View {
        Group {
            switch trainer.phase {
            case .idle: ReadyView()
            case .running: CopyingView()
            case .finished: ResultsView()
            }
        }
        .animation(.smooth(duration: 0.35), value: trainer.phase)
        .navigationTitle("Train")
    }
}

// MARK: - Ready

private struct ReadyView: View {
    @Environment(TrainerModel.self) private var trainer
    @Environment(HistoryModel.self) private var history
    @AppStorage(Pref.startCPM) private var startCPM = 100.0
    @AppStorage(Pref.count) private var count = 50
    @AppStorage(Pref.showWPM) private var showWPM = false
    private var prefs = SourcePrefs()

    var body: some View {
        let source = trainer.sourceName()
        let item = prefs.mode.itemName
        let attempts = history.records(source: source)
        let best = history.best(source: source)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready to copy")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Listen to each \(item), type it, press Return. Copy correctly and the speed goes up; miss and it drops.")
                        .foregroundStyle(.secondary)
                }

                WhatToCopyCard()

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Start speed").font(.headline)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(SpeedFormat.value(startCPM, wpm: showWPM))")
                                    .font(.system(size: 56, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: startCPM))
                                    .animation(.snappy, value: startCPM)
                                Picker("Unit", selection: $showWPM) {
                                    Text("CPM").tag(false)
                                    Text("WPM").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .fixedSize()
                                Spacer()
                                Text(SpeedFormat.secondary(startCPM, wpm: showWPM))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $startCPM, in: 25...600, step: 5) {
                                Text("Start speed")
                            } minimumValueLabel: {
                                Text("25").font(.caption)
                            } maximumValueLabel: {
                                Text("600").font(.caption)
                            }
                            .labelsHidden()
                            if let best {
                                Button("Use \(SpeedFormat.string(suggestedStart(best), wpm: showWPM)) (80% of your peak)") {
                                    withAnimation { startCPM = suggestedStart(best) }
                                }
                                .buttonStyle(.link)
                                .font(.callout)
                            }
                            if prefs.farnsworth {
                                Label("Farnsworth spacing: overall \(Int(prefs.farnsworthPercent))% of character speed",
                                      systemImage: "arrow.left.and.right")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(item.capitalized)s per attempt").font(.headline)
                            Picker("\(item.capitalized)s", selection: $count) {
                                ForEach([10, 25, 50, 100], id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text(count == 50 ? "50 is the classic attempt length, so scores stay comparable."
                                             : count > 50 ? "Long attempts build stamina." : "Shorter attempts are good for warming up.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Divider()
                            Label(source, systemImage: prefs.mode.symbol)
                                .font(.callout)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: 320)
                }

                HStack(spacing: 16) {
                    StatTile(title: "Best score", value: best.map { "\($0.score)" } ?? "—",
                             detail: best?.date.formatted(date: .abbreviated, time: .omitted), symbol: "trophy.fill", tint: .yellow)
                    StatTile(title: "Peak speed", value: attempts.map(\.peakCPM).max().map { SpeedFormat.string($0, wpm: showWPM) } ?? "—",
                             symbol: "speedometer", tint: .orange)
                    StatTile(title: "Attempts", value: "\(attempts.count)",
                             detail: attempts.last.map { "Last: \($0.score) points" }, symbol: "number", tint: .blue)
                }

                HStack(spacing: 14) {
                    Button {
                        trainer.start()
                    } label: {
                        Label("Start Attempt", systemImage: "play.fill")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .disabled(!trainer.canStart())
                    KeyHint("⌘↩")
                    Spacer()
                    Button("Test tone", systemImage: "speaker.wave.2") { trainer.playTestTone() }
                        .buttonStyle(.bordered)
                }

                Card {
                    HStack(alignment: .top, spacing: 24) {
                        tip("ear", "Copy in your head", "Don't write while listening. Hear the whole \(item), then type it.")
                        tip("arrow.counterclockwise", "Repeat with F6 / ⌘R", "Plays it again, but that \(item) scores nothing.")
                        tip("chart.line.uptrend.xyaxis", "Speed adapts", "Every correct copy is faster, every miss is slower.")
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
    }

    private func suggestedStart(_ best: AttemptRecord) -> Double {
        max(25, min(600, (best.peakCPM * 0.8 / 5).rounded() * 5))
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Copying

private struct CopyingView: View {
    @Environment(TrainerModel.self) private var trainer
    @AppStorage(Pref.showWPM) private var showWPM = false
    @FocusState private var fieldFocused: Bool
    @State private var keys = KeyMonitor()

    var body: some View {
        @Bindable var trainer = trainer
        let session = trainer.session

        VStack(spacing: 0) {
            HStack {
                Text("\(trainer.itemName.capitalized) \(min((session?.index ?? 0) + 1, session?.callsigns.count ?? 0)) of \(session?.callsigns.count ?? 0)")
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text("\(session?.score ?? 0)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(session?.score ?? 0)))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer(minLength: 16)

            SpeedRing(
                cpm: session?.currentCPM ?? 0,
                progress: session?.progress ?? 0,
                playing: trainer.isPlaying,
                trend: trainer.lastResult.map { $0.isCorrect ? 1 : -1 } ?? 0,
                showWPM: showWPM
            )

            Spacer(minLength: 24)

            TextField(trainer.itemName.capitalized, text: $trainer.entry, prompt: Text(trainer.awaitingAnswer ? "Type what you heard" : "Get ready…"))
                .textFieldStyle(.plain)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .onSubmit { trainer.submit() }
                .onChange(of: trainer.entry) { _, new in
                    let clean = String(Self.normalised(new).filter { Morse.code(for: $0) != nil }.prefix(20))
                    if clean != new { trainer.entry = clean }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .frame(maxWidth: 560)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(fieldFocused ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: fieldFocused ? 2 : 1)
                )
                .padding(.horizontal, 32)

            FeedbackRow(result: trainer.lastResult, showWPM: showWPM)
                .frame(height: 64)
                .padding(.top, 16)

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Button("Repeat", systemImage: "arrow.counterclockwise") { trainer.repeatCurrent() }
                    .disabled(!trainer.awaitingAnswer)
                KeyHint("F6")
                Text("no points for a repeat").font(.caption).foregroundStyle(.secondary)
                Spacer()
                KeyHint("esc")
                Button("End Attempt", systemImage: "xmark", role: .destructive) { trainer.abort() }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .onAppear {
            fieldFocused = true
            keys.install { event in
                switch event.keyCode {
                case 97:  // F6
                    trainer.repeatCurrent()
                    return true
                case 53:  // Esc
                    trainer.abort()
                    return true
                default:
                    return false
                }
            }
        }
        .onDisappear { keys.remove() }
        .onChange(of: trainer.awaitingAnswer) { _, waiting in if waiting { fieldFocused = true } }
    }

    /// Upper-cases and turns typographic quotes back into the plain ones Morse has codes for.
    static func normalised(_ text: String) -> String {
        text.uppercased()
            .replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
    }
}

/// The big live speed readout, with a ring showing progress through the attempt.
private struct SpeedRing: View {
    let cpm: Double
    let progress: Double
    let playing: Bool
    let trend: Int
    let showWPM: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(colors: [.accentColor.opacity(0.5), .accentColor], center: .center),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)

            VStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(playing ? Color.accentColor : Color.secondary.opacity(0.4))
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: playing)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(SpeedFormat.value(cpm, wpm: showWPM))")
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: cpm))
                        .animation(.snappy, value: cpm)
                    if trend != 0 {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(trend > 0 ? .green : .red)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(SpeedFormat.unit(wpm: showWPM) + "  ·  " + SpeedFormat.secondary(cpm, wpm: showWPM))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(width: 280, height: 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed \(SpeedFormat.string(cpm, wpm: showWPM)), \(Int(progress * 100)) percent complete")
    }
}

/// Shows the last answer: what was sent, what you typed (mistakes highlighted) and the points earned.
private struct FeedbackRow: View {
    let result: CallResult?
    let showWPM: Bool

    var body: some View {
        ZStack {
            if let r = result {
                HStack(spacing: 16) {
                    Image(systemName: r.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(r.isCorrect ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.sent).font(.title3.monospaced().weight(.semibold))
                        if !r.isCorrect {
                            Diff.received(r).font(.body.monospaced())
                        } else if r.repeated {
                            Text("Repeated").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider().frame(height: 36)
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("+\(r.points)").font(.title3.weight(.bold)).monospacedDigit()
                                .foregroundStyle(r.points > 0 ? Color.primary : Color.secondary)
                            Text("/ \(r.maxPoints)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text(SpeedFormat.string(r.cpm, wpm: showWPM)).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: "timer").font(.callout).foregroundStyle(.secondary)
                        Text(ResponseFormat.withUnit(r.responseMs)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Response time \(ResponseFormat.withUnit(r.responseMs))")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .id(r.index)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: result?.index)
    }
}

// MARK: - Results

private struct ResultsView: View {
    @Environment(TrainerModel.self) private var trainer
    @AppStorage(Pref.showWPM) private var showWPM = false

    var body: some View {
        if let record = trainer.finishedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Attempt complete")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text("\(record.source) · \(record.date.shortDateTime)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if trainer.isNewBest {
                            Label("New personal best", systemImage: "trophy.fill")
                                .font(.headline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.yellow.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                                .symbolEffect(.bounce, value: record.id)
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 16) {
                        StatTile(title: "Score", value: "\(record.score)",
                                 detail: trainer.previousBest.map { "Previous best \($0)" }, symbol: "star.fill", tint: .yellow)
                        StatTile(title: "Correct", value: "\(record.correctCount)/\(record.results.count)",
                                 detail: record.accuracy.formatted(.percent.precision(.fractionLength(0))), symbol: "checkmark.circle.fill", tint: .green)
                        StatTile(title: "Peak speed", value: SpeedFormat.string(record.peakCPM, wpm: showWPM),
                                 detail: SpeedFormat.secondary(record.peakCPM, wpm: showWPM), symbol: "speedometer", tint: .orange)
                        StatTile(title: "Average", value: SpeedFormat.string(record.averageCPM, wpm: showWPM),
                                 detail: "Started at \(SpeedFormat.string(record.config.startCPM, wpm: showWPM))", symbol: "gauge.with.dots.needle.50percent", tint: .blue)
                        StatTile(title: "Response (ms)", value: ResponseFormat.string(record.averageResponseMs),
                                 detail: "Average time to answer", symbol: "timer", tint: .purple)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Speed through the attempt").font(.headline)
                            AttemptSpeedChart(record: record, showWPM: showWPM)
                                .frame(height: 200)
                        }
                    }

                    Card(padding: 0) {
                        AttemptResultsTable(record: record, showWPM: showWPM)
                            .frame(minHeight: 320)
                    }

                    HStack(spacing: 12) {
                        Button {
                            trainer.start()
                        } label: {
                            Label("New Attempt", systemImage: "play.fill").frame(minWidth: 160)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        KeyHint("⌘↩")
                        Button("Done") { trainer.dismissResults() }
                            .controlSize(.large)
                    }
                }
                .padding(32)
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct AttemptSpeedChart: View {
    let record: AttemptRecord
    let showWPM: Bool

    var body: some View {
        Chart(record.results) { r in
            LineMark(x: .value("Item", r.index + 1), y: .value("Speed", speed(r.cpm)))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor.opacity(0.6))
            PointMark(x: .value("Item", r.index + 1), y: .value("Speed", speed(r.cpm)))
                .foregroundStyle(by: .value("Result", r.isCorrect ? "Correct" : "Missed"))
                .symbolSize(36)
        }
        .chartForegroundStyleScale(["Correct": Color.green, "Missed": Color.red])
        .chartYAxisLabel(SpeedFormat.unit(wpm: showWPM))
        .chartXAxisLabel("#")
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private func speed(_ cpm: Double) -> Double { showWPM ? Morse.wpm(fromCPM: cpm) : cpm }
}

struct AttemptResultsTable: View {
    let record: AttemptRecord
    let showWPM: Bool

    var body: some View {
        Table(record.results) {
            TableColumn("#") { r in Text("\(r.index + 1)").monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 28, ideal: 36)
            TableColumn("") { r in
                Image(systemName: r.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(r.isCorrect ? .green : .red)
            }
            .width(24)
            TableColumn("Sent") { r in Text(r.sent).font(.body.monospaced()) }
                .width(min: 60, ideal: 120)
            TableColumn("Copied") { r in Diff.received(r).font(.body.monospaced()) }
                .width(min: 60, ideal: 120)
            TableColumn("Speed (\(SpeedFormat.unit(wpm: showWPM)))") { r in Text("\(SpeedFormat.value(r.cpm, wpm: showWPM))").monospacedDigit() }
                .width(min: 50, ideal: 90)
            TableColumn("Response (ms)") { r in
                Text(ResponseFormat.string(r.responseMs))
                    .monospacedDigit()
                    .help(r.soundMs.map { "From the start of the sound. It lasted \($0) ms." } ?? "")
            }
                .width(min: 50, ideal: 100)
            TableColumn("Max points") { r in Text("\(r.maxPoints)").monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 50, ideal: 80)
            TableColumn("Points") { r in
                HStack(spacing: 4) {
                    Text("\(r.points)").monospacedDigit()
                    if r.repeated { Image(systemName: "arrow.counterclockwise").foregroundStyle(.secondary).help("Repeated") }
                }
            }
            .width(min: 44, ideal: 60)
        }
        .scrollContentBackground(.hidden)
    }
}
