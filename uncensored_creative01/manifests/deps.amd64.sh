# shellcheck shell=bash
# Runtime hydrate manifest for uncensored_creative01 on linux/amd64.

CREATIVE_MANIFEST_ID="uncensored_creative01-amd64-cu124"
CREATIVE_MANIFEST_PLATFORM="linux/amd64"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://pypi.org/simple}"
PYTORCH_INDEX_URL="${PYTORCH_INDEX_URL:-https://download.pytorch.org/whl/cu124}"
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
  torch==2.5.1+cu124
  torchvision==0.20.1+cu124
  torchaudio==2.5.1+cu124
)

TORCH_WHEEL_URLS=(
  "https://download.pytorch.org/whl/cu124/torch-2.5.1%2Bcu124-cp312-cp312-linux_x86_64.whl|torch-2.5.1+cu124-cp312-cp312-linux_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/torchvision-0.20.1%2Bcu124-cp312-cp312-linux_x86_64.whl|torchvision-0.20.1+cu124-cp312-cp312-linux_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/torchaudio-2.5.1%2Bcu124-cp312-cp312-linux_x86_64.whl|torchaudio-2.5.1+cu124-cp312-cp312-linux_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cuda_nvrtc_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|nvidia_cuda_nvrtc_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cuda_runtime_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|nvidia_cuda_runtime_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cuda_cupti_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|nvidia_cuda_cupti_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cudnn_cu12-9.1.0.70-py3-none-manylinux2014_x86_64.whl|nvidia_cudnn_cu12-9.1.0.70-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cublas_cu12-12.4.5.8-py3-none-manylinux2014_x86_64.whl|nvidia_cublas_cu12-12.4.5.8-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cufft_cu12-11.2.1.3-py3-none-manylinux2014_x86_64.whl|nvidia_cufft_cu12-11.2.1.3-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_curand_cu12-10.3.5.147-py3-none-manylinux2014_x86_64.whl|nvidia_curand_cu12-10.3.5.147-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cusolver_cu12-11.6.1.9-py3-none-manylinux2014_x86_64.whl|nvidia_cusolver_cu12-11.6.1.9-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cusparse_cu12-12.3.1.170-py3-none-manylinux2014_x86_64.whl|nvidia_cusparse_cu12-12.3.1.170-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_cusparselt_cu12-0.6.2-py3-none-manylinux2014_x86_64.whl|nvidia_cusparselt_cu12-0.6.2-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_nccl_cu12-2.21.5-py3-none-manylinux2014_x86_64.whl|nvidia_nccl_cu12-2.21.5-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_nvtx_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|nvidia_nvtx_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|"
  "https://download.pytorch.org/whl/cu124/nvidia_nvjitlink_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|nvidia_nvjitlink_cu12-12.4.127-py3-none-manylinux2014_x86_64.whl|"
)

RUNTIME_ARTIFACTS=(
  "ollama|https://ollama.com/download/ollama-linux-amd64.tar.zst|ollama-linux-amd64.tar.zst||0644|artifacts/ollama"
  "cloudflared|https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64|cloudflared-linux-amd64||0755|artifacts/cloudflared"
)

SOURCE_ARCHIVES=(
  "ComfyUI|https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/${COMFYUI_REF}.tar.gz|ComfyUI-${COMFYUI_REF}.tar.gz|main.py|artifacts/repos/ComfyUI"
  "ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager/archive/refs/heads/${COMFYUI_MANAGER_REF}.tar.gz|ComfyUI-Manager-${COMFYUI_MANAGER_REF}.tar.gz|__init__.py|artifacts/repos/ComfyUI-Manager"
  "ComfyUI-Ollama|https://github.com/stavsap/comfyui-ollama/archive/refs/heads/${COMFYUI_OLLAMA_REF}.tar.gz|ComfyUI-Ollama-${COMFYUI_OLLAMA_REF}.tar.gz|__init__.py|artifacts/repos/ComfyUI-Ollama"
  "AIGODLIKE-ComfyUI-Translation|https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Translation/archive/refs/heads/${COMFYUI_TRANSLATION_REF}.tar.gz|AIGODLIKE-ComfyUI-Translation-${COMFYUI_TRANSLATION_REF}.tar.gz|README.md|artifacts/repos/AIGODLIKE-ComfyUI-Translation"
)
