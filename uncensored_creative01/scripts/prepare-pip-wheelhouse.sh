#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${F013_ROOT:-/data/xforce_ai_test/xforce-creative-suite}"
SRC="${F013_SRC:-${ROOT}/src/workspace_web}"
APP_DIR="${SRC}/xforce_dockers/uncensored_creative01"
WHEELHOUSE="${F013_WHEELHOUSE:-${APP_DIR}/wheelhouse}"
ARTIFACT_DIR="${F013_ARTIFACT_DIR:-${APP_DIR}/artifacts}"
OLLAMA_ARTIFACT_DIR="${F013_OLLAMA_ARTIFACT_DIR:-${ARTIFACT_DIR}/ollama}"
OLLAMA_ARTIFACT_URL="${OLLAMA_ARTIFACT_URL:-https://ollama.com/download/ollama-linux-amd64.tar.zst}"
OLLAMA_ARTIFACT_NAME="${OLLAMA_ARTIFACT_NAME:-ollama-linux-amd64.tar.zst}"
CLOUDFLARED_ARTIFACT_DIR="${F013_CLOUDFLARED_ARTIFACT_DIR:-${ARTIFACT_DIR}/cloudflared}"
CLOUDFLARED_ARTIFACT_URL="${CLOUDFLARED_ARTIFACT_URL:-https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64}"
CLOUDFLARED_ARTIFACT_NAME="${CLOUDFLARED_ARTIFACT_NAME:-cloudflared-linux-amd64}"
REPO_ARTIFACT_DIR="${F013_REPO_ARTIFACT_DIR:-${ARTIFACT_DIR}/repos}"
SOURCE_ARCHIVE_DIR="${F013_SOURCE_ARCHIVE_DIR:-${ARTIFACT_DIR}/source-archives}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-${ROOT}/cache/pip}"
VENV="${F013_WHEELHOUSE_VENV:-${PIP_CACHE_DIR}/wheelhouse-venv}"
COMFYUI_REF="${COMFYUI_REF:-master}"
COMFYUI_REQ_SRC="${PIP_CACHE_DIR}/ComfyUI-${COMFYUI_REF}"
PYTORCH_INDEX_URL="${PYTORCH_INDEX_URL:-https://download.pytorch.org/whl/cu124}"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://pypi.org/simple}"
ARIA2_JOBS="${ARIA2_JOBS:-16}"

log() {
  printf '[pip-wheelhouse] %s\n' "$*" >&2
}

download_source_archive() {
  local name="$1"
  local url="$2"
  local out_name="$3"
  local marker="$4"
  local archive="${SOURCE_ARCHIVE_DIR}/${out_name}"
  local extract_tmp="${SOURCE_ARCHIVE_DIR}/${name}.extract.$$"
  local dest="${REPO_ARTIFACT_DIR}/${name}"

  log "prefetching source snapshot ${name} into ${dest}"
  aria2c \
    --continue=true \
    --max-connection-per-server="$ARIA2_JOBS" \
    --split="$ARIA2_JOBS" \
    --min-split-size=1M \
    --retry-wait=5 \
    --max-tries=0 \
    --timeout=30 \
    --connect-timeout=15 \
    --dir="$SOURCE_ARCHIVE_DIR" \
    --out="$out_name" \
    "$url"

  rm -rf "$extract_tmp"
  mkdir -p "$extract_tmp"
  tar -xzf "$archive" -C "$extract_tmp" --strip-components=1
  test -e "${extract_tmp}/${marker}"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  mv "$extract_tmp" "$dest"
}

mkdir -p "$WHEELHOUSE" "$PIP_CACHE_DIR" "$OLLAMA_ARTIFACT_DIR" "$CLOUDFLARED_ARTIFACT_DIR" "$REPO_ARTIFACT_DIR" "$SOURCE_ARCHIVE_DIR"

if ! command -v aria2c >/dev/null 2>&1; then
  log "aria2c missing; installing host package for multi-connection resume downloads"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends aria2
fi

python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip wheel setuptools packaging

bootstrap_requirements="${PIP_CACHE_DIR}/bootstrap-requirements.txt"
cat > "$bootstrap_requirements" <<'REQS'
pip
wheel
setuptools
packaging
python-multipart==0.0.20
REQS

log "downloading build/runtime bootstrap wheels into ${WHEELHOUSE}"
"$VENV/bin/pip" download \
  --dest "$WHEELHOUSE" \
  --cache-dir "$PIP_CACHE_DIR" \
  --prefer-binary \
  --index-url "$PYPI_INDEX_URL" \
  -r "$bootstrap_requirements"

torch_urls="${PIP_CACHE_DIR}/torch-cu124.urls"
cat > "$torch_urls" <<'URLS'
https://download.pytorch.org/whl/cu124/torch-2.5.1%2Bcu124-cp312-cp312-linux_x86_64.whl
  out=torch-2.5.1+cu124-cp312-cp312-linux_x86_64.whl
https://download.pytorch.org/whl/cu124/torchvision-0.20.1%2Bcu124-cp312-cp312-linux_x86_64.whl
  out=torchvision-0.20.1+cu124-cp312-cp312-linux_x86_64.whl
https://download.pytorch.org/whl/cu124/torchaudio-2.5.1%2Bcu124-cp312-cp312-linux_x86_64.whl
  out=torchaudio-2.5.1+cu124-cp312-cp312-linux_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cuda_nvrtc_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cuda_nvrtc_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cuda_runtime_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cuda_runtime_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cuda_cupti_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cuda_cupti_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cudnn_cu12-9.1.0.70-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cudnn_cu12-9.1.0.70-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cublas_cu12-12.4.5.8-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cublas_cu12-12.4.5.8-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cufft_cu12-11.2.1.3-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cufft_cu12-11.2.1.3-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_curand_cu12-10.3.5.147-py3-none-manylinux2014_x86_64.whl
  out=nvidia_curand_cu12-10.3.5.147-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cusolver_cu12-11.6.1.9-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cusolver_cu12-11.6.1.9-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cusparse_cu12-12.3.1.170-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cusparse_cu12-12.3.1.170-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_cusparselt_cu12-0.6.2-py3-none-manylinux2014_x86_64.whl
  out=nvidia_cusparselt_cu12-0.6.2-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_nccl_cu12-2.21.5-py3-none-manylinux2014_x86_64.whl
  out=nvidia_nccl_cu12-2.21.5-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_nvtx_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
  out=nvidia_nvtx_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
https://download.pytorch.org/whl/cu124/nvidia_nvjitlink_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
  out=nvidia_nvjitlink_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl
URLS

log "prefetching explicit PyTorch CUDA wheels and NVIDIA dependency wheels into ${WHEELHOUSE}"
aria2c \
  --continue=true \
  --max-connection-per-server="$ARIA2_JOBS" \
  --split="$ARIA2_JOBS" \
  --min-split-size=8M \
  --retry-wait=5 \
  --max-tries=0 \
  --timeout=30 \
  --connect-timeout=15 \
  --dir="$WHEELHOUSE" \
  --input-file="$torch_urls"

log "prefetching Ollama artifact into ${OLLAMA_ARTIFACT_DIR}"
aria2c \
  --continue=true \
  --max-connection-per-server="$ARIA2_JOBS" \
  --split="$ARIA2_JOBS" \
  --min-split-size=8M \
  --retry-wait=5 \
  --max-tries=0 \
  --timeout=30 \
  --connect-timeout=15 \
  --dir="$OLLAMA_ARTIFACT_DIR" \
  --out="$OLLAMA_ARTIFACT_NAME" \
  "$OLLAMA_ARTIFACT_URL"

log "prefetching Cloudflared artifact into ${CLOUDFLARED_ARTIFACT_DIR}"
aria2c \
  --continue=true \
  --max-connection-per-server="$ARIA2_JOBS" \
  --split="$ARIA2_JOBS" \
  --min-split-size=1M \
  --retry-wait=5 \
  --max-tries=0 \
  --timeout=30 \
  --connect-timeout=15 \
  --dir="$CLOUDFLARED_ARTIFACT_DIR" \
  --out="$CLOUDFLARED_ARTIFACT_NAME" \
  "$CLOUDFLARED_ARTIFACT_URL"
chmod 0755 "${CLOUDFLARED_ARTIFACT_DIR}/${CLOUDFLARED_ARTIFACT_NAME}"

if [ ! -d "$COMFYUI_REQ_SRC/.git" ]; then
  rm -rf "$COMFYUI_REQ_SRC"
  git clone --depth 1 --branch "$COMFYUI_REF" https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_REQ_SRC"
else
  git -C "$COMFYUI_REQ_SRC" fetch --depth 1 origin "$COMFYUI_REF"
  git -C "$COMFYUI_REQ_SRC" checkout FETCH_HEAD
fi

download_source_archive \
  "ComfyUI" \
  "https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/${COMFYUI_REF}.tar.gz" \
  "ComfyUI-${COMFYUI_REF}.tar.gz" \
  "main.py"

download_source_archive \
  "ComfyUI-Manager" \
  "https://github.com/ltdrdata/ComfyUI-Manager/archive/refs/heads/${COMFYUI_MANAGER_REF:-main}.tar.gz" \
  "ComfyUI-Manager-${COMFYUI_MANAGER_REF:-main}.tar.gz" \
  "__init__.py"

download_source_archive \
  "ComfyUI-Ollama" \
  "https://github.com/stavsap/comfyui-ollama/archive/refs/heads/${COMFYUI_OLLAMA_REF:-main}.tar.gz" \
  "ComfyUI-Ollama-${COMFYUI_OLLAMA_REF:-main}.tar.gz" \
  "__init__.py"

download_source_archive \
  "AIGODLIKE-ComfyUI-Translation" \
  "https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Translation/archive/refs/heads/${COMFYUI_TRANSLATION_REF:-main}.tar.gz" \
  "AIGODLIKE-ComfyUI-Translation-${COMFYUI_TRANSLATION_REF:-main}.tar.gz" \
  "README.md"

log "resolving and downloading remaining wheels with pip cache=${PIP_CACHE_DIR}"
"$VENV/bin/pip" download \
  --dest "$WHEELHOUSE" \
  --cache-dir "$PIP_CACHE_DIR" \
  --prefer-binary \
  --find-links "$WHEELHOUSE" \
  --index-url "$PYPI_INDEX_URL" \
  --extra-index-url "$PYTORCH_INDEX_URL" \
  --constraint "$APP_DIR/constraints-pytorch-cu124.txt" \
  -r "$APP_DIR/requirements-comfyui.txt" \
  -r "$COMFYUI_REQ_SRC/requirements.txt"

manifest="${WHEELHOUSE}/WHEELHOUSE_MANIFEST.txt"
{
  printf 'created_at=%s\n' "$(date -u +%FT%TZ)"
  printf 'pytorch_index=%s\n' "$PYTORCH_INDEX_URL"
  printf 'pypi_index=%s\n' "$PYPI_INDEX_URL"
  printf 'ollama_artifact=%s/%s\n' "$OLLAMA_ARTIFACT_DIR" "$OLLAMA_ARTIFACT_NAME"
  printf 'cloudflared_artifact=%s/%s\n' "$CLOUDFLARED_ARTIFACT_DIR" "$CLOUDFLARED_ARTIFACT_NAME"
  printf 'repo_artifacts=%s\n' "$REPO_ARTIFACT_DIR"
  find "$WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -printf '%f\n' | sort
} > "$manifest"

log "complete wheel_count=$(find "$WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' | wc -l) size=$(du -sh "$WHEELHOUSE" | awk '{print $1}')"
