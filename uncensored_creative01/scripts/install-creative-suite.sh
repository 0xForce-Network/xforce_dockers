#!/usr/bin/env bash
set -Eeuo pipefail

CREATIVE_IMAGE_ID="${CREATIVE_IMAGE_ID:-uncensored_creative01}"
CREATIVE_ROOT="${CREATIVE_ROOT:-/opt/creative}"
CREATIVE_CACHE_ROOT="${CREATIVE_CACHE_ROOT:-/workspace/cache/xforce_dockers/${CREATIVE_IMAGE_ID}}"
CREATIVE_MANIFEST_DIR="${CREATIVE_MANIFEST_DIR:-${CREATIVE_ROOT}/manifests}"
COMFYUI_DIR="${COMFYUI_DIR:-${CREATIVE_ROOT}/ComfyUI}"
COMFYUI_VENV="${COMFYUI_VENV:-/venv/comfyui}"
WHEELHOUSE="${CREATIVE_WHEELHOUSE:-${CREATIVE_CACHE_ROOT}/wheelhouse}"
CREATIVE_REQUIREMENTS="${CREATIVE_REQUIREMENTS:-${CREATIVE_ROOT}/requirements-comfyui.txt}"
CREATIVE_CONSTRAINTS="${CREATIVE_CONSTRAINTS:-${CREATIVE_ROOT}/constraints-pytorch-cu124.txt}"
XFORCE_UID="${XFORCE_UID:-1000}"
XFORCE_GID="${XFORCE_GID:-1000}"
HYDRATE_IF_MISSING="${CREATIVE_HYDRATE_IF_MISSING:-1}"

log() {
  printf '[creative-install] %s\n' "$*" >&2
}

normalize_arch() {
  local raw="${1:-$(uname -m)}"
  case "$raw" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *) printf '%s' "$raw" ;;
  esac
}

ARCH="$(normalize_arch "${TARGETARCH:-${CREATIVE_TARGET_ARCH:-}}")"
MANIFEST="${CREATIVE_DEP_MANIFEST:-${CREATIVE_MANIFEST_DIR}/deps.${ARCH}.sh}"
if [ ! -f "$MANIFEST" ]; then
  log "missing manifest=${MANIFEST} arch=${ARCH}"
  exit 1
fi
# shellcheck source=/dev/null
source "$MANIFEST"

if [ ! -d "$WHEELHOUSE" ] || ! find "$WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -print -quit | grep -q .; then
  if [ "$HYDRATE_IF_MISSING" = "1" ]; then
    log "wheelhouse missing; hydrating cache first"
    "${CREATIVE_ROOT}/bin/hydrate-creative-suite.sh"
  else
    log "wheelhouse missing and CREATIVE_HYDRATE_IF_MISSING=0"
    exit 1
  fi
fi

mkdir -p "$CREATIVE_ROOT" "$COMFYUI_VENV" /workspace/models/ollama /workspace/models/checkpoints /workspace/models/loras /workspace/outputs /workspace/creative

copy_repo() {
  local src="$1"
  local dest="$2"
  local marker="$3"
  if [ ! -e "${src}/${marker}" ]; then
    log "missing repo artifact src=${src} marker=${marker}"
    exit 1
  fi
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  rsync -a --delete "${src}/" "${dest}/"
}

copy_repo "${CREATIVE_CACHE_ROOT}/artifacts/repos/ComfyUI" "$COMFYUI_DIR" main.py
mkdir -p "${COMFYUI_DIR}/custom_nodes"
copy_repo "${CREATIVE_CACHE_ROOT}/artifacts/repos/ComfyUI-Manager" "${COMFYUI_DIR}/custom_nodes/ComfyUI-Manager" __init__.py
copy_repo "${CREATIVE_CACHE_ROOT}/artifacts/repos/ComfyUI-Ollama" "${COMFYUI_DIR}/custom_nodes/ComfyUI-Ollama" __init__.py
copy_repo "${CREATIVE_CACHE_ROOT}/artifacts/repos/AIGODLIKE-ComfyUI-Translation" "${COMFYUI_DIR}/custom_nodes/AIGODLIKE-ComfyUI-Translation" README.md

python3 -m venv "$COMFYUI_VENV"
"${COMFYUI_VENV}/bin/pip" install --no-index --find-links "$WHEELHOUSE" --upgrade pip wheel setuptools packaging
if [ "${#TORCH_PACKAGES[@]}" -gt 0 ]; then
  "${COMFYUI_VENV}/bin/pip" install --no-index --find-links "$WHEELHOUSE" --prefer-binary "${TORCH_PACKAGES[@]}"
fi
base_pip_args=(--no-index --find-links "$WHEELHOUSE" --prefer-binary)
if [ -f "$CREATIVE_CONSTRAINTS" ] && [ "$ARCH" = "amd64" ]; then
  base_pip_args+=(--constraint "$CREATIVE_CONSTRAINTS")
fi
"${COMFYUI_VENV}/bin/pip" install "${base_pip_args[@]}" -r "$CREATIVE_REQUIREMENTS"
if [ -f "${COMFYUI_DIR}/requirements.txt" ]; then
  "${COMFYUI_VENV}/bin/pip" install "${base_pip_args[@]}" -r "${COMFYUI_DIR}/requirements.txt"
fi

ollama_artifact=""
cloudflared_artifact=""
if [ "${#RUNTIME_ARTIFACTS[@]}" -gt 0 ]; then
  for artifact in "${RUNTIME_ARTIFACTS[@]}"; do
    IFS='|' read -r name _url out _sha256 _mode rel_dir <<< "$artifact"
    case "$name" in
      ollama) ollama_artifact="${CREATIVE_CACHE_ROOT}/${rel_dir}/${out}" ;;
      cloudflared) cloudflared_artifact="${CREATIVE_CACHE_ROOT}/${rel_dir}/${out}" ;;
    esac
  done
fi

if [ -n "$ollama_artifact" ] && [ -s "$ollama_artifact" ]; then
  case "$ollama_artifact" in
    *.tar.zst) tar --zstd -xf "$ollama_artifact" -C /usr/local ;;
    *.tgz|*.tar.gz) tar -xzf "$ollama_artifact" -C /usr/local ;;
    *) log "unknown ollama artifact format: ${ollama_artifact}"; exit 1 ;;
  esac
fi
if [ -n "$cloudflared_artifact" ] && [ -s "$cloudflared_artifact" ]; then
  install -m 0755 "$cloudflared_artifact" /usr/local/bin/cloudflared
fi

mkdir -p "${CREATIVE_STATE_DIR:-/workspace/.xforce-creative-state}"
cat > "${CREATIVE_STATE_DIR:-/workspace/.xforce-creative-state}/install-status.json" <<JSON
{"imageId":"${CREATIVE_IMAGE_ID}","arch":"${ARCH}","installedAt":"$(date -u +%FT%TZ)","creativeRoot":"${CREATIVE_ROOT}","comfyuiDir":"${COMFYUI_DIR}","comfyuiVenv":"${COMFYUI_VENV}"}
JSON

chown -R "${XFORCE_UID}:${XFORCE_GID}" "$CREATIVE_ROOT" "$COMFYUI_VENV" /workspace/models /workspace/outputs /workspace/creative "${CREATIVE_STATE_DIR:-/workspace/.xforce-creative-state}" || true
log "install complete"
