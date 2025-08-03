## Overview

This Docker image provides a Jupyter Lab environment based on Micromamba (a lightweight Conda alternative) for data science, geospatial analysis (with GDAL/PROJ support), and Python development. It uses a multi-stage build for efficiency: a build stage installs dependencies from `conda-lock.yml` and `requirements.in`, and a slimmer runtime stage copies the artifacts. The image runs as non-root user `jovyan` with sudo access, activates the `base` Micromamba environment on startup, and supports shells like Bash and Fish.

## Managing Dependencies

This image uses a locked dependency approach for reproducibility:

### Conda Dependencies

Installed via `conda-lock.yml`, which is generated from an `environment.yaml` file. This locks exact package versions, ensuring consistent builds across environments.

**How to Generate `conda-lock.yml`**:

1.  Install `conda-lock` (e.g., via pip or conda in your local environment): `pip install conda-lock`.
2.  Create or update `environment.yaml` with your Conda/Micromamba dependencies (e.g., channels, packages like `python=3.12`, `jupyterlab`, etc.).
3.  Run: `conda-lock lock -f environment.yaml -p linux-64`

> **Note on Resource Usage**: Generating or updating `conda-lock.yml` can be memory-intensive. The last build used approximately 12 GB of memory, so beware when updating on systems with limited RAM. Run this on a machine with sufficient resources to avoid crashes.

### Pip Dependencies

Additional Python packages are handled via `requirements.in` (compiled to `requirements.txt` during build) for standard pip installs.

### Updating Dependencies

- For small updates or additions, prefer adding to `requirements.in` (e.g., `package==version`) and rebuild the image. This is lighter and avoids the high memory cost of regenerating `conda-lock.yml`.
- If a new package causes dependency conflicts with existing libraries (from `conda-lock.yml`) and it's crucial to add, install it forcefully in the Dockerfile's custom pip section:
  ```
  RUN /opt/conda/bin/pip install --no-cache-dir --force-reinstall --no-deps \
      ## some other packages &&\
      # your-package==version
  ```
  The `--force-reinstall --no-deps` flags ignore dependencies and conflicts, but use cautiously as it may break compatibility. Test thoroughly after adding.
