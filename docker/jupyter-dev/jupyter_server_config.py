import os
c = get_config()                       # noqa: F821

# ---- terminal -----------------------------------
c.ServerApp.terminado_settings = {
    "shell_command": [os.environ.get("SHELL", "/bin/bash")]
}
c.ServerApp.terminado_settings = {
    'shell_command': ['/bin/bash']
}

# ---- basic behavior -----------------------------
c.ServerApp.root_dir = "/home/jovyan"

# ---- basic network settings --------------------
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.allow_root = True
c.ServerApp.open_browser = False

# ---- content management -------------------------
c.ServerApp.kernel_spec_manager_class = 'jupyter_client.kernelspec.KernelSpecManager'
c.ServerApp.kernel_manager_class = 'jupyter_server.services.kernels.kernelmanager.MappingKernelManager'

# ---- performance settings ----------------------
c.ServerApp.iopub_data_rate_limit = 1000000000
c.ServerApp.iopub_msg_rate_limit = 3000

# ---- logging ------------------------------------
c.Application.log_level = 'INFO'

# ---- ssl (always disabled in container) --------
c.ServerApp.certfile = ''
c.ServerApp.keyfile = ''

# ---- templates ----------------------------------
c.ServerApp.extra_template_paths = []