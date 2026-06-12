ARG XFORCE_BASE_IMAGE=ghcr.io/xforce-ai/xforce-ai:nvidia-dev
FROM ${XFORCE_BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG XFORCE_USER=user
ARG XFORCE_UID=1000
ARG XFORCE_GID=1000
ARG CREATIVE_ROOT=/opt/creative
ARG CREATIVE_IMAGE_ID=uncensored_creative01
ARG CREATIVE_CACHE_ROOT=/workspace/cache/xforce_dockers/uncensored_creative01
ARG CREATIVE_HYDRATE_AT_BUILD=0
ARG CREATIVE_INSTALL_AT_BUILD=0
ARG NUSHELL_VERSION=0.113.1
ARG NUSHELL_SHA256_AMD64=9008d309aaa35e29ed5d5985306a83e2bf5093e31677d4cd969914552d12b8fb
ARG NUSHELL_SHA256_ARM64=08b94c6fd9c66881616df4c89adc03e8a42a57fdf6876cfd1b16cec7e82348b4
ARG CADDY_VERSION=2.11.4
ARG CADDY_SHA512_AMD64=8220d1f013b6f27510247b2360c9e0ca9f018feebd82515f07635318b34ff9777ccc8fd0b6e6f2486ce3a33fe389fbb7db12d05baa474f4587509fb4f5ebf1c9
ARG CADDY_SHA512_ARM64=d5a7c423853c24a799765e0e8210d5c7c22a8f56ed37a3cae2fb9f58be138853c02b4efd6b59d576e6d8c7c0d30b9c1592deeaa6a536ff69bcca23b8c1ea709c
ARG XFORCE_IMAGE_REVISION=unknown
ARG XFORCE_IMAGE_SOURCE=https://github.com/0xForce-Network/xforce_AI
ARG XFORCE_IMAGE_CREATED=unknown

ENV CREATIVE_ROOT=${CREATIVE_ROOT} \
    COMFYUI_DIR=${CREATIVE_ROOT}/ComfyUI \
    COMFYUI_VENV=/venv/comfyui \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    CREATIVE_IMAGE_ID=${CREATIVE_IMAGE_ID} \
    CREATIVE_CACHE_ROOT=${CREATIVE_CACHE_ROOT} \
    CREATIVE_MODEL_ROOT=/workspace/models \
    CREATIVE_OUTPUT_ROOT=/workspace/outputs \
    CREATIVE_STATE_DIR=/workspace/.xforce-creative-state \
    CREATIVE_FILE_ROOTS=models:/workspace/models,outputs:/workspace/outputs,creative:/workspace/creative \
    OLLAMA_HOST=127.0.0.1:11434 \
    OLLAMA_MODELS=/workspace/models/ollama \
    OLLAMA_NUM_PARALLEL=1 \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_FLASH_ATTENTION=0 \
    PYTHONUNBUFFERED=1

LABEL org.opencontainers.image.title="xforce creative suite" \
    org.opencontainers.image.description="Lightweight xforce_dockers creative suite image with runtime hydrate/install cache flow" \
    org.opencontainers.image.vendor="xforce" \
    org.opencontainers.image.source="${XFORCE_IMAGE_SOURCE}" \
    org.opencontainers.image.revision="${XFORCE_IMAGE_REVISION}" \
    org.opencontainers.image.created="${XFORCE_IMAGE_CREATED}" \
    image.family="xforce-ai" \
    image.variant="nvidia-creative-suite" \
    image.source="workspace_web/xforce_dockers/uncensored_creative01" \
    xforce.image.family="xforce-dockers" \
    xforce.image.id="${CREATIVE_IMAGE_ID}" \
    xforce.base.image="${XFORCE_BASE_IMAGE}" \
    xforce.hydrate.mode="runtime" \
    xforce.creative.nodes="ComfyUI,ComfyUI-Manager,ComfyUI-Ollama,AIGODLIKE-ComfyUI-Translation"

COPY xforce_dockers/uncensored_creative01/requirements-comfyui.txt /tmp/creative-requirements-comfyui.txt
COPY xforce_dockers/uncensored_creative01/constraints-pytorch-cu124.txt /tmp/creative-constraints-pytorch-cu124.txt
COPY xforce_AI/docker/common/install-nushell.sh /tmp/xforce-install-nushell.sh
COPY xforce_AI/docker/common/install-caddy.sh /tmp/xforce-install-caddy.sh

RUN apt_opts='-o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::ForceIPv4=true' \
    && apt-get ${apt_opts} update \
    && apt-get ${apt_opts} install -y --no-install-recommends \
    aria2 \
    ffmpeg \
    git-lfs \
    libgl1 \
    libglib2.0-0 \
    libgoogle-perftools4 \
    libsm6 \
    libxext6 \
    libxrender1 \
    python3-dev \
    rsync \
    zstd \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${CREATIVE_ROOT}" "${CREATIVE_ROOT}/manifests" "${CREATIVE_CACHE_ROOT}" /workspace/models/ollama /workspace/models/checkpoints /workspace/models/loras /workspace/outputs /workspace/creative \
    && "${VENV_DIR:-/venv/main}/bin/pip" install --prefer-binary python-multipart==0.0.20 \
    && CADDY_VERSION="${CADDY_VERSION}" CADDY_SHA512_AMD64="${CADDY_SHA512_AMD64}" CADDY_SHA512_ARM64="${CADDY_SHA512_ARM64}" bash /tmp/xforce-install-caddy.sh \
    && caddy version | grep -q "${CADDY_VERSION}" \
    && if ! command -v nu >/dev/null 2>&1 && [ ! -x /usr/local/bin/nu ]; then NUSHELL_VERSION="${NUSHELL_VERSION}" NUSHELL_SHA256_AMD64="${NUSHELL_SHA256_AMD64}" NUSHELL_SHA256_ARM64="${NUSHELL_SHA256_ARM64}" bash /tmp/xforce-install-nushell.sh; fi \
    && test -x /usr/local/bin/nu \
    && { grep -qxF /usr/local/bin/nu /etc/shells || printf '%s\n' /usr/local/bin/nu >> /etc/shells; } \
    && usermod --shell /usr/local/bin/nu "${XFORCE_USER}" \
    && chown -R "${XFORCE_UID}:${XFORCE_GID}" "${CREATIVE_ROOT}" "${CREATIVE_CACHE_ROOT}" /workspace/models /workspace/outputs /workspace/creative \
    && rm -f /tmp/creative-requirements-comfyui.txt /tmp/creative-constraints-pytorch-cu124.txt /tmp/xforce-install-nushell.sh /tmp/xforce-install-caddy.sh

COPY xforce_dockers/uncensored_creative01/supervisor.conf /etc/supervisor/conf.d/40-creative-suite.conf
COPY xforce_dockers/uncensored_creative01/services.yaml /etc/xforce-ai/services.yaml
COPY xforce_dockers/uncensored_creative01/routes.yaml /etc/xforce-ai/caddy/routes.yaml
COPY xforce_dockers/uncensored_creative01/creative-suite-provisioning.yaml /etc/xforce-ai/provisioning.yaml
COPY xforce_dockers/uncensored_creative01/Modelfile.qwen2.5-creative /opt/creative/Modelfile.qwen2.5-creative
COPY xforce_dockers/uncensored_creative01/comfyui-extra-model-paths.yaml /opt/creative/comfyui-extra-model-paths.yaml
COPY xforce_dockers/uncensored_creative01/requirements-comfyui.txt /opt/creative/requirements-comfyui.txt
COPY xforce_dockers/uncensored_creative01/constraints-pytorch-cu124.txt /opt/creative/constraints-pytorch-cu124.txt
COPY xforce_dockers/uncensored_creative01/manifests/ /opt/creative/manifests/
COPY xforce_dockers/uncensored_creative01/scripts/ /opt/creative/bin/
COPY xforce_dockers/uncensored_creative01/portal/ /opt/creative/portal/

RUN mkdir -p /tmp/xforce-ai/services/ollama /tmp/xforce-ai/services/ollama-model-init /tmp/xforce-ai/services/comfyui /tmp/xforce-ai/services/creative-portal \
    && chmod 0755 /opt/creative/bin/*.sh /opt/creative/bin/xforce-creative-portal \
    && if [ "${CREATIVE_HYDRATE_AT_BUILD}" = "1" ]; then /opt/creative/bin/hydrate-creative-suite.sh; fi \
    && if [ "${CREATIVE_INSTALL_AT_BUILD}" = "1" ]; then /opt/creative/bin/install-creative-suite.sh; fi \
    && chown -R "${XFORCE_UID}:${XFORCE_GID}" /opt/creative "${CREATIVE_CACHE_ROOT}" /workspace/models /workspace/outputs /workspace/creative

EXPOSE 8088 8080 8090 8188 11434
WORKDIR /workspace
