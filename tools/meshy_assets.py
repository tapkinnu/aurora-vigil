#!/usr/bin/env python3
"""Reusable Meshy AI asset pipeline for Aurora Vigil.

Drives, per asset declared in data/manifest/meshy_assets.json, the full
text-to-3D pipeline:

    preview  ->  refine (textured)  ->  remesh (MANDATORY)  ->  download GLB

The remesh stage is required before game integration: it normalises topology
and polycount and resizes the mesh to a target real-world height so scale is
predictable (then verified empirically in Godot via tools/verify_glb_scale.gd).

The API key is read from $MESHY_KEY (preferred) or $MESY_API_KEY. It is never
printed or logged.

State is cached in data/manifest/meshy_state.json so interrupted runs resume
instead of re-spending credits. Provenance is written to
data/manifest/meshy_provenance.json.

Usage:
    tools/meshy_assets.py                 # process every asset in the manifest
    tools/meshy_assets.py --only lumen    # one asset by id (repeatable)
    tools/meshy_assets.py --force         # ignore cached state, regenerate
    tools/meshy_assets.py --status        # print cached state, no API calls
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "data", "manifest", "meshy_assets.json")
STATE = os.path.join(ROOT, "data", "manifest", "meshy_state.json")
PROVENANCE = os.path.join(ROOT, "data", "manifest", "meshy_provenance.json")

API_BASE = "https://api.meshy.ai/openapi"
POLL_INTERVAL = 6.0
STAGE_TIMEOUT = 900.0  # seconds per async stage


class MeshyRetryable(Exception):
    """A transient Meshy failure worth retrying with a fresh task."""


RETRYABLE_TYPES = {"service_unavailable", "internal_error", "rate_limited"}


def log(msg: str) -> None:
    print(f"[meshy] {msg}", flush=True)


def get_key() -> str:
    key = os.environ.get("MESHY_KEY") or os.environ.get("MESY_API_KEY") or ""
    key = key.strip()
    if not key:
        log("ERROR: no Meshy key in $MESHY_KEY or $MESY_API_KEY")
        sys.exit(2)
    return key


def _request(method: str, url: str, key: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"HTTP {e.code} {method} {url.split('/openapi')[-1]}: {detail}") from None
    if not raw:
        return {}
    return json.loads(raw)


def balance(key: str) -> int:
    return int(_request("GET", f"{API_BASE}/v1/balance", key).get("balance", -1))


def poll(stage: str, get_url: str, key: str) -> dict:
    start = time.time()
    last_progress = -1
    while True:
        info = _request("GET", get_url, key)
        status = info.get("status")
        progress = info.get("progress", 0)
        if progress != last_progress:
            log(f"  {stage}: {status} {progress}%")
            last_progress = progress
        if status == "SUCCEEDED":
            return info
        if status in ("FAILED", "CANCELED", "EXPIRED"):
            err = info.get("task_error") or {}
            etype = err.get("type", "") if isinstance(err, dict) else ""
            msg = f"{stage} {status}: {err or info}"
            if etype in RETRYABLE_TYPES or status == "EXPIRED":
                raise MeshyRetryable(msg)
            raise RuntimeError(msg)
        if time.time() - start > STAGE_TIMEOUT:
            raise MeshyRetryable(f"{stage} timed out after {STAGE_TIMEOUT:.0f}s (last status {status})")
        time.sleep(POLL_INTERVAL)


def load_json(path: str, default):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return default


def save_json(path: str, obj) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def download(url: str, dest: str) -> tuple[int, str]:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as resp, open(dest, "wb") as f:
        data = resp.read()
        f.write(data)
    h = hashlib.sha256(data).hexdigest()
    return len(data), h


def stage_preview(asset: dict, manifest: dict, key: str) -> str:
    body = {
        "mode": "preview",
        "prompt": asset["prompt"],
        "art_style": manifest.get("art_style", "realistic"),
        "ai_model": manifest.get("ai_model", "meshy-4"),
        "topology": asset.get("topology", "triangle"),
        "target_polycount": asset.get("target_polycount", 20000),
        "should_remesh": True,
        "negative_prompt": manifest.get("negative_prompt", ""),
    }
    res = _request("POST", f"{API_BASE}/v2/text-to-3d", key, body)
    tid = res.get("result")
    log(f"  preview task: {tid}")
    return tid


def stage_refine(preview_id: str, key: str) -> str:
    body = {"mode": "refine", "preview_task_id": preview_id, "enable_pbr": True}
    res = _request("POST", f"{API_BASE}/v2/text-to-3d", key, body)
    tid = res.get("result")
    log(f"  refine task: {tid}")
    return tid


def stage_remesh(asset: dict, refine_id: str, key: str) -> str:
    body = {
        "input_task_id": refine_id,
        "target_formats": ["glb"],
        "topology": asset.get("topology", "triangle"),
        "target_polycount": asset.get("target_polycount", 20000),
        "resize_height": float(asset.get("target_height_m", 1.0)),
        "origin_at": "bottom",
    }
    res = _request("POST", f"{API_BASE}/v1/remesh", key, body)
    tid = res.get("result")
    log(f"  remesh task: {tid}")
    return tid


MAX_RETRIES = 4


def run_stage(name: str, id_key: str, get_base: str, create_fn, st: dict, state: dict, aid: str, key: str) -> dict:
    """Create (if needed), poll, and retry a single async stage.

    On a retryable failure the stored task id is discarded and the stage is
    recreated with exponential backoff, so a transient Meshy outage does not
    abort the whole run."""
    for attempt in range(1, MAX_RETRIES + 1):
        if not st.get(id_key):
            st[id_key] = create_fn()
            state[aid] = st
            save_json(STATE, state)
        try:
            return poll(name, f"{get_base}/{st[id_key]}", key)
        except MeshyRetryable as e:
            log(f"  {name} retryable failure (attempt {attempt}/{MAX_RETRIES}): {e}")
            st[id_key] = ""
            state[aid] = st
            save_json(STATE, state)
            if attempt == MAX_RETRIES:
                raise RuntimeError(f"{name} failed after {MAX_RETRIES} attempts: {e}") from None
            time.sleep(min(30.0, 5.0 * attempt))
    raise RuntimeError(f"{name} exhausted retries")


def process(asset: dict, manifest: dict, key: str, state: dict, force: bool) -> dict:
    aid = asset["id"]
    st = {} if force else dict(state.get(aid, {}))
    log(f"asset '{aid}' ({asset['name']})")

    run_stage("preview", "preview_id", f"{API_BASE}/v2/text-to-3d",
              lambda: stage_preview(asset, manifest, key), st, state, aid, key)

    run_stage("refine", "refine_id", f"{API_BASE}/v2/text-to-3d",
              lambda: stage_refine(st["preview_id"], key), st, state, aid, key)

    remesh_info = run_stage("remesh", "remesh_id", f"{API_BASE}/v1/remesh",
                            lambda: stage_remesh(asset, st["refine_id"], key), st, state, aid, key)

    glb_url = (remesh_info.get("model_urls") or {}).get("glb")
    if not glb_url:
        raise RuntimeError(f"remesh produced no GLB url: {remesh_info}")

    # Download
    dest = os.path.join(ROOT, asset["out_path"])
    size, sha = download(glb_url, dest)
    log(f"  downloaded {asset['out_path']} ({size} bytes)")
    st["glb_path"] = asset["out_path"]
    st["bytes"] = size
    st["sha256"] = sha
    state[aid] = st
    save_json(STATE, state)

    return {
        "id": aid,
        "name": asset["name"],
        "kind": asset.get("kind"),
        "provider": "Meshy AI",
        "prompt": asset["prompt"],
        "negative_prompt": manifest.get("negative_prompt", ""),
        "art_style": manifest.get("art_style"),
        "ai_model": manifest.get("ai_model"),
        "target_polycount": asset.get("target_polycount"),
        "topology": asset.get("topology"),
        "remesh_resize_height_m": asset.get("target_height_m"),
        "preview_task_id": st["preview_id"],
        "refine_task_id": st["refine_id"],
        "remesh_task_id": st["remesh_id"],
        "glb_path": asset["out_path"],
        "bytes": size,
        "sha256": sha,
        "license": "Meshy AI generated asset (per Meshy ToS) - original IP, no third-party characters",
        "downloaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=[], help="asset id(s) to process")
    ap.add_argument("--force", action="store_true", help="ignore cached state")
    ap.add_argument("--status", action="store_true", help="print cached state and exit")
    args = ap.parse_args()

    manifest = load_json(MANIFEST, None)
    if manifest is None:
        log(f"ERROR: manifest not found at {MANIFEST}")
        return 2
    state = load_json(STATE, {})

    if args.status:
        print(json.dumps(state, indent=2))
        return 0

    key = get_key()
    bal = balance(key)
    log(f"balance: {bal}")
    if bal <= 0:
        log("ERROR: insufficient Meshy balance")
        return 2

    assets = manifest["assets"]
    if args.only:
        assets = [a for a in assets if a["id"] in args.only]
        if not assets:
            log(f"ERROR: no manifest asset matched {args.only}")
            return 2

    provenance = load_json(PROVENANCE, {"provider": "Meshy AI", "assets": []})
    prov_by_id = {p["id"]: p for p in provenance.get("assets", [])}
    for asset in assets:
        rec = process(asset, manifest, key, state, args.force)
        prov_by_id[rec["id"]] = rec
    provenance["assets"] = list(prov_by_id.values())
    provenance["generated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    save_json(PROVENANCE, provenance)
    log(f"done. provenance -> {os.path.relpath(PROVENANCE, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
