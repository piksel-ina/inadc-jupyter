#!/bin/bash -l
set -e

export PYTHONPATH="${HOME}/.local/site-packages:${PYTHONPATH:-}"

/usr/local/bin/initialize_home.sh

nohup /usr/local/bin/memory_watchdog.py > /tmp/memory_watchdog.log 2>&1 &
nohup /usr/local/bin/disk_monitor.sh > /tmp/disk_monitor.log 2>&1 &

exec "$@"
