#!/usr/bin/env bash
# Lezione 07 — un playbook: check, diff, handler, tag, limit, validate, lint.
source "$(dirname "$0")/../lib/passo.sh"
export PATH="$HOME/.local/bin:$PATH"
titolo "07. Ansible: playbook"
cartella ansible
[[ -f inventory.yml ]] || { echo "prima esegui la lezione 06"; exit 1; }

passo "Copio il playbook della lezione come site.yml: installa nginx, scrive config e pagina da template, handler di reload" \
  "cp $LEZIONI/terraform/07-ansible-playbook.yml site.yml && grep -n 'name:\|tags:\|notify\|handlers' site.yml | head -30"
passo "Controllo di sintassi" \
  'ansible-playbook site.yml --syntax-check'
passo "--check --diff: cosa FAREBBE senza farlo. Su host vergini fallisce al service nginx (in check il pacchetto non viene installato davvero)" \
  'ansible-playbook site.yml --check --diff'
passo "Prima esecuzione: tutto changed" \
  'ansible-playbook site.yml'
passo "Seconda esecuzione: changed=0. Un playbook ben scritto è idempotente" \
  'ansible-playbook site.yml'
passo "Cambio una variabile della pagina: il file cambia (--diff lo mostra), ma l'handler NON scatta: il notify sta solo sulla config di nginx, che non dipende da messaggio" \
  'ansible-playbook site.yml -e messaggio="ciao" --diff'
passo "--tags config --limit web1: solo i task con quel tag, solo su quell'host" \
  'ansible-playbook site.yml --tags config --limit web1'
passo "Porta non valida: 'validate' prova la config con nginx -t PRIMA di sostituirla, la rifiuta, il file buono resta" \
  'ansible-playbook site.yml --limit web1 -e porta_http=abc'
passo "nginx risponde ancora" \
  'docker exec web1 curl -s localhost'
passo "ansible-lint: buone pratiche (FQCN dei moduli, nomi dei task, permessi dei file…)" \
  'ansible-lint site.yml'
