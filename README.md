# sbx-kit-uv

A Docker Sandboxes kit (v3 format) that adds **uv**, Astral's fast Python
package and project manager, to any agent sandbox. It is a mixin, so you layer
it onto any agent: claude, codex, copilot, opencode, or a plain shell.


## The files a v3 kit needs

| File | Role |
|---|---|
| `sbx-kit-uv.yaml` | The **descriptor** — kind, args, provides, network policy, lifecycle, agent context. First line is the `# syntax=docker/sandbox-kit:3` frontend. |
| `sbx-kit-uv.dockerfile` | The **content recipe** — found by filename stem (same as the `.yaml`). Downloads the official uv release and copies it into a `scratch` overlay. |
| `uv-context.md` | The **agent-context** body the agent reads (referenced by `contentFile:`). |
| `README.md` | Human docs (this file). |
| `.gitignore` | Ignores the local `skills/` dir. |

## What it does

- Installs the `uv` and `uvx` binaries into `/usr/local/bin`, from the official
  Astral GitHub release. The **fully static musl** builds are used, so the
  overlay lands on any base (glibc or musl) with no libc or interpreter
  dependency of its own. The binaries are baked into the kit image at build
  time, so every sandbox has uv the instant it starts, with no per-create
  download.
- Pins the version through a kit arg. `uvVersion` defaults to `0.12.19` and
  accepts a semver such as `0.12.0`. That one value drives the install, the
  `uv@<version>` provide, the published image version, and the tag.
- Opens only the network egress that resolving and installing needs (PyPI, the
  PyPI CDN, and the GitHub hosts uv fetches standalone Python builds from).
- Runs `uv --version` on startup as a health check.

## Requirements

None. The kit ships static binaries and needs nothing from the base image — no
Python interpreter, no package manager, no particular libc. That is why the
descriptor declares no `requires`: it is a hard, closed-set precondition on
every composition, and declaring one would make the kit refuse to compose on
bases it would in fact run on perfectly.

## Run it locally

A v3 mixin must layer onto a v3 **workload** kit. The built-in `shell`/`claude`
agent names resolve to plain images, not v3 workloads, so composing directly
onto them fails with "no workload kit in the set." Use a published v3 workload
base such as `ajeetraina777/sbx-kit-shell` (or `ajeetraina777/sbx-kit-codex`,
`ajeetraina777/sbx-kit-claude`, etc.):

> **Note:** these `ajeetraina777/*` workload bases must be published under your
> own Docker ID first. If you have not published your own, use Docker's official
> bases instead (`docker/sbx-kit-shell`, `docker/sbx-kit-codex`,
> `docker/sbx-kit-claude`), which work out of the box.

```sh
# Layer the kit onto the v3 shell workload, in the current directory.
sbx run ajeetraina777/sbx-kit-shell --kit . .

# Pin a specific uv version.
sbx run ajeetraina777/sbx-kit-shell --kit . --kit-arg uvVersion=0.12.0 .

# Layer it onto a coding agent instead of the shell.
sbx run ajeetraina777/sbx-kit-codex --kit . .
```

Inside the sandbox:

```sh
uv --version
uv init myapp && cd myapp
uv add requests
uv run python -c "import requests; print(requests.__version__)"
```

## Run it in the cloud

Cloud sandboxes take the same flags:

```sh
sbx --cloud run ajeetraina777/sbx-kit-shell --kit .
```

Or reference the kit by its published OCI tag once you have pushed it (see
[Publishing](#publishing)):

```sh
sbx --cloud run ajeetraina777/sbx-kit-shell --kit docker.io/ajeetraina777/sbx-kit-uv:latest
```

## Network allowlist

The kit allows only these hosts at runtime, and each is exercised by resolving,
installing, or provisioning a Python interpreter:

| Host | Why |
|---|---|
| `pypi.org` | PyPI Simple/JSON index that uv resolves against |
| `files.pythonhosted.org` | PyPI CDN that serves wheels and sdists |
| `github.com` | `uv python install` fetches standalone Python builds |
| `objects.githubusercontent.com` | GitHub release asset CDN those downloads redirect to |

Drop the last two if you only install packages against a Python already on the
base image. The install-time hosts (`astral.sh`, the uv release assets) are
reached by `docker buildx build` when the kit image is built, not by the running
sandbox, so they are not in the runtime policy.

## How it is built

This is a v3 kit: a Dockerfile-based overlay built by the `docker/sandbox-kit:3`
BuildKit frontend.

- `sbx-kit-uv.yaml` is the descriptor.
- `sbx-kit-uv.dockerfile` is the overlay recipe: it downloads the official uv
  release tarball in a build stage and copies the binaries into a `scratch`
  overlay.
- `uv-context.md` is the instruction file the agent reads.

The build stage runs on a Docker Hardened Image
(`dhi.io/debian-base:trixie-dev`, the base the sandbox-kit-spec RECIPES.md
recommends for a mixin overlay). Nothing from it ships in the kit (the final
stage is `scratch` and copies only the `uv`/`uvx` binaries), so this is about
supply-chain hygiene of the build, not the delivered artifact. Because it pulls
from dhi.io, run `docker login dhi.io` before building, or override the builder
with a public base via `--build-arg BUILDER_IMAGE=debian:trixie-slim`.

Validate and build locally:

```sh
docker login dhi.io          # the build stage pulls a DHI base

# Preview how the kit resolves.
sbx kit inspect .

# Validate the descriptor without building content (fails fast on a bad field).
docker buildx build . -f sbx-kit-uv.yaml --output type=cacheonly

# Build to an OCI layout and run the conformance suite.
docker buildx build . -f sbx-kit-uv.yaml \
  -t sbx-kit-uv:0.12.19 \
  --output type=oci,dest=/tmp/sbx-kit-uv-layout,tar=false
kit-tck validate --layout /tmp/sbx-kit-uv-layout 0.12.19
```

## Publishing

v3 kits are published as OCI images with `docker buildx build --push`, not with
`sbx kit push` (that verb is for the older schemaVersion 1 and 2 ZIP/tar kits).
Push both platforms in one build so the tag serves a proper multi-arch index:

```sh
docker buildx build . -f sbx-kit-uv.yaml \
  --platform linux/amd64,linux/arm64 --push \
  -t docker.io/ajeetraina777/sbx-kit-uv:0.12.19 \
  -t docker.io/ajeetraina777/sbx-kit-uv:latest
```

To pin a specific uv release into the published image, add
`--build-arg UV_VERSION=0.12.0` (or use `--kit-arg uvVersion=0.12.0` at run
time on an unpinned image).
