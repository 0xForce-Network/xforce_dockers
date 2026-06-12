#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "${script_dir}/.." && pwd)"
workspace_web="$(cd -- "${app_dir}/../.." && pwd)"

for arg in "$@"; do
  case "$arg" in
    [A-Za-z_]*=*)
      export "$arg"
      ;;
    *)
      printf 'unsupported argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

build_context="${BUILD_CONTEXT:-$workspace_web}"

IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-ghcr.io/0xforce-network/xforce-dockers-uncensored-creative01}"
IMAGE_ALIAS_REPOSITORY="${IMAGE_ALIAS_REPOSITORY:-ghcr.io/0xforce-network/xforce-creative-suite}"
LOCAL_IMAGE="${LOCAL_IMAGE:-xforce-creative-suite:${IMAGE_TAG}}"
PUSH="${PUSH:-0}"
LOAD="${LOAD:-auto}"
NO_CACHE="${NO_CACHE:-0}"
DRY_RUN="${DRY_RUN:-0}"
XFORCE_BASE_IMAGE="${XFORCE_BASE_IMAGE:-ghcr.io/xforce-ai/xforce-ai:nvidia-dev}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
PUSH_LATEST="${PUSH_LATEST:-0}"
INCLUDE_ALIAS="${INCLUDE_ALIAS:-1}"
CREATIVE_IMAGE_ID="${CREATIVE_IMAGE_ID:-uncensored_creative01}"
CREATIVE_CACHE_ROOT="${CREATIVE_CACHE_ROOT:-/workspace/cache/xforce_dockers/${CREATIVE_IMAGE_ID}}"

tag_args=()
if [ -n "${IMAGE_TAGS:-}" ]; then
  tag_args=()
  IFS=',' read -r -a provided_tags <<< "$IMAGE_TAGS"
  for tag in "${provided_tags[@]}"; do
    tag="${tag//[[:space:]]/}"
    [ -n "$tag" ] || continue
    tag_args+=(-t "$tag")
  done
else
  if [ "$PUSH" != "1" ]; then
    tag_args+=(-t "$LOCAL_IMAGE")
  fi
  tag_args+=(-t "${IMAGE_REPOSITORY}:${IMAGE_TAG}")
  if [ "$INCLUDE_ALIAS" = "1" ]; then
    tag_args+=(-t "${IMAGE_ALIAS_REPOSITORY}:${IMAGE_TAG}")
  fi
  if [ "$PUSH_LATEST" = "1" ]; then
    tag_args+=(-t "${IMAGE_REPOSITORY}:creative01-latest")
    if [ "$INCLUDE_ALIAS" = "1" ]; then
      tag_args+=(-t "${IMAGE_ALIAS_REPOSITORY}:creative01-latest")
    fi
  fi
fi

if [ "${#tag_args[@]}" -eq 0 ]; then
  printf 'no image tags resolved\n' >&2
  exit 1
fi

build_args=(
  --build-arg "XFORCE_BASE_IMAGE=${XFORCE_BASE_IMAGE}"
  --build-arg "CREATIVE_IMAGE_ID=${CREATIVE_IMAGE_ID}"
  --build-arg "CREATIVE_CACHE_ROOT=${CREATIVE_CACHE_ROOT}"
)

known_build_args=(
  CREATIVE_HYDRATE_AT_BUILD
  CREATIVE_INSTALL_AT_BUILD
  NUSHELL_VERSION
  NUSHELL_SHA256_AMD64
  NUSHELL_SHA256_ARM64
  CADDY_VERSION
  CADDY_SHA512_AMD64
  CADDY_SHA512_ARM64
  XFORCE_IMAGE_REVISION
  XFORCE_IMAGE_SOURCE
  XFORCE_IMAGE_CREATED
)

for build_arg_name in "${known_build_args[@]}"; do
  build_arg_value="${!build_arg_name:-}"
  if [ -n "$build_arg_value" ]; then
    build_args+=(--build-arg "${build_arg_name}=${build_arg_value}")
  fi
done

if docker buildx version >/dev/null 2>&1; then
  cmd=(docker buildx build --platform "$PLATFORMS")
  if [ -n "${BUILDX_BUILDER:-}" ]; then
    cmd+=(--builder "$BUILDX_BUILDER")
  fi
  cmd+=(-f "${app_dir}/Dockerfile" "${tag_args[@]}" "${build_args[@]}")
  if [ "$PUSH" = "1" ]; then
    cmd+=(--push)
  elif [ "$LOAD" = "1" ] || { [ "$LOAD" = auto ] && [[ "$PLATFORMS" != *,* ]]; }; then
    cmd+=(--load)
  fi
  if [ "$NO_CACHE" = "1" ]; then
    cmd+=(--no-cache)
  fi
  if [ -n "${CACHE_FROM:-}" ]; then
    cmd+=(--cache-from "$CACHE_FROM")
  fi
  if [ -n "${CACHE_TO:-}" ]; then
    cmd+=(--cache-to "$CACHE_TO")
  fi
  if [ -n "${OUTPUT_METADATA:-}" ]; then
    mkdir -p "$(dirname "$OUTPUT_METADATA")"
    cmd+=(--metadata-file "$OUTPUT_METADATA")
  fi
  cmd+=("$build_context")
else
  if [ "$PUSH" = "1" ]; then
    printf 'PUSH=1 requires docker buildx\n' >&2
    exit 1
  fi
  if [[ "$PLATFORMS" == *,* ]]; then
    printf 'multi-platform builds require docker buildx\n' >&2
    exit 1
  fi
  cmd=(docker build -f "${app_dir}/Dockerfile" "${tag_args[@]}" "${build_args[@]}")
  if [ "$NO_CACHE" = "1" ]; then
    cmd+=(--no-cache)
  fi
  cmd+=("$build_context")
fi

printf '+ '
printf '%q ' "${cmd[@]}"
printf '\n'

if [ "$DRY_RUN" = "1" ]; then
  exit 0
fi

exec "${cmd[@]}"
