#!/usr/bin/env bash
set -Eeuo pipefail

COMFYUI_API="${COMFYUI_API:-http://127.0.0.1:8188}"

log() {
  printf '[creative-vram-unload] %s\n' "$*" >&2
}

payload='{"unload_models": true, "free_memory": true}'

if curl -fsS -X POST "${COMFYUI_API}/free" -H 'Content-Type: application/json' -d "$payload" >/dev/null; then
  log "status=ok endpoint=${COMFYUI_API}/free"
  exit 0
fi

if curl -fsS -X POST "${COMFYUI_API}/api/unload" -H 'Content-Type: application/json' -d "$payload" >/dev/null; then
  log "status=ok endpoint=${COMFYUI_API}/api/unload"
  exit 0
fi

log "status=warn reason=unload_endpoint_unavailable api=${COMFYUI_API}"
exit 0
