#!/usr/bin/env bash
# Lezione 08 — un ruolo con defaults, vars, argument_specs, handler, template.
source "$(dirname "$0")/../lib/passo.sh"
export PATH="$HOME/.local/bin:$PATH"
titolo "08. Ansible: ruoli e collection"
cartella ansible
[[ -f inventory.yml ]] || { echo "prima esegui la lezione 06"; exit 1; }

passo "Scrivo il ruolo roles/sito_nginx e il playbook sito.yml con lo script della lezione" \
  "bash $LEZIONI/terraform/08-ansible-ruoli-collection.sh crea"
passo "La struttura di un ruolo: defaults (sovrascrivibili), vars (interni), tasks, handlers, templates, meta" \
  'find roles/sito_nginx -type f | sort'
passo "argument_specs: il ruolo dichiara il tipo dei suoi parametri e Ansible li valida all'ingresso" \
  'cat roles/sito_nginx/meta/argument_specs.yml'
passo "Eseguo il playbook che usa il ruolo" \
  'ansible-playbook sito.yml'
passo "sito_porta=ottanta non è un int: argument_specs blocca il ruolo prima di qualsiasi task" \
  'ansible-playbook sito.yml -e sito_porta=ottanta'
passo "Il sito servito dal ruolo sulla porta 8080" \
  'docker exec web2 curl -s localhost:8080'
passo "Le collection installate (namespace.nome): da lì vengono i moduli e i plugin con FQCN" \
  'ansible-galaxy collection list 2>/dev/null | grep -E "community.docker|ansible.posix"'
