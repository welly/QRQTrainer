#!/bin/bash
# Copies the web version into the G3AJM site (welly.github.io) as qrq/, stamped with this commit so a
# browser never mixes new and cached files. Builds the wasm first. Doesn't commit or push the site.
#   ./scripts/publish-web.sh [site folder]   (default: ../welly.github.io)
set -euo pipefail
cd "$(dirname "$0")/.."
SITE="${1:-../welly.github.io}"
TARGET="$SITE/qrq"
[ -f "$SITE/CNAME" ] || { echo "No site at $SITE" >&2; exit 1; }
if [ -n "$(git status --porcelain -- Sources web Package.swift)" ]; then
  echo "Commit the changes in Sources/ and web/ first, so the version stamp matches what's published." >&2
  exit 1
fi
VERSION="$(git rev-parse --short HEAD)"
./scripts/build-web.sh
mkdir -p "$TARGET"
rm -f "$TARGET"/* 2>/dev/null || true
cp web/index.html web/app.js web/engine.js web/qrq.wasm web/sw.js web/manifest.webmanifest \
   web/icon.png web/apple-touch-icon.png web/icon-192.png web/icon-512.png "$TARGET/"
sed -i '' "s|src=\"app.js\"|src=\"app.js?v=$VERSION\"|" "$TARGET/index.html"
grep -q "app.js?v=$VERSION" "$TARGET/index.html" || { echo "Couldn't stamp index.html" >&2; exit 1; }
# The service worker caches this version's files, and a changed sw.js is how browsers notice an update.
sed -i '' "s|^const VERSION = 'dev';|const VERSION = '$VERSION';|" "$TARGET/sw.js"
grep -q "const VERSION = '$VERSION';" "$TARGET/sw.js" || { echo "Couldn't stamp sw.js" >&2; exit 1; }
echo "Copied web/ ($VERSION) to $TARGET. Commit and push $SITE to publish it at https://$(cat "$SITE/CNAME")/qrq/"
