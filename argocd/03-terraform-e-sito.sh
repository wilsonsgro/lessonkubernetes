#!/usr/bin/env bash
# Argo CD 3 — l'immagine del sito e l'infrastruttura con Terraform: tutto quello che Argo CD NON fa.
source "$(dirname "$0")/comune.sh"
guardia_lab
titolo "Argo CD 3. Immagine del sito e Terraform"
[[ -d "$REPO/.git" ]] || { echo "prima esegui argocd/02-git-locale.sh"; exit 1; }

nota "Argo CD applica manifest, non costruisce immagini e non crea il terreno su cui girano." \
     "L'immagine la fa la CI (qui: docker build a mano), il namespace con quote e limiti lo fa Terraform."

passo "Il Dockerfile del sito: nginx con una pagina statica, la versione entra al build" \
  "cat $REPO/sito/Dockerfile"
passo "Build dell'immagine mio-sito:v1 (tag immutabile: per cambiare versione si cambia tag, mai si sovrascrive)" \
  "docker build -q --build-arg VERSIONE=v1 -t mio-sito:v1 $REPO/sito"
passo "minikube non vede le immagini di questo docker: le carico nei nodi del cluster (senza registry)" \
  'minikube -p lab image load mio-sito:v1 && minikube -p lab image ls | grep mio-sito'
passo "Ingress controller di minikube (serve per ingress.yaml): lo accendo e aspetto che sia pronto" \
  'minikube -p lab addons enable ingress >/dev/null && kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=3m'
passo "Terraform: il codice dell'infrastruttura (provider kubernetes, contesto lab)" \
  "cat $REPO/terraform/main.tf"
passo "init: scarica il provider hashicorp/kubernetes e prepara la cartella .terraform (ignorata da git)" \
  "cd $REPO/terraform && terraform init -input=false"
passo "fmt e validate: stile e coerenza del codice, senza toccare il cluster" \
  "cd $REPO/terraform && terraform fmt -check -diff && terraform validate"
passo "plan: cosa creerebbe (3 risorse: namespace, ResourceQuota, LimitRange)" \
  "cd $REPO/terraform && terraform plan -input=false"
passo "apply: le crea davvero" \
  "cd $REPO/terraform && terraform apply -input=false -auto-approve"
passo "Il namespace porta l'etichetta gestito-da=terraform; la quota limita quanti pod e quante risorse ci potrà mettere Argo" \
  'kubectl get ns mio-sito --show-labels && kubectl -n mio-sito describe resourcequota quota'
passo "Lo stato di Terraform è locale (terraform.tfstate) e fuori da git: è infrastruttura, non applicazione" \
  "cd $REPO/terraform && terraform state list && git -C $REPO status --short --ignored terraform"
passo "Il .terraform.lock.hcl invece va in git: fissa la versione esatta del provider per chiunque cloni il progetto" \
  "cd $REPO && git add terraform/.terraform.lock.hcl && { git commit -qm 'terraform: lock del provider' || true; } && git push -q origin main && git log --oneline -2"

nota "Prossimo:  bash argocd/04-gitops.sh"
