ARG GDAL_VERSION=ubuntu-small-3.12.0

# --- Builder stage ---
FROM ghcr.io/osgeo/gdal:${GDAL_VERSION} AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc \
      g++ \
      git \
      libpq-dev \
      python3-dev \
      build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml uv.lock LICENSE ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-dev --extra jupyter

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-dev --extra jupyter --extra notebooks

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-dev --extra jupyter --extra notebooks --extra piksel

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install python-geohash mapclassify dea-intertidal && \
    uv pip install --no-deps git+https://github.com/auspatious/coastlines.git

# --- Runtime stage ---
FROM ghcr.io/osgeo/gdal:${GDAL_VERSION} AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      wget \
      git \
      tini \
      ca-certificates \
      postgresql-client \
      nano \
      vim-tiny \
      openssh-client \
      procps \
      htop \
      fontconfig \
      unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/share/fonts/truetype/hack-nerd-font && \
    wget -q -O /tmp/Hack.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/Hack.zip && \
    unzip -q /tmp/Hack.zip -d /usr/share/fonts/truetype/hack-nerd-font && \
    rm /tmp/Hack.zip && \
    fc-cache -fv

RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

ENV NB_USER=jovyan \
    NB_UID=1000 \
    HOME=/home/jovyan

RUN EXISTING_USER=$(getent passwd 1000 | cut -d: -f1) && \
    EXISTING_GROUP=$(getent group 1000 | cut -d: -f1) && \
    usermod -l ${NB_USER} -d ${HOME} -m ${EXISTING_USER} && \
    groupmod -n ${NB_USER} ${EXISTING_GROUP} && \
    mkdir -p ${HOME}/.config ${HOME}/.jupyter && \
    chown -R ${NB_USER}:${NB_USER} ${HOME} && \
    chown -R ${NB_USER}:${NB_USER} /app/.venv

ENV GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR" \
    CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif,.tiff" \
    GDAL_HTTP_MAX_RETRY="10" \
    GDAL_HTTP_RETRY_DELAY="1" \
    DASK_DISTRIBUTED__DASHBOARD__LINK="/proxy/{port}/status"

COPY docker/shared/jupyter_lab_config.py /etc/jupyter/
COPY docker/shared/jupyter_server_config.py /etc/jupyter/
ENV JUPYTER_CONFIG_PATH=/etc/jupyter:${HOME}/.jupyter

RUN mkdir -p /usr/local/share/jupyter/lab/settings
COPY docker/shared/overrides.json /usr/local/share/jupyter/lab/settings/overrides.json

RUN mkdir -p /etc/skel/.config
COPY docker/shared/starship.toml /etc/skel/.config/starship.toml
COPY --chown=${NB_USER}:${NB_USER} docker/shared/starship.toml ${HOME}/.config/starship.toml
COPY docker/jupyter/bashrc /etc/skel/.bashrc
COPY --chown=${NB_USER}:${NB_USER} docker/jupyter/bashrc ${HOME}/.bashrc

COPY docker/jupyter/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

COPY docker/jupyter/scripts/memory_watchdog.py /usr/local/bin/memory_watchdog.py
COPY docker/jupyter/scripts/disk_monitor.sh /usr/local/bin/disk_monitor.sh
RUN chmod +x /usr/local/bin/memory_watchdog.py /usr/local/bin/disk_monitor.sh

RUN git config --system --add safe.directory '*'

LABEL maintainer="taufik.shf@gmail.com" \
      description="INADC Jupyter Lab production image — GDAL + uv + Open Data Cube"

USER ${NB_UID}
WORKDIR ${HOME}

EXPOSE 8888 8787

ENTRYPOINT ["tini", "-g", "--", "start.sh"]
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--no-browser"]
