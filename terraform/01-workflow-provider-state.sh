#!/usr/bin/env bash
# Lezione 01 — il ciclo init/plan/apply/destroy con il provider docker, lo state e il drift.
source "$(dirname "$0")/../lib/passo.sh"
titolo "01. Workflow, provider e state"
cartella iac/01

passo "Copio il file della lezione come main.tf: rete docker, immagine nginx e container lab-web sulla porta 8088" \
  "cp $LEZIONI/terraform/01-workflow-provider-state.tf main.tf && grep -n '^resource\|^terraform\|^provider' main.tf"
passo "terraform init: scarica il provider docker in .terraform/ e scrive .terraform.lock.hcl (versioni bloccate, va in git)" \
  'terraform init'
passo "terraform fmt e validate: formattazione e controllo di sintassi/tipi, senza toccare niente" \
  'terraform fmt -check -diff; terraform validate'
passo "terraform plan -out: calcola le differenze fra codice e realtà e le SALVA. L'apply eseguirà esattamente questo piano" \
  'terraform plan -out=piano.tfplan'
passo "terraform apply del piano salvato: niente domanda di conferma, il piano è già stato approvato" \
  'terraform apply piano.tfplan'
passo "Il container risponde" \
  'curl -s localhost:8088 | head -3'
passo "Lo state: Terraform ricorda cosa ha creato e con quali id" \
  'terraform state list'
passo "Tutti gli attributi di una risorsa nello state" \
  'terraform state show docker_container.web | head -25'
passo "DRIFT: fermo il container a mano, fuori da Terraform. Il plan se ne accorge e propone di ricrearlo (-/+)" \
  'docker stop lab-web && terraform plan'
passo "-replace: ricrea una risorsa anche quando il plan non lo chiederebbe (qui rimette a posto il drift)" \
  'terraform apply -replace=docker_container.web -auto-approve && curl -s -o /dev/null -w "HTTP %{http_code}\n" localhost:8088'
passo "terraform destroy: distrugge tutto quello che è nello state" \
  'terraform destroy -auto-approve'
