#!/usr/bin/env bash
# Lezione 10 — Terraform crea i nodi e scrive l'inventario, Ansible li configura.
source "$(dirname "$0")/../lib/passo.sh"
export PATH="$HOME/.local/bin:$PATH"
titolo "10. Terraform + Ansible"
cartella iac/10

passo "Scrivo la catena con lo script della lezione: main.tf, template dell'inventario, playbook" \
  "bash $LEZIONI/terraform/10-terraform-piu-ansible.sh crea"
passo "Il template: Terraform lo riempie con i nodi che ha creato (templatefile + local_file)" \
  'cat catena/inventory.yml.tftpl'
passo "init e apply: crea i container e SCRIVE inventory.yml" \
  'cd catena && terraform init && terraform apply -auto-approve'
passo "L'inventario generato: nessuno lo scrive a mano, è un output di Terraform" \
  'cat inventory.yml'
passo "Ansible configura i nodi appena creati" \
  'ansible-playbook -i inventory.yml site.yml'
passo "Un nodo in più: Terraform crea app03 e riscrive l'inventario…" \
  'terraform apply -auto-approve -var repliche=3 && cat inventory.yml'
passo "…lo stesso playbook lo configura. I due già configurati restano verdi (idempotenza)" \
  'ansible-playbook -i inventory.yml site.yml'
passo "Pulizia" \
  'terraform destroy -auto-approve'
