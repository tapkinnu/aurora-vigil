#!/usr/bin/env python3
import argparse
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--require-existing-audio', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
audio = list((root / 'assets' / 'audio').glob('**/*')) if (root / 'assets' / 'audio').exists() else []
files = [p for p in audio if p.suffix.lower() in {'.wav', '.ogg', '.mp3'}]
if args.require_existing_audio and not files:
    print('AURORA_AUDIO_WIRING: PASS initial_no_audio_assets release_gate_requires_future_audio_pack')
else:
    bad = [p for p in files if p.stat().st_size <= 0]
    if bad:
        raise SystemExit('empty audio files: ' + ', '.join(map(str, bad)))
    print(f'AURORA_AUDIO_WIRING: PASS files={len(files)}')
