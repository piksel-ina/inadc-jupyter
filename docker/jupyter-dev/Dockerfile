ARG GDAL_VERSION=ubuntu-small-3.12.0

# ---------- Stage 1: Base System Setup --------------------------------------
FROM ghcr.io/osgeo/gdal:${GDAL_VERSION} AS system-base

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ca-certificates \
    vim \
    nano \
    sudo \
    build-essential \
    python3-pip \
    python3-venv \
    python3-dev \
    fontconfig \
    unzip \
    openssh-server \
    jq \
    tree \
    htop \
    tini \
    libpq-dev \
    libxml2-dev \
    libxslt1-dev \
    libsqlite3-dev \
    postgresql-client \
    make \
    gcc \
    g++ \
    libspatialindex-dev \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

# ---------- Stage 2: Font and CLI Tools --------------------------------------
FROM system-base AS tools-setup

RUN mkdir -p /usr/share/fonts/truetype/hack-nerd-font && \
    wget -q -O /tmp/Hack.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/Hack.zip && \
    unzip -q /tmp/Hack.zip -d /usr/share/fonts/truetype/hack-nerd-font && \
    rm /tmp/Hack.zip && \
    fc-cache -fv

RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# ---------- Stage 3: Builder ------------------------------------------------
FROM tools-setup AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0

WORKDIR /app

COPY pyproject.toml uv.lock LICENSE ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /app/.venv && \
    uv sync --locked --no-install-project --no-dev --extra jupyter --extra notebooks

# ---------- Stage 4: User Setup ---------------------------------------------
FROM tools-setup AS user-setup

RUN EXISTING_USER=$(getent passwd 1000 | cut -d: -f1) && \
    EXISTING_GROUP=$(getent group 1000 | cut -d: -f1) && \
    usermod -l jovyan -d /home/jovyan -m $EXISTING_USER && \
    groupmod -n jovyan $EXISTING_GROUP && \
    echo "jovyan ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/jovyan/.config /home/jovyan/.jupyter && \
    chown -R jovyan:jovyan /home/jovyan

# ---------- Stage 5: Final Image --------------------------------------------
FROM user-setup AS final-image

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    JUPYTER_ENABLE_LAB=yes \
    JUPYTER_SHOW_HIDDEN=true \
    HOME=/home/jovyan

COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

RUN --mount=type=cache,target=/root/.cache/uv \
    jupyter lab build --dev-build=False --minimize=False && \
    rm -rf /home/jovyan/.cache /tmp/*

RUN mkdir -p /usr/local/share/jupyter/lab/settings /etc/jupyter
COPY docker/jupyter-dev/overrides.json /usr/local/share/jupyter/lab/settings/overrides.json
COPY docker/shared/jupyter_server_config.py /etc/jupyter/jupyter_server_config.py
COPY docker/shared/jupyter_lab_config.py /etc/jupyter/jupyter_lab_config.py
ENV JUPYTER_CONFIG_PATH=/etc/jupyter:/home/jovyan/.jupyter

RUN mkdir -p /etc/skel/.config
COPY docker/shared/starship.toml /etc/skel/.config/starship.toml
COPY --chown=jovyan:jovyan docker/shared/starship.toml /home/jovyan/.config/starship.toml
COPY docker/jupyter-dev/bashrc /etc/skel/.bashrc
COPY --chown=jovyan:jovyan docker/jupyter-dev/bashrc /home/jovyan/.bashrc

COPY docker/jupyter/scripts/initialize_home.sh /usr/local/bin/initialize_home.sh
COPY docker/jupyter/scripts/memory_watchdog.py /usr/local/bin/memory_watchdog.py
COPY docker/jupyter/scripts/disk_monitor.sh /usr/local/bin/disk_monitor.sh
RUN chmod +x /usr/local/bin/initialize_home.sh /usr/local/bin/memory_watchdog.py /usr/local/bin/disk_monitor.sh

COPY docker/jupyter-dev/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN git config --system --add safe.directory '*'

LABEL maintainer="taufik.shf@gmail.com" \
      description="JupyterLab development environment with sudo, UV, GDAL, Git and more development tools."

USER jovyan
WORKDIR /home/jovyan

EXPOSE 8888 8787

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["jupyter-lab", "--ip=0.0.0.0", "--no-browser"]
