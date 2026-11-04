# QRQ Trainer

A modern, native macOS trainer for **high-speed copying of amateur radio callsigns**. It's in the spirit of the
classic "Rufzeichen-Hören" trainers: callsigns are sent one at a time at real speed, and you copy each one in your head and type it.
Copy it right and the next one is faster. Miss it and the next one is slower. It's not a contest simulator: there's no QRM and no pile-ups,
just pure speed work.

Built with SwiftUI, Swift Charts and AVAudioEngine. Requires **macOS 14 Sonoma or later** and runs natively on Apple Silicon and Intel.

**[Download the latest release](https://github.com/welly/QRQTrainer/releases/latest/download/QRQ-Trainer.dmg)** · [Website](https://welly.github.io/QRQTrainer/)

> The app isn't signed with an Apple Developer ID yet. On first launch, open it once, then go to
> **System Settings → Privacy & Security → Open Anyway**.

## Features

- **Adaptive speed.** Every correct copy raises the speed by a configurable percentage (4% by default); every miss lowers it.
- **Real-speed Morse.** Each callsign is rendered sample-accurately with raised-cosine keying. It stays clean well beyond 600 CPM (120 WPM), with no element jitter.
- **Scoring.** Points grow with the callsign's Morse length and the speed it was sent at. Each wrong character costs points, and a repeated callsign (F6 / ⌘R) scores nothing.
- **Instant feedback.** You see what was sent next to what you typed, with each mistake highlighted.
- **Results.** A per-attempt speed chart, a full callsign table, and personal-best detection.
- **Insights.** Accuracy for every letter, digit and `/`; your weakest and strongest characters; common mix-ups (e.g. 5 → H, with their Morse); and accuracy by speed. **Practise these** starts an attempt that focuses on your weakest characters.
- **History.** A sortable list of attempts, with the selected attempt's full detail in a resizable lower pane; CSV export.
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
swift test
```

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
| `Sources/QRQCore/CharacterAnalysis.swift` | Per-character accuracy, mix-ups, speed bands, focused drills |
| `Sources/QRQCore/History.swift` | JSON persistence and CSV export |
| `Sources/QRQTrainer/` | macOS app: audio player, models, SwiftUI views |

`QRQCore` has no Apple-only dependencies, so the logic is unit-tested independently of the UI.

Data is stored in `~/Library/Application Support/QRQTrainer/`.

## Scoring

```
max points = Morse length of the callsign (dit units) × CPM ÷ 100
points     = max points × accuracy × answer speed
accuracy   = max(0, 1 − 2 × errors ÷ length)                 errors = edit distance
speed      = 1 within the grace period, then −5% per second, never below 0.5
grace      = 1 s + 0.25 s per character, timed from the end of the callsign to Return
```

For example, `R` (`.-.`, 7 units) at 25 WPM (125 CPM) is worth 7 × 125 ÷ 100 ≈ **9**. Copied correctly within
1.25 s it scores 9; answered after 3.25 s (2 s past the grace period) it scores 9 × 0.9 ≈ 8. A repeated callsign scores 0. The results table
shows the **Time**, **Points** and **Max** for every callsign. You can turn the time penalty off in
Settings → Training.

Scores are only comparable between attempts that use the same callsign source and attempt length (50 is the classic).

## Releasing

Push a version tag. The **Release** workflow tests, builds a universal app, and attaches `QRQ-Trainer.dmg` and
`QRQ-Trainer.zip` to a new GitHub Release:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The download page in `docs/` is published by the **Pages** workflow (Settings → Pages → Source: GitHub Actions).

## Not included

There is no connection to the official RufzXP International Toplist; that's a separate service run by the RufzXP authors.
Export your history as CSV if you want to share results.

## Licence

MIT. See [LICENSE](LICENSE).
