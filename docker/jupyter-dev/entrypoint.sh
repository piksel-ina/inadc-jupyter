#!/bin/bash
set -e

# Create JupyterLab settings directory
mkdir -p /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/terminal-extension

# Configure terminal to use Nerd Font
cat > /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings << 'EOF'
{
    "fontFamily": "Hack Nerd Font, Hack Nerd Font Mono, monospace",
    "fontSize": 14,
    "lineHeight": 1.4,
    "theme": "dark",
    "scrollback": 10000,
    "shutdownOnClose": false,
    "closeOnExit": false,
    "pasteWithCtrlV": true
}
EOF

echo "Python: $(python3 --version)"
echo "UV: $(uv --version)"
echo "JupyterLab: $(jupyter-lab --version)"

# Execute the main command
exec "$@"