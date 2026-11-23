# INADC Jupyter

Docker images and tutorial notebooks for the [Piksel platform](https://piksel.big.go.id) (Digital Earth Indonesia), built on [Open Data Cube](https://www.opendatacube.org/). The images provide the JupyterLab environment, and the notebooks are the tutorials and case studies that JupyterHub delivers to users.

The notebooks and the Docker images live in one repository so that every dependency a notebook needs is installed by the image. Dependencies are added only when a notebook needs them, to keep the images small. Packages are managed with [uv](https://docs.astral.sh/uv/).

- `notebooks/`: the notebook collection displayed in the [Sandbox](https://sandbox.piksel.big.go.id).
- `docker/`: the Docker images.
- `site/`: a web gallery of the notebooks, under development.
- `notebooks/assets/`: images shared by the notebooks.
- `pyproject.toml`: the single list of dependencies for the images and the notebooks.

## Docker images

- Public Sandbox image: the environment delivered for most users of the Sandbox.
- Developer Sandbox image: a less restricted environment for product development.

For building and releasing, see [docker/README.md](docker/README.md).

## Notebooks

Learning material from guided tutorials to full case studies, in English and Indonesian. By convention, notebooks are committed without outputs. See [notebooks/README.md](notebooks/README.md).

## Getting started

This is for developing the notebooks or the Docker images, not for running the notebooks as a Sandbox user.

`make up` starts the Developer Sandbox image, which needs a running Open Data Cube. We recommend [inadc-odc](https://github.com/piksel-ina/inadc-odc), which has a quick datacube setup and product definitions, and keeps the datacube version consistent across development. Any other ODC setup can be used. Run `make help` for the other commands.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
