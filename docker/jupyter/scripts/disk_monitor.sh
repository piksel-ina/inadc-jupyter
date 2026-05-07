#!/bin/bash
set -e

THRESHOLD="${DISK_MONITOR_THRESHOLD:-80}"
INTERVAL="${DISK_MONITOR_INTERVAL:-300}"
HOME_DIR="${HOME:-/home/jovyan}"
WARNING_FILE="$HOME_DIR/DISK_WARNING_README.txt"
LOG_PREFIX="disk_monitor"

echo "$LOG_PREFIX: monitoring disk — threshold ${THRESHOLD}%, check every ${INTERVAL}s"

while true; do
    USAGE=$(df "$HOME_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')

    if [ -n "$USAGE" ] && [ "$USAGE" -ge "$THRESHOLD" ]; then
        if [ ! -f "$WARNING_FILE" ]; then
            cat > "$WARNING_FILE" <<EOF
==========================================
  WARNING: Storage usage at ${USAGE}%
==========================================

Your home directory is ${USAGE}% full.

Please clean up unnecessary files. If storage
reaches 100%, your server may stop working.

Tips:
- Remove large outputs from notebooks
- Delete unused files in your home directory
- Clear package caches: rm -rf ~/.cache/uv ~/.cache/pip

This file will disappear automatically when
storage drops below ${THRESHOLD}%.
EOF
            echo "$LOG_PREFIX: storage at ${USAGE}% — created warning file"
        fi
    else
        if [ -f "$WARNING_FILE" ]; then
            rm -f "$WARNING_FILE"
            echo "$LOG_PREFIX: storage below threshold — removed warning file"
        fi
    fi

    sleep "$INTERVAL"
done
