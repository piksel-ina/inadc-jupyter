#!/bin/bash -l
set -e

# Pangeo-specific environment setup
export PANGEO_ENV="${PANGEO_ENV:-pangeo-notebook}" 
if [ -n "${PANGEO_SCRATCH_PREFIX}" ] && [ -n "${JUPYTERHUB_USER}" ]; then
    export PANGEO_SCRATCH="${PANGEO_SCRATCH_PREFIX}/${JUPYTERHUB_USER}/"
    mkdir -p "${PANGEO_SCRATCH}" 2>/dev/null || true
fi

# Activate micromamba environment
eval "$(micromamba shell hook --shell bash)"
micromamba activate base

exec "$@"
