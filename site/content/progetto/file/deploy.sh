#!/usr/bin/env bash
# Punto d'ingresso: prepara Ansible (collection e libreria docker, senza sudo) e lancia il playbook: ./deploy.sh [site|distruggi] [opzioni di ansible-playbook]
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/ansible"

playbook=site
case "${1:-}" in site|distruggi) playbook=$1; shift ;; esac

ansible-galaxy collection install -r requirements.yml > /dev/null
pipx runpip ansible-core show docker > /dev/null 2>&1 || pipx inject ansible-core docker > /dev/null
exec ansible-playbook "$playbook.yml" "$@"
