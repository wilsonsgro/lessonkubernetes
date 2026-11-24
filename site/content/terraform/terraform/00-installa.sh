#!/usr/bin/env bash
# Prerequisiti del corso Terraform & Ansible: terraform dal repository HashiCorp, ansible-core con pipx.
source "$(dirname "$0")/../lib/passo.sh"
titolo "00. Installazione di Terraform e Ansible"

passo "Pacchetti per aggiungere un repository firmato" \
  'sudo apt-get update && sudo apt-get install -y gnupg software-properties-common wget'
passo "Chiave GPG di HashiCorp: apt verificherà con questa la firma dei pacchetti" \
  'wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp.gpg'
passo "Repository HashiCorp per la tua versione di Ubuntu (lsb_release -cs = noble), legato SOLO a quella chiave (signed-by)" \
  'echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list'
passo "Installo terraform" \
  'sudo apt-get update && sudo apt-get install -y terraform && terraform version'
passo "ansible-core con pipx: un virtualenv isolato solo per Ansible, senza sporcare il Python di sistema" \
  'pipx install --include-deps ansible-core && pipx ensurepath'
passo "pipx mette i comandi in ~/.local/bin: lo aggiungo al PATH di questa sessione" \
  'export PATH="$HOME/.local/bin:$PATH"; ansible --version | head -3'
passo "Collection: community.docker (connessione ai container senza SSH) e ansible.posix (callback profile_tasks)" \
  'ansible-galaxy collection install community.docker ansible.posix'
passo "ansible-lint, per la lezione 07 (anche lui in un suo virtualenv)" \
  'pipx install ansible-lint'
nota "Apri un terminale nuovo (o 'source ~/.bashrc') perché ~/.local/bin resti nel PATH."
