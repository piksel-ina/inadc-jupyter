# AGENTS.md

## What this repo is

Docker images and Jupyter notebooks for the Piksel Sandbox — Indonesia's Earth Observation analysis platform built on Open Data Cube. The `inadc_jupyter/` Python package is empty; the real content is Docker configs and tutorial notebooks.

## Commands

```bash
uv sync --locked --extra dev           # Install dev tools (ruff, pytest, ipython)
uv sync --locked --extra notebooks     # Install geospatial/data libraries
uv sync --locked --extra jupyter       # Install JupyterLab + extensions
uv run ruff check .                    # Lint
uv run ruff check --fix .              # Lint with autofix
uv run ruff format .                   # Format
```

There are no tests and no test runner configured.

## Notebook conventions

- `notebooks/English/Beginners_Guide/` — tutorials, `NN_Name.ipynb` (underscores)
- `notebooks/English/Case_Studies/` — analysis walkthroughs
- `notebooks/Indonesia/01-Panduan-Pengguna/` — Indonesian translations, `NN-name.ipynb` (hyphens)
- New notebooks pick the next number in sequence within the target directory
- Standard cell order: `# Title` → `## Background` → `## Description` (numbered steps + `***`) → `## Getting started` → `### Load packages` → content → conclusion
- Leave `execution_count: null` and `outputs: []` for new/cleaned cells
- Notebooks are delivered to users via nbgitpuller on JupyterHub login

## Docker

Two images, both based on `ghcr.io/osgeo/gdal:ubuntu-small-3.12.0`:

| Image | Dockerfile | ECR repo |
|-------|-----------|----------|
| Production | `docker/jupyter/Dockerfile` | `jupyter-lab` |
| Development | `docker/jupyter-dev/Dockerfile` | `jupyter-dev` |

```bash
docker build -t jupyter-lab -f docker/jupyter/Dockerfile .
docker build -t jupyter-dev -f docker/jupyter-dev/Dockerfile .
```

## CI / Release

Single workflow (`.github/workflows/build-image.yml`): builds and pushes to AWS ECR on tag push.

Tag formats (strict regex):
- Production: `jupyter-lab-vYYYYMMDD-HHMM`
- Development: `dev-jupyter-vYYYYMMDD-HHMM`

The tag prefix determines which Dockerfile is built and which ECR repo receives the image.

## Constraints

- Python `>=3.12,<3.13` — pinned to 3.12 only
- `uv.lock` is committed — always use `--locked` with uv sync
- `datacube-compute` is installed from a pre-built wheel URL, not PyPI
- `piksel` package is sourced from a git repo, not PyPI
- Ruff config: `E501` ignored, extended selectors `ANN I RUF UP`, autofix enabled
- `.tif`, `.aux.xml`, and `data/` are gitignored — geospatial output artifacts should not be committed
