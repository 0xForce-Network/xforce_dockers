from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import urllib.error
import urllib.request
import urllib.parse
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Query, Request, Response, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse

from caddy_manager.auth import AuthConfig, sign_cookie, token_matches

from . import CREATIVE_PORTAL_VERSION


class CreativePortalError(Exception):
    def __init__(self, status_code: int, error: str, message: str) -> None:
        self.status_code = status_code
        self.error = error
        self.message = message


@dataclass(frozen=True)
class FileRoot:
    name: str
    path: Path


MODEL_DOWNLOAD_JOBS: dict[str, dict[str, Any]] = {}
MODEL_DOWNLOAD_LOCK = threading.Lock()
MODEL_FILENAME_RE = re.compile(r"[^A-Za-z0-9._+@=-]+")
MODEL_EXTENSIONS = {
    ".safetensors",
    ".ckpt",
    ".pt",
    ".pth",
    ".bin",
    ".gguf",
    ".onnx",
    ".json",
    ".yaml",
    ".yml",
}


def _static_dir() -> Path:
    return Path(os.environ.get("CREATIVE_PORTAL_STATIC", "/opt/creative/portal/static"))


def _parse_roots() -> dict[str, FileRoot]:
    raw = os.environ.get("CREATIVE_FILE_ROOTS", "models:/workspace/models,outputs:/workspace/outputs,creative:/workspace/creative")
    roots: dict[str, FileRoot] = {}
    for item in raw.split(","):
        item = item.strip()
        if not item or ":" not in item:
            continue
        name, path = item.split(":", 1)
        name = name.strip().lower()
        if not name.replace("-", "").replace("_", "").isalnum():
            continue
        root = Path(path.strip()).resolve()
        root.mkdir(parents=True, exist_ok=True)
        roots[name] = FileRoot(name=name, path=root)
    return roots


def _error(status_code: int, error: str, message: str) -> None:
    raise CreativePortalError(status_code, error, message)


def _auth_cfg() -> AuthConfig:
    return AuthConfig.from_yaml_env(Path("/etc/xforce-ai/caddy/auth.yaml"))


def _login_html() -> str:
    return "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"0;url=/\"><title>xforce login</title></head><body><script>location.replace('/')</script><a href=\"/\">Continue to xforce creative suite</a></body></html>"


def _json_url(url: str, timeout: float = 2.0) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return {"ok": True, "status": response.status, "data": json.loads(body) if body else {}}
    except urllib.error.HTTPError as exc:
        return {"ok": False, "status": exc.code, "error": str(exc)}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "status": 0, "error": str(exc)}


def _text_url(url: str, timeout: float = 2.0) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return {"ok": True, "status": response.status, "body": response.read(4096).decode("utf-8", errors="replace")}
    except urllib.error.HTTPError as exc:
        return {"ok": False, "status": exc.code, "error": str(exc)}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "status": 0, "error": str(exc)}


def _safe_child(root: FileRoot, rel_path: str) -> Path:
    rel_path = rel_path.strip().lstrip("/")
    candidate = (root.path / rel_path).resolve()
    if candidate != root.path and root.path not in candidate.parents:
        _error(403, "path_denied", "requested path escapes the configured file root")
    return candidate


def _entry(path: Path, root: FileRoot) -> dict[str, Any]:
    stat = path.stat()
    rel = "" if path == root.path else path.relative_to(root.path).as_posix()
    return {
        "name": path.name or root.name,
        "root": root.name,
        "path": rel,
        "type": "directory" if path.is_dir() else "file",
        "size": stat.st_size,
        "modified": stat.st_mtime,
    }


def _list_dir(path: Path, root: FileRoot) -> dict[str, Any]:
    return _list_dir_page(path, root)


def _list_dir_page(path: Path, root: FileRoot, page: int = 1, page_size: int = 15, search: str = "", sort: str = "name", order: str = "asc") -> dict[str, Any]:
    if not path.exists():
        _error(404, "not_found", "path does not exist")
    if not path.is_dir():
        return {"root": root.name, "entry": _entry(path, root), "entries": []}
    normalized_search = search.strip().lower()
    entries = [_entry(child, root) for child in path.iterdir()]
    if normalized_search:
        entries = [entry for entry in entries if normalized_search in entry["name"].lower() or normalized_search in entry["path"].lower()]
    sort_key = sort if sort in {"name", "type", "size", "modified"} else "name"
    reverse = order.lower() == "desc"
    entries = sorted(
        entries,
        key=lambda item: (
            item["type"] != "directory",
            item[sort_key].lower() if isinstance(item[sort_key], str) else item[sort_key],
            item["name"].lower(),
        ),
        reverse=reverse,
    )
    safe_page_size = min(max(page_size, 1), 100)
    safe_page = max(page, 1)
    total = len(entries)
    start = (safe_page - 1) * safe_page_size
    end = start + safe_page_size
    return {
        "root": root.name,
        "entry": _entry(path, root),
        "entries": entries[start:end],
        "pagination": {"page": safe_page, "pageSize": safe_page_size, "total": total, "pages": max((total + safe_page_size - 1) // safe_page_size, 1)},
        "query": {"search": search, "sort": sort_key, "order": "desc" if reverse else "asc"},
    }


def _cpu_info() -> dict[str, Any]:
    host_threads = os.cpu_count() or 1
    effective_threads = host_threads
    cpu_max = Path("/sys/fs/cgroup/cpu.max")
    try:
        quota_raw, period_raw = cpu_max.read_text(encoding="utf-8").split()[:2]
        if quota_raw != "max":
            quota = int(quota_raw)
            period = int(period_raw)
            if quota > 0 and period > 0:
                effective_threads = max(1, min(host_threads, int((quota + period - 1) / period)))
    except Exception:
        pass
    recommended = max(1, min(effective_threads, int(round(effective_threads * 0.75))))
    return {"hostThreads": host_threads, "effectiveThreads": effective_threads, "recommendedThreads": recommended, "policy": "75% of available CPU threads"}


def _disk_info() -> dict[str, Any]:
    def usage(path: str) -> dict[str, Any]:
        try:
            total, used, free = shutil.disk_usage(path)
            return {"path": path, "totalBytes": total, "usedBytes": used, "freeBytes": free}
        except Exception as exc:  # noqa: BLE001
            return {"path": path, "error": str(exc)}

    return {"root": usage("/"), "workspace": usage("/workspace"), "configuredStorageSize": os.environ.get("CREATIVE_DEPLOY_STORAGE_SIZE", "")}


def _gpu_info() -> dict[str, Any]:
    nvidia_smi = shutil.which("nvidia-smi")
    if not nvidia_smi:
        return {"available": False, "count": 0, "gpus": [], "error": "nvidia-smi not found"}
    try:
        completed = subprocess.run(
            [nvidia_smi, "--query-gpu=name,memory.total,memory.free,driver_version", "--format=csv,noheader,nounits"],
            check=False,
            text=True,
            capture_output=True,
            timeout=5,
        )
        gpus = []
        for line in completed.stdout.splitlines():
            parts = [part.strip() for part in line.split(",")]
            if len(parts) >= 4:
                gpus.append({"name": parts[0], "vramTotalMiB": parts[1], "vramFreeMiB": parts[2], "driverVersion": parts[3]})
        cuda = subprocess.run([nvidia_smi], check=False, text=True, capture_output=True, timeout=5).stdout
        cuda_version = ""
        match = re.search(r"CUDA Version:\s*([0-9.]+)", cuda)
        if match:
            cuda_version = match.group(1)
        return {"available": bool(gpus), "count": len(gpus), "cudaVersion": cuda_version, "gpus": gpus}
    except Exception as exc:  # noqa: BLE001
        return {"available": False, "count": 0, "gpus": [], "error": str(exc)}


def _tail_text(path: Path, limit: int = 65536) -> str:
    if not path.exists():
        return ""
    data = path.read_bytes()[-limit:]
    return data.decode("utf-8", errors="replace")


def _model_targets() -> dict[str, Path]:
    base = Path(os.environ.get("CREATIVE_MODEL_ROOT", "/workspace/models")).resolve()
    targets = {
        "checkpoints": base / "checkpoints",
        "loras": base / "loras",
        "vae": base / "vae",
        "controlnet": base / "controlnet",
        "embeddings": base / "embeddings",
        "animatediff": base / "animatediff",
        "upscale_models": base / "upscale_models",
        "clip": base / "clip",
        "unet": base / "unet",
        "diffusion_models": base / "diffusion_models",
        "cogvideox": base / "cogvideox",
    }
    for path in targets.values():
        path.mkdir(parents=True, exist_ok=True)
    return targets


def _normalize_model_url(url: str) -> str:
    url = url.strip()
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        _error(400, "invalid_model_url", "model URL must be an absolute http(s) URL")
    if parsed.netloc.lower() == "huggingface.co" and "/blob/" in parsed.path:
        parsed = parsed._replace(path=parsed.path.replace("/blob/", "/resolve/", 1))
    return urllib.parse.urlunparse(parsed)


def _model_filename(url: str, requested: str | None = None) -> str:
    raw = requested.strip() if requested else Path(urllib.parse.unquote(urllib.parse.urlparse(url).path)).name
    name = MODEL_FILENAME_RE.sub("_", raw).strip("._ ")
    if not name:
        _error(400, "invalid_filename", "model filename could not be inferred from URL")
    suffixes = [suffix.lower() for suffix in Path(name).suffixes]
    if not any(suffix in MODEL_EXTENSIONS for suffix in suffixes):
        _error(400, "unsupported_model_extension", "model filename must use a ComfyUI model extension")
    return name


def _update_model_job(job_id: str, **values: Any) -> None:
    with MODEL_DOWNLOAD_LOCK:
        job = MODEL_DOWNLOAD_JOBS.setdefault(job_id, {})
        job.update(values)


def _get_model_job(job_id: str) -> dict[str, Any] | None:
    with MODEL_DOWNLOAD_LOCK:
        job = MODEL_DOWNLOAD_JOBS.get(job_id)
        return dict(job) if job else None


def _run_model_download(job_id: str, url: str, target_dir: Path, filename: str, force: bool) -> None:
    log_dir = Path(os.environ.get("CREATIVE_MODEL_DOWNLOAD_LOG_DIR", "/tmp/xforce-creative-portal/model-downloads"))
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"{job_id}.log"
    target = target_dir / filename
    aria2 = shutil.which("aria2c")
    if aria2:
        cmd = [
            aria2,
            "--continue=true",
            "--max-connection-per-server=16",
            "--split=16",
            "--min-split-size=8M",
            "--retry-wait=5",
            "--max-tries=0",
            "--timeout=30",
            "--connect-timeout=15",
            "--allow-overwrite=true",
            "--auto-file-renaming=false",
            "--dir",
            str(target_dir),
            "--out",
            filename,
            url,
        ]
    else:
        curl = shutil.which("curl") or "/usr/bin/curl"
        cmd = [curl, "-fL", "--retry", "5", "--retry-delay", "5", "-C", "-", "-o", str(target), url]
    if force:
        try:
            (target_dir / f"{filename}.aria2").unlink()
        except FileNotFoundError:
            pass
    _update_model_job(job_id, status="running", command=" ".join(cmd), logFile=str(log_file))
    with log_file.open("w", encoding="utf-8") as handle:
        handle.write(f"url={url}\ntarget={target}\nmode={'aria2' if aria2 else 'curl-fallback'}\n\n")
        handle.flush()
        completed = subprocess.run(cmd, cwd=str(target_dir), check=False, text=True, stdout=handle, stderr=subprocess.STDOUT)
    if completed.returncode == 0 and target.exists() and target.stat().st_size > 0:
        try:
            target.chmod(0o664)
        except OSError:
            pass
        _update_model_job(
            job_id,
            status="completed",
            ok=True,
            returncode=completed.returncode,
            size=target.stat().st_size,
            message="模型下载/更新完成。刷新 ComfyUI 页面或在 ComfyUI 中刷新模型列表即可使用。",
        )
        return
    _update_model_job(job_id, status="failed", ok=False, returncode=completed.returncode, message="模型下载失败，请查看日志输出。")


def _pty_wrapper() -> str | None:
    for candidate in (shutil.which("xforce-pty-wrap"), "/opt/xforce-ai/bin/xforce-pty-wrap"):
        if candidate and Path(candidate).exists():
            return candidate
    return None


def _shell_command_args(command: str) -> tuple[str, list[str]]:
    nu = shutil.which("nu") or ("/usr/local/bin/nu" if Path("/usr/local/bin/nu").exists() else "") or ("/usr/bin/nu" if Path("/usr/bin/nu").exists() else "")
    shell = nu or "/bin/bash"
    if shell.endswith("/nu"):
        return shell, [shell, "--no-std-lib", "-c", command]
    return shell, [shell, "-lc", command]


def create_app() -> FastAPI:
    roots = _parse_roots()
    app = FastAPI(title="xforce Creative Suite Portal", version=CREATIVE_PORTAL_VERSION)

    @app.exception_handler(CreativePortalError)
    async def creative_error_handler(_request: Any, exc: CreativePortalError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content={"error": exc.error, "message": exc.message})

    @app.get("/", response_class=HTMLResponse)
    def index() -> FileResponse:
        path = _static_dir() / "index.html"
        if not path.exists():
            _error(500, "static_missing", "creative portal index.html is missing")
        return FileResponse(path)

    @app.get("/favicon.ico")
    def favicon() -> Response:
        return Response(status_code=204)

    @app.get("/comfy/user.css")
    def comfy_user_css() -> Response:
        try:
            with urllib.request.urlopen("http://127.0.0.1:8188/api/userdata/user.css", timeout=2.0) as response:
                body = response.read()
        except Exception:  # noqa: BLE001
            body = b""
        return Response(content=body, media_type="text/css")

    @app.get("/__xforce_login/{token}")
    def login(token: str) -> HTMLResponse:
        auth_cfg = _auth_cfg()
        if not token_matches(token, auth_cfg):
            _error(401, "unauthorized", "valid xforce auth token is required")
        cookie = sign_cookie(auth_cfg.token, auth_cfg.cookie_secret)
        response = HTMLResponse(_login_html(), status_code=200)
        response.set_cookie(auth_cfg.cookie_name, cookie, httponly=True, samesite="lax", max_age=auth_cfg.cookie_ttl_seconds)
        return response

    @app.post("/api/creative/shell/run")
    async def run_shell(request: Request) -> dict[str, Any]:
        payload = await request.json()
        command = str(payload.get("command") or "").strip()
        cwd_raw = str(payload.get("cwd") or "/workspace").strip() or "/workspace"
        timeout = min(max(int(payload.get("timeoutSeconds") or 120), 1), 900)
        if not command:
            _error(400, "empty_command", "command is required")
        cwd = Path(cwd_raw).resolve()
        allowed = [Path("/workspace").resolve(), Path("/opt/creative").resolve(), Path("/tmp").resolve()]
        if not any(cwd == root or root in cwd.parents for root in allowed):
            _error(403, "cwd_denied", "cwd must stay under /workspace, /opt/creative, or /tmp")
        shell, shell_args = _shell_command_args(command)
        run_id = f"creative-{uuid.uuid4().hex[:16]}"
        pty = _pty_wrapper()
        if pty:
            log_dir = Path(os.environ.get("CREATIVE_PTY_LOG_DIR", "/tmp/xforce-creative-portal/pty"))
            log_dir.mkdir(parents=True, exist_ok=True)
            args = [pty, "run", "--run-id", run_id, "--log-dir", str(log_dir), "--cwd", str(cwd), "--no-console", "--json", "--", *shell_args]
            timeout_bin = shutil.which("timeout")
            if timeout_bin:
                args = [timeout_bin, "--kill-after=10s", f"{timeout}s", *args]
            completed = subprocess.run(args, cwd=str(cwd), check=False, text=True, capture_output=True, timeout=timeout + 15)
            run_dir = log_dir / run_id
            return {
                "ok": completed.returncode == 0,
                "mode": "pty",
                "runId": run_id,
                "shell": shell,
                "cwd": str(cwd),
                "returncode": completed.returncode,
                "state": completed.stdout[-16384:],
                "stdout": _tail_text(run_dir / "stdout.plain.log"),
                "stderr": completed.stderr[-65536:],
            }
        completed = subprocess.run(shell_args, cwd=str(cwd), check=False, text=True, capture_output=True, timeout=timeout)
        return {
            "ok": completed.returncode == 0,
            "mode": "subprocess",
            "runId": run_id,
            "shell": shell,
            "cwd": str(cwd),
            "returncode": completed.returncode,
            "stdout": completed.stdout[-65536:],
            "stderr": completed.stderr[-65536:],
        }

    @app.get("/api/creative/status")
    def status() -> dict[str, Any]:
        return {
            "status": "ok",
            "version": CREATIVE_PORTAL_VERSION,
            "mode": {
                "name": "creative",
                "serialOllama": os.environ.get("OLLAMA_NUM_PARALLEL", "1"),
                "ollamaThreads": _cpu_info()["recommendedThreads"],
                "vramProfile": "lowvram",
            },
            "cpu": _cpu_info(),
            "gpu": _gpu_info(),
            "storage": _disk_info(),
            "deployment": {
                "profile": os.environ.get("CREATIVE_DEPLOY_PROFILE", "custom"),
                "cpus": os.environ.get("CREATIVE_DEPLOY_CPUS", ""),
                "cpusetCpus": os.environ.get("CREATIVE_DEPLOY_CPUSET_CPUS", ""),
                "memory": os.environ.get("CREATIVE_DEPLOY_MEMORY", ""),
                "memorySwap": os.environ.get("CREATIVE_DEPLOY_MEMORY_SWAP", ""),
                "shmSize": os.environ.get("CREATIVE_DEPLOY_SHM_SIZE", ""),
                "pidsLimit": os.environ.get("CREATIVE_DEPLOY_PIDS_LIMIT", ""),
                "gpus": os.environ.get("CREATIVE_DEPLOY_GPUS", "all"),
                "storageSize": os.environ.get("CREATIVE_DEPLOY_STORAGE_SIZE", ""),
            },
            "shell": {
                "preferred": _shell_command_args("version")[0],
                "ptyWrapper": _pty_wrapper() or "",
                "ptyLogDir": os.environ.get("CREATIVE_PTY_LOG_DIR", "/tmp/xforce-creative-portal/pty"),
            },
            "modelDownloader": {
                "targets": {name: str(path) for name, path in _model_targets().items()},
                "logDir": os.environ.get("CREATIVE_MODEL_DOWNLOAD_LOG_DIR", "/tmp/xforce-creative-portal/model-downloads"),
                "supportsHuggingFaceBlobUrls": True,
                "downloader": "aria2c" if shutil.which("aria2c") else "curl-fallback",
            },
            "services": {
                "ollama": _json_url("http://127.0.0.1:11434/api/tags"),
                "comfyui": _text_url("http://127.0.0.1:8188/"),
                "portal": _json_url("http://127.0.0.1:8080/api/v1/health"),
            },
            "fileRoots": [{"name": root.name, "path": str(root.path)} for root in roots.values()],
        }

    @app.post("/api/creative/models/download")
    async def download_model(request: Request) -> dict[str, Any]:
        payload = await request.json()
        url = _normalize_model_url(str(payload.get("url") or ""))
        targets = _model_targets()
        target_name = str(payload.get("target") or "checkpoints").strip().lower()
        target_dir = targets.get(target_name)
        if not target_dir:
            _error(400, "unknown_model_target", "target must be one of the configured ComfyUI model folders")
        filename = _model_filename(url, str(payload.get("filename") or "").strip() or None)
        force = bool(payload.get("force") or False)
        target = target_dir / filename
        job_id = f"model-{uuid.uuid4().hex[:16]}"
        if target.exists() and target.stat().st_size > 0 and not force and not (target_dir / f"{filename}.aria2").exists():
            job = {
                "ok": True,
                "jobId": job_id,
                "status": "completed",
                "url": url,
                "target": target_name,
                "path": str(target),
                "filename": filename,
                "size": target.stat().st_size,
                "message": "模型已存在。刷新 ComfyUI 页面或在 ComfyUI 中刷新模型列表即可使用。",
            }
            _update_model_job(job_id, **job)
            return job
        job = {
            "ok": None,
            "jobId": job_id,
            "status": "queued",
            "url": url,
            "target": target_name,
            "path": str(target),
            "filename": filename,
            "force": force,
            "message": "后台多线程下载已启动。完成后刷新 ComfyUI 页面即可。",
        }
        _update_model_job(job_id, **job)
        thread = threading.Thread(target=_run_model_download, args=(job_id, url, target_dir, filename, force), daemon=True)
        thread.start()
        return dict(job)

    @app.get("/api/creative/models/download/{job_id}")
    def model_download_status(job_id: str) -> dict[str, Any]:
        job = _get_model_job(job_id)
        if not job:
            _error(404, "unknown_model_download", "model download job was not found")
        log_file = Path(str(job.get("logFile") or ""))
        job["logTail"] = _tail_text(log_file, limit=32768) if str(log_file) else ""
        path = Path(str(job.get("path") or ""))
        if str(path):
            job["exists"] = path.exists()
            job["size"] = path.stat().st_size if path.exists() else job.get("size", 0)
        return job

    @app.post("/api/creative/unload")
    def unload_vram() -> dict[str, Any]:
        script = os.environ.get("CREATIVE_UNLOAD_SCRIPT", "/opt/creative/bin/unload-vram.sh")
        if not Path(script).exists():
            _error(500, "script_missing", "VRAM unload script is missing")
        completed = subprocess.run([script], check=False, text=True, capture_output=True, timeout=30)
        return {"ok": completed.returncode == 0, "returncode": completed.returncode, "stdout": completed.stdout[-4096:], "stderr": completed.stderr[-4096:]}

    @app.get("/files/")
    def list_roots() -> dict[str, Any]:
        return {"roots": [{"name": root.name, "path": str(root.path)} for root in roots.values()]}

    @app.get("/files/{root_name}")
    def list_root(root_name: str, page: int = Query(default=1), pageSize: int = Query(default=15), search: str = Query(default=""), sort: str = Query(default="name"), order: str = Query(default="asc")) -> dict[str, Any]:
        root = roots.get(root_name.lower())
        if not root:
            _error(404, "unknown_root", "file root is not configured")
        return _list_dir_page(root.path, root, page=page, page_size=pageSize, search=search, sort=sort, order=order)

    @app.get("/files/{root_name}/{rel_path:path}")
    def get_file(root_name: str, rel_path: str, download: bool = Query(default=False), page: int = Query(default=1), pageSize: int = Query(default=15), search: str = Query(default=""), sort: str = Query(default="name"), order: str = Query(default="asc")) -> Any:
        root = roots.get(root_name.lower())
        if not root:
            _error(404, "unknown_root", "file root is not configured")
        path = _safe_child(root, rel_path)
        if not path.exists():
            _error(404, "not_found", "path does not exist")
        if path.is_dir() and not download:
            return _list_dir_page(path, root, page=page, page_size=pageSize, search=search, sort=sort, order=order)
        if path.is_dir():
            _error(400, "directory_download_denied", "directory download is not supported")
        return FileResponse(path, filename=path.name if download else None)

    @app.post("/files/{root_name}/{rel_path:path}")
    async def upload_file(root_name: str, rel_path: str, file: UploadFile = File(...)) -> dict[str, Any]:
        root = roots.get(root_name.lower())
        if not root:
            _error(404, "unknown_root", "file root is not configured")
        directory = _safe_child(root, rel_path)
        directory.mkdir(parents=True, exist_ok=True)
        if not directory.is_dir():
            _error(400, "upload_target_invalid", "upload target must be a directory")
        filename = Path(file.filename or "upload.bin").name
        target = _safe_child(root, str(directory.relative_to(root.path) / filename))
        with target.open("wb") as handle:
            while chunk := await file.read(1024 * 1024):
                handle.write(chunk)
        return {"ok": True, "entry": _entry(target, root)}

    return app
