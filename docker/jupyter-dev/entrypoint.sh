#!/bin/bash
set -e

mkdir -p /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/terminal-extension 2>/dev/null || true
mkdir -p /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/filebrowser-extension 2>/dev/null || true
mkdir -p /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/apputils-extension 2>/dev/null || true
mkdir -p /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/docmanager-extension 2>/dev/null || true

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

cat > /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/filebrowser-extension/browser.jupyterlab-settings << 'EOF'
{
    "showHiddenFiles": true
}
EOF

cat > /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/apputils-extension/notification.jupyterlab-settings << 'EOF'
{
    "fetchNews": "false"
}
EOF

cat > /home/jovyan/.jupyter/lab/user-settings/@jupyterlab/docmanager-extension/plugin.jupyterlab-settings << 'EOF'
{
    "defaultViewers": {
        "markdown": "Markdown Preview"
    }
}
EOF

echo "Python: $(python3 --version)"
echo "UV: $(uv --version)"
echo "JupyterLab: $(jupyter-lab --version)"

exec "$@"
