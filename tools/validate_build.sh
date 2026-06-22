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
VOLUMES_LOG=.godot_validation/volumes.log
VOLUME_TEST_LOG=.godot_validation/volume_tests.log
CITY_ROADS_TEST_LOG=.godot_validation/city_roads_tests.log
CITY_FACADE_TEXTURES_TEST_LOG=.godot_validation/city_facade_textures_tests.log
CITY_FACADE_POLISH_TEST_LOG=.godot_validation/city_facade_polish_tests.log
"$GODOT" --headless --path . --import --quit-after 120 >"$IMPORT_LOG" 2>&1 || { tail -120 "$IMPORT_LOG"; exit 1; }
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$IMPORT_LOG" | grep -v "USER ERROR"; then
  echo "AURORA_IMPORT: FAIL"; exit 1
fi
echo "AURORA_IMPORT: PASS"
python3 tools/validate_data.py >"$DATA_LOG" 2>&1 || { cat "$DATA_LOG"; exit 1; }
grep -q "AURORA_DATA_VALIDATE: PASS" "$DATA_LOG" || { cat "$DATA_LOG"; exit 1; }
echo "AURORA_DATA: PASS"
python3 tools/validate_volumes.py >"$VOLUMES_LOG" 2>&1 || { cat "$VOLUMES_LOG"; exit 1; }
grep -q "AURORA_VOLUMES_VALIDATE: PASS" "$VOLUMES_LOG" || { cat "$VOLUMES_LOG"; exit 1; }
echo "AURORA_VOLUMES: PASS"
"$GODOT" --headless --path . -s tests/test_logic.gd >"$TEST_LOG" 2>&1 || { cat "$TEST_LOG"; exit 1; }
grep -q "AURORA_LOGIC_TESTS: PASS" "$TEST_LOG" || { cat "$TEST_LOG"; exit 1; }
echo "AURORA_LOGIC: PASS"
"$GODOT" --headless --path . -s tests/test_interaction_volumes.gd >"$VOLUME_TEST_LOG" 2>&1 || { cat "$VOLUME_TEST_LOG"; exit 1; }
grep -q "AURORA_VOLUME_TESTS: PASS" "$VOLUME_TEST_LOG" || { cat "$VOLUME_TEST_LOG"; exit 1; }
echo "AURORA_VOLUME_TESTS: PASS"
AURORA_CAPTURE_MODE=city "$GODOT" --headless --path . -s tests/test_city_capture_roads.gd >"$CITY_ROADS_TEST_LOG" 2>&1 || { cat "$CITY_ROADS_TEST_LOG"; exit 1; }
grep -q "AURORA_CITY_ROADS_TESTS: PASS" "$CITY_ROADS_TEST_LOG" || { cat "$CITY_ROADS_TEST_LOG"; exit 1; }
echo "AURORA_CITY_ROADS_TESTS: PASS"
AURORA_CAPTURE_MODE=city "$GODOT" --headless --path . -s tests/test_city_capture_facade_textures.gd >"$CITY_FACADE_TEXTURES_TEST_LOG" 2>&1 || { cat "$CITY_FACADE_TEXTURES_TEST_LOG"; exit 1; }
grep -q "AURORA_CITY_FACADE_TEXTURES: PASS" "$CITY_FACADE_TEXTURES_TEST_LOG" || { cat "$CITY_FACADE_TEXTURES_TEST_LOG"; exit 1; }
echo "AURORA_CITY_FACADE_TEXTURES: PASS"
AURORA_CAPTURE_MODE=city "$GODOT" --headless --path . -s tests/test_city_capture_facade_polish.gd >"$CITY_FACADE_POLISH_TEST_LOG" 2>&1 || { cat "$CITY_FACADE_POLISH_TEST_LOG"; exit 1; }
grep -q "AURORA_CITY_FACADE_POLISH: PASS" "$CITY_FACADE_POLISH_TEST_LOG" || { cat "$CITY_FACADE_POLISH_TEST_LOG"; exit 1; }
echo "AURORA_CITY_FACADE_POLISH: PASS"
SAVE_LOAD_LOG=.godot_validation/save_load_gd.log
"$GODOT" --headless --path . -s tests/test_save_load.gd >"$SAVE_LOAD_LOG" 2>&1 || { cat "$SAVE_LOAD_LOG"; exit 1; }
grep -q "AURORA_SAVE_LOAD_GD: PASS" "$SAVE_LOAD_LOG" || { cat "$SAVE_LOAD_LOG"; exit 1; }
echo "AURORA_SAVE_LOAD_GD: PASS"
python3 tools/verify_save_load.py >.godot_validation/save_load_py.log 2>&1 || { cat .godot_validation/save_load_py.log; exit 1; }
grep -q "AURORA_SAVE_LOAD: PASS" .godot_validation/save_load_py.log || { cat .godot_validation/save_load_py.log; exit 1; }
echo "AURORA_SAVE_LOAD_PY: PASS"
AURORA_AUTO_QUIT=1 timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver vulkan >"$SMOKE_LOG" 2>&1 || { cat "$SMOKE_LOG"; exit 1; }
grep -q "AURORA_SMOKE:" "$SMOKE_LOG" || { cat "$SMOKE_LOG"; exit 1; }
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$SMOKE_LOG" | grep -v "USER ERROR"; then
  echo "AURORA_SMOKE: FAIL"; exit 1
fi
echo "AURORA_SMOKE: PASS"
echo "AURORA_VALIDATE: PASS"
