#!/usr/bin/env bash
# Packages build/QRQ Trainer.app into dist/QRQ-Trainer.zip and dist/QRQ-Trainer.dmg (stable names, so
# https://github.com/<owner>/<repo>/releases/latest/download/QRQ-Trainer.dmg always points at the newest build).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/QRQ Trainer.app"
[ -d "$APP" ] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }
rm -rf dist && mkdir -p dist

ditto -c -k --keepParent "$APP" dist/QRQ-Trainer.zip

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "QRQ Trainer" -srcfolder "$STAGE" -ov -format UDZO dist/QRQ-Trainer.dmg
rm -rf "$STAGE"
ls -lh dist
