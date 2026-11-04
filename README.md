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
- **Scoring.** Points grow with the callsign's Morse length and the speed it was sent at. Each wrong character costs points, a slow answer costs a little, and a repeated callsign (F6 / ⌘R) scores nothing. Results show the maximum and gained points and the response time for each item.
- **Instant feedback.** You see what was sent next to what you typed, with each mistake highlighted.
- **Results.** A per-attempt speed chart, a full callsign table, and personal-best detection.
- **Progress dashboard.** Score and peak/average speed trends, filterable by callsign source and time range.
- **History.** A sortable table with an inspector for each attempt, plus CSV export.
- **Callsigns.** A built-in generator that produces realistic calls from about 60 ITU prefix groups (optional /P, /M and foreign prefixes), or import real calls from Super Check Partial `MASTER.SCP` or any text file.
- **Trainer modes.** Besides callsigns: ham codes (Q codes, abbreviations, reports), and random character groups of letters, figures, symbols or any mix of them. Groups can have a fixed length or a variable min–max length, can be mixed or separated by class, and you can pick exactly which characters are used.
- **Farnsworth spacing.** Characters are sent at full speed with longer gaps between them, at an overall speed you choose as a percentage of the character speed.
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

The app icon (`Resources/AppIcon.icns`) is drawn in code. After changing the design in `scripts/make-icon.swift`, regenerate it with:

```bash
swift scripts/make-icon.swift Resources/AppIcon-1024.png
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
max points = morseUnits(item) × CPM / 100
points     = max points × max(0, 1 − 2 × errors / length) × max(0.5, 1 − 0.03 × ms / 1000)
```

`errors` is the edit distance between what was sent and what you typed. The response time is measured, as in RufzXP,
from the start of the first tone (allowing for output latency) to pressing Return. Only the part after the sound has
ended counts against the score, so long or slow items aren't penalised for their length: `ms` is the response time minus
the sound's length, never below 0. Every 1000 ms of it costs 3% of the points, and a correct copy always keeps at least half. A repeated item scores 0.
Attempts recorded before response timing was added have no response time and weren't penalised for it.
Scores are only comparable between attempts that use the same callsign source and attempt length (50 is the classic).

## Releasing

Push a version tag (or use **Actions → Release → Run workflow** and enter the version). The **Release** workflow tests,
builds a universal app, and attaches `QRQ-Trainer.dmg` and `QRQ-Trainer.zip` to a new GitHub Release:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

To package locally after `./scripts/build-app.sh`, run `./scripts/package.sh`; the files go in `dist/`.

The download page is `docs/index.html`, served by GitHub Pages from the `main` branch's `/docs` folder. Changes go live
a minute or so after they are pushed.

## Not included

There is no connection to the official RufzXP International Toplist; that's a separate service run by the RufzXP authors.
Export your history as CSV if you want to share results.

## Licence

MIT. See [LICENSE](LICENSE).
