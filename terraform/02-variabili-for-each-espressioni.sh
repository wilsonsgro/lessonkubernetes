#!/usr/bin/env bash
# Lezione 02 — variabili tipizzate con validation, locals, for_each, output, console.
source "$(dirname "$0")/../lib/passo.sh"
titolo "02. Variabili, for_each ed espressioni"
cartella iac/02

passo "Copio il file della lezione come main.tf" \
  "cp $LEZIONI/terraform/02-variabili-for-each-espressioni.tf main.tf && grep -n '^variable\|^locals\|^resource\|^output' main.tf"
passo "init" \
  'terraform init'
passo "plan con ambiente=prod: for_each crea un container per ogni chiave di var.servizi (api, web, admin)" \
  "terraform plan -var 'ambiente=prod'"
passo "ambiente=collaudo non è fra i valori ammessi: la validation dà 'Invalid value for variable' e il plan fallisce (uscita 1), quindi non c'è niente da applicare" \
  "terraform plan -var 'ambiente=collaudo'"
passo "apply con i default" \
  'terraform apply -auto-approve'
passo "Output in JSON, comodo per gli script (jq)" \
  'terraform output -json servizi | jq'
passo "Un output sensitive viene nascosto…" \
  'terraform output'
passo "…ma -raw lo stampa, e NELLO STATE è in chiaro: lo state è un segreto" \
  'terraform output -raw token; echo'
passo "terraform console: valuta espressioni con i valori veri (locals e un for)" \
  "echo 'local.porte' | terraform console; echo '{ for k, v in var.servizi : k => v.porta }' | terraform console"
passo "Passo a prod: admin esiste solo in prod (il for del local lo filtra in dev), e count porta debug a 0. api e web vengono RICREATI: il nome contiene il prefisso lab-<ambiente> e il nome di un container non si cambia sul posto" \
  "terraform apply -auto-approve -var 'ambiente=prod' && terraform state list"
passo "Tolgo 'admin' da var.servizi…" \
  "sed -i '/admin = { porta = 8103 }/d' main.tf && grep -n 'porta = 81' main.tf"
passo "…e il plan distrugge SOLO admin. Con count invece di for_each gli indici scalerebbero e cambierebbero anche gli altri" \
  "terraform plan -var 'ambiente=prod'"
passo "Pulizia" \
  "terraform destroy -auto-approve -var 'ambiente=prod'"
