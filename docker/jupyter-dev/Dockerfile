FROM ghcr.io/osgeo/gdal:ubuntu-small-3.12.0 AS jupyter-dev-base

ARG DATACUBE_VERSION=1.9.10

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PYTHONUNBUFFERED=1 \
    JUPYTER_ENABLE_LAB=yes

# Install additional system dependencies
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
    nodejs \
    npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Verify GDAL installation
RUN echo "GDAL Version: $(gdal-config --version)" && \
    python3 -c "from osgeo import gdal; print(f'Python GDAL: {gdal.__version__}')"

# Install Nerd Font for better terminal experience
RUN mkdir -p /usr/share/fonts/truetype/hack-nerd-font && \
    wget -q -O /tmp/Hack.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/Hack.zip && \
    unzip -q /tmp/Hack.zip -d /usr/share/fonts/truetype/hack-nerd-font && \
    rm /tmp/Hack.zip && \
    fc-cache -fv

# Install starship prompt
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

# Install uv package manager
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Create jovyan user with sudo privileges
RUN EXISTING_USER=$(getent passwd 1000 | cut -d: -f1) && \
    EXISTING_GROUP=$(getent group 1000 | cut -d: -f1) && \
    usermod -l jovyan -d /home/jovyan -m $EXISTING_USER && \
    groupmod -n jovyan $EXISTING_GROUP && \
    echo "jovyan ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/jovyan/.config /home/jovyan/.jupyter /home/jovyan/workspace

# Copy configuration files
COPY docker/jupyter-dev/bashrc /home/jovyan/.bashrc
COPY docker/jupyter-dev/starship.toml /home/jovyan/.config/starship.toml
COPY docker/jupyter-dev/jupyter_lab_config.py /home/jovyan/.jupyter/jupyter_lab_config.py
COPY docker/jupyter-dev/jupyter_server_config.py /etc/jupyter/jupyter_server_config.py
COPY docker/jupyter-dev/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/jupyter-dev/requirements.txt /home/jovyan/requirements.txt

# Fix permissions
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chown -R jovyan:jovyan /home/jovyan

# Switch to non-root user
USER jovyan
WORKDIR /home/jovyan


# Create virtual environment and install Python packages
RUN uv venv /home/jovyan/.venv && \
    . /home/jovyan/.venv/bin/activate && \
    uv pip install "datacube==${DATACUBE_VERSION}" && \
    uv pip install -r /home/jovyan/requirements.txt

# Update PATH to include virtual environment
ENV PATH="/home/jovyan/.local/bin:/home/jovyan/.venv/bin:$PATH"

WORKDIR /home/jovyan/workspace

EXPOSE 8888

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["jupyter-lab", "--ip=0.0.0.0", "--no-browser"]
