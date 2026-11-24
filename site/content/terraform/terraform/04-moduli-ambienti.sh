#!/usr/bin/env bash
# Lezione 04 — un modulo riusabile e due ambienti (dev, prod) che lo chiamano.
source "$(dirname "$0")/../lib/passo.sh"
titolo "04. Moduli e ambienti"
cartella iac/04

passo "Scrivo la struttura con lo script della lezione: modules/servizio + envs/dev + envs/prod" \
  "bash $LEZIONI/terraform/04-moduli-ambienti.sh crea"
passo "Com'è fatto: il modulo ha input (variables.tf), risorse (main.tf), output (outputs.tf); ogni ambiente è un root module" \
  'find iac -name "*.tf" | sort'
passo "L'ambiente dev chiama il modulo con i SUOI valori (1 replica, porta 8201)" \
  'cat iac/envs/dev/main.tf'
passo "dev: init (vede il modulo locale) e apply" \
  'cd iac/envs/dev && terraform init && terraform apply -auto-approve'
passo "Gli output del root module rilanciano quelli del modulo" \
  'terraform output'
passo "Indirizzi nello state: module.<nome>.<risorsa>[chiave]" \
  'terraform state list'
passo "prod: STESSO modulo, valori diversi (3 repliche, porta 8301), state SEPARATO. Solo plan" \
  'cd ../prod && terraform init && terraform plan'
passo "Pulizia di dev" \
  'cd ../dev && terraform destroy -auto-approve'
