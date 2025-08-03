#!/bin/bash
set -e

# Pangeo-specific environment setup (for backward compatibility)
export PANGEO_ENV="${PANGEO_ENV:-pangeo-notebook}" 
if [ -n "${PANGEO_SCRATCH_PREFIX}" ] && [ -n "${JUPYTERHUB_USER}" ]; then
    export PANGEO_SCRATCH="${PANGEO_SCRATCH_PREFIX}/${JUPYTERHUB_USER}/"
fi

mkdir -p ~/.jupyter
echo "c.TerminalManager.shell_command = ['/bin/bash']" > ~/.jupyter/jupyter_lab_config.py
echo "Jupyter config updated to use bash for terminals."

# Ensure the environment is activated
echo "Activating micromamba environment..."
eval "$(micromamba shell hook --shell bash)"
micromamba activate base || { echo "Activation failed!"; exit 1; }

# Start Jupyter Lab
echo "Starting Jupyter Lab on port ${JUPYTER_PORT:-8888}..."
exec jupyter lab \
    --ip=0.0.0.0 \
    --port="${JUPYTER_PORT:-8888}" \
    --no-browser \
    "$@"
