#!/usr/bin/env python3
"""Verify Aurora Vigil audio assets, manifests, and gameplay trigger wiring."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
AUDIO_ROOT = ROOT / "assets" / "audio"
GDSCRIPT_RE = re.compile(r"res://assets/audio/[^\"'\s]+")
TRIGGER_RE = re.compile(r"AuroraAudio\.trigger\(\s*\"([A-Za-z0-9_]+)\"\s*\)")
LOOP_RE = re.compile(r"AuroraAudio\.start_loop\(\s*\"([A-Za-z0-9_]+)\"\s*\)")
AUDIO_PATH_RE = re.compile(r"\"([A-Za-z0-9_]+)\"\s*:\s*\"(res://assets/audio/[^\"'\s]+)\"")


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def audio_files() -> List[Path]:
    if not AUDIO_ROOT.exists():
        return []
    return sorted(p for p in AUDIO_ROOT.rglob("*") if p.is_file() and p.suffix.lower() in {".ogg", ".wav", ".mp3"})


def run_ffprobe(path: Path) -> Tuple[bool, str]:
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
    except FileNotFoundError:
        return True, "ffprobe unavailable"
    if result.returncode != 0:
        return False, result.stderr.strip() or result.stdout.strip()
    text = result.stdout.strip()
    try:
        duration = float(text)
    except ValueError:
        return False, f"invalid duration: {text}"
    if duration <= 0.05:
        return False, f"duration too short: {duration}s"
    return True, f"duration={duration:.2f}s"


def parse_gdscript_paths() -> Dict[str, str]:
    paths: Dict[str, str] = {}
    for path in ROOT.rglob("*.gd"):
        text = path.read_text(encoding="utf-8")
        for key, asset_path in AUDIO_PATH_RE.findall(text):
            paths[key] = asset_path
    return paths


def parse_trigger_calls() -> Set[str]:
    calls: Set[str] = set()
    for path in ROOT.rglob("*.gd"):
        text = path.read_text(encoding="utf-8")
        calls.update(TRIGGER_RE.findall(text))
    return calls


def parse_loop_calls() -> Set[str]:
    calls: Set[str] = set()
    for path in ROOT.rglob("*.gd"):
        text = path.read_text(encoding="utf-8")
        calls.update(LOOP_RE.findall(text))
    return calls


def referenced_assets_from_code() -> Set[str]:
    refs: Set[str] = set()
    for path in ROOT.rglob("*.gd"):
        refs.update(GDSCRIPT_RE.findall(path.read_text(encoding="utf-8")))
    for path in ROOT.rglob("*.tscn"):
        refs.update(GDSCRIPT_RE.findall(path.read_text(encoding="utf-8")))
    return refs


def load_manifest() -> Dict[str, str]:
    manifest = ROOT / "assets" / "audio" / "audio_manifest.json"
    if not manifest.exists():
        return {}
    data = json.loads(manifest.read_text(encoding="utf-8"))
    out: Dict[str, str] = {}
    for entry in data.get("entries", []):
        if "output_path" in entry:
            out[str(entry["output_path"])] = str(entry.get("provider", "unknown"))
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-existing-audio", action="store_true", help="fail if no generated audio files exist")
    args = parser.parse_args()

    files = audio_files()
    if not files:
        if args.require_existing_audio:
            raise SystemExit("AURORA_AUDIO_WIRING: FAIL no generated audio files under assets/audio")
        print("AURORA_AUDIO_WIRING: PASS initial_no_audio_assets")
        return 0

    errors: List[str] = []
    for path in files:
        if path.stat().st_size <= 0:
            errors.append(f"{rel(path)} is empty")
            continue
        ok, detail = run_ffprobe(path)
        if not ok:
            errors.append(f"{rel(path)} {detail}")

    assets_by_path = {("res://" + rel(p)): p for p in files}
    code_refs = referenced_assets_from_code()
    missing_refs = sorted(ref for ref in code_refs if ref not in assets_by_path)
    if missing_refs:
        errors.append("GDScript/TSCN references missing audio files: " + ", ".join(missing_refs))

    manifest_refs = set(load_manifest().keys())
    manifest_missing = sorted(ref for ref in manifest_refs if ref not in assets_by_path)
    if manifest_missing:
        errors.append("audio_manifest entries missing files: " + ", ".join(manifest_missing))

    audio_paths = parse_gdscript_paths()
    if not audio_paths:
        errors.append("no AuroraAudio AUDIO_PATHS entries found in GDScript")
    else:
        missing_path_files = {key: path for key, path in audio_paths.items() if path not in assets_by_path}
        if missing_path_files:
            errors.append("AUDIO_PATHS entries missing files: " + ", ".join(f"{k}={v}" for k, v in sorted(missing_path_files.items())))

        trigger_calls = parse_trigger_calls()
        loop_calls = parse_loop_calls()
        unused_keys = sorted(set(audio_paths) - trigger_calls - loop_calls)
        if unused_keys:
            errors.append("AUDIO_PATHS entries not triggered or looped: " + ", ".join(unused_keys))

        unknown_triggers = sorted(trigger_calls - set(audio_paths))
        if unknown_triggers:
            errors.append("trigger calls without AUDIO_PATHS: " + ", ".join(unknown_triggers))

        unknown_loops = sorted(loop_calls - set(audio_paths))
        if unknown_loops:
            errors.append("loop calls without AUDIO_PATHS: " + ", ".join(unknown_loops))

    if errors:
        print("AURORA_AUDIO_WIRING: FAIL")
        for error in errors:
            print(" - " + error)
        return 1

    durations = []
    for path in files:
        ok, detail = run_ffprobe(path)
        if ok and detail.startswith("duration="):
            raw_duration = detail.split("=", 1)[1]
            durations.append(float(raw_duration.rstrip("s")))
    avg_duration = sum(durations) / len(durations) if durations else 0.0
    print(f"AURORA_AUDIO_WIRING: PASS files={len(files)} refs={len(code_refs)} triggers={len(parse_trigger_calls())} loops={len(parse_loop_calls())} avg_duration={avg_duration:.2f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
