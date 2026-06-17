#!/usr/bin/env bash
set -euo pipefail
GODOT=${GODOT:-/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
mkdir -p .godot_validation
IMPORT_LOG=.godot_validation/import.log
TEST_LOG=.godot_validation/logic.log
SMOKE_LOG=.godot_validation/smoke.log
DATA_LOG=.godot_validation/data.log
"$GODOT" --headless --path . --import --quit-after 120 >"$IMPORT_LOG" 2>&1 || { tail -120 "$IMPORT_LOG"; exit 1; }
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$IMPORT_LOG" | grep -v "USER ERROR"; then
  echo "AURORA_IMPORT: FAIL"; exit 1
fi
echo "AURORA_IMPORT: PASS"
python3 tools/validate_data.py >"$DATA_LOG" 2>&1 || { cat "$DATA_LOG"; exit 1; }
grep -q "AURORA_DATA_VALIDATE: PASS" "$DATA_LOG" || { cat "$DATA_LOG"; exit 1; }
echo "AURORA_DATA: PASS"
"$GODOT" --headless --path . -s tests/test_logic.gd >"$TEST_LOG" 2>&1 || { cat "$TEST_LOG"; exit 1; }
grep -q "AURORA_LOGIC_TESTS: PASS" "$TEST_LOG" || { cat "$TEST_LOG"; exit 1; }
echo "AURORA_LOGIC: PASS"
AURORA_AUTO_QUIT=1 timeout 20 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 >"$SMOKE_LOG" 2>&1 || { cat "$SMOKE_LOG"; exit 1; }
grep -q "AURORA_SMOKE:" "$SMOKE_LOG" || { cat "$SMOKE_LOG"; exit 1; }
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$SMOKE_LOG" | grep -v "USER ERROR"; then
  echo "AURORA_SMOKE: FAIL"; exit 1
fi
echo "AURORA_SMOKE: PASS"
echo "AURORA_VALIDATE: PASS"
