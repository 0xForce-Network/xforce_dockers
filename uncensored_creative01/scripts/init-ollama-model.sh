#!/usr/bin/env bash
set -Eeuo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
MODEL_NAME="${CREATIVE_OLLAMA_MODEL:-qwen2.5-creative}"
MODELFILE="${CREATIVE_OLLAMA_MODELFILE:-/opt/creative/Modelfile.qwen2.5-creative}"
MODEL_GGUF="${CREATIVE_OLLAMA_GGUF:-/workspace/models/llm/qwen2.5-creative-q4_k_m.gguf}"
STAMP_DIR="${CREATIVE_STATE_DIR:-/workspace/.xforce-creative-state}"
STAMP_FILE="${STAMP_DIR}/ollama-${MODEL_NAME}.created"
TIMEOUT_SECONDS="${CREATIVE_OLLAMA_WAIT_SECONDS:-120}"

log() {
  printf '[creative-ollama-init] %s\n' "$*" >&2
}

mkdir -p "$STAMP_DIR"

if [ -f "$STAMP_FILE" ] && ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$MODEL_NAME"; then
  log "model=${MODEL_NAME} status=already_created"
  exit 0
fi

if [ ! -f "$MODELFILE" ]; then
  log "status=skipped reason=model_file_missing path=${MODELFILE}"
  exit 0
fi

if [ ! -f "$MODEL_GGUF" ]; then
  log "status=skipped reason=gguf_missing path=${MODEL_GGUF} hint=run_provisioner_or_upload_model"
  exit 0
fi

elapsed=0
until curl -fsS "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; do
  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    log "status=failed reason=ollama_timeout host=${OLLAMA_HOST}"
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

log "status=creating model=${MODEL_NAME} model_file=${MODELFILE}"
ollama create "$MODEL_NAME" -f "$MODELFILE"
date -u +%Y-%m-%dT%H:%M:%SZ > "$STAMP_FILE"
log "status=created model=${MODEL_NAME}"
