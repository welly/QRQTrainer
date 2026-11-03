import QRQCore
import SwiftUI

/// The preferences that decide what an attempt sends. Views that show the source name hold this so they
/// refresh when any of them changes.
struct SourcePrefs: DynamicProperty {
    @AppStorage(Pref.mode) var mode = TrainerMode.callsigns
    @AppStorage(Pref.useImported) var useImported = false
    @AppStorage(Pref.variableLength) var variableLength = false
    @AppStorage(Pref.groupLength) var groupLength = 5
    @AppStorage(Pref.groupMin) var groupMin = 1
    @AppStorage(Pref.groupMax) var groupMax = 12
    @AppStorage(Pref.composition) var composition = GroupComposition.mixed
    @AppStorage(Pref.enabledCharacters) var enabledCharacters = Pref.allCharacters
    @AppStorage(Pref.farnsworth) var farnsworth = false
    @AppStorage(Pref.farnsworthPercent) var farnsworthPercent = 60.0
}

extension TrainerMode {
    var symbol: String {
        switch self {
        case .callsigns: "antenna.radiowaves.left.and.right"
        case .hamCodes: "text.bubble"
        case .letters: "textformat.abc"
        case .figures: "number"
        case .symbols: "questionmark.circle"
        default: "square.grid.3x3"
        }
    }
}

/// Ready-screen card: choose the trainer mode, group length, composition and characters.
struct WhatToCopyCard: View {
    @Environment(CallsignLibrary.self) private var library
    private var prefs = SourcePrefs()
    @State private var showCharacters = false
    @State private var seed = UInt64.random(in: 0...UInt64.max)

    private static let groupLengths = 1...12

    var body: some View {
        let mode = prefs.mode
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("What to copy").font(.headline)
                    Spacer()
                    modePicker
                }

                if mode.usesGroups {
                    groupOptions(mode)
                } else if mode == .callsigns {
                    HStack {
                        Label(TrainerSettings.current().sourceName(library: library), systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        SettingsLink { Text("Callsign settings…") }.buttonStyle(.link)
                    }
                    .font(.callout)
                } else {
                    Text("Q codes, abbreviations and reports such as QTH, TNX and 5NN.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()
                preview
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: prefs.$mode) {
            ForEach([TrainerMode.callsigns, .hamCodes]) { Label($0.title, systemImage: $0.symbol).tag($0) }
            Divider()
            ForEach([TrainerMode.letters, .figures, .symbols]) { Label($0.title, systemImage: $0.symbol).tag($0) }
            Divider()
            ForEach([TrainerMode.lettersFigures, .lettersSymbols, .figuresSymbols, .all]) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func groupOptions(_ mode: TrainerMode) -> some View {
        let generator = TrainerSettings.current().groupGenerator
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Group length").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Picker("Group length", selection: prefs.$variableLength) {
                        Text("Fixed").tag(false)
                        Text("Variable").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if prefs.variableLength {
                        lengthStepper(prefs.$groupMin, range: Self.groupLengths.lowerBound...prefs.groupMax)
                        Text("to").foregroundStyle(.secondary)
                        lengthStepper(prefs.$groupMax, range: prefs.groupMin...Self.groupLengths.upperBound)
                    } else {
                        lengthStepper(prefs.$groupLength, range: Self.groupLengths)
                    }
                    Text("characters").foregroundStyle(.secondary)
                }
            }

            if mode.classes.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Composition").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Composition", selection: prefs.$composition) {
                        Text("Mixed").tag(GroupComposition.mixed)
                        Text("Separated").tag(GroupComposition.separated)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Mixed: any group can combine \(classList(mode)). Separated: each group uses only one of them.")
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Text("Characters").font(.subheadline).foregroundStyle(.secondary)
                Button {
                    showCharacters = true
                } label: {
                    Label("\(selectedCount(mode)) of \(mode.classes.flatMap(\.characters).count)", systemImage: "character.textbox")
                        .monospacedDigit()
                }
                .popover(isPresented: $showCharacters, arrowEdge: .bottom) {
                    CharacterPicker(classes: mode.classes).padding(20)
                }
            }
        }
        if !generator.canGenerate {
            Label("Select at least one \(classList(mode, joiner: "or")) character to start.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private func lengthStepper(_ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            Text("\(value.wrappedValue)").monospacedDigit().frame(minWidth: 18, alignment: .trailing)
        }
        .fixedSize()
    }

    private var preview: some View {
        HStack(spacing: 10) {
            Text("Example").font(.callout).foregroundStyle(.secondary)
            Text(examples().joined(separator: "   "))
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button("Shuffle", systemImage: "shuffle") { seed = .random(in: 0...UInt64.max) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show other examples")
        }
    }

    private func examples() -> [String] {
        // Reads every source preference, so it changes whenever one of them does.
        _ = (prefs.mode, prefs.variableLength, prefs.groupLength, prefs.groupMin, prefs.groupMax,
             prefs.composition, prefs.enabledCharacters, prefs.useImported)
        var rng = SeededRandom(seed: seed)
        let s = TrainerSettings.current()
        switch s.mode {
        case .callsigns:
            if s.useImported, !library.calls.isEmpty { return CallsignList.pick(6, from: library.calls, using: &rng) }
            return CallsignGenerator(portableProbability: s.portablePercent / 100, prefixedProbability: s.prefixedPercent / 100)
                .generate(6, using: &rng)
        case .hamCodes:
            return CallsignList.pick(8, from: HamCodes.all, using: &rng)
        default:
            return s.groupGenerator.generate(8, using: &rng)
        }
    }

    private func selectedCount(_ mode: TrainerMode) -> Int {
        let enabled = Set(prefs.enabledCharacters)
        return mode.classes.flatMap(\.characters).filter(enabled.contains).count
    }

    private func classList(_ mode: TrainerMode, joiner: String = "and") -> String {
        let names = mode.classes.map { $0.title.lowercased() }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " \(joiner) " + names.last!
    }
}

/// Grid of toggleable characters per class, with All / None / Invert.
struct CharacterPicker: View {
    let classes: [CharacterClass]
    @AppStorage(Pref.enabledCharacters) private var enabledString = Pref.allCharacters

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 13)

    var body: some View {
        let enabled = Set(enabledString)
        VStack(alignment: .leading, spacing: 20) {
            ForEach(classes, id: \.self) { cls in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(cls.title).font(.headline)
                        Text("\(cls.characters.filter(enabled.contains).count) of \(cls.characters.count)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        HStack(spacing: 12) {
                            Button("All") { update(cls) { _ in true } }
                            Button("None") { update(cls) { _ in false } }
                            Button("Invert") { update(cls) { !$0 } }
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(cls.characters, id: \.self) { ch in
                            chip(ch, isOn: enabled.contains(ch))
                        }
                    }
                }
            }
        }
        .frame(width: 13 * 34 + 12 * 6)
    }

    private func chip(_ ch: Character, isOn: Bool) -> some View {
        Button {
            update(only: ch) { !$0 }
        } label: {
            Text(String(ch))
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .frame(width: 34, height: 30)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(isOn ? Color.accentColor : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Character \(String(ch))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.snappy(duration: 0.15), value: isOn)
    }

    private func update(_ cls: CharacterClass, _ transform: (Bool) -> Bool) {
        apply(to: Set(cls.characters), transform)
    }

    private func update(only ch: Character, _ transform: (Bool) -> Bool) {
        apply(to: [ch], transform)
    }

    private func apply(to targets: Set<Character>, _ transform: (Bool) -> Bool) {
        var enabled = Set(enabledString)
        for ch in targets {
            if transform(enabled.contains(ch)) { enabled.insert(ch) } else { enabled.remove(ch) }
        }
        // Keep a canonical order so the stored value is stable.
        enabledString = String(CharacterClass.allCharacters.filter(enabled.contains))
    }
}
