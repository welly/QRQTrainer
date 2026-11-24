#!/usr/bin/env bash
# Builds QRQCore to WebAssembly for the web page (web/qrq.wasm).
#
# Needs the swift.org toolchain (Xcode's Swift can't target Wasm) and the matching Swift SDK for Wasm:
#   https://www.swift.org/documentation/articles/wasm-getting-started.html
# Set SWIFT_TOOLCHAIN to the toolchain's usr/bin if it isn't the default below.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${SWIFT_WASM_VERSION:-6.4.3}"
BIN="${SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-$VERSION-RELEASE.xctoolchain/usr/bin}"
SDK="${SWIFT_WASM_SDK:-swift-$VERSION-RELEASE_wasm}"

EXPORTS=(qrq_input qrq_call qrq_samples qrq_sample_count qrq_result qrq_result_length)
# Its own build folder, so it never waits on (or invalidates) the Mac build.
FLAGS=(-c release --product QRQWeb --swift-sdk "$SDK" --scratch-path .build/wasm
       -Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor
       -Xlinker --strip-all)
for e in "${EXPORTS[@]}"; do FLAGS+=(-Xlinker "--export=$e"); done

"$BIN/swift" build "${FLAGS[@]}"
OUT="$("$BIN/swift" build "${FLAGS[@]}" --show-bin-path)/QRQWeb.wasm"

# Optimise for size if Binaryen's wasm-opt is installed (brew install binaryen); it's optional.
if command -v wasm-opt >/dev/null; then
    wasm-opt -Os --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int \
        --enable-mutable-globals "$OUT" -o web/qrq.wasm
else
    cp "$OUT" web/qrq.wasm
fi
ls -l web/qrq.wasm | awk '{printf "web/qrq.wasm: %.1f MB\n", $5 / 1048576}'
printf 'gzip: %.1f MB\n' "$(gzip -9 -c web/qrq.wasm | wc -c | awk '{print $1 / 1048576}')"
