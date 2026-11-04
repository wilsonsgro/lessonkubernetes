# ═══════════════════════════════════════════════════════════════════════════
# 02. VARIABILI, LOCALS, FOR_EACH, DYNAMIC E VALIDAZIONE
# Versione: Terraform 1.17 · provider kreuzwerker/docker 4.6
# Livello: 1 — Linguaggio HCL
# ═══════════════════════════════════════════════════════════════════════════
# INPUT, CALCOLI, OUTPUT
#   variable   l'interfaccia: tipo, default, validazione, sensitive
#   locals     valori calcolati una volta e riusati (DRY)
#   output     ciò che esce: per l'utente, per altri moduli, per la CI
#
# PRECEDENZA DEI VALORI (l'ultima vince)
#   default < variabili d'ambiente TF_VAR_nome < terraform.tfvars
#   < *.auto.tfvars < -var-file=… < -var nome=…
#
# count O for_each? (domanda quasi certa)
#   count = N copie indicizzate per POSIZIONE: web[0], web[1], web[2].
#   Togli "b" dalla lista ["a","b","c"] e "c" scala da [2] a [1]:
#   Terraform DISTRUGGE e RICREA "c" anche se non è cambiato niente.
#   for_each = copie indicizzate per CHIAVE: web["a"], web["c"]. Togliere
#   "b" tocca solo "b". Regola: for_each per tutto ciò che ha un'identità;
#   count solo per "0 o 1" (risorsa opzionale) o copie davvero anonime.
#
# LAB
#   cp 02-variabili-for-each-espressioni.tf ~/iac/02/main.tf && cd ~/iac/02
#   terraform init
#   terraform plan -var 'ambiente=prod'                      # 3 servizi
#   terraform plan -var 'ambiente=collaudo'                  # errore di validazione
#   terraform apply -auto-approve
#   terraform output -json servizi | jq
#   terraform console      →   local.porte   ·   { for k, v in var.servizi : k => v.porta }
#   terraform apply -auto-approve -var 'ambiente=prod'      # admin esiste solo in prod
#   togli "admin" da var.servizi e rifai il plan con -var 'ambiente=prod':
#   solo admin viene distrutto (in dev non c'era: il plan non cambierebbe niente)

terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 4.6" }
  }
}

provider "docker" {}

# ── VARIABILI ───────────────────────────────────────────────────────────────
variable "ambiente" {
  type        = string
  description = "dev | prod"
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.ambiente)
    error_message = "ambiente deve essere dev o prod."
  }
}

variable "servizi" {
  description = "Servizi da avviare: chiave = nome"
  type = map(object({
    porta     = number
    repliche  = optional(number, 1) # optional con default (Terraform >= 1.3)
    variabili = optional(map(string), {})
  }))
  default = {
    api   = { porta = 8101, variabili = { LOG_LEVEL = "info" } }
    web   = { porta = 8102 }
    admin = { porta = 8103 }
  }

  validation {
    condition     = alltrue([for s in values(var.servizi) : s.porta >= 1024 && s.porta <= 65535])
    error_message = "Le porte devono stare tra 1024 e 65535."
  }
}

variable "token_api" {
  type      = string
  default   = "solo-per-il-lab"
  sensitive = true # nascosto in plan e output; NELLO STATO resta in chiaro
}

# ── LOCALS ──────────────────────────────────────────────────────────────────
locals {
  prefisso = "lab-${var.ambiente}"

  etichette_comuni = {
    ambiente   = var.ambiente
    gestito-da = "terraform"
  }

  # condizionale: in dev niente admin
  servizi_attivi = {
    for nome, s in var.servizi : nome => s
    if var.ambiente == "prod" || nome != "admin"
  }

  porte = [for s in values(local.servizi_attivi) : s.porta]
}

# ── RISORSE ─────────────────────────────────────────────────────────────────
resource "docker_image" "whoami" {
  name         = "traefik/whoami:v1.12"
  keep_locally = true
}

resource "docker_container" "servizio" {
  for_each = local.servizi_attivi # each.key = nome, each.value = oggetto

  name  = "${local.prefisso}-${each.key}"
  image = docker_image.whoami.image_id
  # whoami ascolta su 80 e con --name scrive il nome nella risposta
  command = ["--name", each.key]

  ports {
    internal = 80
    external = each.value.porta
  }

  env = concat(
    [for k, v in each.value.variabili : "${k}=${v}"],
    each.key == "api" ? ["TOKEN=${var.token_api}"] : []
  )

  # dynamic: un blocco ripetuto generato da una collezione
  dynamic "labels" {
    for_each = merge(local.etichette_comuni, { servizio = each.key })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# count per una risorsa OPZIONALE (0 o 1)
resource "docker_container" "debug" {
  count = var.ambiente == "dev" ? 1 : 0

  name    = "${local.prefisso}-debug"
  image   = docker_image.whoami.image_id
  command = ["--name", "debug"]
}

# ── OUTPUT ──────────────────────────────────────────────────────────────────
output "servizi" {
  value = {
    for nome, c in docker_container.servizio :
    nome => "http://localhost:${c.ports[0].external}"
  }
}

output "debug_attivo" {
  # one() = null se la lista è vuota, l'elemento se ce n'è uno
  value = one(docker_container.debug[*].name) != null
}

output "token" {
  value     = var.token_api
  sensitive = true # senza, l'output fallisce: "Output refers to sensitive values"
}

# ── FUNZIONI DA AVERE IN MANO ───────────────────────────────────────────────
#   merge, concat, flatten, lookup(map, k, default), try(expr, fallback)
#   coalesce, one, toset, keys/values, zipmap, cidrsubnet("10.0.0.0/16", 8, 1)
#   templatefile("cloud-init.tftpl", { … }), jsonencode/yamlencode
#   can(regex(...)) dentro una validation
#
# D: Come trasformi una lista di oggetti in una mappa per for_each?
# R: { for o in var.lista : o.nome => o }. for_each accetta solo mappe o
#    set di stringhe; e le chiavi devono essere note al plan (non un ID
#    generato da un'altra risorsa: "Invalid for_each argument").
#
# D: "sensitive" protegge il segreto?
# R: Solo dalla stampa in plan, output e log. Nello stato è in chiaro:
#    il backend va cifrato e con accesso ristretto, o il segreto non passa
#    da Terraform (lo legge l'app da un secret manager). Da Terraform 1.10
#    esistono anche le risorse "ephemeral" e gli argomenti write-only, che
#    non finiscono nello stato.

# ══════════════════════════════════════════════════════════════════════════
# RIEPILOGO
# • variable (tipo, optional, validation, sensitive) · locals · output
# • for_each per chiave, count solo per 0/1: niente ricreazioni a catena
# • for expression per filtrare e trasformare; dynamic per i blocchi
# • sensitive nasconde a video, non nello stato
# • terraform console per provare le espressioni
# ══════════════════════════════════════════════════════════════════════════
