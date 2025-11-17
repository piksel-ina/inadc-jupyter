# ---------- Stage 1: Base System Setup --------------------------------------
FROM ghcr.io/osgeo/gdal:ubuntu-small-3.12.0 AS system-base

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

# ---------- Stage 3: User Setup --------------------------------------
FROM tools-setup AS user-setup

RUN EXISTING_USER=$(getent passwd 1000 | cut -d: -f1) && \
    EXISTING_GROUP=$(getent group 1000 | cut -d: -f1) && \
    usermod -l jovyan -d /home/jovyan -m $EXISTING_USER && \
    groupmod -n jovyan $EXISTING_GROUP && \
    echo "jovyan ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/jovyan/.config /home/jovyan/.jupyter /home/jovyan/workspace

# ---------- Stage 4: Python Environment --------------------------------------
FROM user-setup AS python-env

ARG DATACUBE_VERSION=1.9.10

COPY docker/jupyter-dev/requirements.txt /tmp/requirements.txt

USER jovyan
WORKDIR /home/jovyan

RUN uv venv /home/jovyan/.venv && \
    . /home/jovyan/.venv/bin/activate && \
    uv pip install "datacube==${DATACUBE_VERSION}" && \
    uv pip install -r /tmp/requirements.txt && \
    jupyter lab build --dev-build=False --minimize=False

# ---------- Stage 5: Final Image --------------------------------------
FROM user-setup AS jupyter-dev

ARG DATACUBE_VERSION=1.9.10

ENV PYTHONUNBUFFERED=1 \
    JUPYTER_ENABLE_LAB=yes \
    PATH="/home/jovyan/.local/bin:/home/jovyan/.venv/bin:$PATH"

COPY --from=python-env /home/jovyan/.venv /home/jovyan/.venv

COPY --chown=jovyan:jovyan docker/jupyter-dev/bashrc /home/jovyan/.bashrc
COPY --chown=jovyan:jovyan docker/jupyter-dev/starship.toml /home/jovyan/.config/starship.toml
COPY --chown=jovyan:jovyan docker/jupyter-dev/jupyter_lab_config.py /home/jovyan/.jupyter/jupyter_lab_config.py

USER root
COPY docker/jupyter-dev/jupyter_server_config.py /etc/jupyter/jupyter_server_config.py
COPY docker/jupyter-dev/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER jovyan
WORKDIR /home/jovyan

EXPOSE 8888

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["jupyter-lab", "--ip=0.0.0.0", "--no-browser"]
