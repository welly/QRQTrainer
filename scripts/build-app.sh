#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) QRQ Trainer.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/QRQ Trainer.app"
VERSION="${VERSION:-1.0.0}"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/QRQTrainer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QRQTrainer"
# App icon: build AppIcon.icns from the 1024 px master (Resources/AppIcon-1024.png, drawn from AppIcon.svg).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>QRQ Trainer</string>
    <key>CFBundleDisplayName</key><string>QRQ Trainer</string>
    <key>CFBundleIdentifier</key><string>net.qrqtrainer.QRQTrainer</string>
    <key>CFBundleExecutable</key><string>QRQTrainer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Callsign copying trainer for amateur radio operators.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets it run locally. Use a Developer ID to distribute.
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
