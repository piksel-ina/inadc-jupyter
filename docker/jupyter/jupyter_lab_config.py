# JupyterLab Configuration
import os
c = get_config()           # noqa: F821

# ---- browser behaviour -----------------------------------------
c.LabApp.open_browser = False
c.LabApp.default_url  = "/lab"

# ---- UI tweaks --------------------------------------------------
c.LabApp.collaborative = False
# c.LabApp.theme = "JupyterLab Dark"

# ---- News / update banner --------------------------------------
c.LabApp.news_url                = None
c.LabApp.check_for_updates_class = "jupyterlab.NeverCheckForUpdate"
