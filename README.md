# QRQ Trainer

A modern, native macOS trainer for **high-speed copying of amateur radio callsigns**. It's in the spirit of the
classic "Rufzeichen-Hören" trainers: callsigns are sent one at a time at real speed, and you copy each one in your head and type it.
Copy it right and the next one is faster. Miss it and the next one is slower. It's not a contest simulator: there's no QRM and no pile-ups,
just pure speed work.

Built with SwiftUI, Swift Charts and AVAudioEngine. Requires **macOS 14 Sonoma or later** and runs natively on Apple Silicon and Intel.

## Features

- **Adaptive speed.** Every correct copy raises the speed by a configurable percentage (4% by default); every miss lowers it.
- **Real-speed Morse.** Each callsign is rendered sample-accurately with raised-cosine keying. It stays clean well beyond 600 CPM (120 WPM), with no element jitter.
- **Scoring.** Points grow with the callsign's Morse length and the speed it was sent at. Each wrong character costs points, and a repeated callsign (F6 / ⌘R) scores nothing.
- **Instant feedback.** You see what was sent next to what you typed, with each mistake highlighted.
- **Results.** A per-attempt speed chart, a full callsign table, and personal-best detection.
- **Progress dashboard.** Score and peak/average speed trends, filterable by callsign source and time range.
- **History.** A sortable table with an inspector for each attempt, plus CSV export.
- **Callsigns.** A built-in generator that produces realistic calls from about 60 ITU prefix groups (optional /P, /M and foreign prefixes), or import real calls from Super Check Partial `MASTER.SCP` or any text file.
- **Audio settings.** Pitch, optional per-call pitch variation, volume and edge shaping, plus a test tone.
- **Display.** Shows speed in CPM (the classic Rufz unit) or WPM (PARIS); 1 WPM = 5 CPM.
- **Keyboard-first.** `⌘↩` starts, `↩` submits, `F6`/`⌘R` repeats, `esc` ends the attempt. The sidebar collapses while you copy.

## Build & run

Open the package in Xcode (15 or later) and run the **QRQTrainer** scheme:

```bash
open Package.swift
```

Or from the command line:

```bash
swift run QRQTrainer
```

To build a double-clickable, universal `.app` in `build/`:

```bash
./scripts/build-app.sh
```

Run the core unit tests:

```bash
./scripts/test.sh
```

With full Xcode installed, plain `swift test` works too; the script adds the framework paths that the Command Line Tools need for Swift Testing.

### Real callsigns

```bash
./scripts/fetch-master-scp.sh
```

Then go to **Settings → Callsigns → Import File…** and pick `~/Downloads/MASTER.SCP`.

## Project layout

| Path | What |
| --- | --- |
| `Sources/QRQCore/Morse.swift` | Morse table, PARIS timing, PCM synthesis |
| `Sources/QRQCore/Callsigns.swift` | Callsign generator, list parser, seeded RNG |
| `Sources/QRQCore/Scoring.swift` | Edit distance, mistake alignment, points |
| `Sources/QRQCore/TrainingSession.swift` | Attempt rules (speed adaptation, repeats) and records |
| `Sources/QRQCore/History.swift` | JSON persistence and CSV export |
| `Sources/QRQTrainer/` | macOS app: audio player, models, SwiftUI views |

`QRQCore` has no Apple-only dependencies, so the logic is unit-tested independently of the UI.

Data is stored in `~/Library/Application Support/QRQTrainer/`.

## Scoring

```
points = morseUnits(callsign) × CPM / 100 × max(0, 1 − 2 × errors / length)
```

`errors` is the edit distance between what was sent and what you typed. A repeated callsign scores 0.
Scores are only comparable between attempts that use the same callsign source and attempt length (50 is the classic).

## Not included

There is no connection to the official RufzXP International Toplist; that's a separate service run by the RufzXP authors.
Export your history as CSV if you want to share results.
