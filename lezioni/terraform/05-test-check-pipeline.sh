#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 05. TESTARE L'INFRASTRUTTURA: terraform test, MOCK, CHECK E PIPELINE
# Versione: Terraform 1.17 · provider docker 4.6 · hashicorp/http 3.5
# Livello: 3 — Qualità e automazione
# ═══════════════════════════════════════════════════════════════════════════
# Quattro livelli di controllo, dal più economico:
#   1. STATICO      fmt -check, validate, tflint (regole dei provider),
#                   checkov / trivy config (sicurezza: bucket pubblici,
#                   security group 0.0.0.0/0…)
#   2. CONTRATTI    validation sulle variabili, precondition/postcondition
#                   sulle risorse: falliscono il plan/apply con un messaggio
#   3. TEST         `terraform test` con file .tftest.hcl:
#                   command = plan  → test unitari, veloci, nessuna risorsa
#                   command = apply → integrazione: crea, verifica, distrugge
#                   mock_provider   → unitari senza credenziali né API
#   4. CONTINUI     blocchi check: asserzioni valutate a OGNI plan/apply,
#                   che avvisano (warning) senza bloccare: drift funzionale
#
# LAB
#   bash 05-test-check-pipeline.sh crea
#   cd t05 && terraform init
#   terraform test                  # unitari con mock + integrazione su Docker
#   terraform apply -auto-approve   # il check "risponde" passa
#   curl -X POST -d 500 localhost:8401/health   # whoami: da ora /health risponde 500
#   terraform plan     # 0 to change + "Warning: Error making request" dal check:
#                      # avvisa e NON blocca (con retry, l'http provider dà errore
#                      # invece dello status). Con `docker stop` invece il check
#                      # non scatta: il container va ricreato e il check aspetta l'apply.
#   terraform destroy -auto-approve
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Oggi il controllo dopo il deploy lo fa Ansible (ruolo verifica): codici
#   HTTP attesi attraverso HAProxy, e meta.total > 0 sull'API.
#     grep -n -E 'atteso:|failed_when' ansible/roles/verifica/tasks/main.yml
#   ESERCIZIO: porta un controllo in Terraform con un blocco
#   `check "api" { data "http" … }` nello stack app, e `terraform test`
#   con mock_provider per la logica dei checksum. Un check fallito avvisa,
#   ma non ferma l'apply: per fermarlo serve la verifica di Ansible.

set -euo pipefail
D=./t05

crea() {
  mkdir -p $D/tests

  cat > $D/main.tf <<'EOF'
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
    http   = { source = "hashicorp/http", version = "~> 3.5" }
  }
}

provider "docker" {}

variable "nome" {
  type    = string
  default = "t05-web"
}

variable "porta" {
  type    = number
  default = 8401
  validation {
    condition     = var.porta > 1024
    error_message = "Porta privilegiata: usa una porta > 1024."
  }
}

variable "immagine" {
  type    = string
  default = "traefik/whoami:v1.12"
}

resource "docker_image" "web" {
  name         = var.immagine
  keep_locally = true
}

resource "docker_container" "web" {
  name  = var.nome
  image = docker_image.web.image_id

  ports {
    internal = 80
    external = var.porta
  }

  lifecycle {
    precondition {
      condition     = !endswith(var.immagine, ":latest")
      error_message = "Vietato :latest: usa un tag immutabile."
    }
    postcondition {
      condition     = self.ports[0].external == var.porta
      error_message = "La porta pubblicata non è quella richiesta."
    }
  }
}

output "url" {
  value = "http://localhost:${docker_container.web.ports[0].external}"
}

# Valutato a ogni plan/apply DOPO il resto: un fallimento è un warning.
check "risponde" {
  data "http" "salute" {
    url = "http://localhost:${var.porta}/health"
    retry { attempts = 3 }
  }
  assert {
    condition     = data.http.salute.status_code == 200
    error_message = "${var.nome} non risponde 200 su /health."
  }
}
EOF

  # ── TEST UNITARI: provider finto, nessun container creato ───────────────
  cat > $D/tests/unitari.tftest.hcl <<'EOF'
mock_provider "docker" {
  mock_resource "docker_image" {
    defaults = { image_id = "sha256:finto" }
  }
  mock_resource "docker_container" {
    defaults = { ports = [{ internal = 80, external = 8401, ip = "0.0.0.0", protocol = "tcp" }] }
  }
}
# senza default il finto http dà status_code 0 e il check "risponde"
# fa FALLIRE il run: nei test un check fallito non è un warning (provato)
mock_provider "http" {
  mock_data "http" {
    defaults = { status_code = 200 }
  }
}

run "url_costruito_dalla_porta" {
  command = plan
  assert {
    condition     = output.url == "http://localhost:8401"
    error_message = "URL sbagliato: ${output.url}"
  }
}

run "porta_privilegiata_rifiutata" {
  command = plan
  variables { porta = 80 }
  expect_failures = [var.porta] # il test PASSA se la validazione fallisce
}

run "latest_vietato" {
  command = plan
  variables { immagine = "traefik/whoami:latest" }
  expect_failures = [docker_container.web]
}
EOF

  # ── TEST DI INTEGRAZIONE: risorse vere, distrutte alla fine ─────────────
  cat > $D/tests/integrazione.tftest.hcl <<'EOF'
variables {
  nome  = "t05-test"
  porta = 8402
}

# Il data source del check non è raggiungibile da qui ("Reference to scoped
# resource", provato): la prova che risponde è il check stesso, perché in
# un test un check fallito fa fallire il run.
run "crea_e_risponde" {
  command = apply
  assert {
    condition     = docker_container.web.name == "t05-test"
    error_message = "Nome del container inatteso."
  }
  assert {
    condition     = output.url == "http://localhost:8402"
    error_message = "URL inatteso: ${output.url}"
  }
}
EOF
  echo "progetto scritto in $D"
}

case "${1:-}" in
  crea) crea ;;
  *) echo "uso: $0 crea" ;;
esac

# ── LA PIPELINE TERRAFORM (GitLab CI, schema) ───────────────────────────────
#   MR:     fmt -check · validate · tflint · trivy config · terraform test
#           plan -out=piano.tfplan  →  terraform show -no-color piano.tfplan
#           commentato nella MR (o show -json per una policy OPA/Conftest:
#           "niente destroy su risorse con tag critico")
#   main:   apply piano.tfplan  (lo STESSO piano rivisto, job manuale per prod)
#   notte:  plan -detailed-exitcode → exit 2 = drift → alert
#   Credenziali: OIDC del job verso il cloud (id_tokens + ruolo con
#   AssumeRoleWithWebIdentity), mai chiavi statiche nelle variabili CI.
#   resource_group per non lanciare due apply sullo stesso stato.

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Come testi un modulo Terraform?
# R: terraform test: run con command=plan e mock_provider per la logica
#    (espressioni, condizionali, validazioni, expect_failures), run con
#    command=apply in un account/progetto di test per l'integrazione.
#    Terratest (Go) quando serve verificare il comportamento da fuori.
#
# D: precondition, postcondition, check: differenze?
# R: precondition: prima di creare/aggiornare la risorsa, blocca.
#    postcondition: dopo, sul risultato (self), blocca. check: alla fine,
#    sull'insieme, NON blocca: avvisa. Validation: sulla singola variabile.
#
# D: -detailed-exitcode?
# R: plan esce 0 = nessun cambiamento, 1 = errore, 2 = ci sono cambiamenti.
#    È il modo di trasformare il drift in un job rosso.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Statico (fmt, validate, tflint, trivy) → contratti → test → check
# • .tftest.hcl: plan + mock per gli unitari, apply per l'integrazione
# • expect_failures prova che le validazioni scattano davvero
# • check { } = asserzioni continue che avvisano senza bloccare
# • Pipeline: plan in MR, apply dello stesso piano, drift notturno con exit 2
# ══════════════════════════════════════════════════════════════════════════
