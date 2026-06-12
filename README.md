# xforce_dockers dynamic distribution

`xforce_dockers` contains application images built on top of the `xforce_AI` base images.

The first image is `uncensored_creative01`:

- Source: `workspace_web/xforce_dockers/uncensored_creative01/`
- Main image: `ghcr.io/0xforce-network/xforce-dockers-uncensored-creative01`
- Compatibility alias: `ghcr.io/0xforce-network/xforce-creative-suite`

## Distribution model

The image is intentionally lightweight. Large dependencies are not baked into the image by default.

The container ships with:

- portal code
- supervisor service definitions
- Caddy route definitions
- provisioning metadata
- runtime hydrate/install scripts
- architecture-aware dependency manifests

Deployment then runs:

```bash
/opt/creative/bin/hydrate-creative-suite.sh
/opt/creative/bin/install-creative-suite.sh
```

The hydrate phase uses `aria2c --continue=true` and `ARIA2_JOBS` to resume and parallelize downloads into a persistent cache volume.

## Cache layout

Default cache root:

```text
/workspace/cache/xforce_dockers/uncensored_creative01
```

Important subdirectories:

- `wheelhouse/` — Python wheels
- `artifacts/ollama/` — Ollama runtime artifact
- `artifacts/cloudflared/` — Cloudflared artifact
- `artifacts/repos/` — extracted ComfyUI source snapshots
- `source-archives/` — downloaded source archives

## Multi-arch behavior

The lightweight base image is designed for:

- `linux/amd64`
- `linux/arm64`

Heavy dependency selection happens at runtime through manifest files:

- `uncensored_creative01/manifests/deps.amd64.sh`
- `uncensored_creative01/manifests/deps.arm64.sh`

The `amd64` manifest uses the CUDA 12.4 PyTorch wheel path. The `arm64` manifest defaults to CPU PyTorch and arm64 runtime artifacts unless overridden by deployment environment variables.

## Build locally

Dry run:

```bash
workspace_web/xforce_dockers/uncensored_creative01/scripts/build-creative-suite.sh DRY_RUN=1 IMAGE_TAG=creative01-dev
```

Build and load a local amd64 image:

```bash
workspace_web/xforce_dockers/uncensored_creative01/scripts/build-creative-suite.sh IMAGE_TAG=creative01-dev PLATFORMS=linux/amd64 LOAD=1
```

## Publish through GitHub Actions

Workflow:

```text
workspace_web/xforce_dockers/.github/workflows/xforce-dockers-release.yml
```

The workflow publishes to GHCR and can also publish the compatibility alias. It is rooted under `xforce_dockers` and stages a temporary Docker build context containing this tree plus an `xforce_AI` companion checkout for shared install helpers.

## Production pinning

For fast update channels, use a tag such as:

```text
ghcr.io/0xforce-network/xforce-dockers-uncensored-creative01:creative01-latest
```

For production, prefer digest-pinned references such as:

```text
ghcr.io/0xforce-network/xforce-dockers-uncensored-creative01@sha256:<digest>
```

For strict reproducibility, pair digest-pinned images with locked hydrate manifests containing pinned URLs and sha256 checksums.
