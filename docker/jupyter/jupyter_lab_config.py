# JupyterLab Configuration
import os

c = get_config()  # noqa: F821

# Disable news and update checks
c.LabApp.news_url = None
c.LabApp.check_for_updates_class = "jupyterlab.NeverCheckForUpdate"


