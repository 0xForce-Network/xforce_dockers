#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "${script_dir}/.." && pwd)"
xforce_ai_dir="${XFORCE_AI_DIR:-${app_dir}/../../xforce_AI}"

fail() {
  printf '[creative-suite-smoke] FAIL %s\n' "$*" >&2
  exit 1
}

ok() {
  printf '[creative-suite-smoke] OK %s\n' "$*" >&2
}

required_files=(
  Dockerfile
  supervisor.conf
  services.yaml
  routes.yaml
  creative-suite-provisioning.yaml
  Modelfile.qwen2.5-creative
  comfyui-extra-model-paths.yaml
  requirements-comfyui.txt
  manifests/deps.amd64.sh
  manifests/deps.arm64.sh
  portal/creative_portal/app.py
  portal/static/index.html
  scripts/init-ollama-model.sh
  scripts/unload-vram.sh
  scripts/hydrate-creative-suite.sh
  scripts/install-creative-suite.sh
  scripts/creative-suite-cache-status.sh
  scripts/xforce-creative-portal
)

for file in "${required_files[@]}"; do
  [ -f "${app_dir}/${file}" ] || fail "missing ${file}"
done
[ -f "${xforce_ai_dir}/docker/common/install-caddy.sh" ] || fail "missing xforce_AI companion install-caddy.sh at ${xforce_ai_dir}"
ok "required files present"

bash -n "${app_dir}/scripts/init-ollama-model.sh"
bash -n "${app_dir}/scripts/unload-vram.sh"
bash -n "${app_dir}/scripts/build-creative-suite.sh"
bash -n "${app_dir}/scripts/hydrate-creative-suite.sh"
bash -n "${app_dir}/scripts/install-creative-suite.sh"
bash -n "${app_dir}/scripts/creative-suite-cache-status.sh"
bash -n "${app_dir}/scripts/creative-suite-smoke.sh"
bash -n "${app_dir}/scripts/xforce-creative-portal"
ok "shell syntax"

python3 - <<'PY' "${app_dir}/portal/creative_portal/app.py" "${app_dir}/portal/creative_portal/__main__.py"
from pathlib import Path
import ast
import sys

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY
ok "python syntax"

python3 - <<'PY' "${app_dir}" "${xforce_ai_dir}"
from pathlib import Path
import sys

app = Path(sys.argv[1])
xforce_ai = Path(sys.argv[2])
html = (app / "portal/static/index.html").read_text(encoding="utf-8")
for needle in ["Claude Cream", "Warm Cream", "创意模式", "files", "ComfyUI", "Ollama", "ComfyUI 模型一键部署", "multi-language", "status-output", "file-search", "show-services", "target=\"_blank\"", "height: 38lh", "max-height: 38lh", "height: 26lh", "max-height: 26lh", "overflow-wrap: anywhere", "/api/v1/portal-assets/file-browser.js", "XForceFileBrowser.create"]:
    if needle not in html:
        raise SystemExit(f"missing html marker: {needle}")

shared_browser = (xforce_ai / "docker/common/portal/static/file-browser.js").resolve().read_text(encoding="utf-8")
for needle in ["window.XForceFileBrowser", "renderIpfs", "/api/v1/files", "/api/v1/ipfs/backup", "IPFS"]:
    if needle not in shared_browser:
        raise SystemExit(f"missing shared file browser marker: {needle}")

portal_app = (app / "portal/creative_portal/app.py").read_text(encoding="utf-8")
for needle in ["/api/creative/models/download", "aria2c", "supportsHuggingFaceBlobUrls", "@app.get(\"/comfy/user.css\")", "_cpu_info", "_gpu_info", "_disk_info", "_list_dir_page", "pageSize", "AIGODLIKE-ComfyUI-Translation"]:
    if needle == "AIGODLIKE-ComfyUI-Translation":
        continue
    if needle not in portal_app:
        raise SystemExit(f"missing portal app marker: {needle}")

for name in ["services.yaml", "routes.yaml", "creative-suite-provisioning.yaml", "comfyui-extra-model-paths.yaml"]:
    text = (app / name).read_text(encoding="utf-8")
    if "apiVersion" not in text and name != "comfyui-extra-model-paths.yaml":
        raise SystemExit(f"missing apiVersion: {name}")

routes = (app / "routes.yaml").read_text(encoding="utf-8")
for needle in ["/comfy/user.css", "/comfy/ws", "upstream: http://127.0.0.1:8090/comfy/user.css", "upstream: http://127.0.0.1:8188/ws", "auth: excluded", "flushInterval: -1", "readTimeout: 24h", "writeTimeout: 24h", "dialTimeout: 30s", "keepAlive: 24h"]:
    if needle not in routes:
        raise SystemExit(f"missing routes marker: {needle}")

caddy_routes = (xforce_ai / "docker/common/caddy_manager/routes.py").read_text(encoding="utf-8")
for needle in ["flush_interval", "read_timeout", "write_timeout", "dial_timeout", "keepalive", "flushInterval", "readTimeout", "writeTimeout", "dialTimeout", "keepAlive"]:
    if needle not in caddy_routes:
        raise SystemExit(f"missing caddy route marker: {needle}")

caddy_render = (xforce_ai / "docker/common/caddy_manager/render.py").read_text(encoding="utf-8")
for needle in ["flush_interval", "transport http", "read_timeout", "write_timeout", "dial_timeout", "keepalive"]:
    if needle not in caddy_render:
        raise SystemExit(f"missing caddy render marker: {needle}")

dockerfile = (app / "Dockerfile").read_text(encoding="utf-8")
for needle in ["ComfyUI", "ollama", "requirements-comfyui.txt", "creative-suite-provisioning.yaml", "AIGODLIKE-ComfyUI-Translation", "CREATIVE_CACHE_ROOT", "xforce.hydrate.mode", "hydrate-creative-suite.sh", "CADDY_VERSION=2.11.4", "CADDY_SHA512_AMD64", "install-caddy.sh", "caddy version | grep -q"]:
    if needle not in dockerfile:
        raise SystemExit(f"missing Dockerfile marker: {needle}")

base_dockerfile = (xforce_ai / "docker/nvidia/Dockerfile").read_text(encoding="utf-8")
for needle in ["CADDY_VERSION=2.11.4", "CADDY_SHA512_AMD64", "CADDY_SHA512_ARM64", "install-caddy.sh"]:
    if needle not in base_dockerfile:
        raise SystemExit(f"missing base Dockerfile marker: {needle}")

base_packages = (xforce_ai / "docker/common/base-packages.txt").read_text(encoding="utf-8").splitlines()
if "caddy" in {line.strip() for line in base_packages}:
    raise SystemExit("base packages should not install distro caddy")

install_caddy = (xforce_ai / "docker/common/install-caddy.sh").read_text(encoding="utf-8")
for needle in ["CADDY_VERSION", "caddyserver/caddy/releases/download", "sha512sum -c", '"$install_path" version']:
    if needle not in install_caddy:
        raise SystemExit(f"missing install-caddy marker: {needle}")
PY
ok "static content markers"

"${app_dir}/scripts/build-creative-suite.sh" DRY_RUN=1 IMAGE_TAG=creative01-smoke >/tmp/xforce-creative-suite-build-dry-run.txt
grep -q 'xforce-dockers-uncensored-creative01:creative01-smoke' /tmp/xforce-creative-suite-build-dry-run.txt || fail "build dry-run repository tag missing"
grep -q 'xforce-creative-suite:creative01-smoke' /tmp/xforce-creative-suite-build-dry-run.txt || fail "build dry-run alias tag missing"
ok "build dry-run"

if [ "${RUN_DOCKER_SMOKE:-0}" = "1" ]; then
  image="${LOCAL_IMAGE:-xforce-creative-suite:smoke}"
  IMAGE_TAG=smoke LOCAL_IMAGE="$image" "${app_dir}/scripts/build-creative-suite.sh"
  docker run --rm --gpus all "$image" /opt/creative/bin/unload-vram.sh
  ok "docker smoke"
fi

ok "creative suite smoke complete"
