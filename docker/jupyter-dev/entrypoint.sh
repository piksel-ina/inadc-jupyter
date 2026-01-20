#!/bin/bash
set -e

echo " --- Environment ---"
echo "PATH: $PATH"
echo "which jupyter-lab: $(which jupyter-lab || echo 'NOT FOUND')"
echo "which jupyterhub-singleuser: $(which jupyterhub-singleuser || echo 'NOT FOUND')"
echo "Command: $@"
echo " -------------------"
echo ""
echo " ---- Versions -----"
echo "Versions:"
echo "Python: $(python3 --version)"
echo "UV: $(uv --version)"
echo "JupyterLab: $(jupyter-lab --version)"
echo " -------------------"

if [ -n "$JUPYTERHUB_USER" ]; then
    echo "JupyterHub environment: $JUPYTERHUB_USER"
    export DASK_DISTRIBUTED__DASHBOARD__LINK="/user/${JUPYTERHUB_USER}/proxy/{port}/status"
else
    echo "Local environment"
    export DASK_DISTRIBUTED__DASHBOARD__LINK="/proxy/{port}/status"
fi

exec "$@"
