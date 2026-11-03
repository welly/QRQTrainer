#!/usr/bin/env bash
# Runs the QRQCore tests. With full Xcode, plain `swift test` works; with only the
# Command Line Tools, Swift Testing's framework isn't on the default search paths.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
if [[ "$DEV" == *CommandLineTools* ]]; then
    D="$DEV/Library/Developer"
    exec swift test \
        -Xswiftc -F -Xswiftc "$D/Frameworks" \
        -Xlinker -F -Xlinker "$D/Frameworks" \
        -Xlinker -rpath -Xlinker "$D/Frameworks" \
        -Xlinker -rpath -Xlinker "$D/usr/lib" "$@"
fi
exec swift test "$@"
