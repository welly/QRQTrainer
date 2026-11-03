#!/usr/bin/env bash
# Downloads the Super Check Partial MASTER.SCP callsign list (active contest/CW callsigns).
# Import it in QRQ Trainer → Settings → Callsigns → Import File…
set -euo pipefail
OUT="${1:-$HOME/Downloads/MASTER.SCP}"
curl -fL --retry 3 -o "$OUT" "https://www.supercheckpartial.com/MASTER.SCP"
echo "Saved $(wc -l < "$OUT" | tr -d ' ') lines to $OUT"
