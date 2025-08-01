# This image already contains:
# - JupyterHub for multi-user management
# - JupyterLab for the modern interface
# - Complete scientific Python stack
FROM pangeo/pangeo-notebook:2025.06.02

USER root

# Install all necessary build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    gcc \
    g++ \
    build-essential \
    libpq-dev \
    postgresql-client \
    python3-dev \
    libpython3-dev \
    # Some utility tools \
    htop \
    wget \
    fish \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER $NB_USER

# Upgrade pip
RUN python -m pip install --no-cache-dir --upgrade pip

# Install packages in specific order to avoid conflicts
RUN pip install --no-cache-dir \
    psycopg2-binary \
    boto3 \
    "scikit-learn>=1.5.0" \
    openpyxl

# Clean up old pip packages
RUN pip uninstall --yes datacube odc-stac odc-loader

# Then install packages that might have dependencies
RUN pip install --upgrade --no-cache-dir \
    dask-ml \
    leafmap \
    localtileserver \
    country-bounding-boxes \
    eo-tides \
    odc-stac==0.4.0 \
    odc-loader==0.5.1 \
    datacube==1.9.6 \
    git+https://github.com/GeoscienceAustralia/dea-intertidal.git

# Add some data science packages
RUN pip install --no-cache-dir --force-reinstall --no-deps \
    git+https://github.com/auspatious/pyTMD.git@update-with-INATIDES-compatibility \
    git+https://github.com/piksel-ina/piksel-notebooks.git \
    dea-tools \
    wofs \
    https://github.com/auspatious/datacube-compute/releases/download/0.0.7/datacube_compute-0.0.7-cp312-cp312-linux_x86_64.whl

ENV JUPYTER_ENABLE_LAB=yes
