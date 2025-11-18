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

exec "$@"
