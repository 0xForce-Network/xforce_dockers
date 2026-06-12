#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
xforce_resource_helper="${XFORCE_RESOURCE_HELPER:-${script_dir}/../../../xforce_AI/scripts/docker-resource-profile.sh}"

CONTAINER="${F013_CONTAINER:-f013-creative-suite}"
IMAGE="${F013_IMAGE:-ghcr.io/0xforce-network/xforce-dockers-uncensored-creative01:creative01-latest}"
ROOT="${F013_ROOT:-/data/xforce_ai_test/xforce-creative-suite}"
DOCKER="${DOCKER:-docker}"
RECREATE="${F013_RECREATE:-1}"
PUBLIC_ON_BOOT="${F013_PUBLIC_ON_BOOT:-1}"
PUBLIC_TARGET="${F013_PUBLIC_TARGET:-portal}"
TUNNEL_MODE="${XFORCE_TUNNEL_ON_BOOT:-quick}"
RESOURCE_PROFILE="${F013_RESOURCE_PROFILE:-custom}"
HYDRATE_ON_DEPLOY="${F015_HYDRATE_ON_DEPLOY:-1}"
INSTALL_ON_DEPLOY="${F015_INSTALL_ON_DEPLOY:-1}"
START_SERVICES_ON_DEPLOY="${F015_START_SERVICES_ON_DEPLOY:-1}"

MODEL_DIR="${F013_MODEL_DIR:-${ROOT}/workspace/models}"
OUTPUT_DIR="${F013_OUTPUT_DIR:-${ROOT}/workspace/outputs}"
CREATIVE_DIR="${F013_CREATIVE_DIR:-${ROOT}/workspace/creative}"
CACHE_DIR="${F015_CACHE_DIR:-${ROOT}/workspace/cache/xforce_dockers/uncensored_creative01}"

DOCKER_CPUS="${F013_DOCKER_CPUS:-}"
DOCKER_CPUSET_CPUS="${F013_DOCKER_CPUSET_CPUS:-}"
DOCKER_MEMORY="${F013_DOCKER_MEMORY:-}"
DOCKER_MEMORY_SWAP="${F013_DOCKER_MEMORY_SWAP:-}"
DOCKER_SHM_SIZE="${F013_DOCKER_SHM_SIZE:-}"
DOCKER_PIDS_LIMIT="${F013_DOCKER_PIDS_LIMIT:-}"
DOCKER_GPUS="${F013_DOCKER_GPUS:-all}"
DOCKER_STORAGE_SIZE="${F013_DOCKER_STORAGE_SIZE:-}"

if [ -f "$xforce_resource_helper" ]; then
  XFORCE_DOCKER_RESOURCE_PROFILE="${F013_RESOURCE_PROFILE:-${XFORCE_DOCKER_RESOURCE_PROFILE:-custom}}"
  XFORCE_DOCKER_CPUS="${F013_DOCKER_CPUS:-${XFORCE_DOCKER_CPUS:-}}"
  XFORCE_DOCKER_CPUSET_CPUS="${F013_DOCKER_CPUSET_CPUS:-${XFORCE_DOCKER_CPUSET_CPUS:-}}"
  XFORCE_DOCKER_MEMORY="${F013_DOCKER_MEMORY:-${XFORCE_DOCKER_MEMORY:-}}"
  XFORCE_DOCKER_MEMORY_SWAP="${F013_DOCKER_MEMORY_SWAP:-${XFORCE_DOCKER_MEMORY_SWAP:-}}"
  XFORCE_DOCKER_SHM_SIZE="${F013_DOCKER_SHM_SIZE:-${XFORCE_DOCKER_SHM_SIZE:-}}"
  XFORCE_DOCKER_PIDS_LIMIT="${F013_DOCKER_PIDS_LIMIT:-${XFORCE_DOCKER_PIDS_LIMIT:-}}"
  XFORCE_DOCKER_GPUS="${F013_DOCKER_GPUS:-${XFORCE_DOCKER_GPUS:-all}}"
  XFORCE_DOCKER_STORAGE_SIZE="${F013_DOCKER_STORAGE_SIZE:-${XFORCE_DOCKER_STORAGE_SIZE:-}}"
  # shellcheck source=/dev/null
  source "$xforce_resource_helper"
  xforce_apply_docker_resource_profile
  RESOURCE_PROFILE="$XFORCE_DOCKER_RESOURCE_PROFILE"
  DOCKER_CPUS="$XFORCE_DOCKER_CPUS"
  DOCKER_CPUSET_CPUS="$XFORCE_DOCKER_CPUSET_CPUS"
  DOCKER_MEMORY="$XFORCE_DOCKER_MEMORY"
  DOCKER_MEMORY_SWAP="$XFORCE_DOCKER_MEMORY_SWAP"
  DOCKER_SHM_SIZE="$XFORCE_DOCKER_SHM_SIZE"
  DOCKER_PIDS_LIMIT="$XFORCE_DOCKER_PIDS_LIMIT"
  DOCKER_GPUS="$XFORCE_DOCKER_GPUS"
  DOCKER_STORAGE_SIZE="$XFORCE_DOCKER_STORAGE_SIZE"
fi

PORT_CADDY="${F013_PORT_CADDY:-18088}"
PORT_PORTAL="${F013_PORT_PORTAL:-18090}"
PORT_COMFY="${F013_PORT_COMFY:-18188}"
PORT_OLLAMA="${F013_PORT_OLLAMA:-11434}"

log() {
  printf '[f013-deploy] %s\n' "$*" >&2
}

append_docker_flag() {
  local flag="$1"
  local value="$2"
  if [ -n "$value" ]; then
    DOCKER_RUN_ARGS+=("$flag" "$value")
  fi
}

apply_resource_profile() {
  case "$RESOURCE_PROFILE" in
    custom|default|none|"")
      ;;
    gpu-small)
      : "${DOCKER_CPUS:=4}"
      : "${DOCKER_MEMORY:=16g}"
      : "${DOCKER_MEMORY_SWAP:=16g}"
      : "${DOCKER_SHM_SIZE:=4g}"
      : "${DOCKER_PIDS_LIMIT:=4096}"
      : "${DOCKER_GPUS:=all}"
      : "${DOCKER_STORAGE_SIZE:=80G}"
      ;;
    gpu-pro)
      : "${DOCKER_CPUS:=8}"
      : "${DOCKER_MEMORY:=32g}"
      : "${DOCKER_MEMORY_SWAP:=32g}"
      : "${DOCKER_SHM_SIZE:=8g}"
      : "${DOCKER_PIDS_LIMIT:=8192}"
      : "${DOCKER_GPUS:=all}"
      : "${DOCKER_STORAGE_SIZE:=160G}"
      ;;
    gpu-studio)
      : "${DOCKER_CPUS:=16}"
      : "${DOCKER_MEMORY:=64g}"
      : "${DOCKER_MEMORY_SWAP:=64g}"
      : "${DOCKER_SHM_SIZE:=16g}"
      : "${DOCKER_PIDS_LIMIT:=16384}"
      : "${DOCKER_GPUS:=all}"
      : "${DOCKER_STORAGE_SIZE:=320G}"
      ;;
    *)
      log "unknown F013_RESOURCE_PROFILE=${RESOURCE_PROFILE}; use custom, gpu-small, gpu-pro, or gpu-studio"
      exit 2
      ;;
  esac
}

apply_resource_profile

mkdir -p "$MODEL_DIR" "$OUTPUT_DIR" "$CREATIVE_DIR" "$CACHE_DIR" "${ROOT}/logs"

log "resource profile name=${RESOURCE_PROFILE} cpus=${DOCKER_CPUS:-default} cpuset=${DOCKER_CPUSET_CPUS:-default} memory=${DOCKER_MEMORY:-default} swap=${DOCKER_MEMORY_SWAP:-default} shm=${DOCKER_SHM_SIZE:-default} pids=${DOCKER_PIDS_LIMIT:-default} gpus=${DOCKER_GPUS} storage=${DOCKER_STORAGE_SIZE:-default}"

if $DOCKER inspect "$CONTAINER" >/dev/null 2>&1; then
  if [ "$RECREATE" = "1" ]; then
    log "removing existing container: ${CONTAINER}"
    $DOCKER rm -f "$CONTAINER" >/dev/null
  else
    log "container already exists; skipping docker run: ${CONTAINER}"
  fi
fi

if ! $DOCKER inspect "$CONTAINER" >/dev/null 2>&1; then
  log "starting ${CONTAINER} from ${IMAGE}"
  DOCKER_RUN_ARGS=(
    --name "$CONTAINER"
    --restart unless-stopped
    --gpus "$DOCKER_GPUS"
  )
  append_docker_flag --cpus "$DOCKER_CPUS"
  append_docker_flag --cpuset-cpus "$DOCKER_CPUSET_CPUS"
  append_docker_flag --memory "$DOCKER_MEMORY"
  append_docker_flag --memory-swap "$DOCKER_MEMORY_SWAP"
  append_docker_flag --shm-size "$DOCKER_SHM_SIZE"
  append_docker_flag --pids-limit "$DOCKER_PIDS_LIMIT"
  append_docker_flag --storage-opt "${DOCKER_STORAGE_SIZE:+size=${DOCKER_STORAGE_SIZE}}"
  $DOCKER run -d \
    "${DOCKER_RUN_ARGS[@]}" \
    -e XFORCE_PROVISION_ON_BOOT="${XFORCE_PROVISION_ON_BOOT:-0}" \
    -e NVIDIA_VISIBLE_DEVICES="${NVIDIA_VISIBLE_DEVICES:-all}" \
    -e NVIDIA_DRIVER_CAPABILITIES="${NVIDIA_DRIVER_CAPABILITIES:-compute,utility}" \
    -e XFORCE_TUNNEL_ON_BOOT="off" \
    -e CREATIVE_DEPLOY_PROFILE="${RESOURCE_PROFILE}" \
    -e CREATIVE_DEPLOY_CPUS="${DOCKER_CPUS}" \
    -e CREATIVE_DEPLOY_CPUSET_CPUS="${DOCKER_CPUSET_CPUS}" \
    -e CREATIVE_DEPLOY_MEMORY="${DOCKER_MEMORY}" \
    -e CREATIVE_DEPLOY_MEMORY_SWAP="${DOCKER_MEMORY_SWAP}" \
    -e CREATIVE_DEPLOY_SHM_SIZE="${DOCKER_SHM_SIZE}" \
    -e CREATIVE_DEPLOY_PIDS_LIMIT="${DOCKER_PIDS_LIMIT}" \
    -e CREATIVE_DEPLOY_GPUS="${DOCKER_GPUS}" \
    -e CREATIVE_DEPLOY_STORAGE_SIZE="${DOCKER_STORAGE_SIZE}" \
    -e CREATIVE_CACHE_ROOT="/workspace/cache/xforce_dockers/uncensored_creative01" \
    -v "${MODEL_DIR}:/workspace/models" \
    -v "${OUTPUT_DIR}:/workspace/outputs" \
    -v "${CREATIVE_DIR}:/workspace/creative" \
    -v "${CACHE_DIR}:/workspace/cache/xforce_dockers/uncensored_creative01" \
    -p "${PORT_CADDY}:8088" \
    -p "${PORT_PORTAL}:8090" \
    -p "${PORT_COMFY}:8188" \
    -p "${PORT_OLLAMA}:11434" \
    "$IMAGE" \
    sleep infinity >/dev/null
fi

if [ "$HYDRATE_ON_DEPLOY" = "1" ]; then
  log "hydrating creative suite cache in container"
  $DOCKER exec "$CONTAINER" /opt/creative/bin/hydrate-creative-suite.sh
fi

if [ "$INSTALL_ON_DEPLOY" = "1" ]; then
  log "installing creative suite from cache in container"
  $DOCKER exec "$CONTAINER" /opt/creative/bin/install-creative-suite.sh
fi

if [ "$START_SERVICES_ON_DEPLOY" = "1" ]; then
  log "starting supervisor managed creative services"
  $DOCKER exec "$CONTAINER" sh -lc 'if [ ! -S /tmp/xforce-ai/supervisor/supervisor.sock ]; then . /etc/xforce_ai_boot.d/60-supervisor.sh; fi; supervisorctl -c /etc/supervisor/supervisord.conf reread >/dev/null 2>&1 || true; supervisorctl -c /etc/supervisor/supervisord.conf update >/dev/null 2>&1 || true; supervisorctl -c /etc/supervisor/supervisord.conf start creative-portal caddy ollama comfyui ollama-model-init >/dev/null 2>&1 || true'
fi

log "waiting for local Caddy surface"
for _ in $(seq 1 90); do
  if $DOCKER exec "$CONTAINER" sh -lc 'curl -fsS http://127.0.0.1:8088/healthz >/dev/null 2>&1 || curl -fsS http://127.0.0.1:8090/api/creative/status >/dev/null 2>&1'; then
    break
  fi
  sleep 2
done

if [ "$PUBLIC_ON_BOOT" = "1" ]; then
  log "starting public Cloudflare Tunnel post-deploy flow target=${PUBLIC_TARGET} mode=${TUNNEL_MODE}"
  DOCKER="$DOCKER" \
  F013_CONTAINER="$CONTAINER" \
  F013_ROOT="$ROOT" \
  F013_PUBLIC_TARGET="$PUBLIC_TARGET" \
  XFORCE_TUNNEL_ON_BOOT="$TUNNEL_MODE" \
  "${script_dir}/post-deploy-cloudflared.sh"
else
  log "public tunnel disabled by F013_PUBLIC_ON_BOOT=0"
fi
