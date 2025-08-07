#!/bin/bash -l
set -e

# For backwards compatibility, we set the default PANGEO_SCRATCH_PREFIX to /scratch
export PANGEO_ENV="${PANGEO_ENV:-pangeo-notebook}" 
if [ -n "${PANGEO_SCRATCH_PREFIX}" ] && [ -n "${JUPYTERHUB_USER}" ]; then
    export PANGEO_SCRATCH="${PANGEO_SCRATCH_PREFIX}/${JUPYTERHUB_USER}/"
    mkdir -p "${PANGEO_SCRATCH}" 2>/dev/null || true
fi

# Activate micromamba environment
echo "Activating micromamba environment..."
eval "$(micromamba shell hook --shell bash)"
micromamba activate base

exec "$@"
