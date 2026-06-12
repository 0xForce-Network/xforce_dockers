#!/usr/bin/env bash
set -Eeuo pipefail

CREATIVE_IMAGE_ID="${CREATIVE_IMAGE_ID:-uncensored_creative01}"
CREATIVE_ROOT="${CREATIVE_ROOT:-/opt/creative}"
CREATIVE_CACHE_ROOT="${CREATIVE_CACHE_ROOT:-/workspace/cache/xforce_dockers/${CREATIVE_IMAGE_ID}}"
CREATIVE_MANIFEST_DIR="${CREATIVE_MANIFEST_DIR:-${CREATIVE_ROOT}/manifests}"
CREATIVE_REQUIREMENTS="${CREATIVE_REQUIREMENTS:-${CREATIVE_ROOT}/requirements-comfyui.txt}"
CREATIVE_CONSTRAINTS="${CREATIVE_CONSTRAINTS:-${CREATIVE_ROOT}/constraints-pytorch-cu124.txt}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-${CREATIVE_CACHE_ROOT}/pip-cache}"
WHEELHOUSE="${CREATIVE_WHEELHOUSE:-${CREATIVE_CACHE_ROOT}/wheelhouse}"
SOURCE_ARCHIVE_DIR="${CREATIVE_SOURCE_ARCHIVE_DIR:-${CREATIVE_CACHE_ROOT}/source-archives}"
REPO_ARTIFACT_DIR="${CREATIVE_REPO_ARTIFACT_DIR:-${CREATIVE_CACHE_ROOT}/artifacts/repos}"
HYDRATE_VENV="${CREATIVE_HYDRATE_VENV:-${PIP_CACHE_DIR}/hydrate-venv}"
ARIA2_JOBS="${ARIA2_JOBS:-16}"
VERIFY_ONLY=0
SKIP_PIP="${CREATIVE_HYDRATE_SKIP_PIP:-0}"

log() {
  printf '[creative-hydrate] %s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage: hydrate-creative-suite.sh [--verify-only]

Downloads deployment cache for the lightweight uncensored_creative01 image.
The cache is safe to reuse across container recreations when mounted at
CREATIVE_CACHE_ROOT.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verify-only)
      VERIFY_ONLY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

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

mkdir -p "$CREATIVE_CACHE_ROOT" "$PIP_CACHE_DIR" "$WHEELHOUSE" "$SOURCE_ARCHIVE_DIR" "$REPO_ARTIFACT_DIR"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "missing required command: ${cmd}"
    exit 1
  fi
}

download_one() {
  local name="$1"
  local url="$2"
  local dir="$3"
  local out="$4"
  local sha256="$5"
  local mode="${6:-0644}"
  local dest="${dir}/${out}"
  mkdir -p "$dir"
  if [ -s "$dest" ] && { [ -z "$sha256" ] || printf '%s  %s\n' "$sha256" "$dest" | sha256sum -c - >/dev/null 2>&1; }; then
    log "cache hit name=${name} path=${dest}"
    chmod "$mode" "$dest" || true
    return 0
  fi
  if [ "$VERIFY_ONLY" = "1" ]; then
    log "verify-only would download name=${name} url=${url} out=${dest}"
    return 0
  fi
  log "downloading name=${name} url=${url} out=${dest}"
  aria2c \
    --continue=true \
    --max-connection-per-server="$ARIA2_JOBS" \
    --split="$ARIA2_JOBS" \
    --min-split-size=1M \
    --retry-wait=5 \
    --max-tries=0 \
    --timeout=30 \
    --connect-timeout=15 \
    --dir="$dir" \
    --out="$out" \
    "$url"
  chmod "$mode" "$dest" || true
  if [ -n "$sha256" ]; then
    printf '%s  %s\n' "$sha256" "$dest" | sha256sum -c -
  fi
}

extract_source_archive() {
  local name="$1"
  local archive="$2"
  local marker="$3"
  local dest="$4"
  local extract_tmp="${SOURCE_ARCHIVE_DIR}/${name}.extract.$$"
  if [ -e "${dest}/${marker}" ]; then
    log "source cache hit name=${name} dest=${dest}"
    return 0
  fi
  if [ "$VERIFY_ONLY" = "1" ]; then
    log "verify-only would extract source name=${name} archive=${archive} dest=${dest}"
    return 0
  fi
  rm -rf "$extract_tmp"
  mkdir -p "$extract_tmp"
  tar -xzf "$archive" -C "$extract_tmp" --strip-components=1
  test -e "${extract_tmp}/${marker}"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  mv "$extract_tmp" "$dest"
}

write_lines() {
  local file="$1"
  shift
  : > "$file"
  for item in "$@"; do
    printf '%s\n' "$item" >> "$file"
  done
}

if [ "$VERIFY_ONLY" != "1" ]; then
  require_command aria2c
fi
require_command python3
require_command tar
require_command sha256sum

log "manifest=${CREATIVE_MANIFEST_ID:-unknown} platform=${CREATIVE_MANIFEST_PLATFORM:-unknown} arch=${ARCH} cache=${CREATIVE_CACHE_ROOT}"

if [ "${#RUNTIME_ARTIFACTS[@]}" -gt 0 ]; then
  for artifact in "${RUNTIME_ARTIFACTS[@]}"; do
    IFS='|' read -r name url out sha256 mode rel_dir <<< "$artifact"
    download_one "$name" "$url" "${CREATIVE_CACHE_ROOT}/${rel_dir}" "$out" "$sha256" "$mode"
  done
fi

if [ "${#TORCH_WHEEL_URLS[@]}" -gt 0 ]; then
  for torch_item in "${TORCH_WHEEL_URLS[@]}"; do
    IFS='|' read -r url out sha256 <<< "$torch_item"
    download_one "torch-wheel" "$url" "$WHEELHOUSE" "$out" "$sha256" 0644
  done
fi

if [ "${#SOURCE_ARCHIVES[@]}" -gt 0 ]; then
  for source in "${SOURCE_ARCHIVES[@]}"; do
    IFS='|' read -r name url out marker rel_dest <<< "$source"
    download_one "$name" "$url" "$SOURCE_ARCHIVE_DIR" "$out" "" 0644
    extract_source_archive "$name" "${SOURCE_ARCHIVE_DIR}/${out}" "$marker" "${CREATIVE_CACHE_ROOT}/${rel_dest}"
  done
fi

if [ "$SKIP_PIP" != "1" ]; then
  if [ "$VERIFY_ONLY" = "1" ]; then
    log "verify-only would resolve pip wheelhouse via ${PYPI_INDEX_URL} and ${PYTORCH_INDEX_URL}"
  else
    python3 -m venv "$HYDRATE_VENV"
    write_lines "${PIP_CACHE_DIR}/bootstrap-requirements.txt" "${BOOTSTRAP_REQUIREMENTS[@]}"
    "$HYDRATE_VENV/bin/pip" install --upgrade pip wheel setuptools packaging
    "$HYDRATE_VENV/bin/pip" download \
      --dest "$WHEELHOUSE" \
      --cache-dir "$PIP_CACHE_DIR" \
      --prefer-binary \
      --index-url "$PYPI_INDEX_URL" \
      -r "${PIP_CACHE_DIR}/bootstrap-requirements.txt"
    if [ "${#TORCH_PACKAGES[@]}" -gt 0 ]; then
      write_lines "${PIP_CACHE_DIR}/torch-requirements.txt" "${TORCH_PACKAGES[@]}"
      "$HYDRATE_VENV/bin/pip" download \
        --dest "$WHEELHOUSE" \
        --cache-dir "$PIP_CACHE_DIR" \
        --prefer-binary \
        --find-links "$WHEELHOUSE" \
        --index-url "$PYTORCH_INDEX_URL" \
        -r "${PIP_CACHE_DIR}/torch-requirements.txt"
    fi
    comfy_req="${CREATIVE_CACHE_ROOT}/artifacts/repos/ComfyUI/requirements.txt"
    pip_args=(
      --dest "$WHEELHOUSE"
      --cache-dir "$PIP_CACHE_DIR"
      --prefer-binary
      --find-links "$WHEELHOUSE"
      --index-url "$PYPI_INDEX_URL"
      --extra-index-url "$PYTORCH_INDEX_URL"
    )
    if [ -f "$CREATIVE_CONSTRAINTS" ] && [ "$ARCH" = "amd64" ]; then
      pip_args+=(--constraint "$CREATIVE_CONSTRAINTS")
    fi
    pip_args+=(-r "$CREATIVE_REQUIREMENTS")
    if [ -f "$comfy_req" ]; then
      pip_args+=(-r "$comfy_req")
    fi
    "$HYDRATE_VENV/bin/pip" download "${pip_args[@]}"
  fi
fi

manifest_file="${CREATIVE_CACHE_ROOT}/HYDRATE_MANIFEST.txt"
{
  printf 'created_at=%s\n' "$(date -u +%FT%TZ)"
  printf 'image_id=%s\n' "$CREATIVE_IMAGE_ID"
  printf 'arch=%s\n' "$ARCH"
  printf 'manifest_id=%s\n' "${CREATIVE_MANIFEST_ID:-unknown}"
  printf 'cache_root=%s\n' "$CREATIVE_CACHE_ROOT"
  printf 'wheelhouse=%s\n' "$WHEELHOUSE"
  find "$WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -printf 'wheel=%f\n' 2>/dev/null | sort || true
} > "$manifest_file"

log "hydrate complete manifest=${manifest_file}"
