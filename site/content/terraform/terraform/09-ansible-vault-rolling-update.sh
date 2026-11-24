#!/usr/bin/env bash
# Lezione 09 — segreti con ansible-vault e rolling update a lotti (serial).
source "$(dirname "$0")/../lib/passo.sh"
export PATH="$HOME/.local/bin:$PATH"
titolo "09. Ansible Vault e rolling update"
cartella ansible
[[ -f inventory.yml ]] || { echo "prima esegui la lezione 06 e la 07"; exit 1; }

passo "La password del vault in un file leggibile solo da te (in CI arriva da una variabile protetta)" \
  "echo 'lab-vault' > ~/.vault_pass && chmod 600 ~/.vault_pass && ls -l ~/.vault_pass"
passo "Copio il playbook della lezione: contiene db_password già cifrata con quella password" \
  "cp $LEZIONI/terraform/09-ansible-vault-rolling-update.yml rolling.yml && grep -n -A3 'db_password' rolling.yml | head -6"
passo "Come si cifra un valore: encrypt_string produce il blocco !vault da incollare nel YAML" \
  "ansible-vault encrypt_string --vault-password-file ~/.vault_pass 'S3greta!' --name db_password"
passo "Rolling update alla versione di default: serial = un host alla volta, tolto dal bilanciatore, aggiornato, verificato, rimesso" \
  'ansible-playbook rolling.yml --vault-password-file ~/.vault_pass'
passo "Chi è nel bilanciatore finto (db1 fa da load balancer)" \
  'docker exec db1 cat /etc/lb/backends'
passo "Versione 2.0 con un guasto su web2: web1 passa, web2 fallisce la verifica e RESTA FUORI dal bilanciatore" \
  'ansible-playbook rolling.yml --vault-password-file ~/.vault_pass -e versione=2.0 -e rompi=web2'
passo "Nel bilanciatore resta solo l'host sano: il guasto non arriva agli utenti" \
  'docker exec db1 cat /etc/lb/backends'
nota "Pulizia dei server finti:  docker rm -f web1 web2 db1"
