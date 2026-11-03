#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) QRQ Trainer.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/QRQ Trainer.app"
VERSION="${VERSION:-1.0.0}"

# Universal builds need Xcode's build system; with only the Command Line Tools, build for this Mac.
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    ARCHS=()
    echo "Command Line Tools only: building for $(uname -m) (install Xcode for a universal build)."
else
    ARCHS=(--arch arm64 --arch x86_64)
fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/QRQTrainer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QRQTrainer"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

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
