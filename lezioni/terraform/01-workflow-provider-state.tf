# ═══════════════════════════════════════════════════════════════════════════
# 01. TERRAFORM: WORKFLOW, PROVIDER, RISORSE E STATO
# Versione: Terraform 1.17 · provider kreuzwerker/docker 4.6
# Livello: 0 — Fondamenta IaC
# ═══════════════════════════════════════════════════════════════════════════
# Infrastructure as Code: l'infrastruttura descritta in file versionati,
# rivisti in merge request, applicati da una pipeline. Due famiglie:
#   DICHIARATIVO (Terraform, OpenTofu, Pulumi, CloudFormation)
#     descrivi lo stato finale; il tool calcola il diff e lo applica
#   PROCEDURALE / di configurazione (Ansible, Chef, Puppet)
#     descrivi i passi (idempotenti) per portare un server in uno stato
#   Regola pratica: Terraform CREA l'infrastruttura (rete, VM, DNS, DB
#   gestiti, cluster), Ansible CONFIGURA ciò che gira dentro (lezione 10).
#
# IL WORKFLOW
#   terraform init      scarica provider e moduli, configura il backend
#   terraform fmt       formatta (in CI: fmt -check)
#   terraform validate  sintassi e tipi, senza toccare niente
#   terraform plan      legge lo stato, interroga le API (refresh),
#                       calcola il DIFF: + crea, ~ modifica, -/+ ricrea, - distrugge
#   terraform apply     esegue il piano (meglio: apply di un piano salvato)
#   terraform destroy   distrugge tutto ciò che è nello stato
#
# LO STATO (terraform.tfstate) è il cuore: la mappa tra gli indirizzi del
# codice (docker_container.web) e gli ID reali (l'ID del container).
#   • senza stato Terraform non sa cosa ha creato → ricreerebbe tutto
#   • contiene SEGRETI in chiaro (password generate, chiavi): mai in git
#   • in team va su un backend remoto con lock (lezione 03)
#
# LAB SU UBUNTU (il provider docker usa il Docker locale: niente cloud)
#   sudo apt-get install -y gnupg software-properties-common
#   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
#   echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
#     | sudo tee /etc/apt/sources.list.d/hashicorp.list
#   sudo apt-get update && sudo apt-get install -y terraform
#
#   mkdir -p ~/iac/01 && cp 01-workflow-provider-state.tf ~/iac/01/main.tf && cd ~/iac/01
#   terraform init && terraform plan -out=piano.tfplan
#   terraform apply piano.tfplan
#   curl -s localhost:8088 | head -3
#   terraform state list ; terraform state show docker_container.web
#   docker stop lab-web && terraform plan       # DRIFT: lo vede e propone -/+ (ricrea,
#                                               # non riavvia: le porte di un container fermo spariscono)
#   terraform apply -replace=docker_container.web   # ricrea una risorsa sana
#   terraform destroy

terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6" # ~> 4.6 = >= 4.6, < 5.0: patch e minor sì, major no
    }
  }
}

# Il provider traduce le risorse in chiamate API (qui: API di Docker).
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_network" "lab" {
  name = "lab-iac"
}

resource "docker_image" "nginx" {
  name         = "nginx:1.29-alpine"
  keep_locally = true # destroy non cancella l'immagine dal disco
}

resource "docker_container" "web" {
  name = "lab-web"
  # riferimento a un'altra risorsa = DIPENDENZA IMPLICITA:
  # Terraform crea prima l'immagine e la rete, poi il container
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 8088
  }

  networks_advanced {
    name = docker_network.lab.name
  }

  restart = "unless-stopped"
  # must_run (default true): se il container è fermo, il plan lo
  # considera da sistemare. È così che vedi il drift del LAB.

  labels {
    label = "gestito-da"
    value = "terraform"
  }

  lifecycle {
    # create_before_destroy: prima crea il nuovo, poi distrugge il vecchio
    # (qui fallirebbe: nome e porta sono unici, servirebbero nomi diversi)
    # prevent_destroy = true   → un plan che lo distrugge FALLISCE
    # ignore_changes = [labels] → modifiche esterne a questi campi ignorate
    ignore_changes = []
  }
}

output "url" {
  value       = "http://localhost:${docker_container.web.ports[0].external}"
  description = "Indirizzo del container"
}

output "container_id" {
  value = docker_container.web.id
}

# ── DOMANDE DA COLLOQUIO ────────────────────────────────────────────────────
# D: Cos'è il drift e come lo gestisci?
# R: Differenza tra stato reale e codice (modifica manuale in console).
#    `terraform plan` la mostra; `plan -refresh-only` mostra SOLO ciò che è
#    cambiato fuori, e `apply -refresh-only` accetta la realtà nello stato.
#    In produzione: plan schedulato in CI che apre un alert se il diff
#    non è vuoto; e permessi di console in sola lettura.
#
# D: -/+ nel plan: perché vuole ricreare la risorsa?
# R: Hai cambiato un attributo "ForceNew" (immutabile per l'API: nome di un
#    bucket, AMI di una VM, qui l'immagine del container). Il plan lo dice
#    con "# forces replacement". Se è un DB: fermati e ragiona.
#
# D: Terraform vs OpenTofu?
# R: OpenTofu è il fork open source (MPL) nato dopo il passaggio di
#    Terraform alla licenza BSL nel 2023, ora sotto la Linux Foundation.
#    Stessa sintassi HCL, stessi provider; differenze nelle funzioni nuove
#    (cifratura dello stato nativa in OpenTofu).
#
# D: Perché `apply` di un piano salvato e non `apply` diretto?
# R: Il piano rivisto (in MR o dall'approvatore) è esattamente ciò che
#    viene eseguito. Un apply diretto ricalcola il piano: se nel frattempo
#    è cambiato qualcosa, applichi una cosa che nessuno ha visto.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • Dichiarativo: descrivi lo stato, Terraform calcola il diff
# • init → fmt → validate → plan -out → apply piano → destroy
# • Le dipendenze nascono dai riferimenti tra risorse
# • Lo stato mappa codice ↔ realtà; contiene segreti; mai in git
# • Drift: plan lo mostra, -refresh-only lo accetta, -replace ricrea
# ══════════════════════════════════════════════════════════════════════════
