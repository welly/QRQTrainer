**Download:** `QRQ-Trainer.dmg` (or `QRQ-Trainer.zip`). Requires macOS 14 Sonoma or later, Apple Silicon or Intel.

### First launch
QRQ Trainer isn't signed with an Apple Developer ID yet, so macOS blocks it the first time:

1. Open the DMG and drag **QRQ Trainer** to **Applications**.
2. Open it. When macOS says it can't verify the app, click **Done**.
3. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to QRQ Trainer.

You only need to do this once. Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/QRQ Trainer.app"`
