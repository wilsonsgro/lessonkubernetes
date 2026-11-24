#!/usr/bin/env bash
# Lezione 05 — terraform test (unitari con mock e integrazione) e blocchi check.
source "$(dirname "$0")/../lib/passo.sh"
titolo "05. Test, check e pipeline"
cartella iac/05

passo "Scrivo il progetto t05: main.tf con un check, tests/unitari.tftest.hcl (provider finto), tests/integrazione.tftest.hcl" \
  "bash $LEZIONI/terraform/05-test-check-pipeline.sh crea"
passo "Un test unitario: blocchi run con assert su output e risorse, provider mock (nessun container creato)" \
  'sed -n "1,30p" t05/tests/unitari.tftest.hcl'
passo "init" \
  'cd t05 && terraform init'
passo "terraform test: esegue unitari (mock) e integrazione (Docker vero, creato e distrutto dal test)" \
  'terraform test'
passo "apply: il check 'risponde' interroga /health dopo l'apply e passa" \
  'terraform apply -auto-approve'
passo "Rompo l'app: whoami da ora risponde 500 su /health" \
  'curl -s -X POST -d 500 localhost:8401/health; curl -s -o /dev/null -w "HTTP %{http_code}\n" localhost:8401/health'
passo "plan: 0 to change ma Warning dal check. Un check AVVISA, non blocca (al contrario di una precondition)" \
  'terraform plan'
passo "Pulizia" \
  'terraform destroy -auto-approve'
nota "In pipeline: fmt -check → validate → tflint → test → plan -out (artefatto) → approvazione → apply del piano."
