#!/bin/bash
set -e

echo "Generating datacube config from template..."

# Generate config from template using environment variables
envsubst < /home/venv/.datacube.conf.template > /home/venv/.datacube.conf

echo "Config file location: /home/venv/.datacube.conf"

# Execute the original command
exec "$@"