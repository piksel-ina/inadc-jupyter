# Jupyter Notebook Configuration
import os

c = get_config() 

# Terminal settings
c.ServerApp.terminado_settings = {
    'shell_command': [os.environ.get('SHELL', '/bin/bash')]
}

# Server shutdown timeout
c.ServerApp.shutdown_no_activity_timeout = 3600 

# https://discourse.jupyter.org/t/notebook-takes-a-long-time-to-start-the-kernel-but-if-restarted-it-kicks-in-immediately/19482
c.NotebookApp.show_banner = False 

# Configure nb_conda_kernels to avoid registering jupyter kernels in conda env
c.CondaKernelSpecManager.env_filter = f'.*envs/{os.environ["CONDA_ENV"]}.*'

# Set notebook directory
c.ServerApp.root_dir = os.environ.get('JUPYTER_ROOT_DIR', '/home/jovyan')
