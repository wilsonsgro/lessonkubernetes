#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# 04. MODULI E AMBIENTI: STRUTTURA DI UN REPO TERRAFORM VERO
# Versione: Terraform 1.17 · provider kreuzwerker/docker 4.6
# Livello: 2 — Stato e refactoring
# ═══════════════════════════════════════════════════════════════════════════
# Un modulo è una cartella di .tf con input (variable) e output. Il "root
# module" è quello da cui lanci terraform; gli altri si chiamano con
# `module "nome" { source = … }`.
#
#   iac/
#   ├── modules/
#   │   └── servizio/          un servizio: rete + N container + healthcheck
#   │       ├── main.tf
#   │       ├── variables.tf
#   │       ├── outputs.tf
#   │       └── versions.tf    required_providers: il MODULO non configura
#   │                          il provider, lo riceve dal root
#   └── envs/
#       ├── dev/main.tf        root: backend dev, modulo con valori dev
#       └── prod/main.tf       root: backend prod, modulo con valori prod
#
# SOURCE DI UN MODULO
#   "../../modules/servizio"                          locale (monorepo)
#   "git::https://gitlab.com/org/tf-mod.git//servizio?ref=v1.4.0"  git + tag
#   "app.terraform.io/org/servizio/docker", version = "~> 1.4"     registry
# In produzione: SEMPRE una versione fissa (tag o version), mai un branch.
#
# LAB
#   bash 04-moduli-ambienti.sh crea
#   cd iac/envs/dev && terraform init && terraform apply -auto-approve
#   terraform output                         # output del root ← output del modulo
#   cd ../prod && terraform init && terraform plan    # stesso modulo, 3 repliche
#   terraform state list                     # module.negozio.docker_container.replica["0"]…
#
# ── NEL PROGETTO VERO: il Biodistretto su minikube ───────────────────────
#   ~/biodistretto/kubernetes (branch kubernetes). I grep partono da lì:
#   cd ~/biodistretto/kubernetes · come si usa: il README della cartella
#   Il progetto usa due root module e non moduli dentro un'unica root.
#   Il motivo: il provider kubernetes si configura con gli output del
#   cluster, e kubernetes_manifest vuole il cluster raggiungibile già al
#   plan. Nella stessa root, il primo plan da zero fallirebbe.
#     grep -n -A6 'provider "kubernetes"' terraform/app/versions.tf
#   ESERCIZIO: un secondo ambiente è un altro dominio e un altro namespace
#   (variabili dominio e namespace). Prova
#   `terraform -chdir=terraform/app plan -var dominio=prova.lab` e conta
#   cosa verrebbe sostituito: certificati, ConfigMap e Pod.

set -euo pipefail
R=./iac

crea() {
  mkdir -p $R/modules/servizio $R/envs/dev $R/envs/prod

  cat > $R/modules/servizio/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = ">= 4.6, < 5.0" }
  }
}
EOF

  cat > $R/modules/servizio/variables.tf <<'EOF'
variable "nome" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.nome))
    error_message = "nome: minuscole, numeri e trattini, 3-21 caratteri."
  }
}

variable "ambiente" {
  type = string
}

variable "immagine" {
  type    = string
  default = "traefik/whoami:v1.12"
}

variable "repliche" {
  type    = number
  default = 1
  validation {
    condition     = var.repliche >= 1 && var.repliche <= 5
    error_message = "repliche tra 1 e 5."
  }
}

variable "porta_base" {
  type        = number
  description = "La replica i ascolta su porta_base + i"
}
EOF

  cat > $R/modules/servizio/main.tf <<'EOF'
locals {
  prefisso = "${var.ambiente}-${var.nome}"
  # mappa "0","1",… → for_each con chiavi stabili
  repliche = { for i in range(var.repliche) : tostring(i) => var.porta_base + i }
}

resource "docker_network" "this" {
  name = "${local.prefisso}-net"
}

resource "docker_image" "this" {
  name         = var.immagine
  keep_locally = true
}

resource "docker_container" "replica" {
  for_each = local.repliche

  name    = "${local.prefisso}-${each.key}"
  image   = docker_image.this.image_id
  command = ["--name", "${local.prefisso}-${each.key}"]

  ports {
    internal = 80
    external = each.value
  }

  networks_advanced {
    name    = docker_network.this.name
    aliases = [var.nome]
  }

  labels {
    label = "ambiente"
    value = var.ambiente
  }
}
EOF

  cat > $R/modules/servizio/outputs.tf <<'EOF'
output "url" {
  description = "Un URL per replica"
  value       = [for k, c in docker_container.replica : "http://localhost:${c.ports[0].external}"]
}

output "rete" {
  value = docker_network.this.name
}
EOF

  for amb in dev prod; do
    local repliche=1 porta=8201
    [[ $amb == prod ]] && repliche=3 porta=8301
    cat > $R/envs/$amb/main.tf <<EOF
terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
  }
  # in un repo vero: backend separato per ambiente
  # backend "s3" { bucket = "tfstate-$amb" key = "negozio/terraform.tfstate" use_lockfile = true }
}

provider "docker" {}

module "negozio" {
  source = "../../modules/servizio"

  nome       = "negozio"
  ambiente   = "$amb"
  repliche   = $repliche
  porta_base = $porta
}

output "url" {
  value = module.negozio.url
}
EOF
  done
  echo "struttura scritta in $R"
}

case "${1:-}" in
  crea) crea ;;
  *) echo "uso: $0 crea" ;;
esac

# ── WORKSPACES O CARTELLE? ──────────────────────────────────────────────────
#   terraform workspace new staging  → stesso codice, stato separato,
#   terraform.workspace come variabile. Pro: zero duplicazione.
#   Contro: stesso backend e stessi permessi per tutti gli ambienti, e
#   l'ambiente su cui lavori è uno stato invisibile del terminale ("ero
#   in prod?"). Per dev/staging/prod quasi tutti usano CARTELLE (o
#   Terragrunt, che genera backend e input per cartella e riduce la
#   duplicazione). I workspace vanno bene per copie effimere identiche.
#
# ── BUONI MODULI ────────────────────────────────────────────────────────────
#   • piccoli e con uno scopo ("rete", "cluster", "database"), non "tutto"
#   • input con tipi, validazioni e default sensati; output di ciò che
#     serve a valle (ID, endpoint), non di tutto
#   • niente provider configurati dentro; required_providers con range
#   • versionati con SemVer, CHANGELOG, esempi in examples/ e test
#   • niente "god module" con 80 variabili e un count su ogni risorsa

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Cambio il modulo usato da 40 progetti: come lo rilasci in sicurezza?
# R: Nuova versione SemVer (major se rompe l'interfaccia), i progetti la
#    adottano uno per uno cambiando ref/version, con plan in MR. Mai
#    `ref=main`: un merge sul modulo cambierebbe 40 plan insieme.
#
# D: Un modulo usa count e voglio passare a for_each senza ricreare.
# R: Blocchi moved per ogni indice: from = x[0] to = x["a"] (lezione 03).
#
# D: depends_on su un modulo?
# R: Si può (Terraform >= 0.13) ma rende "noti dopo l'apply" molti valori
#    e il plan diventa pessimista. Meglio passare un output come input:
#    la dipendenza nasce da sola.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Modulo = cartella con variables / main / outputs / versions
# • Il root configura provider e backend, i moduli no
# • Source versionate (tag git o registry), mai branch
# • Ambienti in cartelle separate (o Terragrunt); workspace per copie effimere
# • Moduli piccoli, tipizzati, validati, versionati
# ══════════════════════════════════════════════════════════════════════════
