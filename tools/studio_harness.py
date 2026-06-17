#!/usr/bin/env python3
"""Thin wrapper: run the shared studio QA harness against THIS repo.

The harness itself lives in /home/ganomix/projects/studio_harness and is shared
across game-studio repos. This file only points it at Aurora Vigil; all gate
logic is in the shared package, not here.
"""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path("/home/ganomix/projects/studio_harness")
sys.path.insert(0, str(HARNESS))

from studio_harness.cli import main  # noqa: E402

if __name__ == "__main__":
    argv = sys.argv[1:]
    if not argv:
        argv = ["run", str(REPO_ROOT)]
    raise SystemExit(main(argv))
