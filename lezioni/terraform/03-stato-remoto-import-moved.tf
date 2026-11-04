# ═══════════════════════════════════════════════════════════════════════════
# 03. STATO REMOTO, LOCKING, IMPORT, MOVED E REMOVED
# Versione: Terraform 1.17 · backend "pg" (PostgreSQL) · provider docker 4.6
# Livello: 2 — Stato e refactoring
# ═══════════════════════════════════════════════════════════════════════════
# In team lo stato locale non funziona: due persone con due stati diversi
# creano doppioni o si distruggono le risorse a vicenda. Serve un BACKEND
# remoto con tre proprietà:
#   1. condiviso      tutti leggono e scrivono lo stesso stato
#   2. LOCK           un solo plan/apply alla volta; il secondo aspetta o
#                     fallisce con "Error acquiring the state lock"
#   3. protetto       cifrato at-rest, versionato, accesso minimo (contiene segreti)
#
# BACKEND TIPICI
#   s3        + use_lockfile = true (lock nativo su S3 da Terraform 1.10;
#               la tabella DynamoDB è deprecata). Bucket con versioning.
#   gcs / azurerm   lock nativo
#   pg        PostgreSQL, lock con advisory lock: perfetto per il lab
#   remote/cloud    HCP Terraform / Terraform Enterprise
# Il blocco backend NON accetta variabili: i valori per ambiente si
# passano con `terraform init -backend-config=file.hcl` o variabili
# d'ambiente (qui PG_CONN_STR).
#
# LAB SU UBUNTU
#   docker run -d --name tfstate -e POSTGRES_PASSWORD=lab -p 5433:5432 postgres:18-alpine
#   export PG_CONN_STR="postgres://postgres:lab@localhost:5433/postgres?sslmode=disable"
#   docker run -d --name vecchio-redis redis:8-alpine        # creato A MANO, fuori da Terraform
#   export TF_VAR_id_vecchio_redis=$(docker inspect -f '{{.Id}}' vecchio-redis)
#   cd ~/iac/03 && terraform init && terraform apply
#     → crea "cache" e IMPORTA vecchio-redis nello stato (blocco import)
#   psql "$PG_CONN_STR" -c 'select name from terraform_remote_state.states'
#   LOCK: terminale 1 `terraform apply` e lascialo fermo al prompt "yes" (tiene il lock);
#         terminale 2 `terraform plan -lock-timeout=0s` → Error acquiring the state lock
#   REFACTOR: rinomina la risorsa "cache" in "sessioni", aggiungi il blocco
#     moved qui sotto (già scritto, commentato): il plan dice "has moved", 0 to destroy
#   terraform state list · terraform state show docker_container.legacy

terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
  }
  backend "pg" {
    # conn_str da PG_CONN_STR; schema_name di default: terraform_remote_state
  }
}

provider "docker" {}

resource "docker_image" "redis" {
  name         = "redis:8-alpine"
  keep_locally = true
}

resource "docker_container" "cache" {
  name    = "lab-cache"
  image   = docker_image.redis.image_id
  command = ["redis-server", "--appendonly", "no"] # niente stringhe vuote: il provider le rifiuta
}

# ── IMPORT DICHIARATIVO (Terraform >= 1.5) ──────────────────────────────────
# Porta sotto Terraform una risorsa creata a mano. Il plan mostra
# "will be imported" e un eventuale diff tra la risorsa reale e il codice.
#   terraform plan -generate-config-out=generato.tf
# scrive il codice al posto tuo partendo dalla risorsa reale (da ripulire).
variable "id_vecchio_redis" {
  type        = string
  description = "ID COMPLETO del container: docker inspect -f '{{.Id}}' vecchio-redis"
}

import {
  to = docker_container.legacy
  # il provider docker vuole l'ID completo: con il nome il plan fallisce con
  # "Cannot import non-existent remote object" (provato). L'id può essere
  # un'espressione nota al plan, come una variabile (Terraform >= 1.6).
  id = var.id_vecchio_redis
}

resource "docker_container" "legacy" {
  name  = "vecchio-redis"
  image = docker_image.redis.image_id
  lifecycle {
    # campi che Docker ha deciso da sé alla creazione manuale: se non li
    # ignori il plan vuole ricreare il container appena importato
    ignore_changes = [image, command, entrypoint, env, hostname, user, working_dir, log_driver, log_opts, network_mode]
  }
  # Il primo plan dopo l'import mostra comunque "update in-place" su must_run,
  # start, wait, logs…: sono impostazioni del provider, non della risorsa
  # Docker, e non toccano il container (provato).
}

# ── REFACTORING SENZA DISTRUGGERE: moved ────────────────────────────────────
# Rinominare una risorsa nel codice = per Terraform "distruggi la vecchia,
# crea la nuova". Il blocco moved dice che è la stessa cosa.
# Funziona anche per entrare in un modulo o passare da count a for_each:
#   moved { from = docker_container.web[0]  to = docker_container.web["a"] }
#   moved { from = docker_container.web     to = module.web.docker_container.this }
#
# moved {
#   from = docker_container.cache
#   to   = docker_container.sessioni
# }

# ── TOGLIERE DALLO STATO SENZA DISTRUGGERE: removed (Terraform >= 1.7) ──────
# Sostituisce `terraform state rm`: la risorsa esce dalla gestione ma resta.
# removed {
#   from = docker_container.legacy
#   lifecycle { destroy = false }
# }

# ── COMANDI SULLO STATO (di emergenza, lasciano traccia solo nei log) ───────
#   terraform state list / show ADDR
#   terraform state mv  A B        → meglio un blocco moved (rivisto in MR)
#   terraform state rm  ADDR       → meglio un blocco removed
#   terraform state pull > backup.tfstate   (prima di qualunque intervento)
#   terraform force-unlock LOCK_ID (solo se sei SICURO che nessuno stia lavorando)
#   terraform plan -refresh-only   (cosa è cambiato fuori da Terraform)

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Come organizzi lo stato per più ambienti e team?
# R: Stati piccoli e separati per ambiente e per dominio (rete, dati,
#    app): un errore ha un raggio limitato e i plan sono veloci. Si
#    leggono gli output degli altri con terraform_remote_state o, meglio,
#    con data source sulle risorse vere. Workspaces solo per copie
#    identiche (es. ambienti effimeri per MR), non per dev/prod che
#    divergono.
#
# D: Il lock è rimasto appeso dopo una pipeline cancellata.
# R: Verifica che nessun job stia girando, poi `terraform force-unlock`
#    con l'ID dell'errore. Prima: `state pull` come backup.
#
# D: Hai cancellato per sbaglio una risorsa dallo stato.
# R: Terraform ora vuole crearla di nuovo (e fallisce per nome già in
#    uso). Si reimporta con un blocco import. Con un backend versionato si
#    può anche ripristinare la versione precedente dello stato.
#
# D: Differenza tra data source e terraform_remote_state?
# R: Il data source interroga l'API del provider (la realtà) e accoppia
#    solo per nome/tag; remote_state legge lo stato di un altro progetto
#    e richiede l'accesso a TUTTO quello stato (segreti compresi).

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Backend remoto: condiviso, con lock, cifrato e versionato
# • s3 + use_lockfile (niente più DynamoDB); pg per il lab
# • import { } per adottare risorse esistenti; -generate-config-out
# • moved { } per rinominare/spostare, removed { } per lasciare andare
# • Stati piccoli per ambiente e dominio; state pull prima di toccare
# ══════════════════════════════════════════════════════════════════════════
