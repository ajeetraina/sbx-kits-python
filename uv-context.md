# uv (Python package manager)

`uv` and `uvx` are installed in `/usr/local/bin`, so they work out of the box.
uv is an extremely fast, drop-in replacement for pip, pip-tools, pipx, virtualenv
and more, and it can also provision Python interpreters for you.

No sign-in is needed for public PyPI. uv resolves against `pypi.org` and
downloads wheels/sdists from `files.pythonhosted.org`; both are open in this
sandbox's network policy.

## Common commands

```sh
uv --version

# Project workflow: create, add deps, run. uv manages a .venv automatically.
uv init myapp && cd myapp
uv add requests
uv run python -c "import requests; print(requests.__version__)"

# Sync an existing project's locked dependencies.
uv sync

# Run a tool in an ephemeral environment (like pipx run), e.g. a linter.
uvx ruff check .

# pip-compatible interface, if you prefer it.
uv pip install httpx
uv pip list
```

## Python interpreters

uv can download and manage standalone Python builds. This reaches
`github.com` / `objects.githubusercontent.com` (the astral-sh
python-build-standalone releases), which are open at runtime:

```sh
uv python install 3.12
uv python list
uv run --python 3.12 python --version
```

If you only ever install packages against a Python already present on the base
image, those two hosts are not needed and can be removed from the kit's runtime
allowlist.

## Notes

- The kit ships the fully static musl builds of uv/uvx, so it runs on any base
  (glibc or musl) with no interpreter or libc dependency of its own.
- uv caches downloads under `$XDG_CACHE_HOME` / `~/.cache/uv`. Add a
  `volume@1` capability on that path if you want the cache to persist across
  sandbox restarts.
