# INADC Jupyter

Jupyter environments and tutorial notebooks for the [BIG Piksel platform](https://piksel-ina.github.io/piksel-core/) — Indonesia's satellite data analysis infrastructure built on [Open Data Cube](https://www.opendatacube.org/).

## Repository structure

```
inadc-jupyter/
├── docker/
│   ├── jupyter/          Production Jupyter Lab image (GDAL base + uv)
│   └── jupyter-dev/      Development Jupyter Lab image (GDAL base + uv + dev tools)
└── notebooks/
    ├── English/          Tutorial notebooks (English)
    ├── Indonesia/        Tutorial notebooks (Bahasa Indonesia)
    └── assets/           Shared assets for notebooks
```

## Docker images

Two images are built from this repo and pushed to AWS ECR:

| Image | Dockerfile | ECR repo | Tag pattern |
|-------|-----------|----------|-------------|
| Production | `docker/jupyter/Dockerfile` | `jupyter-lab` | `jupyter-*` |
| Development | `docker/jupyter-dev/Dockerfile` | `jupyter-dev` | `dev-jupyter-*` |

Both images are based on `ghcr.io/osgeo/gdal:ubuntu-small-3.12.0` and use [uv](https://docs.astral.sh/uv/) for Python dependency management.

### Building locally

```bash
# Production image
docker build -t jupyter-lab -f docker/jupyter/Dockerfile .

# Development image
docker build -t jupyter-dev -f docker/jupyter-dev/Dockerfile .
```

## Notebooks

Tutorial notebooks are delivered to running Jupyter instances via [nbgitpuller](https://github.com/jupyterhub/nbgitpuller). When users log in to JupyterHub, nbgitpuller pulls the latest notebooks from this repository into their workspace.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
