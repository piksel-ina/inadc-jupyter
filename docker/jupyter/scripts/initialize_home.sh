#!/bin/bash
set -euo pipefail

skel_dir="${SKEL_DIR:-/etc/skel}"
starship_init='eval "$(starship init bash)"'

mkdir -p "${HOME}/.config" "${HOME}/.local/site-packages"

if [ ! -e "${HOME}/.bashrc" ]; then
    cp "${skel_dir}/.bashrc" "${HOME}/.bashrc"
elif ! grep -Fqx "${starship_init}" "${HOME}/.bashrc"; then
    printf '\n%s\n' "${starship_init}" >> "${HOME}/.bashrc"
fi

if [ ! -e "${HOME}/.config/starship.toml" ]; then
    cp "${skel_dir}/.config/starship.toml" "${HOME}/.config/starship.toml"
fi
