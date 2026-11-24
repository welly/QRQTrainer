# QRQ Trainer

High-speed Morse copying trainer (RufzXP style: callsigns, ham codes, words, character groups): a Mac app and a web version. See README.md for features.

## Layout

- `QRQCore`: Morse, callsigns, groups/words/ham codes, scoring, `TrainingSession`, `CharacterAnalysis`.
  Shared by the Mac app and the web version.
- `QRQTrainer`: the Mac app (SwiftUI). Preferences are `Pref` keys in `Model/Preferences.swift`.
- `QRQWeb` + `web/`: the web version, built like HW CPY's and Mock QSO's. `scripts/build-web.sh` compiles QRQCore
  to Wasm (WASI reactor) with the swift.org toolchain + Swift SDK for Wasm. `Exports.swift` has one command export
  (`qrq_call`: JSON in, JSON and samples out) and keeps the running `TrainingSession`; `WebSettings.swift` reads the
  page's settings, which use the Mac app's `Pref` keys and defaults. `web/app.js` has the screens, audio and
  timing; settings and history (the Mac app's `history.json` record format) are in `localStorage` under `qrq.`.
  `node scripts/web-check.mjs [mode] [items]` runs a short attempt in Node.
  The page uses HW CPY's web design (`../hw_cpy/web/index.html`: palette, bar, cards, sheets, switches, steppers).

## Rules

- QRQCore must build without Foundation on WASI (it would add megabytes): Foundation is imported only
  `#if !os(WASI)`, `History.swift` and `AttemptRecord` are Mac-only, and string helpers Foundation would give go in
  `Text.swift` (`trimmingSpaces()`). Check with `./scripts/build-web.sh` after QRQCore changes.
- Keep `WebSettings` in step with `TrainerSettings` (source names decide which attempts are compared), and
  `web/app.js` `DEFAULTS` in step with `Pref.defaults`.
- Response timing (both versions): from when the first tone is heard (playback start + output latency + lead-in) to
  Return; instant recognition uses the first key. The web page uses `AudioContext.getOutputTimestamp()`.
- Times shown in the web page are UTC (`2026-11-24 1403Z`).
- Tests: `./scripts/test.sh`. App: `./scripts/build-app.sh`.
