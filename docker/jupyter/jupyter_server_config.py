import os
c = get_config()                       # noqa: F821

# ---- terminal ---------------------------------------------------
c.ServerApp.terminado_settings = {
    "shell_command": [os.environ.get("SHELL", "/bin/bash")]
}

# ---- behaviour --------------------------------------------------
c.ServerApp.shutdown_no_activity_timeout = 3600
c.ServerApp.root_dir                     = "/home/jovyan"
c.NotebookApp.show_banner                = False

# ---- kernels ----------------------------------------------------
# Keep nb_conda_kernels but restrict the scan:
from nb_conda_kernels.manager import CondaKernelSpecManager
c.CondaKernelSpecManager.env_filter = rf".*envs/{os.environ.get('CONDA_DEFAULT_ENV','base')}.*"
