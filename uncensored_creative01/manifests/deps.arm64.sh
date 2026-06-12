# shellcheck shell=bash
# Runtime hydrate manifest for uncensored_creative01 on linux/arm64.
# The lightweight base image is multi-arch. Heavy ML dependencies are hydrated
# at deploy time; arm64 defaults to CPU PyTorch unless callers override URLs.

CREATIVE_MANIFEST_ID="uncensored_creative01-arm64-runtime"
CREATIVE_MANIFEST_PLATFORM="linux/arm64"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://pypi.org/simple}"
PYTORCH_INDEX_URL="${PYTORCH_INDEX_URL:-https://download.pytorch.org/whl/cpu}"
COMFYUI_REF="${COMFYUI_REF:-master}"
COMFYUI_MANAGER_REF="${COMFYUI_MANAGER_REF:-main}"
COMFYUI_OLLAMA_REF="${COMFYUI_OLLAMA_REF:-main}"
COMFYUI_TRANSLATION_REF="${COMFYUI_TRANSLATION_REF:-main}"

BOOTSTRAP_REQUIREMENTS=(
  pip
  wheel
  setuptools
  packaging
  python-multipart==0.0.20
)

TORCH_PACKAGES=(
  torch==2.5.1
  torchvision==0.20.1
  torchaudio==2.5.1
)

TORCH_WHEEL_URLS=()

RUNTIME_ARTIFACTS=(
  "ollama|https://ollama.com/download/ollama-linux-arm64.tgz|ollama-linux-arm64.tgz||0644|artifacts/ollama"
  "cloudflared|https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64|cloudflared-linux-arm64||0755|artifacts/cloudflared"
)

SOURCE_ARCHIVES=(
  "ComfyUI|https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/${COMFYUI_REF}.tar.gz|ComfyUI-${COMFYUI_REF}.tar.gz|main.py|artifacts/repos/ComfyUI"
  "ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager/archive/refs/heads/${COMFYUI_MANAGER_REF}.tar.gz|ComfyUI-Manager-${COMFYUI_MANAGER_REF}.tar.gz|__init__.py|artifacts/repos/ComfyUI-Manager"
  "ComfyUI-Ollama|https://github.com/stavsap/comfyui-ollama/archive/refs/heads/${COMFYUI_OLLAMA_REF}.tar.gz|ComfyUI-Ollama-${COMFYUI_OLLAMA_REF}.tar.gz|__init__.py|artifacts/repos/ComfyUI-Ollama"
  "AIGODLIKE-ComfyUI-Translation|https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Translation/archive/refs/heads/${COMFYUI_TRANSLATION_REF}.tar.gz|AIGODLIKE-ComfyUI-Translation-${COMFYUI_TRANSLATION_REF}.tar.gz|README.md|artifacts/repos/AIGODLIKE-ComfyUI-Translation"
)
