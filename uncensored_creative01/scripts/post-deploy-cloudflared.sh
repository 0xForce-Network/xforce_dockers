#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER="${F013_CONTAINER:-f013-creative-suite}"
ROOT="${F013_ROOT:-/data/xforce_ai_test/xforce-creative-suite}"
CACHE_DIR="${F013_CLOUDFLARED_CACHE_DIR:-${ROOT}/cache/cloudflared}"
TOKEN_FILE="${F013_PUBLIC_AUTH_TOKEN_FILE:-${ROOT}/logs/cloudflared/auth-token.txt}"
SUMMARY_FILE="${F013_PUBLIC_SUMMARY_FILE:-${ROOT}/logs/cloudflared/public-access.json}"
PUBLIC_TARGET="${F013_PUBLIC_TARGET:-portal}"
TUNNEL_MODE="${XFORCE_TUNNEL_ON_BOOT:-quick}"
TUNNEL_URL="${XFORCE_TUNNEL_URL:-http://127.0.0.1:8088}"
METRICS="${XFORCE_TUNNEL_METRICS:-127.0.0.1:0}"
TUNNEL_RESTART="${F013_TUNNEL_RESTART:-0}"
PREHEAT_SD15="${F013_PREHEAT_SD15:-1}"
SD15_URL="${F013_SD15_URL:-https://huggingface.co/Comfy-Org/stable-diffusion-v1-5-archive/resolve/main/v1-5-pruned-emaonly-fp16.safetensors}"
SD15_NAME="${F013_SD15_NAME:-v1-5-pruned-emaonly-fp16.safetensors}"
CLOUDFLARED_URL="${CLOUDFLARED_ARTIFACT_URL:-https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64}"
CLOUDFLARED_BIN="${CLOUDFLARED_ARTIFACT_NAME:-cloudflared-linux-amd64}"
DOCKER="${DOCKER:-docker}"

log() {
  printf '[f013-post-cloudflared] %s\n' "$*" >&2
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

require_container() {
  if ! $DOCKER inspect "$CONTAINER" >/dev/null 2>&1; then
    log "container not found: ${CONTAINER}"
    exit 2
  fi
}

ensure_token() {
  mkdir -p "$(dirname "$TOKEN_FILE")"
  if [ -z "${XFORCE_AUTH_TOKEN:-}" ]; then
    if [ ! -s "$TOKEN_FILE" ]; then
      umask 077
      openssl rand -hex 24 > "$TOKEN_FILE"
    fi
    XFORCE_AUTH_TOKEN="$(cat "$TOKEN_FILE")"
  else
    umask 077
    printf '%s\n' "$XFORCE_AUTH_TOKEN" > "$TOKEN_FILE"
  fi
}

ensure_cloudflared() {
  if $DOCKER exec "$CONTAINER" sh -lc 'command -v cloudflared >/dev/null 2>&1'; then
    return 0
  fi
  mkdir -p "$CACHE_DIR"
  if [ ! -x "${CACHE_DIR}/${CLOUDFLARED_BIN}" ]; then
    log "cloudflared missing in container; downloading host cache with resume: ${CACHE_DIR}/${CLOUDFLARED_BIN}"
    if command -v aria2c >/dev/null 2>&1; then
      aria2c --continue=true --max-connection-per-server=16 --split=16 --min-split-size=1M --retry-wait=5 --max-tries=0 --timeout=30 --connect-timeout=15 --dir="$CACHE_DIR" --out="$CLOUDFLARED_BIN" "$CLOUDFLARED_URL"
    else
      curl -fL --retry 5 --retry-delay 5 -o "${CACHE_DIR}/${CLOUDFLARED_BIN}" "$CLOUDFLARED_URL"
    fi
    chmod 0755 "${CACHE_DIR}/${CLOUDFLARED_BIN}"
  fi
  $DOCKER cp "${CACHE_DIR}/${CLOUDFLARED_BIN}" "${CONTAINER}:/usr/local/bin/cloudflared"
  $DOCKER exec "$CONTAINER" chmod 0755 /usr/local/bin/cloudflared
}

signed_cookie() {
  python3 - "$XFORCE_AUTH_TOKEN" <<'PY'
import base64
import hashlib
import hmac
import sys
import time

token = sys.argv[1]
secret = token
issued = int(time.time())
payload = f"v1:{issued}:{hashlib.sha256(token.encode()).hexdigest()}"
signature = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
raw = f"{payload}:{signature}".encode()
print(base64.urlsafe_b64encode(raw).decode().rstrip("="))
PY
}

configure_auth() {
  local cookie
  cookie="$(signed_cookie)"
  $DOCKER exec -i "$CONTAINER" sh <<EOF
set -eu
umask 077
mkdir -p /etc/xforce-ai/caddy /tmp/xforce-ai/caddy /tmp/xforce-ai/tunnel /tmp/xforce-ai/services/cloudflared
cat > /etc/xforce-ai/caddy/auth.yaml <<'AUTH'
auth:
  token: ${XFORCE_AUTH_TOKEN}
  cookieSecret: ${XFORCE_AUTH_TOKEN}
  bearerEnabled: true
  headerName: X-XForce-Token
  queryName: token
  cookieTtlSeconds: 86400
AUTH
export XFORCE_CADDY_CONFIG="/tmp/xforce-ai/caddy/Caddyfile.generated"
export XFORCE_CADDY_ROUTES="/etc/xforce-ai/caddy/routes.yaml"
export XFORCE_CADDY_AUTH="/etc/xforce-ai/caddy/auth.yaml"
/opt/xforce-ai/bin/xforce-caddy render >/dev/null
/opt/xforce-ai/bin/xforce-caddy validate >/dev/null
/opt/xforce-ai/bin/xforce-caddy reload >/dev/null 2>&1 || supervisorctl -c /etc/supervisor/supervisord.conf restart caddy >/dev/null
EOF
}

configure_comfy_userdata() {
  $DOCKER exec "$CONTAINER" sh -lc '
set -eu
user_root="/opt/creative/ComfyUI/user/default"
mkdir -p "$user_root/workflows" "$user_root/subgraphs"
touch "$user_root/user.css"
if [ ! -s "$user_root/comfy.templates.json" ]; then
  printf "[]\n" > "$user_root/comfy.templates.json"
fi
chown -R user:user /opt/creative/ComfyUI/user
'
}

ensure_sd15_checkpoint() {
  if [ "$PREHEAT_SD15" != "1" ]; then
    log 'skipping SD1.5 checkpoint preheat because F013_PREHEAT_SD15!=1'
    return 0
  fi
  local model_dir="${ROOT}/workspace/models/checkpoints"
  local model_path="${model_dir}/${SD15_NAME}"
  mkdir -p "$model_dir" "${ROOT}/logs/model-preheat"
  if [ -s "$model_path" ] && [ ! -e "${model_path}.aria2" ]; then
    log "SD1.5 checkpoint already cached: ${model_path}"
    return 0
  fi
  log "preheating SD1.5 checkpoint with resume: ${model_path}"
  if command -v aria2c >/dev/null 2>&1; then
    aria2c \
      --continue=true \
      --max-connection-per-server=16 \
      --split=16 \
      --min-split-size=8M \
      --retry-wait=5 \
      --max-tries=0 \
      --timeout=30 \
      --connect-timeout=15 \
      --dir="$model_dir" \
      --out="$SD15_NAME" \
      "$SD15_URL" \
      > "${ROOT}/logs/model-preheat/sd15.out" \
      2> "${ROOT}/logs/model-preheat/sd15.err"
  else
    curl -fL --retry 5 --retry-delay 5 -C - -o "$model_path" "$SD15_URL"
  fi
  chown 1000:1000 "$model_path" 2>/dev/null || true
}

configure_supervisor() {
  local supervisor_env=""
  local command="/opt/xforce-ai/bin/xforce-tunnel quick --url ${TUNNEL_URL} --metrics ${METRICS}"
  if [ "$TUNNEL_MODE" = "quick" ] && [ "$TUNNEL_RESTART" != "1" ]; then
    if $DOCKER exec "$CONTAINER" sh -lc 'test -s /tmp/xforce-ai/tunnel/quick-url.txt && supervisorctl -c /etc/supervisor/supervisord.conf status cloudflared 2>/dev/null | grep -q RUNNING'; then
      log 'reusing existing quick tunnel; set F013_TUNNEL_RESTART=1 to rotate URL'
      return 0
    fi
  fi
  if [ "$TUNNEL_MODE" = "named" ]; then
    if [ -z "${CF_TUNNEL_TOKEN:-}" ]; then
      log 'TUNNEL_MODE=named requires CF_TUNNEL_TOKEN'
      exit 2
    fi
    command="/opt/xforce-ai/bin/xforce-tunnel named --url ${TUNNEL_URL} --metrics ${METRICS}"
    supervisor_env="environment=CF_TUNNEL_TOKEN=\"${CF_TUNNEL_TOKEN}\",XFORCE_TUNNEL_ON_BOOT=\"named\""
  elif [ "$TUNNEL_MODE" != "quick" ]; then
    log "unsupported XFORCE_TUNNEL_ON_BOOT=${TUNNEL_MODE}; use quick or named"
    exit 2
  fi

  $DOCKER exec -i "$CONTAINER" sh <<EOF
set -eu
supervisorctl -c /etc/supervisor/supervisord.conf stop cloudflared >/dev/null 2>&1 || true
pkill -f 'cloudflared tunnel' >/dev/null 2>&1 || true
pkill -f 'python.*tunnel_manager' >/dev/null 2>&1 || true
cat > /etc/supervisor/conf.d/30-cloudflared.conf <<'CONF'
[program:cloudflared]
command=${command}
autostart=false
autorestart=true
startsecs=2
stdout_logfile=/tmp/xforce-ai/services/cloudflared/stdout.log
stderr_logfile=/tmp/xforce-ai/services/cloudflared/stderr.log
${supervisor_env}
CONF
rm -f /tmp/xforce-ai/tunnel/quick-url.txt /tmp/xforce-ai/tunnel/state.json
supervisorctl -c /etc/supervisor/supervisord.conf reread >/dev/null || true
supervisorctl -c /etc/supervisor/supervisord.conf update >/dev/null || true
supervisorctl -c /etc/supervisor/supervisord.conf restart cloudflared >/dev/null 2>&1 || supervisorctl -c /etc/supervisor/supervisord.conf start cloudflared >/dev/null
EOF
}

wait_for_url() {
  local url=""
  local status=""
  if [ "$TUNNEL_MODE" = "named" ]; then
    printf '%s' "${PUBLIC_URL:-}"
    return 0
  fi
  for _ in $(seq 1 90); do
    url="$($DOCKER exec "$CONTAINER" sh -lc 'cat /tmp/xforce-ai/tunnel/quick-url.txt 2>/dev/null || true' | tr -d '\r' | head -n1)"
    if [ -n "$url" ]; then
      sleep 4
      status="$($DOCKER exec "$CONTAINER" sh -lc 'supervisorctl -c /etc/supervisor/supervisord.conf status cloudflared 2>/dev/null || true')"
      case "$status" in
        *RUNNING*)
          printf '%s' "$url"
          return 0
          ;;
        *)
          log "quick tunnel URL appeared but cloudflared is not stable yet: ${status}"
          ;;
      esac
    fi
    sleep 2
  done
  log 'quick tunnel URL not ready'
  $DOCKER exec "$CONTAINER" sh -lc 'supervisorctl -c /etc/supervisor/supervisord.conf status cloudflared || true; tail -n 120 /tmp/xforce-ai/services/cloudflared/stdout.log 2>/dev/null || true; tail -n 120 /tmp/xforce-ai/services/cloudflared/stderr.log 2>/dev/null || true' >&2 || true
  return 1
}

write_summary() {
  local public_url="$1"
  local login_url=""
  local header_name="X-XForce-Token"
  mkdir -p "$(dirname "$SUMMARY_FILE")"
  if [ -n "$public_url" ]; then
    login_url="${public_url}/__xforce_login/${XFORCE_AUTH_TOKEN}"
  fi
  cat > "$SUMMARY_FILE" <<EOF
{
  "container": $(printf '%s' "$CONTAINER" | json_escape),
  "mode": $(printf '%s' "$TUNNEL_MODE" | json_escape),
  "publicTarget": $(printf '%s' "$PUBLIC_TARGET" | json_escape),
  "publicUrl": $(printf '%s' "$public_url" | json_escape),
  "loginUrl": $(printf '%s' "$login_url" | json_escape),
  "tokenFile": $(printf '%s' "$TOKEN_FILE" | json_escape),
  "headerName": $(printf '%s' "$header_name" | json_escape)
}
EOF
  cat "$SUMMARY_FILE"
}

require_container
ensure_token
ensure_cloudflared
configure_auth
configure_comfy_userdata
ensure_sd15_checkpoint
configure_supervisor
public_url="$(wait_for_url)"
write_summary "$public_url"
