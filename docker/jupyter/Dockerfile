FROM mambaorg/micromamba:2.3-debian11 as sandbox-conda

ENV CONDA_ENV=notebook \
    DEBIAN_FRONTEND=noninteractive \
    NB_USER=jovyan \
    NB_UID=1000 \
    NB_GID=100 \
    SHELL=/bin/bash \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CONDA_DIR=/srv/conda

# Additional environment setup
ENV GDAL_DRIVER_PATH=/env/lib/gdalplugins \
    PROJ_LIB=/env/share/proj \
    GDAL_DATA=/env/share/gdal \
    SQLALCHEMY_SILENCE_UBER_WARNING=1 \
    USE_PYGEOS=0 \
    TZ=UTC

# Path and Python environment setup
ENV NB_PYTHON_PREFIX=/env \
    HOME=/home/${NB_USER}

ENV PATH=${NB_PYTHON_PREFIX}/bin:${CONDA_DIR}/bin:/env/bin:${PATH} \
    DASK_ROOT_CONFIG=${CONDA_DIR}/etc

# Switch to root to perform system setup
USER root 

# Install all necessary build dependencies and system packages
RUN echo "Installing system packages and build dependencies..." && \
    apt-get update --fix-missing > /dev/null && \
    apt-get install -y \
        apt-utils \
        wget \
        zip \
        tzdata \
        curl \
        git \
        gcc \
        g++ \
        build-essential \
        libpq-dev \
        postgresql-client \
        python3-dev \
        libpython3-dev \
        htop \
        fish \
        sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create jovyan user and group
RUN echo "Creating ${NB_USER} user..." && \
    # Check if group with GID 100 exists, if not create it
    if ! getent group ${NB_GID} >/dev/null; then \
        groupadd --gid ${NB_GID} ${NB_USER}; \
    fi && \
    # Get the name of the group with GID 100
    GROUP_NAME=$(getent group ${NB_GID} | cut -d: -f1) && \
    echo "Using group: $GROUP_NAME (GID: ${NB_GID})" && \
    # Create user with the existing group
    useradd --uid ${NB_UID} --gid ${NB_GID} --create-home --shell ${SHELL} ${NB_USER} && \
    echo "${NB_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R ${NB_USER}:$GROUP_NAME /srv

# Copy configuration files (from root context perspective)
COPY docker/jupyter/conda-lock.yml .
COPY docker/jupyter/requirements.in .

# Create environment directly from conda-lock.yml
RUN echo "Creating environment from 'conda-lock.yml'..." && \
    micromamba create -p /env -f conda-lock.yml && \
    /env/bin/python -m pip install --no-cache-dir --upgrade pip && \
    echo "Installing pip dependencies..." && \
    /env/bin/pip install --no-cache-dir pip-tools && \
    /env/bin/pip-compile requirements.in && \
    /env/bin/pip install --no-cache-dir -r requirements.txt && \
    # Clean up everything in one layer
    micromamba clean --all --yes && \
    /env/bin/pip cache purge && \
    rm -rf /tmp/* /var/tmp/* && \
    rm -rf /env/conda-meta/* && \
    rm -rf /env/lib/python*/site-packages/*/tests && \
    rm -rf /env/lib/python*/site-packages/*/__pycache__ && \
    find /env -name "*.pyc" -delete && \
    find /env -name "*.pyo" -delete && \
    find /env -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Install other deps
RUN pip install --no-cache-dir --force-reinstall --no-deps \
    git+https://github.com/auspatious/pyTMD.git@update-with-INATIDES-compatibility \
    https://github.com/auspatious/datacube-compute/releases/download/0.0.7/datacube_compute-0.0.7-cp312-cp312-linux_x86_64.whl

# Copy and setup postBuild script if it exists (from root context)
COPY docker/jupyter/postBuild* ./
RUN echo "Setup 'postBuild' script for JupyterLab configuration..." && \
    if [ -f "postBuild" ]; then \
        echo "Found postBuild script, executing..." && \
        chmod +x postBuild && \
        ./postBuild && \
        echo "Cleaning up after postBuild..." && \
        rm -rf /tmp/* && \
        rm -rf ${HOME}/.cache ${HOME}/.npm ${HOME}/.yarn && \
        rm -rf ${NB_PYTHON_PREFIX}/share/jupyter/lab/staging && \
        find ${CONDA_DIR} -follow -type f -name '*.a' -delete 2>/dev/null || true && \
        find ${CONDA_DIR} -follow -type f -name '*.js.map' -delete 2>/dev/null || true; \
    else \
        echo "No postBuild script found, skipping..."; \
    fi

# Runtime Stage: Copy built artifacts into a slimmer image
FROM mambaorg/micromamba:2.3-debian11

# Re-declare environment variables for runtime stage
ENV CONDA_ENV=notebook \
    DEBIAN_FRONTEND=noninteractive \
    NB_USER=jovyan \
    NB_UID=1000 \
    NB_GID=100 \
    SHELL=/bin/bash \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CONDA_DIR=/srv/conda \
    GDAL_DRIVER_PATH=/env/lib/gdalplugins \
    PROJ_LIB=/env/share/proj \
    GDAL_DATA=/env/share/gdal \
    SQLALCHEMY_SILENCE_UBER_WARNING=1 \
    USE_PYGEOS=0 \
    TZ=UTC \
    NB_PYTHON_PREFIX=/env \
    HOME=/home/${NB_USER} \
    PATH=${NB_PYTHON_PREFIX}/bin:${CONDA_DIR}/bin:/env/bin:${PATH} \
    DASK_ROOT_CONFIG=${CONDA_DIR}/etc

# Switch to root for setup
USER root

# Install only runtime system packages (no build tools)
RUN apt-get update --fix-missing > /dev/null && \
    apt-get install -y \
        apt-utils \
        wget \
        zip \
        tzdata \
        curl \
        git \
        libpq-dev \
        postgresql-client \
        htop \
        fish \
        sudo \
        tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy user/group setup and sudoers from build stage
COPY --from=sandbox-conda /etc/passwd /etc/passwd
COPY --from=sandbox-conda /etc/group /etc/group
COPY --from=sandbox-conda /etc/sudoers /etc/sudoers
COPY --from=sandbox-conda /etc/sudoers.d /etc/sudoers.d

# Copy the built Conda environment and user home
COPY --from=sandbox-conda --chown=${NB_UID}:${NB_GID} /env /env
COPY --from=sandbox-conda --chown=${NB_UID}:${NB_GID} /home/${NB_USER} /home/${NB_USER}
COPY --from=sandbox-conda --chown=${NB_UID}:${NB_GID} /srv /srv

# Copy startup script (create this in your build context, e.g., docker/jupyter/start-notebook.sh)
COPY docker/jupyter/start-notebook.sh /usr/local/bin/start-notebook.sh
RUN chmod +x /usr/local/bin/start-notebook.sh

# Switch to non-root user
USER ${NB_UID}

# Set working directory
WORKDIR ${HOME}

# Set ENTRYPOINT to use tini for signal handling
ENTRYPOINT ["tini", "-g", "--"]

# Set CMD to start Jupyter Lab by default
CMD ["start-notebook.sh"]
