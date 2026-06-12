#!/usr/bin/env bash
set -Eeuo pipefail

CREATIVE_IMAGE_ID="${CREATIVE_IMAGE_ID:-uncensored_creative01}"
CREATIVE_ROOT="${CREATIVE_ROOT:-/opt/creative}"
CREATIVE_CACHE_ROOT="${CREATIVE_CACHE_ROOT:-/workspace/cache/xforce_dockers/${CREATIVE_IMAGE_ID}}"
COMFYUI_DIR="${COMFYUI_DIR:-${CREATIVE_ROOT}/ComfyUI}"
COMFYUI_VENV="${COMFYUI_VENV:-/venv/comfyui}"
STATE_DIR="${CREATIVE_STATE_DIR:-/workspace/.xforce-creative-state}"

python3 - <<'PY' "$CREATIVE_IMAGE_ID" "$CREATIVE_ROOT" "$CREATIVE_CACHE_ROOT" "$COMFYUI_DIR" "$COMFYUI_VENV" "$STATE_DIR"
from __future__ import annotations
import json
import sys
from pathlib import Path

image_id, creative_root, cache_root, comfyui_dir, comfyui_venv, state_dir = sys.argv[1:]
cache = Path(cache_root)
wheelhouse = cache / "wheelhouse"
status_file = Path(state_dir) / "install-status.json"
payload = {
    "imageId": image_id,
    "creativeRoot": creative_root,
    "cacheRoot": cache_root,
    "cacheExists": cache.exists(),
    "wheelCount": len(list(wheelhouse.glob("*.whl"))) if wheelhouse.exists() else 0,
    "hydrateManifest": str(cache / "HYDRATE_MANIFEST.txt"),
    "hydrateManifestExists": (cache / "HYDRATE_MANIFEST.txt").exists(),
    "comfyuiInstalled": (Path(comfyui_dir) / "main.py").exists(),
    "comfyuiVenvExists": Path(comfyui_venv).exists(),
    "ollamaInstalled": Path("/usr/local/bin/ollama").exists(),
    "cloudflaredInstalled": Path("/usr/local/bin/cloudflared").exists(),
    "installStatusPath": str(status_file),
    "installStatusExists": status_file.exists(),
}
if status_file.exists():
    try:
        payload["installStatus"] = json.loads(status_file.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - diagnostic only
        payload["installStatusError"] = str(exc)
print(json.dumps(payload, indent=2, sort_keys=True))
PY
