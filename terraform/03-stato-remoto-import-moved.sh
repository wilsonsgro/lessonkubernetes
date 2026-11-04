#!/usr/bin/env bash
# Lezione 03 — state remoto su PostgreSQL con lock, import di una risorsa esistente, moved.
source "$(dirname "$0")/../lib/passo.sh"
titolo "03. Stato remoto, import e moved"
cartella iac/03

passo "Un PostgreSQL in Docker fa da backend dello state (in azienda: S3 + lock, GCS, Terraform Cloud…)" \
  'docker ps -a --format "{{.Names}}" | grep -qx tfstate || docker run -d --name tfstate -e POSTGRES_PASSWORD=lab -p 5433:5432 postgres:18-alpine; sleep 5'
passo "Il backend pg legge la connessione da questa variabile d'ambiente (il blocco backend non accetta variabili Terraform)" \
  'export PG_CONN_STR="postgres://postgres:lab@localhost:5433/postgres?sslmode=disable"; echo $PG_CONN_STR'
passo "Un Redis creato A MANO, fuori da Terraform: lo importeremo" \
  'docker ps -a --format "{{.Names}}" | grep -qx vecchio-redis || docker run -d --name vecchio-redis redis:8-alpine'
passo "L'id del container per il blocco import, passato come variabile TF_VAR_…" \
  "export TF_VAR_id_vecchio_redis=\$(docker inspect -f '{{.Id}}' vecchio-redis); echo \$TF_VAR_id_vecchio_redis"
passo "Copio il file della lezione" \
  "cp $LEZIONI/terraform/03-stato-remoto-import-moved.tf main.tf && grep -n '^terraform\|backend\|^import\|^resource\|moved' main.tf"
passo "init: configura il backend pg (crea lo schema terraform_remote_state)" \
  'terraform init'
passo "apply: crea 'cache' e IMPORTA vecchio-redis nello state ('will be imported')" \
  'terraform apply -auto-approve'
passo "Lo state non è più un file locale: è una riga in PostgreSQL" \
  "ls terraform.tfstate 2>/dev/null || echo 'nessun terraform.tfstate locale'; docker exec tfstate psql -U postgres -c 'select name from terraform_remote_state.states'"
passo "La risorsa importata, ora gestita da Terraform" \
  'terraform state list; terraform state show docker_container.legacy | head -15'
nota "LOCK: apri un SECONDO terminale e lancia:" \
     "   cd $LAVORO/iac/03 && export PG_CONN_STR=\"$PG_CONN_STR\" TF_VAR_id_vecchio_redis=\$(docker inspect -f '{{.Id}}' vecchio-redis) && terraform apply" \
     "lascialo fermo alla domanda 'Enter a value' (tiene il lock), poi torna qui."
passo "Con l'altro apply aperto: il lock blocca questo plan ('Error acquiring the state lock'). Se non hai aperto l'altro terminale, passa" \
  'terraform plan -lock-timeout=0s'
passo "REFACTOR: rinomino la risorsa cache → sessioni e tolgo il commento al blocco moved già scritto nel file" \
  "sed -i -e 's/resource \"docker_container\" \"cache\"/resource \"docker_container\" \"sessioni\"/' -e '/^# moved {/,/^# }/s/^# //' main.tf && grep -n -A3 '^moved' main.tf"
passo "Il plan dice 'has moved to', 0 to destroy: senza moved distruggerebbe e ricreerebbe il container" \
  'terraform plan'
passo "Applico il refactor" \
  'terraform apply -auto-approve && terraform state list'
passo "Pulizia: destroy, poi via il Postgres dello state" \
  'terraform destroy -auto-approve; docker rm -f tfstate vecchio-redis'
