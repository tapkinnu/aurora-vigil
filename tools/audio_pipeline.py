#!/usr/bin/env python3
"""Aurora Vigil P0 audio pipeline.

- Downloads CC0 Kenney mechanical/UI sounds.
- Generates FAL stable-audio SFX/stingers/ambience and stable-audio-25 music.
- Generates FAL ElevenLabs TTS radio/civilian barks with distinct casting.
- Normalizes and encodes everything to Godot-friendly OGG Vorbis.
- Writes assets/audio/SOURCES.md and assets/audio/audio_manifest.json.

The FAL key is read from ~/.hermes/profiles/coder/.env and is never printed.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

ROOT = Path(__file__).resolve().parents[1]
PROFILE_ENV = Path(os.environ.get("AURORA_PROFILE_ENV", "/home/ganomix/.hermes/profiles/coder/.env"))
TMP = Path("/tmp/aurora_vigil_audio_pipeline")
KENNEY_DIR = TMP / "kenney"
RAW_DIR = TMP / "raw"
OUT_ROOT = ROOT / "assets" / "audio"
SOURCES = OUT_ROOT / "SOURCES.md"
MANIFEST = OUT_ROOT / "audio_manifest.json"

KENNEY_PACKS = {
    "sci": "sci-fi-sounds",
    "impact": "impact-sounds",
    "interface": "interface-sounds",
}

KENNEY_JOBS: List[Tuple[str, str, List[str], int]] = [
    ("assets/audio/sfx/ui/ui_click.ogg", "interface", ["click"], 0),
    ("assets/audio/sfx/ui/ui_confirm.ogg", "interface", ["confirmation", "confirm"], 0),
]

FAL_SFX_JOBS: List[Tuple[str, str, int, str]] = [
    (
        "assets/audio/sfx/flight/flight_boost_burst.ogg",
        "short futuristic superhero flight boost whoosh, fast air rush and rising pressure, clean game sound effect, no music, no voice",
        2,
        "sfx",
    ),
    (
        "assets/audio/sfx/powers/power_radiant_beam_fire.ogg",
        "bright heroic energy beam firing through air, warm golden plasma burst, superhero game sound effect, no voice",
        2,
        "sfx",
    ),
    (
        "assets/audio/sfx/powers/power_sonic_burst.ogg",
        "sharp violet sonic shockwave burst, concussive air ripple, non-lethal shutdown pulse, game sound effect",
        2,
        "sfx",
    ),
    (
        "assets/audio/sfx/powers/power_aegis_activate.ogg",
        "protective blue energy shield activating around a hero, crystalline forcefield bloom, short game sound effect",
        3,
        "sfx",
    ),
    (
        "assets/audio/sfx/events/event_alert_rescue_needed.ogg",
        "urgent civic rescue alert stinger, clear emergency callout tone, heroic city defense game cue, no voice",
        4,
        "stinger",
    ),
    (
        "assets/audio/sfx/enemies/drone_alert.ogg",
        "small hostile civic drone alert chirp, scanning target lock warning, sci-fi game sound effect, no voice",
        3,
        "sfx",
    ),
    (
        "assets/audio/sfx/enemies/drone_death.ogg",
        "small civic drone power-down death spark, electronic failure pop and falling debris, game sound effect",
        2,
        "sfx",
    ),
    (
        "assets/audio/sfx/stingers/stinger_mission_intro.ogg",
        "short heroic Aurora Vigil mission intro stinger, hopeful teal and gold city defense fanfare, no voice",
        7,
        "stinger",
    ),
    (
        "assets/audio/ambience/ambience_city_base_loop.ogg",
        "near future city ambience loop, distant traffic hum, soft electric grid noise, gentle wind between towers, no music, no voice",
        6,
        "loop",
    ),
]

FAL_MUSIC_JOBS: List[Tuple[str, str, int, str]] = [
    (
        "assets/audio/music/music_city_exploration.ogg",
        "instrumental near-future superhero city exploration music, hopeful teal and gold synth pads, light pulse percussion, 90 BPM, D minor, seamless loop, no vocals",
        45,
        "music",
    ),
]

FAL_TTS_JOBS: List[Tuple[str, str, str, str]] = [
    (
        "assets/audio/voices/civic_grid/civic_grid_alert.ogg",
        "City grid alert. Emergency vector marked. Respond with caution.",
        "Aria",
        "Civic Grid AI: calm synthetic alto, clipped radio-bandpass delivery",
    ),
    (
        "assets/audio/voices/civilian_panicked/civilian_panicked_help.ogg",
        "Help! The drone has me pinned near the bridge!",
        "Sarah",
        "Civilian Panicked: young adult female, breathy urgent plea",
    ),
    (
        "assets/audio/voices/civilian_grateful/civilian_grateful_thanks.ogg",
        "Thank you, Vigil. I can breathe again.",
        "Charlie",
        "Civilian Grateful: warm middle-aged male, relieved and shaken",
    ),
    (
        "assets/audio/voices/emergency_dispatcher/emergency_dispatcher_dispatch.ogg",
        "All units, contain the surge. Let the hero clear the block.",
        "Callum",
        "Emergency Dispatcher: professional male, rapid-fire radio clarity",
    ),
    (
        "assets/audio/voices/null_choir_cmdr/null_choir_cmdr_threat.ogg",
        "Aegis or not, the grid will sing for us.",
        "George",
        "Null Choir Commander: deep masked male, resonator-filtered threat",
    ),
]


def read_fal_key() -> str:
    if not PROFILE_ENV.exists():
        raise SystemExit(f"missing Hermes profile env: {PROFILE_ENV}")
    for line in PROFILE_ENV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == "FAL_KEY":
            value = value.strip().strip('"').strip("'")
            if value:
                return value
    raise SystemExit("FAL_KEY not found in ~/.hermes/profiles/coder/.env")


def run_curl(url: str, method: str = "GET", payload: Dict[str, Any] | None = None, headers: Dict[str, str] | None = None, timeout: int = 180) -> bytes:
    cmd = ["curl", "-sS", "--fail", "--location", "--max-time", str(timeout)]
    if method.upper() != "GET":
        cmd += ["-X", method.upper()]
    for key, value in (headers or {}).items():
        cmd += ["-H", f"{key}: {value}"]
    if payload is not None:
        cmd += ["--data-binary", json.dumps(payload).encode("utf-8")]
    cmd.append(url)
    return subprocess.check_output(cmd, cwd=str(ROOT))


def fetch_url(url: str, timeout: int = 180) -> bytes:
    return run_curl(url, timeout=timeout)


def fetch_json(url: str, payload: Dict[str, Any] | None = None, headers: Dict[str, str] | None = None, timeout: int = 300) -> Dict[str, Any]:
    data = run_curl(url, method="POST" if payload is not None else "GET", payload=payload, headers=headers, timeout=timeout)
    return json.loads(data.decode("utf-8"))


def extract_audio_url(data: Dict[str, Any]) -> str:
    if "audio" in data and isinstance(data["audio"], dict) and isinstance(data["audio"].get("url"), str):
        return data["audio"]["url"]
    if "audio_file" in data and isinstance(data["audio_file"], dict) and isinstance(data["audio_file"].get("url"), str):
        return data["audio_file"]["url"]
    if "audio_url" in data and isinstance(data["audio_url"], str):
        return data["audio_url"]
    if "url" in data and isinstance(data["url"], str):
        return data["url"]
    raise KeyError(f"no audio URL in FAL response keys: {sorted(data.keys())}")


def fal_request(body: Dict[str, Any], attempts: int = 3) -> Dict[str, Any]:
    raise AssertionError("Use fal_generate(endpoint, body), not fal_request()")


def fal_generate(endpoint: str, body: Dict[str, Any], attempts: int = 3) -> Dict[str, Any]:
    headers = {"Authorization": f"Key {FAL_KEY}", "Content-Type": "application/json"}
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            url = f"https://fal.run/{endpoint}"
            data = json.dumps(body).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=300) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt == attempts:
                break
            time.sleep(3 * attempt)
    raise RuntimeError(f"FAL endpoint {endpoint} failed after {attempts} attempts: {last_error}")


def download_to(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    tmp.write_bytes(fetch_url(url, timeout=300))
    tmp.replace(dest)


def ffmpeg(args: List[str]) -> None:
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + args
    subprocess.run(cmd, check=True)


def encode_ogg(raw_wav_or_mp3: Path, out_ogg: Path, kind: str) -> None:
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    channels = 2 if kind == "music" else 1
    filters: List[str] = []
    if kind in {"sfx", "stinger", "voice"}:
        # Keep short lead-in/tail-out while removing obvious dead air.
        filters.append(
            "silenceremove=start_periods=1:start_duration=0.05:start_threshold=-45dB:start_silence=0.05:"
            "stop_periods=-1:stop_duration=0.15:stop_threshold=-45dB"
        )
    if kind == "music":
        filters.append("loudnorm=I=-18:LRA=11:TP=-3.0")
    else:
        filters.append("loudnorm=I=-16:LRA=11:TP=-1.5")
    filter_arg = ",".join(filters)
    ffmpeg_args = [
        "-i", str(raw_wav_or_mp3),
        "-af", filter_arg,
        "-ar", "48000",
        "-ac", str(channels),
        "-c:a", "libvorbis",
        "-q:a", "5",
        str(out_ogg),
    ]
    ffmpeg(ffmpeg_args)


def kenney_page_url(pack_slug: str) -> str:
    html = fetch_url(f"https://kenney.nl/assets/{pack_slug}", timeout=120).decode("utf-8", "ignore")
    match = re.search(r"href='([^']*kenney_[^']*\.zip)'", html)
    if not match:
        match = re.search(r'href="([^"]*kenney_[^"]*\.zip)"', html)
    if not match:
        raise RuntimeError(f"could not find Kenney zip URL for {pack_slug}")
    raw = match.group(1)
    return raw if raw.startswith("http") else "https://kenney.nl" + raw


def ensure_kenney_pack(pack_key: str) -> Path:
    slug = KENNEY_PACKS[pack_key]
    pack_dir = KENNEY_DIR / slug
    if pack_dir.exists() and any(pack_dir.rglob("*.ogg")):
        return pack_dir
    KENNEY_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = KENNEY_DIR / f"kenney_{slug}.zip"
    if not zip_path.exists():
        print(f"KENNEY download {slug}")
        download_to(kenney_page_url(slug), zip_path)
    extract_dir = KENNEY_DIR / f"kenney_{slug}"
    if not extract_dir.exists():
        extract_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract_dir)
    audio_dir = extract_dir / "Audio"
    if not audio_dir.exists():
        for candidate in extract_dir.rglob("Audio"):
            if candidate.is_dir():
                audio_dir = candidate
                break
    if not audio_dir.exists():
        raise RuntimeError(f"Kenney pack {slug} has no Audio directory")
    return audio_dir


def pick_kenney_file(pack_key: str, tokens: Iterable[str], index: int) -> Path:
    audio_dir = ensure_kenney_pack(pack_key)
    token_list = [t.lower() for t in tokens]
    files = sorted(audio_dir.glob("*.ogg"))
    for token in token_list:
        matches = [p for p in files if token in p.name.lower()]
        if matches:
            return matches[min(index, len(matches) - 1)]
    if files:
        return files[min(index, len(files) - 1)]
    raise RuntimeError(f"no OGG files found in Kenney pack {pack_key} at {audio_dir}")


def copy_kenney(dest_rel: str, pack_key: str, tokens: List[str], index: int) -> Dict[str, Any]:
    src = pick_kenney_file(pack_key, tokens, index)
    dest = ROOT / dest_rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        print(f"KENNEY skip {dest_rel}")
    else:
        shutil.copyfile(src, dest)
        print(f"KENNEY copy {src.name} -> {dest_rel}")
    return {
        "id": Path(dest_rel).stem,
        "path": "res://" + dest_rel,
        "source": f"Kenney CC0 {KENNEY_PACKS[pack_key]}",
        "source_file": str(src.relative_to(KENNEY_DIR)),
        "provider": "Kenney",
        "endpoint": "https://kenney.nl/assets/" + KENNEY_PACKS[pack_key],
        "prompt_or_source": "CC0 mechanical/UI sound selected from Kenney pack",
        "license": "CC0",
    }


def run_fal_job(dest_rel: str, endpoint: str, body: Dict[str, Any], kind: str, provider: str, prompt_or_source: str, license_text: str) -> Dict[str, Any]:
    dest = ROOT / dest_rel
    if dest.exists() and dest.stat().st_size > 0:
        print(f"FAL skip {dest_rel}")
        return {
            "id": Path(dest_rel).stem,
            "path": "res://" + dest_rel,
            "provider": provider,
            "endpoint": endpoint,
            "prompt": prompt_or_source,
            "output_path": "res://" + dest_rel,
            "license": license_text,
            "status": "existing",
        }
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    suffix = ".wav" if kind != "voice" else ".mp3"
    raw = RAW_DIR / f"{Path(dest_rel).stem}{suffix}"
    print(f"FAL generate {kind}: {dest_rel}")
    result = fal_generate(endpoint, body, attempts=3)
    url = extract_audio_url(result)
    download_to(url, raw)
    encode_ogg(raw, dest, kind)
    print(f"FAL wrote {dest_rel} ({dest.stat().st_size} bytes)")
    return {
        "id": Path(dest_rel).stem,
        "path": "res://" + dest_rel,
        "provider": provider,
        "endpoint": endpoint,
        "prompt": prompt_or_source,
        "output_path": "res://" + dest_rel,
        "license": license_text,
        "status": "generated",
    }


def write_sources(entries: List[Dict[str, Any]]) -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps({"pack": "aurora-vigil-p0-audio", "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "entries": entries}, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# Aurora Vigil — Audio Sources & Provenance",
        "",
        "Generated by `tools/audio_pipeline.py`. API keys are read from the Hermes coder profile and are never committed.",
        "",
        "## Provider routing",
        "",
        "- Mechanical/UI sounds: Kenney CC0 packs (`sci-fi-sounds`, `impact-sounds`, `interface-sounds`).",
        "- SFX, stingers, alerts, ambience: `fal-ai/stable-audio` (Stable Audio Open), field `seconds_total`, result key `audio_file`.",
        "- Music: `fal-ai/stable-audio-25/text-to-audio`, field `seconds_total`, result key `audio`.",
        "- Intelligible radio/civilian barks: FAL ElevenLabs TTS `fal-ai/elevenlabs/tts/turbo-v2.5` with distinct voice casting.",
        "",
        "## Casting sheet",
        "",
        "| Character | Voice profile | Lines generated |",
        "|-----------|---------------|-----------------|",
        "| Civic Grid AI | Calm synthetic alto, clipped radio-bandpass | civic_grid_alert |",
        "| Civilian Panicked | Young adult female, breathy urgent plea | civilian_panicked_help |",
        "| Civilian Grateful | Warm middle-aged male, relieved and shaken | civilian_grateful_thanks |",
        "| Emergency Dispatcher | Professional male, rapid-fire radio clarity | emergency_dispatcher_dispatch |",
        "| Null Choir Commander | Deep masked male, resonator-filtered threat | null_choir_cmdr_threat |",
        "",
        "## Audio files",
        "",
        "| Output path | Provider | Endpoint | Prompt/source | License |",
        "|-------------|----------|----------|---------------|---------|",
    ]
    for e in entries:
        prompt = str(e.get("prompt") or e.get("prompt_or_source") or e.get("source_file") or "")
        output_path = str(e.get("output_path") or e.get("path") or "")
        endpoint = str(e.get("endpoint") or "")
        provider = str(e.get("provider") or "unknown")
        license_text = str(e.get("license") or "unknown")
        prompt = prompt.replace("|", "\\|")
        output_path = output_path.replace("|", "\\|")
        lines.append(
            f"| `{output_path}` | {provider} | `{endpoint}` | {prompt} | {license_text} |"
        )
    lines += [
        "",
        "## Regenerating",
        "",
        "```bash",
        "cd /home/ganomix/projects/aurora-vigil",
        "python3 tools/audio_pipeline.py",
        "python3 tools/check_audio_wiring.py --require-existing-audio",
        "ffprobe -hide_banner assets/audio/**/*.ogg  # or run the Python verifier below",
        "```",
        "",
    ]
    SOURCES.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    global FAL_KEY
    FAL_KEY = read_fal_key()
    TMP.mkdir(parents=True, exist_ok=True)
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    OUT_ROOT.mkdir(parents=True, exist_ok=True)

    entries: List[Dict[str, Any]] = []
    for dest_rel, pack_key, tokens, index in KENNEY_JOBS:
        entries.append(copy_kenney(dest_rel, pack_key, tokens, index))

    for dest_rel, prompt, seconds, kind in FAL_SFX_JOBS:
        entries.append(run_fal_job(
            dest_rel,
            "fal-ai/stable-audio",
            {"prompt": prompt, "seconds_total": seconds},
            kind,
            "FAL stable-audio (Open)",
            prompt,
            "Stability AI Community License — verify current terms before commercial release",
        ))

    for dest_rel, prompt, seconds, kind in FAL_MUSIC_JOBS:
        entries.append(run_fal_job(
            dest_rel,
            "fal-ai/stable-audio-25/text-to-audio",
            {"prompt": prompt, "seconds_total": seconds, "num_inference_steps": 8, "guidance_scale": 1},
            kind,
            "FAL stable-audio-25",
            prompt,
            "Stability AI Community License — verify current terms before commercial release",
        ))

    for dest_rel, text, voice, profile in FAL_TTS_JOBS:
        entries.append(run_fal_job(
            dest_rel,
            "fal-ai/elevenlabs/tts/turbo-v2.5",
            {
                "text": text,
                "voice": voice,
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.25,
                "speed": 1.0,
                "apply_text_normalization": "auto",
            },
            "voice",
            "FAL ElevenLabs TTS turbo-v2.5",
            f"Voice={voice}; casting={profile}; line={text}",
            "FAL ElevenLabs — verify commercial use terms",
        ))

    write_sources(entries)
    print(f"AURORA_AUDIO_PIPELINE: PASS entries={len(entries)} out={OUT_ROOT}")
    return 0


if __name__ == "__main__":
    FAL_KEY = ""
    raise SystemExit(main())
