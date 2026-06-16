#!/usr/bin/env bash
set -euo pipefail
GODOT=${GODOT:-/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${1:-$ROOT/artifacts/screenshots}
mkdir -p "$OUT"
cd "$ROOT"
for mode in gameplay city drone closeup; do
  LOG="$OUT/${mode}.log"
  PNG="$OUT/${mode}.png"
  AURORA_CAPTURE_PATH="$PNG" AURORA_CAPTURE_MODE="$mode" timeout 25 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 >"$LOG" 2>&1 || { cat "$LOG"; exit 1; }
  test -s "$PNG" || { echo "missing screenshot $PNG"; cat "$LOG"; exit 1; }
  python3 - "$PNG" <<'PY'
from PIL import Image, ImageStat
import sys
p=sys.argv[1]
im=Image.open(p).convert('RGB')
mean=sum(ImageStat.Stat(im).mean)/3
assert mean > 20, f"too dark {p}: {mean}"
print(f"AURORA_SCREENSHOT_IMAGE PASS {p} mean={mean:.2f} size={im.size}")
PY
done
python3 tools/make_contact_sheet.py "$OUT" "$OUT/contact_sheet.jpg"
echo "AURORA_SCREENSHOT: PASS out=$OUT"
