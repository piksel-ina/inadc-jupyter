#!/bin/bash
set -e

mkdir -p /home/jovyan/.config /home/jovyan/.jupyter

cp -f /etc/skel/.bashrc /home/jovyan/.bashrc
cp -f /etc/skel/.config/starship.toml /home/jovyan/.config/starship.toml

chown jovyan:jovyan /home/jovyan/.bashrc
chown -R jovyan:jovyan /home/jovyan/.config
chown -R jovyan:jovyan /home/jovyan/.jupyter

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
