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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER $NB_USER

# Install packages in specific order to avoid conflicts
RUN pip install --no-cache-dir \
    psycopg2-binary \
    boto3 \
    "scikit-learn>=1.5.0" \
    openpyxl

# Then install packages that might have dependencies
RUN pip install --no-cache-dir \
    dask-ml \
    leafmap \
    localtileserver \
    country-bounding-boxes

# Install git-based package
RUN pip install --no-cache-dir git+https://github.com/digitalearthpacific/dep-tools.git

# Install DEA tools separately
RUN pip install --no-cache-dir \
    dea-tools \
    wofs

# Finally, handle the hdstats package
RUN pip install --no-cache-dir hdstats || \
    pip install --no-cache-dir --force-reinstall --no-deps \
        --trusted-host packages.dea.ga.gov.au \
        https://packages.dea.ga.gov.au/hdstats/hdstats-0.1.8.post1-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl

ENV JUPYTER_ENABLE_LAB=yes
